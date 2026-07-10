# Monoton Agentic Commerce API

REST API for B2B invoice settlement on Canton, enabling AI agents and SaaS platforms to create, approve, and settle invoices programmatically.

## Architecture

This API is a thin REST layer in front of the Daml Ledger API. It implements the **Agentic Commerce API** design from `monoton-agentic-commerce-api.md`.

### Key Design Decisions

1. **JSON Ledger API**: HTTP/JSON for interoperability with agents and external systems
2. **OAuth2/JWT Auth**: Short-lived tokens scoped to `canActAs(party)`
3. **Per-Business Parties**: Each business gets its own Canton party, not shared credentials
4. **Path A Settlement**: Atomic batch transactions for settlement

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/health/ready` | Readiness check (verifies ledger) |
| POST | `/v1/invoices` | Create invoice |
| GET | `/v1/invoices/:id` | Get invoice details |
| GET | `/v1/invoices` | List invoices |
| POST | `/v1/invoices/:id/approve` | Approve invoice |
| POST | `/v1/invoices/:id/settle` | Settle invoice (Path A) |
| GET | `/v1/wallet/balance` | Get wallet balance |
| GET | `/v1/wallet/holdings` | List holdings |
| POST | `/v1/wallet/fund` | Fund wallet (dev only) |

## Setup

### Prerequisites

- Node.js 18+
- DPM SDK installed
- Daml ledger (Sandbox or Devnet)

### Installation

```bash
cd api
npm install
```

### Generate Daml Types

Before running, generate TypeScript types from the Daml DAR:

```bash
npm run codegen
```

### Configuration

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

Required environment variables:

- `LEDGER_HOST`: Daml ledger host
- `LEDGER_PORT`: Daml ledger port
- `AUTH_ISSUER`: OAuth2/JWT issuer URL

### Running

Development:
```bash
npm run dev
```

Production:
```bash
npm run build
npm start
```

## Authentication

The API uses OAuth2 client-credentials JWT tokens. Each token must contain:

- `sub`: The Canton party ID
- `scope`: `canActAs:<partyId>` claim

Example JWT payload:
```json
{
  "sub": "SellerParty",
  "scope": "canActAs:SellerParty",
  "aud": "monoton-api",
  "iss": "https://auth.example.com"
}
```

In development mode, you can use the `generateDevToken()` helper or omit the token to use a default test party.

## API Examples

### Create Invoice

```bash
curl -X POST http://localhost:3000/v1/invoices \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "buyer": "BuyerParty",
    "amount": 1000.00,
    "currency": "CC",
    "description": "Consulting services"
  }'
```

### Approve Invoice

```bash
curl -X POST http://localhost:3000/v1/invoices/INV-123/approve \
  -H "Authorization: Bearer $TOKEN"
```

### Settle Invoice (Path A)

```bash
curl -X POST http://localhost:3000/v1/invoices/INV-123/settle \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"autoMerge": true}'
```

### Get Wallet Balance

```bash
curl http://localhost:3000/v1/wallet/balance \
  -H "Authorization: Bearer $TOKEN"
```

## Path A Settlement Flow

Path A settlement (from `monoton-wallet-invoice-lifecycle.md`) uses a single atomic batch transaction:

1. **TransferFactory_Transfer**: Creates pending TransferInstruction
2. **TransferInstruction_Accept**: Moves Holdings from buyer to seller
3. **Invoice_ConfirmSettled**: Marks invoice as settled

All three execute in one Canton transaction - all succeed or all roll back.

## Development

### Testing

```bash
npm test
```

### Type Checking

```bash
npm run build
```

## Related Documents

- `monoton-build-plan.md` - Overall build plan
- `monoton-wallet-invoice-lifecycle.md` - Token Standard integration
- `monoton-agentic-commerce-api.md` - API design rationale
- `PROTOCOL-FLOW.md` - Settlement protocol details
