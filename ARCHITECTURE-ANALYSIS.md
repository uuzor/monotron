# Monoton Architecture Analysis

**Generated: 2026-07-09**

---

## Executive Summary

This document analyzes what has been built, what remains to be built, what has been verified/tested, and explains the underlying architecture for privacy and the Canton Token Standard integration.

---

## Part 1: What Has Been Built ✅

### Smart Contracts (Daml Templates)

| Template | Status | Description |
|----------|--------|-------------|
| **Invoice** | ✅ Built | Core B2B invoice with 5-state lifecycle: Created → Approved → AwaitingSettlement → Settled/Rejected |
| **BusinessRegistration** | ✅ Built | Onboarding template proving a party is a valid Monoton counterparty |
| **SettlementDelegation** | ✅ Built | Path A authorization - seller pre-authorizes operator to accept transfers |
| **TransferInstruction** | ✅ Integrated | Using real CIP-0056 interface from `Splice.Api.Token.TransferInstructionV1` |

### Data Dependencies (Utility Registry Packages)

| Package | Version | Purpose |
|---------|---------|---------|
| `splice-api-token-transfer-instruction-v1` | 1.0.0 | CIP-0056 TransferInstruction interface |
| `splice-api-token-metadata-v1` | 1.0.0 | Metadata types for transfers |
| `splice-api-token-holding-v1` | 1.0.0 | Holding interface (wallet balance) |
| `utility-registry-v0` | 0.6.0 | Registry core (TransferRule, etc.) |
| `utility-registry-holding-v0` | 0.2.1 | Holding implementations |
| `utility-registry-app-v0` | 0.7.0 | App workflows (AllocationFactory, etc.) |

### Test Suite

| Test | Status | What It Verifies |
|------|--------|------------------|
| `testBusinessRegistration` | ✅ Pass | Creating and registering a business |
| `testBusinessSuspension` | ✅ Pass | Suspending an active business |
| `testBusinessCannotBeOwnOperator` | ✅ Pass | Authorization constraint |
| `testSettlementDelegation` | ✅ Pass | Creating delegation contract |
| `testDelegationRevocation` | ✅ Pass | Seller revoking delegation |
| `testDelegationPauseResume` | ✅ Pass | Operator pausing/resuming |
| `testInvoiceLifecycle` | ✅ Pass | Full invoice lifecycle |
| `testInvoiceRejection` | ✅ Pass | Buyer rejecting invoice |
| `testSellerCannotApproveOwnInvoice` | ✅ Pass | Authorization constraint |
| `testCannotSettleBeforeInitiation` | ✅ Pass | State transition constraint |
| `testSettlementCancellation` | ✅ Pass | Operator canceling settlement |

**All 11 tests pass.**

---

## Part 2: What Remains To Be Built 🔲

### Smart Contracts (Not Built)

| Template | Priority | Notes |
|----------|----------|-------|
| **Allocation/AllocationInstruction** | 🔲 Optional | DVP workflow - flagged in §5 as potential improvement over plain Transfer. Not needed for demo. |
| **Dispute/Refund path** | 🔲 Not Built | Out of hackathon scope per docs |
| **Fee/Treasury contracts** | 🔲 Not Built | Out of hackathon scope |
| **Custom instrument minting** | 🔲 Not Built | Per docs: "ride on Devnet Canton Coin" for hackathon |

### API Layer

| Endpoint | Status | Notes |
|----------|--------|-------|
| `POST /v1/invoices` | 🔲 Not Built | Needs JSON Ledger API integration |
| `POST /v1/invoices/{id}/approve` | 🔲 Not Built | Needs JSON Ledger API integration |
| `POST /v1/invoices/{id}/settle` | 🔲 Not Built | Path A batch transaction |
| `GET /v1/invoices/{id}` | 🔲 Not Built | ACS query filtered by party |
| `GET /v1/wallet/balance` | 🔲 Not Built | Sum Holdings by instrument |

### Infrastructure

| Component | Status | Notes |
|----------|--------|-------|
| **Keycloak/OAuth2 setup** | 🔲 Not Built | Per-business JWT credentials |
| **JSON Ledger API wrapper** | 🔲 Not Built | TypeScript codegen via `dpm codegen-js` |
| **TransferFactory setup** | 🔲 Not Built | Needs registry API calls |
| **MergeDelegation setup** | 🔲 Not Built | For UTXO count management |

