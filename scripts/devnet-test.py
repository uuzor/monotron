#!/usr/bin/env python3
"""
Monotron Devnet Integration Test
Connects to Canton Devnet and runs the invoice settlement flow
"""
import json
import requests
import time
from datetime import datetime

# Devnet configuration
DEVNET_HOST = "ledger-api.validator.devnet.sandbox.fivenorth.io"
DEVNET_AUTH = "https://auth.sandbox.fivenorth.io"
CLIENT_ID = "validator-devnet-m2m"
CLIENT_SECRET = "r69FQmevLRwEgMB8NnKaSDHPewTOSx7Yy5jucsqAlmsAaJc3DlggedCz4tyyonl4W2WoOVzkUIjy8dHTlc16AOJQzx02QzJylAUG56oLTCoVCJUUK40vRv9CqQEY3fjn"

def get_token():
    """Get JWT access token from Devnet auth service"""
    print("[AUTH] Getting access token...")
    response = requests.post(
        f"{DEVNET_AUTH}/application/o/token/",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        data={
            "grant_type": "client_credentials",
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "audience": "validator-devnet-m2m",
            "scope": "daml_ledger_api"
        }
    )
    token_data = response.json()
    if "access_token" in token_data:
        print(f"[AUTH] Token obtained: {token_data['access_token'][:50]}...")
        return token_data["access_token"]
    else:
        print(f"[AUTH] ERROR: {token_data}")
        return None

def upload_dar(token, dar_path):
    """Upload a DAR file to the ledger"""
    print(f"[UPLOAD] Uploading {dar_path}...")
    with open(dar_path, "rb") as f:
        dar_bytes = f.read()
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/octet-stream"
    }
    
    response = requests.post(
        f"https://{DEVNET_HOST}/v2/dars",
        headers=headers,
        data=dar_bytes
    )
    
    print(f"[UPLOAD] Status: {response.status_code}")
    print(f"[UPLOAD] Response: {response.text}")
    return response.status_code == 200

def check_ledger_end(token):
    """Get the current ledger end offset"""
    headers = {"Authorization": f"Bearer {token}"}
    response = requests.get(
        f"https://{DEVNET_HOST}/v2/state/ledger-end",
        headers=headers
    )
    return response.json()

def list_packages(token):
    """List all packages on the ledger"""
    headers = {"Authorization": f"Bearer {token}"}
    response = requests.get(
        f"https://{DEVNET_HOST}/v2/packages",
        headers=headers
    )
    data = response.json()
    return data.get("packageIds", [])

def create_party(token, party_id):
    """Allocate a party on the ledger"""
    print(f"[PARTY] Allocating party: {party_id}")
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "commands": {
            "commandId": f"allocate-{party_id}-{int(time.time())}",
            "party": party_id,
            "applicationId": "monotron-devnet-test",
            "actAs": [party_id],
            "readAs": [],
            "workflowId": "party-allocation",
            "command": {
                "create": {
                    "templateId": {
                        "packageId": "",
                        "moduleName": "",
                        "entityName": "Party"
                    },
                    "arguments": {}
                }
            }
        }
    }
    
    response = requests.post(
        f"https://{DEVNET_HOST}/v2/commands",
        headers=headers,
        json=payload
    )
    print(f"[PARTY] Status: {response.status_code}")
    print(f"[PARTY] Response: {response.text[:500]}")
    return response.json()

def main():
    print("=" * 60)
    print("Monotron Devnet Integration Test")
    print("=" * 60)
    print()
    
    # Get token
    token = get_token()
    if not token:
        print("[ERROR] Failed to get token")
        return
    
    print()
    
    # Check ledger status
    print("[LEDGER] Checking ledger status...")
    ledger_end = check_ledger_end(token)
    print(f"[LEDGER] Ledger end: {ledger_end}")
    print()
    
    # List packages
    print("[PACKAGES] Listing packages...")
    packages = list_packages(token)
    print(f"[PACKAGES] Total packages: {len(packages)}")
    
    # Find monotron package
    monotron_pkg = None
    for pkg in packages:
        try:
            response = requests.get(
                f"https://{DEVNET_HOST}/v2/packages/{pkg}",
                headers={"Authorization": f"Bearer {token}"}
            )
            if response.status_code == 200 and b"Monotron" in response.content:
                monotron_pkg = pkg
                print(f"[PACKAGES] Found Monotron package: {pkg}")
                break
        except:
            pass
    
    if not monotron_pkg:
        print("[PACKAGES] Monotron package NOT found!")
        print("[INFO] Uploading monotron DAR...")
        upload_dar(token, "/workspace/project/monotron/main/.daml/dist/monotron-main-0.0.1.dar")
        print("[INFO] Waiting for package to be processed...")
        time.sleep(10)
        
        # Check again
        packages = list_packages(token)
        print(f"[PACKAGES] Total packages after upload: {len(packages)}")
    
    print()
    print("=" * 60)
    print("Test complete!")
    print("=" * 60)

if __name__ == "__main__":
    main()
