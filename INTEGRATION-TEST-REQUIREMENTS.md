# Monoton Integration Test Requirements

## Overview

This document describes what's needed to run a complete Path A settlement flow integration test against Canton Devnet.

## What's Tested in Unit Tests

Our current unit tests (11 tests, all passing) verify:

| Test | What It Verifies |
|------|------------------|
| `testBusinessRegistration` | Creating BusinessRegistration contracts |
| `testBusinessSuspension` | Suspending/reactivating businesses |
| `testBusinessCannotBeOwnOperator` | Authorization constraints |
| `testSettlementDelegation` | Creating delegation contracts |
| `testDelegationRevocation` | Seller revoking delegation |
| `testDelegationPauseResume` | Operator pause/resume |
| `testInvoiceLifecycle` | Full state machine (Created→Approved) |
| `testInvoiceRejection` | Buyer rejection path |
| `testSellerCannotApproveOwnInvoice` | Authorization constraints |
| `testCannotSettleBeforeInitiation` | State transition validation |
| `testSettlementCancellation` | Cancellation flow |

## What's NOT Tested (Requires Devnet)

The following **cannot be tested in unit tests** because they require real Canton Token Standard contracts:

### 1. Invoice_ConfirmSettled Security Verification

```daml
choice Invoice_ConfirmSettled : ContractId Invoice
  with
    settledHoldingCid : ContractId Holding
    transferResult : TransferInstructionResult
  controller operator
  do
    -- These checks require REAL contracts:
    assert (holdingView.owner == seller)           -- Real Holding owner
    assert (holdingView.amount == amount)          -- Real Holding amount
    assert (holdingView.instrumentId.admin == instrumentAdmin)  -- Real admin
```

**Why unit tests can't do this:**
- We need `ContractId Holding` from a real Holding contract
- We need `TransferInstructionResult` from a real `TransferInstruction_Accept` call
- These only exist when:
  1. TransferFactory exists on ledger
  2. Holding contracts exist with instrumentAdmin authority

### 2. Full Path A Settlement Batch

The complete Path A atomic batch requires:

```json
{
  "commands": [
    {
      "commandType": "exercise",
      "templateId": "TransferFactory:...",
      "choice": "TransferFactory_Transfer",
      "argument": { ... }
    },
    {
      "commandType": "exercise", 
      "templateId": "TransferInstruction:...",
      "choice": "TransferInstruction_Accept"
    },
    {
      "commandType": "exercise",
      "templateId": "Invoice:...",
      "choice": "Invoice_ConfirmSettled",
      "argument": {
        "settledHoldingCid": "<real holding cid>",
        "transferResult": "<real result>"
      }
    }
  ],
  "actAs": ["buyer", "operator"]
}
```

## Devnet Setup Requirements

### 1. Upload DARs to Participant

```bash
# Connect to Devnet participant
canton --config devnet.conf

# Upload utility-registry packages
participant.upload_dar("utility-registry-v0-0.6.0.dar")
participant.upload_dar("utility-registry-holding-v0-0.2.1.dar")
participant.upload_dar("utility-registry-app-v0-0.7.0.dar")
participant.upload_dar("monotron-main-0.0.1.dar")
```

### 2. Create Instrument Admin Party

The instrumentAdmin must:
- Have a key on the participant
- Be authorized to create TransferFactory contracts

### 3. Create TransferFactory

```daml
-- Via Canton console or API
TransferFactory_Create with
  admin = instrumentAdmin
  -- other required fields from Token Standard
```

### 4. Create Holding Contracts for Buyer

```daml
-- Via registry API or direct contract creation
Mint with
  holder = buyer
  amount = 10000.00  -- Give buyer enough to cover invoices
  instrumentId = InstrumentId with
    admin = instrumentAdmin
    id = "CC"  -- Canton Coin
```

### 5. Run Full Integration Test

```bash
./scripts/run-integration-test.sh
```

## Integration Test Script

See `scripts/run-integration-test.sh` for the automated test script.

## Manual Test Steps (Canton Console)

```scala
// 1. Allocate parties
val operator = participant1.allocateParty("Operator")
val seller = participant1.allocateParty("Seller")  
val buyer = participant1.allocateParty("Buyer")
val instrumentAdmin = participant1.allocateParty("CantonCoin")

// 2. Create Settlement Delegation
val delegationCid = seller.create(
  SettlementDelegation(
    seller = seller,
    operator = operator,
    scope = "invoice-settlement",
    validFrom = ...,
    validUntil = ...,
    active = true
  )
)

// 3. Create Invoice
val invoiceCid <- seller.create(
  Invoice(
    seller = seller,
    buyer = buyer,
    operator = operator,
    amount = 1000.00,
    currency = "USD",
    ...
  )
)

// 4. Approve
val approvedCid <- buyer.exercise(
  invoiceCid : Invoice_Approve
)

// 5. PATH A SETTLEMENT
// This is where Devnet is required - need real TransferFactory

// 6. Verify settlement
val settledInvoice <- operator.query(Invoice)
assert(settledInvoice.status == Settled)
```

## Test Results to Capture

When running integration tests on Devnet, document:

1. **State transitions**: Created → Approved → AwaitingSettlement → Settled
2. **Holdings before/after**: Buyer's balance decreases, Seller's increases
3. **Atomicity**: Transaction succeeds or fails completely
4. **Security verification**: Fake Holding rejected by instrumentAdmin check

## Running Tests Locally vs Devnet

| Test Type | Location | What It Tests |
|-----------|----------|---------------|
| Unit Tests | `dpm test` | Template logic, state machines, authorization |
| Sandbox Tests | `dpm sandbox` + script | Multi-contract flows without Token Standard |
| Devnet Tests | Devnet deployment | Full Path A with real Token Standard |

## Status

| Component | Unit Test | Sandbox | Devnet |
|-----------|----------|--------|--------|
| BusinessRegistration | ✅ | ✅ | Pending |
| SettlementDelegation | ✅ | ✅ | Pending |
| Invoice state machine | ✅ | ✅ | Pending |
| Invoice_Approve | ✅ | ✅ | Pending |
| TransferFactory setup | ❌ | ❌ | Pending |
| Holding creation | ❌ | ❌ | Pending |
| Path A batch settlement | ❌ | ❌ | Pending |
| Invoice_ConfirmSettled | ❌ | ❌ | Pending |
| Security verification | ❌ | ❌ | Pending |
