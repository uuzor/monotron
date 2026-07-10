# Canton Network Command Submission Research

## Overview

Research findings for interacting with deployed Canton Network contracts via the JSON Ledger API v2.

---

## 1. JSON API v2 Commands Endpoint

### Endpoint
```
POST <participant-url>/v2/commands/submit-and-wait
```

### Required Headers
```
Content-Type: application/json
Authorization: Bearer <JWT>
```

### Request Structure

```json
{
  "commandId": "unique-command-id",
  "actAs": ["PartyName"],
  "userId": "user-id",
  "workflowId": "optional-workflow-id",
  "commands": [
    {
      "CreateCommand": {
        "templateId": "ModuleName:TemplateName",
        "createArguments": {
          "field1": "value1",
          "field2": 42
        }
      }
    }
  ]
}
```

### Exercise Choice (with contract ID)
```json
{
  "commandId": "exercise-001",
  "actAs": ["Buyer"],
  "userId": "buyer-user",
  "commands": [
    {
      "ExerciseCommand": {
        "contractId": "#ContractId:abc123...",
        "choice": "Approve",
        "choiceArgument": {}
      }
    }
  ]
}
```

### Example cURL
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "commandId": "create-invoice-001",
    "actAs": ["Seller::participant-id"],
    "userId": "seller-user",
    "commands": [
      {
        "CreateCommand": {
          "templateId": "Main:Invoice",
          "createArguments": {
            "seller": "Seller::participant-id",
            "buyer": "Buyer::participant-id",
            "amount": {
              "amount": "1000.00",
              "currency": "USD"
            },
            "description": "Invoice #12345"
          }
        }
      }
    ]
  }' \
  "https://ledger-api.validator.devnet.sandbox.fivenorth.io/v2/commands/submit-and-wait"
```

---

## 2. Common Error Codes & Solutions

### AUTH_INVALID_TOKEN (401)
```
UNAUTHENTICATED: Could not verify JWT token
```
**Cause:** Missing, expired, or invalid JWT token
**Fix:** 
- Verify token has correct `exp`, `ledgerId`, `actAs` claims
- Check `LEDGER_API_AUTH_AUDIENCE` is "daml_ledger_api"
- Decode JWT: `echo "$TOKEN" | cut -d'.' -f2 | base64 -d | jq .`

### PACKAGE_NOT_FOUND (404)
```
NOT_FOUND: PACKAGE_NOT_FOUND - Could not find package <package-id>
```
**Cause:** DAR not uploaded to participant
**Fix:** Upload DAR
```bash
curl -X POST http://participant:5002/v2/packages \
  -F "dar=@your-package.dar"
```

### PARTY_NOT_KNOWN (404)
```
NOT_FOUND: PARTY_NOT_KNOWN - Party not known on participant
```
**Cause:** Party not allocated or not associated with participant
**Fix:**
```bash
curl http://participant:5002/v2/parties | jq '.party_details[].party'
```

### PERMISSION_DENIED (403)
```
PERMISSION_DENIED: An error occurred. Please contact the operator.
```
**Cause:** User lacks `actAs` rights for the party
**Fix:** Grant rights via admin API
```bash
curl -X POST http://participant:5002/v2/users/<user-id>/rights \
  -H "Content-Type: application/json" \
  -d '{"rights": [{"can_act_as": {"party": "<party-id>"}}]}'
```

### INVALID_ARGUMENT (400)
```
INVALID_ARGUMENT: Missing required fields / Invalid party identifier format
```
**Cause:** Malformed command payload
**Fix:** Check template ID format, required fields, party ID syntax

### CONTRACT_NOT_FOUND (404)
```
NOT_FOUND: CONTRACT_NOT_FOUND - Contract could not be found with id
```
**Cause:** Contract archived or not visible to submitting party
**Fix:** Query ACS first, implement fetch-then-exercise pattern

### ABORTED - Contention
```
ABORTED: Interpretation error: contract not active
```
**Cause:** Concurrent transaction consumed the contract
**Fix:** Retry with exponential backoff

---

## 3. Devnet-Specific Considerations

### Seaport Validator Devnet Endpoints
- **Ledger API:** `https://ledger-api.validator.devnet.sandbox.fivenorth.io`
- **Auth:** `https://auth.sandbox.fivenorth.io`

### What Devnet Supports
| Endpoint | Status | Notes |
|----------|--------|-------|
| `GET /v2/state/ledger-end` | ✅ Works | Ledger state queries |
| `GET /v2/packages` | ✅ Works | List uploaded packages |
| `POST /v2/packages` | ✅ Works | DAR upload |
| `POST /v2/parties` | ✅ Works | Party allocation |
| `POST /v2/commands/submit-and-wait` | ❌ 404 | **DISABLED** |

### The Problem
Devnet validator has **command submission disabled**. It only supports:
1. Package management (upload/list DARs)
2. Party allocation
3. Ledger state queries (read-only)

