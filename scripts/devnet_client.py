#!/usr/bin/env python3
"""
Monotron Devnet Client - Interacts with Canton Devnet JSON API
Based on cn-quickstart splice-onboarding utils.sh

Usage:
    export DEVNET_CLIENT_SECRET="your-secret"
    python3 scripts/devnet_client.py
"""
import json
import os
import requests
import time
from typing import Optional, Dict, Any, List

# Devnet Configuration
LEDGER_HOST = "ledger-api.validator.devnet.sandbox.fivenorth.io"
AUTH_URL = "https://auth.sandbox.fivenorth.io"
CLIENT_ID = "validator-devnet-m2m"
# Get secret from environment variable (set DEVNET_CLIENT_SECRET)
CLIENT_SECRET = os.environ.get("DEVNET_CLIENT_SECRET", "")
AUDIENCE = "validator-devnet-m2m"

# Validate secret is set
if not CLIENT_SECRET:
    print("[ERROR] DEVNET_CLIENT_SECRET environment variable not set!")
    print("Run: export DEVNET_CLIENT_SECRET='your-secret'")
    exit(1)

class DevnetClient:
    def __init__(self):
        self.token = self._get_token()
        self.base_url = f"https://{LEDGER_HOST}"
        self.headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }
    
    def _get_token(self) -> str:
        """Get JWT access token"""
        print("[AUTH] Getting access token...")
        response = requests.post(
            f"{AUTH_URL}/application/o/token/",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            data={
                "grant_type": "client_credentials",
                "client_id": CLIENT_ID,
                "client_secret": CLIENT_SECRET,
                "audience": AUDIENCE,
                "scope": "daml_ledger_api"
            }
        )
        token_data = response.json()
        if "access_token" not in token_data:
            raise Exception(f"Failed to get token: {token_data}")
        print(f"[AUTH] Token obtained: {token_data['access_token'][:50]}...")
        return token_data["access_token"]
    
    def _request(self, method: str, path: str, data: Any = None, content_type: str = "application/json") -> Dict:
        """Make HTTP request to Devnet"""
        url = f"{self.base_url}{path}"
        headers = {"Authorization": f"Bearer {self.token}"}
        
        if content_type == "application/octet-stream":
            headers["Content-Type"] = "application/octet-stream"
        else:
            headers["Content-Type"] = "application/json"
        
        if method == "GET":
            response = requests.get(url, headers=headers, verify=False)
        elif method == "POST":
            if isinstance(data, bytes):
                response = requests.post(url, headers=headers, data=data, verify=False)
            elif data:
                response = requests.post(url, headers=headers, json=data, verify=False)
            else:
                response = requests.post(url, headers=headers, verify=False)
        elif method == "DELETE":
            response = requests.delete(url, headers=headers, verify=False)
        else:
            raise ValueError(f"Unsupported method: {method}")
        
        print(f"[API] {method} {path} -> {response.status_code}")
        if response.status_code >= 400:
            print(f"[API] Error: {response.text[:500]}")
        
        if response.text and response.text.strip():
            try:
                return response.json()
            except:
                return {"raw": response.text}
        return {}
    
    def get_ledger_end(self) -> Dict:
        """Get ledger end offset"""
        return self._request("GET", "/v2/state/ledger-end")
    
    def list_packages(self) -> List[str]:
        """List all packages on the ledger"""
        data = self._request("GET", "/v2/packages")
        return data.get("packageIds", [])
    
    def upload_dar(self, dar_path: str) -> bool:
        """Upload a DAR file"""
        print(f"[UPLOAD] Uploading {dar_path}...")
        with open(dar_path, "rb") as f:
            dar_bytes = f.read()
        
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/octet-stream"
        }
        
        response = requests.post(
            f"{self.base_url}/v2/dars",
            headers=headers,
            data=dar_bytes,
            verify=False
        )
        
        print(f"[UPLOAD] Status: {response.status_code}")
        if response.status_code == 200:
            print("[UPLOAD] DAR uploaded successfully!")
            return True
        else:
            print(f"[UPLOAD] Error: {response.text}")
            return False
    
    def allocate_party(self, party_id_hint: str) -> Optional[str]:
        """Allocate a party on the ledger"""
        print(f"[PARTY] Allocating party: {party_id_hint}")
        
        data = self._request("POST", "/v2/parties", {
            "partyIdHint": party_id_hint,
            "displayName": party_id_hint,
            "identityProviderId": ""
        })
        
        if "partyDetails" in data and "party" in data["partyDetails"]:
            party = data["partyDetails"]["party"]
            print(f"[PARTY] Allocated: {party}")
            return party
        elif "party" in data:
            party = data["party"]
            print(f"[PARTY] Allocated: {party}")
            return party
        
        print(f"[PARTY] Error: {data}")
        return None
    
    def list_parties(self) -> List[Dict]:
        """List all parties"""
        data = self._request("GET", "/v2/parties")
        return data.get("partyDetails", [])
    
    def create_user(self, user_id: str, primary_party: str) -> Dict:
        """Create a user with primary party"""
        print(f"[USER] Creating user: {user_id} with party: {primary_party}")
        
        # Check if user exists
        existing = self._request("GET", f"/v2/users/{user_id}")
        if existing and existing.get("status") != 404:
            print(f"[USER] User already exists: {user_id}")
            return existing
        
        data = self._request("POST", "/v2/users", {
            "user": {
                "id": user_id,
                "isDeactivated": False,
                "primaryParty": primary_party,
                "identityProviderId": "",
                "metadata": {
                    "resourceVersion": "",
                    "annotations": {}
                }
            },
            "rights": []
        })
        
        print(f"[USER] Created: {data}")
        return data
    
    def grant_rights(self, user_id: str, party_id: str, rights: List[str]) -> Dict:
        """Grant rights to a user"""
        print(f"[RIGHTS] Granting {rights} to {user_id} for party {party_id}")
        
        rights_list = []
        for right in rights:
            if right == "ParticipantAdmin":
                rights_list.append({"kind": {"ParticipantAdmin": {"value": {}}}})
            elif right == "ActAs":
                rights_list.append({"kind": {"CanActAs": {"value": {"party": party_id}}}})
            elif right == "ReadAs":
                rights_list.append({"kind": {"CanReadAs": {"value": {"party": party_id}}}})
        
        data = self._request("POST", f"/v2/users/{user_id}/rights", {
            "userId": user_id,
            "identityProviderId": "",
            "rights": rights_list
        })
        
        print(f"[RIGHTS] Granted: {data}")
        return data
    
    def submit_command(self, party: str, command: Dict, workflow_id: str = "monotron-test") -> Dict:
        """Submit a command to create/exercise a contract"""
        print(f"[CMD] Submitting command for party: {party}")
        
        # Use octet-stream for command submission like the cn-quickstart
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "commands": {
                "commandId": f"cmd-{party}-{int(time.time())}",
                "party": party,
                "applicationId": "monotron-devnet-client",
                "actAs": [party],
                "readAs": [],
                "workflowId": workflow_id,
                "command": command
            }
        }
        
        response = requests.post(
            f"{self.base_url}/v2/commands",
            headers=headers,
            json=payload,
            verify=False
        )
        
        print(f"[CMD] Status: {response.status_code}")
        if response.status_code >= 400:
            print(f"[CMD] Error: {response.text[:500]}")
            return {"error": response.text}
        
        try:
            return response.json()
        except:
            return {"raw": response.text}
    
    def create_business_registration(self, party: str, operator_party: str) -> Dict:
        """Create a BusinessRegistration contract"""
        print(f"[CREATE] BusinessRegistration for party: {party}")
        
        command = {
            "create": {
                "templateId": {
                    "packageId": "97272681dcc9d7a530739f9a31a77a37cfd87f09b7b7a5ac63519bebd457416c",
                    "moduleName": "Main",
                    "entityName": "BusinessRegistration"
                },
                "arguments": {
                    "business": party,
                    "operator": operator_party,
                    "businessName": f"{party} Business",
                    "taxId": f"TAX-{party}",
                    "status": {"tag": "Active"},
                    "registeredAt": {"value": "2026-07-09T00:00:00Z"}
                }
            }
        }
        
        return self.submit_command(operator_party, command)
    
    def create_invoice(self, seller_party: str, buyer_party: str, operator_party: str, amount: str) -> Dict:
        """Create an Invoice contract"""
        print(f"[CREATE] Invoice: {buyer_party} pays {amount} to {seller_party}")
        
        command = {
            "create": {
                "templateId": {
                    "packageId": "97272681dcc9d7a530739f9a31a77a37cfd87f09b7b7a5ac63519bebd457416c",
                    "moduleName": "Main",
                    "entityName": "Invoice"
                },
                "arguments": {
                    "invoiceId": f"INV-{int(time.time())}",
                    "seller": seller_party,
                    "buyer": buyer_party,
                    "amount": {"amount": amount, "currency": "USD"},
                    "dueDate": {"value": "2026-08-09T00:00:00Z"},
                    "status": {"tag": "Initiated"},
                    "operator": operator_party
                }
            }
        }
        
        return self.submit_command(seller_party, command)


