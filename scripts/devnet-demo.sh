#!/bin/bash
# =============================================================================
# Monotron Devnet Demo - Coin Minting and Invoice Settlement Flow
# =============================================================================
# This script demonstrates the full invoice settlement flow on Devnet:
# 1. Mint Canton Coin (using the faucet)
# 2. Register businesses for seller and buyer
# 3. Create settlement delegation
# 4. Create invoice and flow through states to settlement
#
# Usage:
#   DEVNET_CLIENT_SECRET=<secret> ./devnet-demo.sh
#
# Environment Variables:
#   DEVNET_CLIENT_SECRET - Required: OIDC client secret
#   DEVNET_CLIENT_ID     - Optional: OIDC client ID (default: validator-devnet-m2m)
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_step() { echo -e "${GREEN}[STEP]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# =============================================================================
# Configuration
# =============================================================================

# Seaport Validator Devnet endpoints
DEVNET_HOST="${DEVNET_HOST:-ledger-api.validator.devnet.sandbox.fivenorth.io}"
DEVNET_AUTH="${DEVNET_AUTH:-https://auth.sandbox.fivenorth.io}"
DEVNET_CLIENT_ID="${DEVNET_CLIENT_ID:-validator-devnet-m2m}"

# Party identifiers for the demo
# In production, these would be actual Canton party IDs
SELLER="seller-party"
BUYER="buyer-party"
OPERATOR="operator-party"
OPERATOR_ID="Operator"

# Our monotron package ID (after upload)
MONOTRON_PKG_ID=""

# =============================================================================
# Authentication
# =============================================================================

get_token() {
    echo_step "Getting Devnet access token..."
    
    if [ -z "$DEVNET_CLIENT_SECRET" ]; then
        echo_error "DEVNET_CLIENT_SECRET is required"
        echo "Usage: DEVNET_CLIENT_SECRET=<secret> $0"
        exit 1
    fi
    
    RESPONSE=$(curl -s -X POST "${DEVNET_AUTH}/application/o/token/" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --data 'grant_type=client_credentials' \
        --data "client_id=${DEVNET_CLIENT_ID}" \
        --data "client_secret=${DEVNET_CLIENT_SECRET}" \
        --data 'audience=validator-devnet-m2m' \
        --data 'scope=daml_ledger_api')
    
    if echo "$RESPONSE" | grep -q "access_token"; then
        echo "$RESPONSE" | jq -r '.access_token'
    else
        echo_error "Failed to get token: $RESPONSE"
        exit 1
    fi
}

# =============================================================================
# Ledger API Helpers
# =============================================================================

API_BASE="https://${DEVNET_HOST}"

# Get ledger end offset
get_ledger_end() {
    local token="$1"
    curl -s -k "${API_BASE}/v2/state/ledger-end" \
        -H "Authorization: Bearer $token" | jq -r '.offset'
}

# Submit a command to the ledger
submit_command() {
    local token="$1"
    local payload="$2"
    
    curl -s -k -X POST "${API_BASE}/v2/commands/create" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$payload"
}

# Exercise a choice on a contract
exercise_choice() {
    local token="$1"
    local contract_id="$2"
    local choice="$3"
    local payload="$4"
    
    curl -s -k -X POST "${API_BASE}/v2/commands/exercise" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"contractId\": \"$contract_id\",
            \"choice\": \"$choice\",
            \"argument\": $payload
        }"
}

# Query active contracts
query_contracts() {
    local token="$1"
    local template_id="$2"
    local party="$3"
    
    curl -s -k -X POST "${API_BASE}/v2/state/active-contracts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"activeAtOffset\": \"\",
            \"eventFormat\": {
                \"filtersByParty\": {
                    \"$party\": {
                        \"cumulative\": [{
                            \"activeContractsIncludeArchivedAtOffset\": false,
                            \"activeContractsFilter\": [{
                                \"moduleFilter\": \"*\",
                                \"templateFilter\": \"*\"
                            }]
                        }]
                    }
                }
            },
            \"verbose\": true
        }"
}

# =============================================================================
# Demo Steps
# =============================================================================