### Solutions

#### Option A: Use Local Canton Sandbox
```bash
daml sandbox .daml/dist/*.dar
```
All 11 integration tests pass on local sandbox.

#### Option B: Request Command Access
Contact Seaport/FiveNorth to enable `/v2/commands` on your validator.

#### Option C: Run Your Own Validator
- Deploy a Canton participant node
- Connect to DevNet as a validator
- Requires allowlisting and onboarding

---

## 4. Retry Patterns for Production

### Exponential Backoff Pattern
```python
import time
import requests

def submit_with_retry(url, payload, token, max_retries=5):
    for attempt in range(max_retries):
        try:
            response = requests.post(url, json=payload, headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json"
            })
            
            if response.status_code == 200:
                return response.json()
            
            # Contention - retry
            if response.status_code == 409:  # ABORTED
                wait_time = 2 ** attempt
                time.sleep(wait_time)
                continue
            
            # Non-retryable error
            return {"error": response.json()}
        
        except requests.exceptions.RequestException as e:
            wait_time = 2 ** attempt
            time.sleep(wait_time)
    
    return {"error": "Max retries exceeded"}
```

### Fetch-Then-Exercise Pattern
```python
async def exercise_with_retry(contract_id, choice_name, party, token):
    # Step 1: Fetch contract to verify it exists
    fetch_url = f"{BASE_URL}/v2/contracts/{contract_id}"
    response = requests.get(fetch_url, headers=headers)
    
    if response.status_code == 404:
        return {"error": "Contract not found"}
    
    # Step 2: Exercise choice
    exercise_url = f"{BASE_URL}/v2/commands/submit-and-wait"
    payload = {
        "commandId": f"exercise-{contract_id}-{choice_name}-{int(time.time())}",
        "actAs": [party],
        "commands": [{
            "ExerciseCommand": {
                "contractId": contract_id,
                "choice": choice_name,
                "choiceArgument": {}
            }
        }]
    }
    
    return submit_with_retry(exercise_url, payload, token)
```

---

## 5. Authentication Flow for Devnet

### Getting a JWT Token
```python
import requests

def get_devnet_token(client_id, client_secret):
    auth_url = "https://auth.sandbox.fivenorth.io/oauth/token"
    
    response = requests.post(auth_url, data={
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
        "audience": "daml_ledger_api"
    })
    
    return response.json()["access_token"]
```

### JWT Token Requirements
- **Algorithm:** RS256
- **Required claims:**
  - `ledgerId`: Ledger identifier
  - `applicationId`: Application identifier  
  - `actAs`: Array of party identifiers
  - `exp`: Expiration timestamp
  - `aud`: "daml_ledger_api"

---

## 6. Testing Checklist

Before sending commands to a deployed contract:

- [ ] DAR uploaded to participant
- [ ] Party allocated on participant
- [ ] User created with `actAs` rights for party
- [ ] Valid JWT token obtained
- [ ] Package ID verified: `GET /v2/packages`
- [ ] Template ID format correct: `ModuleName:EntityName`
- [ ] Party ID format correct: `PartyName::ParticipantID`

### Verify DAR Upload
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://ledger-api.validator.devnet.sandbox.fivenorth.io/v2/packages" | jq
```

### Verify Party Allocation
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://ledger-api.validator.devnet.sandbox.fivenorth.io/v2/parties" | jq
```

---

## 7. References

- [Canton JSON API v2 Reference](https://docs.canton.network/reference/json-api-reference/post-v2commandssubmit-and-wait)
- [Ledger API Errors](https://docs.canton.network/appdev/troubleshooting-guide/ledger-api-errors)
- [Error Code Reference](https://docs.canton.network/appdev/troubleshooting-guide/error-code-reference)
- [Development Issues](https://docs.canton.network/appdev/troubleshooting-guide/development-issues)
- [Contracts in Java](https://docs.canton.network/appdev/deep-dives/contracts-and-transactions-in-java)
- [JSON API Tutorial](https://docs.digitalasset.com/build/3.4/tutorials/json-api/canton_and_the_json_ledger_api.html)
- [Canton Forum - JSON API Questions](https://forum.canton.network/t/how-to-use-the-http-json-api/2200)

---

## Summary: Why Commands Don't Work on Devnet

| Issue | Status | Impact |
|-------|--------|--------|
| DAR upload | ✅ Works | Can deploy contracts |
| Party allocation | ✅ Works | Can create parties |
| Ledger queries | ✅ Works | Can read state |
| **Command submission** | ❌ **404** | **Cannot create/exercise contracts** |

**Root Cause:** The Devnet validator is configured without command submission enabled. This is intentional for a restricted/public validator.

**Recommended Path Forward:**
1. Use local Canton Sandbox for development (fully functional)
2. Consider running your own Canton participant node connected to DevNet
3. Contact Seaport/FiveNorth about enabling command submission on your validator