def main():
    print("=" * 60)
    print("Monotron Devnet Client - Contract Creation Test")
    print("=" * 60)
    print()
    
    client = DevnetClient()
    
    # 1. Get ledger status
    print("\n[1] Ledger Status:")
    ledger_end = client.get_ledger_end()
    print(f"    Ledger end: {ledger_end}")
    
    # 2. List packages
    print("\n[2] Packages:")
    packages = client.list_packages()
    monotron_pkg = "97272681dcc9d7a530739f9a31a77a37cfd87f09b7b7a5ac63519bebd457416c"
    if monotron_pkg in packages:
        print(f"    ✓ Monotron package found: {monotron_pkg}")
    
    # 3. Allocate parties
    print("\n[3] Allocating Parties:")
    operator_party = client.allocate_party("MonotronOp")
    seller_party = client.allocate_party("MonotronSeller")
    buyer_party = client.allocate_party("MonotronBuyer")
    
    if not all([operator_party, seller_party, buyer_party]):
        print("[ERROR] Failed to allocate parties")
        return
    
    print("\n" + "=" * 60)
    print("Parties allocated:")
    print(f"  Operator: {operator_party}")
    print(f"  Seller: {seller_party}")
    print(f"  Buyer: {buyer_party}")
    print("=" * 60)
    
    # 4. Create contracts
    print("\n[4] Creating Business Registration Contracts:")
    
    # Create seller business registration
    result = client.create_business_registration(seller_party, operator_party)
    print(f"    Seller BusinessRegistration: {result}")
    
    # Create buyer business registration  
    result = client.create_business_registration(buyer_party, operator_party)
    print(f"    Buyer BusinessRegistration: {result}")
    
    # 5. Create Invoice
    print("\n[5] Creating Invoice:")
    result = client.create_invoice(seller_party, buyer_party, operator_party, "100.00")
    print(f"    Invoice: {result}")
    
    print("\n" + "=" * 60)
    print("Contract creation test complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
