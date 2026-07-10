# Devnet Scripts

This directory contains scripts for interacting with the Canton Devnet validator.

## Prerequisites

1. Python 3.x with `requests` library:
   ```bash
   pip install requests
   ```

2. Node.js with `ws` package (for WebSocket tests):
   ```bash
   npm install
   ```

## Scripts

### devnet_client.py

Python client for interacting with Devnet via HTTP/JSON API.

**Capabilities:**
- Get JWT access token
- Query ledger status (ledger end, packages, parties)
- Allocate parties
- Upload DAR files
- Create users with rights

**Usage:**
```bash
python scripts/devnet_client.py
```

### devnet-ws-test.js

Node.js WebSocket client for Devnet.

**Capabilities:**
- Connect via WebSocket with JWT authentication
- Subscribe to active contracts
- Submit commands via WebSocket

**Usage:**
```bash
node scripts/devnet-ws-test.js
```

### devnet-test.py

Python integration test script.

## Devnet Configuration

- **Ledger Host:** `ledger-api.validator.devnet.sandbox.fivenorth.io`
- **Auth URL:** `https://auth.sandbox.fivenorth.io`
- **Client ID:** `validator-devnet-m2m`

## Known Limitations

The Devnet validator currently supports:
- ✅ DAR upload
- ✅ Package queries
- ✅ Party allocation
- ✅ Ledger end queries
- ❌ Command submission (HTTP/WebSocket) - Not enabled
- ❌ Daml Script execution - Requires gRPC

For full integration testing, use the Canton Console or local sandbox.
