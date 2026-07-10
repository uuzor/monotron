# Monotron - B2B Invoice Settlement Platform

**Legally running towards Canton Megaton Protocol**

A privacy-preserving B2B invoice settlement platform built on Canton Network using Daml smart contracts.

## 🎯 Project Overview

Monotron implements a **Path A settlement** model for B2B invoices on Canton Network:
- Atomic batch transactions for settlement
- Privacy: only stakeholders see contract data
- Token Standard (CIP-0056) for wallet/settlement integration

## 📋 Current Status

| Component | Status | Notes |
|-----------|--------|-------|
| Smart Contracts | ✅ Complete | Invoice, Faucet, BusinessRegistration, TestHolding |
| Integration Tests | ✅ 11 tests | All pass on local Canton Sandbox |
| Devnet Upload | ✅ Works | DAR can be uploaded |
| Devnet Party Alloc | ✅ Works | Parties can be allocated |
| Devnet Command Submit | ❌ **404 Disabled** | Domain-level restriction |
| Local Sandbox | ✅ Full | All features work |

---

## 🏗️ Project Structure

```
monotron/
├── main/daml/
│   └── Main.daml              # Smart contracts (Invoice, Faucet, etc.)
├── test/daml/
│   └── Test.daml              # Integration tests (11 scenarios)
├── api/
│   └── src/                   # TypeScript REST API (Express.js)
├── scripts/
│   ├── devnet_client.py       # Python Devnet HTTP client
│   ├── devnet-ws-test.js      # Node.js WebSocket client
│   ├── run-integration-test.sh # Integration test runner
│   └── devnet-demo.sh          # Devnet demonstration
├── frontend/                   # React + TypeScript (from cn-quickstart)
├── integration-test/           # Playwright E2E tests
└── backend/                   # Java Spring Boot reference

```

---

## 📦 Smart Contracts (Main.daml)

### Templates

| Template | Description | Key Fields |
|----------|-------------|------------|
| **Invoice** | B2B invoice with 5-state lifecycle | seller, buyer, amount, status |
| **BusinessRegistration** | On-chain business identity | business, operator, taxId, status |
| **SettlementDelegation** | Authorization for Path A settlement | delegator, settlementService |
| **Faucet** | Test token minting | operator |
| **TestHolding** | UTXO test token (implements Holding) | issuer, owner, amount |
| **Wallet** | Party wallet (reference) | owner, holdings |

### Invoice Status Lifecycle

```
Created → Approved → AwaitingSettlement → Settled
                                      ↓
                                  Rejected
```

### Daml Dependencies

- `utility-registry-v0-0.6.0.dar`
- `utility-registry-holding-v0-0.2.1.dar`
- `utility-registry-app-v0-0.7.0.dar`
- `splice-api-token-transfer-instruction-v1-1.0.0.dar`

---

## 🔗 Devnet Configuration

### Endpoint

| Service | URL |
|---------|-----|
| **Ledger API** | `https://ledger-api.validator.devnet.sandbox.fivenorth.io` |
| **Auth Server** | `https://auth.sandbox.fivenorth.io` |

### Authentication

```bash
# Auth endpoint
POST https://auth.sandbox.fivenorth.io/application/o/token/

# Client credentials
client_id: validator-devnet-m2m
client_secret: [provided by Seaport]
audience: validator-devnet-m2m
scope: daml_ledger_api
```

### API Endpoints Tested

| Endpoint | Method | Status | Result |
|---------|--------|--------|--------|
| `/v2/state/ledger-end` | GET | ✅ 200 | Returns ledger offset |
| `/v2/packages` | GET | ✅ 200 | Lists uploaded packages |
| `/v2/dars` | POST | ✅ 200 | DAR upload works |
| `/v2/parties` | POST | ✅ 200 | Party allocation works |
| `/v2/commands/submit-and-wait` | POST | ❌ **404** | **DISABLED** |

---

## 🚀 Getting Started

### Prerequisites

- Daml 3.5.2+
- Node.js 18+
- Python 3.9+
- Docker (for Canton Sandbox)

### Build DAR

```bash
cd main
daml build
# Output: .daml/dist/monoton-0.0.1.dar
```

### Run Integration Tests (Local Sandbox)

```bash
./scripts/run-integration-test.sh --sandbox --full
```

### Connect to Devnet

```bash
# Set credentials
export DEVNET_CLIENT_SECRET="your-secret"

# Test connection
python3 scripts/devnet_client.py

# Upload DAR
python3 scripts/devnet_client.py --upload-dar .daml/dist/monoton-0.0.1.dar

# Allocate parties
python3 scripts/devnet_client.py --allocate-parties
```

### Start REST API

```bash
cd api
npm install
npm run dev
# API running at http://localhost:3000
```

---

## 🧪 Integration Tests

### Test Scenarios (11 total)