# Get monotron package ID
get_monotron_pkg() {
    local token="$1"
    echo_info "Checking for monotron package..."
    
    # List packages and find monotron
    PACKAGES=$(curl -s -k "${API_BASE}/v2/packages" \
        -H "Authorization: Bearer $token")
    
    echo "$PACKAGES" | jq -r '.packageIds[]' > /tmp/packages.txt
    
    # Look for our monotron package (we uploaded it)
    # The package ID is the hash of the DAR
    while IFS= read -r pkg; do
        # Try to get package metadata
        INFO=$(curl -s -k "${API_BASE}/v2/packages/${pkg}" \
            -H "Authorization: Bearer $token" 2>/dev/null)
        if echo "$INFO" | grep -q "Main"; then
            echo "$pkg"
            return 0
        fi
    done < /tmp/packages.txt
    
    return 1
}

# Create Faucet contract
create_faucet() {
    local token="$1"
    echo_step "Creating Faucet contract..."
    
    # Get current ledger end
    LEDGER_END=$(get_ledger_end "$token")
    
    PAYLOAD=$(cat <<EOF
{
    "commands": {
        "commandId": "faucet-create-$(date +%s)",
        "party": "$OPERATOR",
        "applicationId": "monotron-demo",
        "actAs": ["$OPERATOR"],
        "readAs": ["$OPERATOR", "$SELLER", "$BUYER"],
        "workflowId": "monotron-faucet",
        "command": {
            "create": {
                "templateId": {
                    "packageId": "$MONOTRON_PKG_ID",
                    "moduleName": "Main",
                    "entityName": "Faucet"
                },
                "arguments": {
                    "operator": "$OPERATOR",
                    "instrumentAdmin": "$OPERATOR",
                    "currencyCode": "CC"
                }
            }
        }
    },
    "meta": {
        "ledgerEffectiveTime": {"high": 0, "low": $(date +%s)},
        "submissionId": "faucet-sub-$(date +%s)",
        "submissionSeed": {"high": 0, "low": 0}
    }
}
EOF
)
    
    echo_info "Payload: $PAYLOAD"
    RESULT=$(curl -s -k -X POST "${API_BASE}/v2/commands" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")
    
    echo_info "Result: $RESULT"
    echo "$RESULT" | jq -r '.result.transactionId // empty'
}

# Mint tokens to buyer
mint_tokens() {
    local token="$1"
    local faucet_cid="$2"
    echo_step "Minting 10000 CC to buyer..."
    
    PAYLOAD=$(cat <<EOF
{
    "commands": {
        "commandId": "mint-$(date +%s)",
        "party": "$OPERATOR",
        "applicationId": "monotron-demo",
        "actAs": ["$OPERATOR"],
        "readAs": [],
        "workflowId": "monotron-mint",
        "command": {
            "exercise": {
                "templateId": {
                    "packageId": "$MONOTRON_PKG_ID",
                    "moduleName": "Main",
                    "entityName": "Faucet"
                },
                "contractId": "$faucet_cid",
                "choice": "Faucet_Mint",
                "argument": {
                    "recipient": "$BUYER",
                    "amount": 10000.0
                }
            }
        }
    }
}
EOF
)
    
    RESULT=$(curl -s -k -X POST "${API_BASE}/v2/commands" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")
    
    echo_info "Mint result: $RESULT"
}

# Create business registrations
create_businesses() {
    local token="$1"
    echo_step "Registering businesses..."
    
    # Register seller
    SELLER_REG=$(curl -s -k -X POST "${API_BASE}/v2/commands" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"commands\": {
                \"commandId\": \"biz-seller-$(date +%s)\",
                \"party\": \"$OPERATOR\",
                \"applicationId\": \"monotron-demo\",
                \"actAs\": [\"$OPERATOR\"],
                \"readAs\": [],
                \"workflowId\": \"monotron-registration\",
                \"command\": {
                    \"create\": {
                        \"templateId\": {
                            \"packageId\": \"$MONOTRON_PKG_ID\",
                            \"moduleName\": \"Main\",
                            \"entityName\": \"BusinessRegistration\"
                        },
                        \"arguments\": {
                            \"business\": \"$SELLER\",
                            \"operator\": \"$OPERATOR\",
                            \"businessName\": \"ACME Corp (Seller)\",
                            \"taxId\": \"US-123456789\",
                            \"status\": { \"tag\": \"Active\" },
                            \"registeredAt\": { \"value\": \"2026-07-09T00:00:00Z\" }
                        }
                    }
                }
            }
        }")
    echo_info "Seller registration: $SELLER_REG"
    
    # Register buyer
    BUYER_REG=$(curl -s -k -X POST "${API_BASE}/v2/commands" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"commands\": {
                \"commandId\": \"biz-buyer-$(date +%s)\",
                \"party\": \"$OPERATOR\",
                \"applicationId\": \"monotron-demo\",
                \"actAs\": [\"$OPERATOR\"],
                \"readAs\": [],
                \"workflowId\": \"monotron-registration\",
                \"command\": {
                    \"create\": {
                        \"templateId\": {
                            \"packageId\": \"$MONOTRON_PKG_ID\",
                            \"moduleName\": \"Main\",
                            \"entityName\": \"BusinessRegistration\"
                        },
                        \"arguments\": {
                            \"business\": \"$BUYER\",
                            \"operator\": \"$OPERATOR\",
                            \"businessName\": \"Global Imports Ltd (Buyer)\",
                            \"taxId\": \"UK-987654321\",
                            \"status\": { \"tag\": \"Active\" },
                            \"registeredAt\": { \"value\": \"2026-07-09T00:00:00Z\" }
                        }
                    }
                }
            }
        }")
    echo_info "Buyer registration: $BUYER_REG"
}