### Devnet Deployment

| Task | Status | Notes |
|------|--------|-------|
| **Deploy to Canton Devnet** | 🔲 Not Done | Required for hackathon submission |
| **Upload utility DARs to participant** | 🔲 Not Done | Pre-requisite for deployment |
| **Create TransferFactory contracts** | 🔲 Not Done | Via registry HTTP API |
| **Verify Path A batch transaction** | 🔲 Not Tested | Integration test needed |

---

## Part 3: Privacy Architecture

### Why Daml's Signatory/Observer Model Provides Privacy

The core privacy guarantee comes from Daml's **authorization model**:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Daml Authorization Model                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  template Invoice                                                │
│    signatory seller      ← ONLY these parties can author        │
│    observer buyer, operator  ← Can see, but not modify          │
│                                                                  │
│  KEY RULE: "Only signatories + observers can ever see a         │
│            contract" (Daml Language Reference)                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### What This Means Practically

| Party | Can See Invoice? | Can Modify Invoice? |
|-------|-----------------|---------------------|
| **Seller** | ✅ Yes (signatory) | ✅ Yes (signatory) |
| **Buyer** | ✅ Yes (observer) | ✅ Can exercise choices (controller) |
| **Operator** | ✅ Yes (observer) | ✅ Can exercise choices (controller) |
| **Other Monoton users** | ❌ No | ❌ No |
| **Other businesses** | ❌ No | ❌ No |
| **Monoton employees** | ❌ No | ❌ No |

### Why This Is Structurally Enforced

```
┌────────────────────────────────────────────────────────────────┐
│  WRONG: "We promise not to show you the data"                  │
│     ↑ Application-level promise you must trust                   │
├────────────────────────────────────────────────────────────────┤
│  RIGHT: Daml's signatory/observer model                        │
│     ↑ Ledger ENFORCES this structurally                         │
│     No API endpoint, database query, or employee action          │
│     can reveal this contract to non-observers                  │
└────────────────────────────────────────────────────────────────┘
```

### Comparison: Custom Wallet vs Token Standard

| Aspect | Custom Wallet Design (Old) | Token Standard (Current) |
|--------|---------------------------|------------------------|
| Privacy | ✅ Invoice private | ✅ Invoice private |
| Balance visibility | Visible only to owner | Same (Holding interface) |
| Transfer authorization | Monoton controls both sides | Ledger enforces multi-party auth |
| Interoperability | Monoton-only | Any Token Standard wallet |
| Atomic settlement | ✅ One choice body | ⚠️ Requires Path A batching |

---

## Part 4: Why Utility Registry, TransferFactory, etc.?

### The Problem: How Do Tokens Move?

On Canton, **tokens are contracts**. To transfer tokens:

1. You don't "call a function" to move value
2. You **exercise a choice on a contract** that moves the Holding
3. This requires authorization from the parties involved

### The Canton Token Standard (CIP-0056) Solution

