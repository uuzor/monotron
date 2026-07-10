#!/usr/bin/env node
/**
 * Monotron Devnet WebSocket Client
 * Connects to Canton Devnet via WebSocket for command submission
 */
const WebSocket = require('ws');
const https = require('https');
const http = require('http');

// Devnet Configuration
const LEDGER_HOST = "ledger-api.validator.devnet.sandbox.fivenorth.io";
const AUTH_URL = "https://auth.sandbox.fivenorth.io";
const CLIENT_ID = "validator-devnet-m2m";
const CLIENT_SECRET = "r69FQmevLRwEgMB8NnKaSDHPewTOSx7Yy5jucsqAlmsAaJc3DlggedCz4tyyonl4W2WoOVzkUIjy8dHTlc16AOJQzx02QzJylAUG56oLTCoVCJUUK40vRv9CqQEY3fjn";
const AUDIENCE = "validator-devnet-m2m";

// Monotron Package ID
const PKG_ID = "97272681dcc9d7a530739f9a31a77a37cfd87f09b7b7a5ac63519bebd457416c";

// Get JWT Token
async function getToken() {
    console.log("[AUTH] Getting access token...");
    
    return new Promise((resolve, reject) => {
        const data = new URLSearchParams({
            grant_type: 'client_credentials',
            client_id: CLIENT_ID,
            client_secret: CLIENT_SECRET,
            audience: AUDIENCE,
            scope: 'daml_ledger_api'
        }).toString();
        
        const options = {
            hostname: 'auth.sandbox.fivenorth.io',
            port: 443,
            path: '/application/o/token/',
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Content-Length': Buffer.byteLength(data)
            }
        };
        
        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                try {
                    const tokenData = JSON.parse(body);
                    if (tokenData.access_token) {
                        console.log(`[AUTH] Token obtained: ${tokenData.access_token.substring(0, 50)}...`);
                        resolve(tokenData.access_token);
                    } else {
                        reject(new Error(`No access token: ${body}`));
                    }
                } catch (e) {
                    reject(e);
                }
            });
        });
        
        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

// HTTP Request helper
async function httpRequest(method, path, token, body = null) {
    console.log(`[HTTP] ${method} ${path}`);
    
    return new Promise((resolve, reject) => {
        const options = {
            hostname: LEDGER_HOST,
            port: 443,
            path: path,
            method: method,
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': body ? 'application/json' : 'application/json'
            }
        };
        
        const req = https.request(options, (res) => {
            let responseBody = '';
            res.on('data', (chunk) => responseBody += chunk);
            res.on('end', () => {
                console.log(`[HTTP] Status: ${res.statusCode}`);
                try {
                    const json = JSON.parse(responseBody);
                    resolve(json);
                } catch (e) {
                    resolve(responseBody);
                }
            });
        });
        
        req.on('error', reject);
        if (body) {
            req.write(JSON.stringify(body));
        }
        req.end();
    });
}

// Allocate party
async function allocateParty(token, partyHint) {
    console.log(`[PARTY] Allocating: ${partyHint}`);
    
    const result = await httpRequest('POST', '/v2/parties', token, {
        partyIdHint: partyHint,
        displayName: partyHint,
        identityProviderId: ""
    });
    
    if (result.partyDetails && result.partyDetails.party) {
        console.log(`[PARTY] Allocated: ${result.partyDetails.party}`);
        return result.partyDetails.party;
    }
    
    // Check if party already exists
    if (result.code === 'INVALID_ARGUMENT' && result.cause.includes('already allocated')) {
        // Try to find the party in existing parties
        const parties = await httpRequest('GET', '/v2/parties', token);
        for (const p of parties.partyDetails || []) {
            if (p.displayName === partyHint || p.party.includes(partyHint)) {
                console.log(`[PARTY] Found existing: ${p.party}`);
                return p.party;
            }
        }
    }
    
    console.log(`[PARTY] Error: ${JSON.stringify(result).substring(0, 200)}`);
    return null;
}