| Test | Description | Sandbox | Devnet |
|------|-------------|---------|--------|
| `testBusinessRegistration` | Business onboarding | ✅ | ⚠️ |
| `testSettlementDelegation` | Path A authorization | ✅ | ⚠️ |
| `testInvoiceLifecycle` | Full invoice lifecycle | ✅ | ⚠️ |
| `testHoldingTransfer` | Token transfer | ✅ | ⚠️ |
| `testBatchMint` | Batch minting | ✅ | ⚠️ |

⚠️ = Would work if commands were enabled

### Run Specific Test

```bash
daml test --color never test/daml/Test.daml:testBusinessRegistration
```

---

## 📡 REST API (TypeScript)

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| POST | `/auth/login` | Get JWT token |
| GET | `/v1/invoices` | List invoices |
| POST | `/v1/invoices` | Create invoice |
| GET | `/v1/invoices/:id` | Get invoice |
| POST | `/v1/invoices/:id/approve` | Approve invoice |
| POST | `/v1/invoices/:id/settle` | Settle (Path A) |
| GET | `/v1/wallet/balance` | Wallet balance |
| POST | `/v1/wallet/mint` | Mint test tokens |

### Example Request

```bash
curl -X POST http://localhost:3000/v1/invoices \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "buyer": "BuyerParty",
    "amount": 1000.00,
    "description": "Invoice #12345"
  }'
```

---

## 🐳 Docker Validator Setup

### Pull Images

```bash
# Canton Open Source
docker pull digitalasset/canton-open-source:latest

# Splice Validator
docker pull ghcr.io/digital-asset/decentralized-canton-sync/helm/splice-validator:0.6.11
```

### Local Sandbox (Recommended for Development)

```bash
docker run -d \
  --name canton-sandbox \
  -p 5001:5001 \
  -p 5002:5002 \
  digitalasset/canton-open-source:latest
```

### Full Docker Compose

See [RUN-VALIDATOR.md](RUN-VALIDATOR.md) for complete setup.

---

## 🔍 Research Findings

### Command Submission Issue

Devnet has **command submission disabled at the domain level**. This means:
- Even with your own participant
- Even with proper authorization
- The sequencer/domain rejects transactions

### Why Local Sandbox Works

The local sandbox runs its **own domain** that:
- Accepts all commands
- Processes transactions locally
- Provides full Canton functionality

### Solutions for Production

1. **Run your own Canton network** (validator + domain)
2. **Request command access** from Devnet operators
3. **Use local sandbox** for development

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [RESEARCH-COMMAND-SUBMISSION.md](RESEARCH-COMMAND-SUBMISSION.md) | JSON API research, error codes |
| [RUN-VALIDATOR.md](RUN-VALIDATOR.md) | Docker validator setup |
| [ARCHITECTURE-ANALYSIS.md](ARCHITECTURE-ANALYSIS.md) | System architecture |
| [PROTOCOL-FLOW.md](PROTOCOL-FLOW.md) | Settlement protocol details |
| [INTEGRATION-TEST-REQUIREMENTS.md](INTEGRATION-TEST-REQUIREMENTS.md) | Test requirements |
| [monoton-agentic-commerce-api.md](monoton-agentic-commerce-api.md) | API specification |

---

## 🔗 External Resources

### Canton Network
- [Canton Documentation](https://docs.canton.network/)
- [JSON API Reference](https://docs.canton.network/reference/json-api-reference/post-v2commandssubmit-and-wait)
- [Error Codes](https://docs.canton.network/appdev/troubleshooting-guide/error-code-reference)
- [Token Standard (CIP-0056)](https://docs.canton.network/appdev/deep-dives/token-standard)

### Community
- [Canton Forum](https://forum.canton.network/)
- [cn-quickstart](https://github.com/digital-asset/cn-quickstart)
- [Splice Network](https://docs.sync.global/)

---

## 📊 GitHub

- **Repository**: https://github.com/uuzor/monotron
- **Branch**: `daml-smart-contracts`
- **PR**: [#1](https://github.com/uuzor/monotron/pull/1) - Main development branch

---

## ⚠️ Known Limitations

1. **Devnet Command Submission** - Disabled (404) - Development must use local sandbox
2. **Path A Only** - Single atomic batch settlement model
3. **Canton Token Standard** - Requires utility-registry packages v0.12.5+

---

## 🚢 Deployment Notes

### What Works Now

- ✅ Build smart contracts (Daml)
- ✅ Run tests on local sandbox
- ✅ Upload DAR to Devnet
- ✅ Allocate parties on Devnet
- ✅ Query ledger state on Devnet

### What Needs Work

- ❌ Submit transactions to Devnet (domain disabled)
- ❌ End-to-end settlement on Devnet
- ❌ Production deployment

---

*Built with Daml 3.5.2 for the Canton Network*