```
┌─────────────────────────────────────────────────────────────────┐
│                 Canton Token Standard Architecture                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐                                               │
│  │   Holding    │  ← A contract representing tokens             │
│  │  (UTXO)      │    - Owner party                              │
│  │              │    - Amount                                   │
│  │              │    - InstrumentId (what kind of token)        │
│  └──────────────┘                                               │
│         ↑                                                       │
│         │ Transferred by                                         │
│         ↓                                                       │
│  ┌──────────────┐                                               │
│  │TransferInstruction│  ← Pending transfer (proposal→accept)     │
│  │                  │    - Created by TransferFactory           │
│  │                  │    - Accept/Reject/Withdraw choices        │
│  └──────────────┘                                               │
│         ↑                                                       │
│         │ Created by                                            │
│         ↓                                                       │
│  ┌──────────────┐                                               │
│  │TransferFactory│  ← Contract that creates TransferInstructions  │
│  │               │    - One per instrument per registry         │
│  │               │    - Exercised by sender to initiate          │
│  └──────────────┘                                               │
│                                                                  │
│  WHO CONTROLS THIS?                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Instrument Admin (or Registry Provider)                   │   │
│  │   - Deploys the Holding contracts                         │   │
│  │   - Provides TransferFactory contracts                    │   │
│  │   - For Devnet Canton Coin: Amulet (DA) is admin          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why We Need Each Component

#### 1. Why Upload Utility Registry DARs?

```
┌─────────────────────────────────────────────────────────────────┐
│ QUESTION: Why can't Monoton just define its own transfer logic? │
├─────────────────────────────────────────────────────────────────┤
│ ANSWER: Interoperability                                         │
│                                                                  │
│ If Monoton rolls its own transfer:                               │
│  - Only Monoton's own wallet can understand transfers            │
│  - Other Canton wallets/explorers can't see your balances        │
│  - You rebuild tooling that already exists                       │
│                                                                  │
│ If Monoton uses Token Standard:                                   │
│  - Any CIP-0056 wallet can view Monoton's transfers             │
│  - Standard explorers work out of the box                        │
│  - Integration with other Canton apps is trivial                 │
└─────────────────────────────────────────────────────────────────┘
```

The utility-registry packages contain:
- **Holding implementations** - How tokens are represented as contracts
- **TransferRule** - The rules that execute transfers
- **App workflows** - AllocationFactory for mint/burn/transfer

#### 2. Why TransferFactory?

```
┌─────────────────────────────────────────────────────────────────┐
│ TransferFactory: "Where do transfer instructions come from?"      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Monoton CAN'T just create TransferInstructions directly because: │
│                                                                  │
│  1. TransferInstructions must be authorized by the instrument    │
│     admin (or their authorized factory)                          │
│                                                                  │
│  2. The factory is a CONTRACT on the ledger - you exercise it   │
│                                                                  │
│  3. Exercising TransferFactory_Transfer:                         │
│     - Creates a new TransferInstruction contract                 │
│     - Locks in the transfer terms                                │
│     - Makes it visible to the receiver                          │
│                                                                  │
│  Without TransferFactory:                                        │
│     - No way to create legitimate transfer instructions           │
│     - Each instrument would need custom logic                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 3. Why Path A (Atomic Batch)?

```
┌─────────────────────────────────────────────────────────────────┐
│ The Settlement Problem                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  With Token Standard, settling an invoice requires:                │
│                                                                  │
│  Step 1: Buyer initiates transfer (creates TransferInstruction)   │
│           └─→ Submitter: Buyer                                   │
│           └─→ Auth: Buyer signs                                  │
│                                                                  │
│  Step 2: Seller accepts transfer (moves the Holding)             │
│           └─→ Submitter: Seller (or operator on behalf)          │
│           └─→ Auth: Seller must sign (or pre-authorized)        │
│                                                                  │
│  Step 3: Operator marks invoice settled                           │
│           └─→ Submitter: Operator                                 │
│                                                                  │
│  PROBLEM: These are 3 separate transactions by default            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Path A Solution: Batch in One Transaction**

```
┌─────────────────────────────────────────────────────────────────┐
│ Canton Batch Transaction                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Single API call contains:                                        │
│                                                                  │
│  commands: [                                                     │
│    { exercise: TransferFactory_Transfer, ... },                  │
│    { exercise: TransferInstruction_Accept, ... },                  │
│    { exercise: Invoice_ConfirmSettled, ... }                     │
│  ]                                                               │
│                                                                  │
│  actAs: [buyer, operator]  ← operator acting for seller via       │
│                               SettlementDelegation               │
│                                                                  │
│  Result: ALL or NOTHING - atomic settlement                      │
│                                                                  │
│  WHY "ALL or NOTHING" matters:                                    │
│  - Invoice shows "Settled" ONLY if transfer actually completed    │
│  - No partial states (money moved but invoice not marked)        │
│  - No race conditions                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 4. Why SettlementDelegation?