// Submit command via WebSocket
function submitCommandWs(token, party, command) {
    return new Promise((resolve, reject) => {
        const wsUrl = `wss://${LEDGER_HOST}/v2/commands`;
        const subprotocol = `jwt.token.${token}`;
        
        console.log(`[WS] Connecting to ${wsUrl}`);
        console.log(`[WS] Subprotocol: jwt.token.xxx${token.slice(-10)}`);
        
        const ws = new WebSocket(wsUrl, [subprotocol, 'daml.ws.auth'], {
            handshakeTimeout: 30000
        });
        
        const commandId = `cmd-${party}-${Date.now()}`;
        
        const payload = {
            commands: {
                commandId: commandId,
                party: party,
                applicationId: "monotron-ws-client",
                actAs: [party],
                readAs: [],
                workflowId: "monotron-test",
                command: command
            }
        };
        
        ws.on('open', () => {
            console.log(`[WS] Connected!`);
            console.log(`[WS] Sending command: ${commandId}`);
            ws.send(JSON.stringify(payload));
        });
        
        ws.on('message', (data) => {
            console.log(`[WS] Received: ${data.toString().substring(0, 500)}`);
            try {
                const response = JSON.parse(data.toString());
                
                // Check for completion or errors
                if (response.status) {
                    console.log(`[WS] Status: ${response.status}`);
                    if (response.status === 200 || response.status === '200') {
                        resolve(response);
                    } else {
                        reject(new Error(`Command failed: ${JSON.stringify(response)}`));
                    }
                    ws.close();
                }
                
                // Handle other message types
                if (response.type === 'error' || response.error) {
                    reject(new Error(`Error: ${JSON.stringify(response)}`));
                    ws.close();
                }
            } catch (e) {
                console.log(`[WS] Parse error: ${e.message}`);
            }
        });
        
        ws.on('error', (error) => {
            console.log(`[WS] Error: ${error.message}`);
            reject(error);
        });
        
        ws.on('close', (code, reason) => {
            console.log(`[WS] Closed: ${code} ${reason}`);
        });
        
        // Timeout after 30 seconds
        setTimeout(() => {
            ws.close();
            reject(new Error('Timeout waiting for response'));
        }, 30000);
    });
}

// Create Business Registration contract
async function createBusinessRegistration(token, party, operatorParty) {
    console.log(`\n[CREATE] BusinessRegistration for ${party}`);
    
    const command = {
        create: {
            templateId: {
                packageId: PKG_ID,
                moduleName: "Main",
                entityName: "BusinessRegistration"
            },
            arguments: {
                business: party,
                operator: operatorParty,
                businessName: `${party} Business`,
                taxId: `TAX-${party.substring(0, 8)}`,
                status: { tag: "Active" },
                registeredAt: { value: "2026-07-09T00:00:00Z" }
            }
        }
    };
    
    try {
        const result = await submitCommandWs(token, operatorParty, command);
        console.log(`[CREATE] Success: ${JSON.stringify(result).substring(0, 200)}`);
        return result;
    } catch (e) {
        console.log(`[CREATE] Error: ${e.message}`);
        return null;
    }
}

// Create Invoice contract
async function createInvoice(token, sellerParty, buyerParty, operatorParty, amount) {
    console.log(`\n[CREATE] Invoice: ${buyerParty} pays ${amount} to ${sellerParty}`);
    
    const command = {
        create: {
            templateId: {
                packageId: PKG_ID,
                moduleName: "Main",
                entityName: "Invoice"
            },
            arguments: {
                invoiceId: `INV-${Date.now()}`,
                seller: sellerParty,
                buyer: buyerParty,
                amount: { amount: amount, currency: "USD" },
                dueDate: { value: "2026-08-09T00:00:00Z" },
                status: { tag: "Initiated" },
                operator: operatorParty
            }
        }
    };
    
    try {
        const result = await submitCommandWs(token, sellerParty, command);
        console.log(`[CREATE] Success: ${JSON.stringify(result).substring(0, 200)}`);
        return result;
    } catch (e) {
        console.log(`[CREATE] Error: ${e.message}`);
        return null;
    }
}