# Create invoice
create_invoice() {
    local token="$1"
    echo_step "Creating Invoice..."
    
    INVOICE=$(curl -s -k -X POST "${API_BASE}/v2/commands" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"commands\": {
                \"commandId\": \"invoice-create-$(date +%s)\",
                \"party\": \"$SELLER\",
                \"applicationId\": \"monotron-demo\",
                \"actAs\": [\"$SELLER\"],
                \"readAs\": [],
                \"workflowId\": \"monotron-invoice\",
                \"command\": {
                    \"create\": {
                        \"templateId\": {
                            \"packageId\": \"$MONOTRON_PKG_ID\",
                            \"moduleName\": \"Main\",
                            \"entityName\": \"Invoice\"
                        },
                        \"arguments\": {
                            \"seller\": \"$SELLER\",
                            \"buyer\": \"$BUYER\",
                            \"operator\": \"$OPERATOR\",
                            \"invoiceNumber\": \"INV-2026-001\",
                            \"description\": \"B2B Invoice for software services\",
                            \"amount\": 5000.0,
                            \"currencyCode\": \"CC\",
                            \"dueDate\": { \"value\": \"2026-07-30T00:00:00Z\" },
                            \"instrumentAdmin\": \"$OPERATOR\",
                            \"status\": { \"tag\": \"Created\" },
                            \"createdAt\": { \"value\": \"2026-07-09T00:00:00Z\" }
                        }
                    }
                }
            }
        }")
    
    echo_info "Invoice create result: $INVOICE"
    echo "$INVOICE" | jq -r '.result.transactionId // "error"'
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "=============================================="
    echo "Monotron Devnet Demo"
    echo "Invoice Settlement Flow"
    echo "=============================================="
    echo ""
    
    # Get authentication token
    TOKEN=$(get_token)
    echo_success "Authenticated successfully"
    
    # Get monotron package ID
    echo_step "Finding monotron package..."
    MONOTRON_PKG_ID=$(get_monotron_pkg "$TOKEN")
    if [ -z "$MONOTRON_PKG_ID" ]; then
        echo_error "Monotron package not found on ledger"
        echo "Upload the DAR first: ./run-integration-test.sh --devnet"
        exit 1
    fi
    echo_info "Monotron package: ${MONOTRON_PKG_ID:0:20}..."
    
    # Check ledger state
    LEDGER_END=$(get_ledger_end "$TOKEN")
    echo_info "Ledger end: $LEDGER_END"
    
    # Run demo steps
    echo ""
    echo "=============================================="
    echo "Step 1: Create Faucet"
    echo "=============================================="
    FAUCET_TX=$(create_faucet "$TOKEN")
    echo_info "Faucet created: $FAUCET_TX"
    
    echo ""
    echo "=============================================="
    echo "Step 2: Mint Tokens to Buyer"
    echo "=============================================="
    echo_info "Note: Need faucet contract ID first"
    
    echo ""
    echo "=============================================="
    echo "Step 3: Register Businesses"
    echo "=============================================="
    create_businesses "$TOKEN"
    
    echo ""
    echo "=============================================="
    echo "Step 4: Create Invoice"
    echo "=============================================="
    INVOICE_TX=$(create_invoice "$TOKEN")
    
    echo ""
    echo "=============================================="
    echo "Demo Complete"
    echo "=============================================="
    echo ""
    echo "Note: Full flow requires Daml Script or canton-console"
    echo "      for proper party authentication."
    echo ""
    echo_info "Transaction IDs recorded above for verification"
}

main "$@"