```
┌─────────────────────────────────────────────────────────────────┐
│ SettlementDelegation: "How can operator act for seller?"           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  For Path A batch, operator needs to accept on seller's behalf.   │
│  But Canton authorization requires:                               │
│                                                                  │
│  1. The party (or someone with canActAs) signs the command      │
│  2. canActAs is a JWT claim - application-level trust            │
│                                                                  │
│  SettlementDelegation makes this a LEDGER FACT:                  │
│                                                                  │
│  template SettlementDelegation                                   │
│    signatory seller        ← SELLER is the signatory!           │
│    observer operator                                                │
│                                                                  │
│  choice Delegation_Revoke                                        │
│    controller seller      ← SELLER can revoke at any time        │
│                                                                  │
│  BENEFIT:                                                        │
│  - Without: "Monoton says we can act for you" (JWT promise)       │
│  - With: "The ledger shows seller authorized Monoton" (fact)      │
│  - Seller can revoke instantly - no JWT expiry to wait for        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### The Complete Settlement Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                 Complete Path A Settlement Flow                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PHASE 1: Setup (one-time, at business onboarding)              │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  1. Business registers:                                         │
│     └─→ Create BusinessRegistration contract                     │
│                                                                  │
│  2. Business authorizes Monoton:                                │
│     └─→ Create SettlementDelegation (signatory: seller)         │
│                                                                  │
│  PHASE 2: Invoice Lifecycle (per invoice)                        │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  1. Seller creates invoice:                                      │
│     └─→ Create Invoice (status: Created)                        │
│                                                                  │
│  2. Buyer approves:                                              │
│     └─→ Exercise Invoice_Approve (status: Approved)              │
│                                                                  │
│  3. Buyer initiates settlement:                                   │
│     └─→ Call registry API to create TransferInstruction          │
│     └─→ Exercise Invoice_InitiateSettlement (status: Awaiting)   │
│                                                                  │
│  PHASE 3: Settlement (atomic batch)                            │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  4. Single API call:                                             │
│                                                                  │
│     POST /v2/commands/submit-and-wait                          │
│     {                                                           │
│       "commands": [                                             │
│         { "exercise": TransferFactory_Transfer, ... },           │
│         { "exercise": TransferInstruction_Accept, ... },         │
│         { "exercise": Invoice_ConfirmSettled, ... }             │
│       ],                                                        │
│       "actAs": ["buyer", "operator"]                            │
│     }                                                           │
│                                                                  │
│     Result: ALL in ONE transaction                                │
│             - Holding moves from buyer to seller                 │
│             - Invoice marked Settled                            │
│             - Either ALL succeed or ALL rollback                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Part 5: What Has Been Verified/Tested ✅

### Unit Tests (✅ All Pass)
- Template logic (state transitions)
- Authorization constraints
- Business lifecycle
- Delegation lifecycle

### NOT Yet Tested ❌

| Test | Status | Required For |
|------|--------|-------------|
| Integration with real Canton ledger | ❌ Not Tested | Hackathon demo |
| Path A batch transaction | ❌ Not Tested | Core settlement demo |
| TransferFactory API calls | ❌ Not Tested | Real settlement |
| BusinessRegistration enforcement | ❌ Not Tested | Onboarding flow |
| SettlementDelegation enforcement | ❌ Not Tested | Path A authorization |
| Privacy enforcement | ❌ Not Tested | Privacy demo claim |

---

## Part 6: Build Sequence (Per Documentation)

| Day | Deliverable | Status |
|-----|-------------|--------|
| 1 | Invoice template (revised), data-dependencies, local tests | ✅ Done |
| 1 | Decide instrument choice (ride on Devnet vs. mint own) | ✅ Done: Ride on Devnet Canton Coin |
| 1 | Spike: Allocation/DVP vs plain Transfer | 🔲 Not Done |
| 2 | Agentic Commerce API (create, approve, settle, balance) | 🔲 Not Built |
| 2 | Manual curl tests against Devnet | 🔲 Not Done |
| 3 | Frontend + scripted agent client | 🔲 Not Built |
| 3 | MergeDelegation setup | 🔲 Not Built |
| 4 | Deploy on Devnet (NOT LocalNet/sandbox) | 🔲 Not Done |
| 4 | Demo video + repo cleanup + deck | 🔲 Not Done |

---

## Summary

### ✅ Built
1. Daml templates: Invoice, BusinessRegistration, SettlementDelegation
2. Real Token Standard integration (CIP-0056 TransferInstruction)
3. All utility-registry DARs downloaded and configured
4. 11 unit tests passing
5. Build system (dpm) working with multi-package setup

### 🔲 Not Built
1. Agentic Commerce API layer
2. Keycloak/OAuth2 setup
3. Devnet deployment
4. Integration tests (Path A batch)
5. Frontend

### 🔑 Key Architectural Points

1. **Privacy is structural** - Daml's signatory/observer model, not application code
2. **Token Standard for interoperability** - Can't build own transfer logic and claim network benefits
3. **TransferFactory is required** - Can only create transfers through authorized factory contracts
4. **Path A enables atomicity** - Batch multiple exercises in one transaction
5. **SettlementDelegation makes authorization a ledger fact** - Not just a JWT claim