// Subscribe to active contracts via WebSocket
function subscribeContracts(token, party) {
    return new Promise((resolve, reject) => {
        const wsUrl = `wss://${LEDGER_HOST}/v2/state/active-contracts`;
        const subprotocol = `jwt.token.${token}`;
        
        console.log(`[WS] Subscribing to active contracts for party: ${party}`);
        
        const ws = new WebSocket(wsUrl, [subprotocol, 'daml.ws.auth'], {
            handshakeTimeout: 30000
        });
        
        const request = {
            activeAtOffset: "",
            eventFormat: {
                filtersForAnyParty: {
                    cumulative: []
                }
            },
            verbose: false,
            ledgerId: ""
        };
        
        ws.on('open', () => {
            console.log(`[WS] Connected!`);
            ws.send(JSON.stringify(request));
        });
        
        ws.on('message', (data) => {
            console.log(`[WS] Received (${data.length} bytes): ${data.toString().substring(0, 300)}`);
            try {
                const response = JSON.parse(data.toString());
                
                if (response.type === 'error') {
                    console.log(`[WS] Error: ${JSON.stringify(response)}`);
                    reject(new Error(JSON.stringify(response)));
                    ws.close();
                }
                
                if (response.status) {
                    console.log(`[WS] Status: ${response.status}`);
                }
            } catch (e) {
                // Ignore parse errors for binary data
            }
        });
        
        ws.on('error', (error) => {
            console.log(`[WS] Error: ${error.message}`);
            // Don't reject on error immediately - might be transient
        });
        
        ws.on('close', (code, reason) => {
            console.log(`[WS] Closed: ${code} ${reason}`);
            resolve({ closed: true });
        });
        
        // Close after 10 seconds
        setTimeout(() => {
            ws.close();
            resolve({ timeout: true });
        }, 10000);
    });
}

// Main function
async function main() {
    console.log("=".repeat(60));
    console.log("Monotron Devnet WebSocket Client");
    console.log("=".repeat(60));
    console.log();
    
    try {
        // 1. Get token
        const token = await getToken();
        console.log();
        
        // 2. Check ledger status
        console.log("[LEDGER] Getting ledger end...");
        const ledgerEnd = await httpRequest('GET', '/v2/state/ledger-end', token);
        console.log(`[LEDGER] End: ${ledgerEnd.offset}`);
        console.log();
        
        // 3. Check packages
        console.log("[PACKAGES] Checking monotron package...");
        const packages = await httpRequest('GET', '/v2/packages', token);
        console.log(`[PACKAGES] Total: ${packages.packageIds.length}`);
        if (packages.packageIds.includes(PKG_ID)) {
            console.log(`[PACKAGES] ✓ Monotron package found`);
        }
        console.log();
        
        // 4. Allocate parties
        console.log("[PARTIES] Allocating parties...");
        const operatorParty = await allocateParty(token, "MonotronOp2");
        const sellerParty = await allocateParty(token, "MonotronSeller2");
        const buyerParty = await allocateParty(token, "MonotronBuyer2");
        console.log();
        
        if (!operatorParty || !sellerParty || !buyerParty) {
            console.log("[ERROR] Failed to allocate parties");
            return;
        }
        
        console.log("=".repeat(60));
        console.log("Parties allocated:");
        console.log(`  Operator: ${operatorParty}`);
        console.log(`  Seller: ${sellerParty}`);
        console.log(`  Buyer: ${buyerParty}`);
        console.log("=".repeat(60));
        console.log();
        
        // 5. Try to subscribe to contracts
        console.log("[SUBSCRIBE] Testing contract subscription...");
        await subscribeContracts(token, operatorParty);
        console.log();
        
        // 6. Create contracts via WebSocket
        console.log("[CONTRACTS] Creating contracts via WebSocket...");
        
        const br1 = await createBusinessRegistration(token, sellerParty, operatorParty);
        await new Promise(r => setTimeout(r, 1000));
        
        const br2 = await createBusinessRegistration(token, buyerParty, operatorParty);
        await new Promise(r => setTimeout(r, 1000));
        
        const invoice = await createInvoice(token, sellerParty, buyerParty, operatorParty, "100.00");
        
        console.log();
        console.log("=".repeat(60));
        console.log("Test complete!");
        console.log("=".repeat(60));
        
    } catch (error) {
        console.error(`[ERROR] ${error.message}`);
        console.error(error.stack);
    }
}

main();
