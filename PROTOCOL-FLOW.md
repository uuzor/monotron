# Monoton: Full Protocol Flow Sketch

**How money moves on Canton: Holdings, not accounts. Two-phase transfer, no custodial escrow.**

---

## IMPORTANT CORRECTION: There IS a Locked State

```
┌─────────────────────────────────────────────────────────────────┐
│              CORRECTION: The "No Escrow" Claim                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ❌ INCORRECT: "No locked state"                               │
│     ─────────────────────────────                               │
│     The TransferInstruction IS a locked, in-between state.         │
│     When TransferFactory_Transfer is called:                     │
│     1. Buyer's input Holding(s) are CONSUMED (archived)        │
│     2. Value sits INSIDE the pending TransferInstruction         │
│     3. Value is locked until Accept/Reject/Withdraw             │
│                                                                  │
│  ✅ CORRECT: "No custodial escrow"                              │
│     ─────────────────────────────────                           │
│     No third party holds the funds.                              │
│     The TransferInstruction contract itself enforces the         │
│     two-phase commit. No admin can seize or redirect.          │
│                                                                  │
│  DIFFERENCE MATTERS:                                            │
│  "No custodial escrow" = True and is the differentiator         │
│  "No locked state"    = False, and someone technical            │
│                          will catch it in Q&A                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Core Concept: On-Canton "Money" Is Different

```
┌─────────────────────────────────────────────────────────────────┐
│            Traditional Finance (Bank Model)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│    Buyer Account          Escrow/Contract          Seller Account │
│    ┌─────────┐           ┌─────────────┐          ┌─────────┐   │
│    │ $10,000 │  ──────► │   Escrow    │ ──────► │ $0      │   │
│    │ balance │   hold   │   holds     │ release  │ balance │   │
│    └─────────┘   funds   │   funds     │          └─────────┘   │
│                                                                  │
│    Bank intermediates. Third party holds funds.                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│            Canton Token Standard (Two-Phase Transfer)                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PHASE 1: Create TransferInstruction                            │
│  ─────────────────────────────────────────────                  │
│  ┌─────────────────┐                                           │
│  │  TransferInstruction │ ← VALUE LOCKED HERE                   │
│  │  (pending)         │   Buyer's Holding(s) consumed          │
│  │                     │   Value held by contract               │
│  │  sender: Buyer    │                                       │
│  │  receiver: Seller │   No third party can access            │
│  │  amount: 1000    │   Contract enforces two-phase           │
│  │  status: Pending │                                       │
│  └─────────────────┘                                           │
│                                                                  │
│  PHASE 2: Accept → Resolve                                     │
│  ──────────────────────────                                      │
│                                                                  │
│  ACCEPT:                                                         │
│  ┌─────────────────┐    ┌─────────────────┐                     │
│  │ TransferInstruction │──►│ NEW Holding    │                     │
│  │ (archived)         │    │ owner: Seller │                     │
│  │                    │    │ amount: 1000 │                     │
│  │                    │    └─────────────────┘                     │
│  └─────────────────┘                                           │
│                                                                  │
│  REJECT/WITHDRAW:                                               │
│  ┌─────────────────┐    ┌─────────────────┐                     │
│  │ TransferInstruction │──►│ ORIGINAL HOLDING│                   │
│  │ (archived)         │    │ returns to     │                   │
│  │                    │    │ buyer          │                   │
│  └─────────────────┘    └─────────────────┘                     │
│                                                                  │
│  KEY: No third party custodies funds.                           │
│       The instruction contract itself enforces escrow.            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Onboarding a Business

```
┌─────────────────────────────────────────────────────────────────┐
│                    BUSINESS ONBOARDING FLOW                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  MONOTON OPERATOR                           NEW BUSINESS          │
│        │                                         │               │
│        │  1. Create Canton Party                 │               │
│        │─────────────────────────────────────────►               │
│        │                                         │               │
│        │  2. Issue OAuth2 credentials           │               │
│        │     (JWT with canActAs/bizParty)        │               │
│        │─────────────────────────────────────────►               │
│        │                                         │               │
│        │  3. Create BusinessRegistration        │               │
│        │     (operator is signatory)             │               │
│        │─────────────────────────────────────────►               │
│        │                                         │               │
│        │                                         │               │
│  NOTES:                                                              │
│  • Business gets a CANTON PARTY, not just an account           │
│  • JWT allows the business to act AS their own party             │
│  • BusinessRegistration proves business is "verified"             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  ON-LEDGER: What Gets Created                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Contract: BusinessRegistration                                   │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │  business : "AliceCorp::participant1"   ← Canton party    │     │
│  │  operator : "Monoton::participant1"                    │     │
│  │  status   : Active                                    │     │
│  │                                                         │     │
│  │  signatory: operator (Monoton)                         │     │
│  │  observer:  business (AliceCorp)                       │     │
│  └─────────────────────────────────────────────────────────┘     │
│                                                                  │
│  What this does NOT do:                                          │
│  • Does NOT give AliceCorp any tokens                            │
│  • Does NOT create a "balance" for AliceCorp                   │
│  • Just proves AliceCorp is a valid Monoton counterparty        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 2: Funding a Business (Getting Holdings)

**Critical question: Where does the money come from?**

```
┌─────────────────────────────────────────────────────────────────┐
│                    FUNDING OPTIONS                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  OPTION A: Ride on Existing Instrument (Canton Coin Devnet)     │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  The instrument (Canton Coin) already exists.                   │
│  Business needs to acquire Holdings of that instrument.           │
│                                                                  │
│  Ways to get Holdings:                                           │
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │ Devnet       │    │ Another     │    │ Mint (if you're    │ │
│  │ Faucet       │───►│ Business    │───►│ the instrument     │ │
│  │ (free test   │    │ (existing   │    │ admin) - V2 only  │ │
│  │ tokens)      │    │ Holdings)   │    │                    │ │
│  └─────────────┘    └─────────────┘    └─────────────────────┘ │
│       │                    │                     │              │
│       ▼                    ▼                     ▼              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              NEW HOLDING CONTRACTS                       │    │
│  │                                                         │    │
│  │  ┌────────────────┐   ┌────────────────┐                │    │
│  │  │ Holding #1     │   │ Holding #2     │                │    │
│  │  │ owner: Alice  │   │ owner: Bob    │                │    │
│  │  │ amount: 5000   │   │ amount: 3000   │                │    │
│  │  │ instrument: CC │   │ instrument: CC │                │    │
│  │  └────────────────┘   └────────────────┘                │    │
│  │                                                         │    │
│  │  CC = Canton Coin (the Devnet test instrument)          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  OPTION B: Mint Own Instrument (V2 / Production)               │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  Monoton becomes instrument admin. Issues tokens against        │
│  fiat reserves. Business gets Holdings of "MonotonUSD".         │
│                                                                  │
│  This requires:                                                 │
│  • Monoton deploying own registry contracts                     │
│  • KYC/AML before minting                                      │
│  • NOT for hackathon - ride on Devnet instead                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### How a Holding Actually Looks on-Ledger

```
┌─────────────────────────────────────────────────────────────────┐
│                  HOLDING CONTRACT (On-Ledger)                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Contract: Holding (implements Holding interface)                │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                                                         │    │
│  │  owner          : Party      ← Who owns these tokens   │    │
│  │  instrumentId    : Instrument ← What kind of tokens     │    │
│  │    .id          : Text        ← "CC" or "MonotonUSD"   │    │
│  │    .admin       : Party      ← Who issued this token   │    │
│  │  amount         : Decimal     ← How many tokens         │    │
│  │                                                         │    │
│  │  signatory: [owner, instrumentAdmin]                    │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  KEY INSIGHT:                                                   │
│  A Holding IS money. Not a record OF money.                    │
│  Transferring money = archiving one Holding, creating another   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 3: Invoice Creation to Settlement

```
┌─────────────────────────────────────────────────────────────────┐
│              FULL INVOICE LIFECYCLE (BEFORE Settlement)             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SELLER (AliceCorp)         CANTON LEDGER           BUYER (BobCo) │
│        │                         │                      │      │
│        │ 1. Create Invoice       │                      │      │
│        │─────────────────────────►                      │      │
│        │                         │                      │      │
│        │                         │ 2. Buyer approves    │      │
│        │                         │◄───────────────────────────│ │
│        │                         │                      │      │
│        │                         │        Invoice Status:     │
│        │                         │        Created ─► Approved  │
│        │                         │                      │      │
│                                                                  │
│  ON-LEDGER STATE:                                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Invoice #123                                              │ │
│  │  ────────────────────────────────────────────────────────  │ │
│  │  seller:      AliceCorp                                   │ │
│  │  buyer:       BobCo                                       │ │
│  │  operator:    Monoton                                     │ │
│  │  amount:      1000.00 CC                                  │ │
│  │  status:      Approved                                    │ │
│  │                                                             │ │
│  │  HOLDINGS (separate from invoice):                         │ │
│  │  ┌──────────────────┐  ┌──────────────────┐               │ │
│  │  │ AliceCorp        │  │ BobCo            │               │ │
│  │  │ Holding: 5000 CC │  │ Holding: 10000 CC│               │ │
│  │  └──────────────────┘  └──────────────────┘               │ │
│  │        (will receive)      (will pay)                      │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  IMPORTANT: Invoice does NOT hold funds.                        │
│  Invoice is just a "promise to pay" contract.                    │
│  Actual money lives in separate Holding contracts.               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────┐
│              SETTLEMENT PHASE - The Transfer                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  The key question: WHERE does the money GO during settlement?   │
│                                                                  │
│  ANSWER: Directly to the SELLER's Holding                       │
│          (No escrow. No intermediate contract.)                   │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │                    BEFORE SETTLEMENT                       │   │
│  │                                                            │   │
│  │   ┌─────────────────┐         ┌─────────────────┐        │   │
│  │   │   HOLDING       │         │   HOLDING       │        │   │
│  │   │   (Buyer)       │         │   (Seller)      │        │   │
│  │   │                 │         │                 │        │   │
│  │   │  owner: BobCo   │         │  owner: Alice  │        │   │
│  │   │  amount: 10000  │         │  amount: 5000  │        │   │
│  │   │                 │         │                 │        │   │
│  │   └─────────────────┘         └─────────────────┘        │   │
│  │         │                                                        │   │
│  │         │ Need to transfer 1000 CC to Alice                   │   │
│  │         │                                                        │   │
│  └─────────┼────────────────────────────────────────────────────┘   │
│            │                                                         │
│            ▼                                                         │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │                   PATH A: ATOMIC BATCH                    │   │
│  │                                                            │   │
│  │   Single Canton transaction containing:                     │   │
│  │   1. Archive: Buyer's Holding (10000 CC)                  │   │
│  │   2. Create: New Buyer Holding (9000 CC) ← change          │   │
│  │   3. Create: Seller Holding (6000 CC) ← receiving         │   │
│  │   4. Archive: Invoice (status: Settled)                    │   │
│  │                                                            │   │
│  │   ALL OR NOTHING - either entire tx succeeds or rolls back  │   │
│  └───────────────────────────────────────────────────────────┘   │
│            │                                                         │
│            ▼                                                         │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │                    AFTER SETTLEMENT                        │   │
│  │                                                            │   │
│  │   ┌─────────────────┐         ┌─────────────────┐        │   │
│  │   │   HOLDING       │         │   HOLDING       │        │   │
│  │   │   (Buyer)        │         │   (Seller)      │        │   │
│  │   │                 │         │                 │        │   │
│  │   │  owner: BobCo   │         │  owner: Alice   │        │   │
│  │   │  amount: 9000   │         │  amount: 6000   │        │   │
│  │   │                 │         │                 │        │   │
│  │   └─────────────────┘         └─────────────────┘        │   │
│  │         (paid 1000)                 (received 1000)        │   │
│  │                                                            │   │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 4: Detailed Settlement Transaction (CORRECTED)

**KEY CORRECTION**: The TransferInstruction IS a locked state. It's not "no locked state" - it's "no custodial escrow."

```
┌─────────────────────────────────────────────────────────────────┐
│     PATH A BATCH: Two-Phase Transfer in One Atomic Transaction       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  In Path A, all steps execute in ONE Canton transaction.          │
│  The TransferInstruction exists only WITHIN this transaction.      │
│  No "pending" state persists between transactions.               │
│                                                                  │
│  API Call: POST /v2/commands/submit-and-wait                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  {                                                       │    │
│  │    "commands": [                                         │    │
│  │                                                           │    │
│  │      // STEP 1: TransferFactory_Transfer                  │    │
│  │      // Consumes Buyer's input Holding(s)                 │    │
│  │      // Value now LOCKED inside pending TransferInstruction │    │
│  │      {                                                    │    │
│  │        "templateId": "TransferFactory:...",               │    │
│  │        "choice": "TransferFactory_Transfer",               │    │
│  │        "argument": {                                     │    │
│  │          "transfer": {                                    │    │
│  │            "sender": "BobCo",                             │    │
│  │            "receiver": "AliceCorp",                      │    │
│  │            "amount": 1000.00,                           │    │
│  │            "instrumentId": { "id": "CC", ... },          │    │
│  │            "inputHoldingCids": ["Holding:abc123"]         │    │
│  │          }                                                │    │
│  │        }                                                  │    │
│  │      },                                                    │    │
│  │                                                           │    │
│  │      // STEP 2: TransferInstruction_Accept                │    │
│  │      // Archives pending instruction, mints new Holding    │    │
│  │      {                                                    │    │
│  │        "templateId": "TransferInstruction:...",            │    │
│  │        "choice": "TransferInstruction_Accept"             │    │
│  │      },                                                    │    │
│  │                                                           │    │
│  │      // STEP 3: Invoice_ConfirmSettled                     │    │
│  │      {                                                    │    │
│  │        "templateId": "Invoice:...",                       │    │
│  │        "choice": "Invoice_ConfirmSettled"                 │    │
│  │      }                                                     │    │
│  │    ],                                                      │    │
│  │    "actAs": ["BobCo", "Monoton"]                          │    │
│  │  }                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  LEDGER EFFECTS (atomic, all-or-nothing):                      │
│                                                                  │
│  1. TransferFactory_Transfer:                                     │
│     - CONSUMES: BobCo's Holding(10000 CC) ← ARCHIVED           │
│     - CREATES: TransferInstruction(pending, holds 1000 CC)    │
│                                                                  │
│  2. TransferInstruction_Accept:                                    │
│     - CONSUMES: TransferInstruction(pending) ← ARCHIVED          │
│     - CREATES: AliceCorp's Holding(6000 CC) ← RECEIVED         │
│     - CREATES: BobCo's Holding(9000 CC) ← CHANGE (if any)     │
│                                                                  │
│  3. Invoice status → Settled                                     │
│                                                                  │
│  The "pending" state exists ONLY within this transaction.        │
│  No intermediate state visible between transactions.              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 5: Path A Only - No "Learning" Step Needed

**DECISION**: Hackathon uses Path A only, no Path B fallback.

```
┌─────────────────────────────────────────────────────────────────┐
│              WHY PATH A ONLY SIMPLIFIES INVOICE                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PATH A (used):                                                 │
│  ───────────────────────────────────────────────────────────    │
│  API constructs ALL commands in one batch:                       │
│    1. TransferFactory_Transfer                                  │
│    2. TransferInstruction_Accept                                 │
│    3. Invoice_ConfirmSettled                                     │
│                                                                  │
│  These execute as ONE Canton transaction.                        │
│                                                                  │
│  Invoice_ConfirmSettled doesn't need to "learn" anything       │
│  because it executes in the SAME transaction as the transfer.    │
│                                                                  │
│  The ledger guarantees:                                         │
│    If Invoice shows Settled → Transfer definitely completed        │
│    If Transfer completed → Invoice definitely shows Settled        │
│                                                                  │
│  ────────────────────────────────────────────────────────────   │
│                                                                  │
│  PATH B (NOT used):                                             │
│  ──────────────────────────────────────────────────────────     │
│  If accept happened separately, Invoice needs to learn:          │
│    - Matching service watches transaction stream                  │
│    - On TransferInstruction_Accept event:                        │
│    - Submit Invoice_ConfirmSettled separately                    │
│    - NOT atomic with transfer                                    │
│                                                                  │
│  This is why Path A is preferred - true atomicity.              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Complete End-to-End Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          COMPLETE PROTOCOL FLOW                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ═══════════════════════════════════════════════════════════════════════    │
│  PHASE 1: SETUP (One-time per business)                                    ║
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                              │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────────────────┐ │
│  │ 1. Create    │      │ 2. Issue     │      │ 3. Create                │ │
│  │ Canton Party │ ───► │ OAuth2 JWT   │ ───► │ BusinessRegistration     │ │
│  │              │      │ (canActAs)   │      │ (Monoton signs)          │ │
│  └──────────────┘      └──────────────┘      └──────────────────────────┘ │
│                                                                              │
│  ═══════════════════════════════════════════════════════════════════════    │
│  PHASE 2: FUNDING (Get Holdings)                                          ║
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ OPTION A (Devnet): Devnet Faucet                                    │   │
│  │ ┌────────┐     ┌────────┐     ┌──────────────┐                     │   │
│  │ │ Faucet │ ──► │ Create │ ──► │ HOLDING      │                     │   │
│  │ │ API    │     │ Holding│     │ owner: Biz   │                     │   │
│  │ └────────┘     └────────┘     │ amount: X CC  │                     │   │
│  │                               └──────────────┘                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ OPTION B (Production): External Transfer or Mint                     │   │
│  │ ┌────────┐     ┌────────┐     ┌──────────────┐                     │   │
│  │ │ Bank   │ ──► │ Monoton│ ──► │ HOLDING      │                     │   │
│  │ │ Wire   │     │ Mints  │     │ owner: Biz   │                     │   │
│  │ └────────┘     └────────┘     │ amount: X    │                     │   │
│  │                               └──────────────┘                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ═══════════════════════════════════════════════════════════════════════    │
│  PHASE 3: INVOICE LIFECYCLE                                               ║
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                              │
│  SELLER                                              BUYER                   │
│    │                                                    │                  │
│    │  CREATE INVOICE                                   │                  │
│    │ ─────────────────────────────────────────────────►│                  │
│    │  (status: Created)                                │                  │
│    │                                                    │                  │
│    │                               APPROVE INVOICE      │                  │
│    │ ◄─────────────────────────────────────────────────│                  │
│    │  (status: Approved)                               │                  │
│    │                                                    │                  │
│    │                               INITIATE SETTLEMENT  │                  │
│    │ ◄─────────────────────────────────────────────────│                  │
│    │  (status: AwaitingSettlement)                     │                  │
│    │                                                    │                  │
│    ═══════════════════════════════════════════════════════════════        ║
│    PHASE 4: SETTLEMENT (Atomic Batch)                               ║
│    ═══════════════════════════════════════════════════════════════════════        ║
│    │                                                    │                  │
│    │        ┌─────────────────────────────────────────────────────┐      │
│    │        │            CANTON BATCH TRANSACTION                  │      │
│    │        │                                                     │      │
│    │        │  1. Archive: Buyer Holding (10000 CC)              │      │
│    │        │  2. Create: Buyer Holding (9000 CC) ← change       │      │
│    │        │  3. Create: Seller Holding (6000 CC) ← received     │      │
│    │        │  4. Update: Invoice (status: Settled)              │      │
│    │        │                                                     │      │
│    │        │  ALL IN ONE TRANSACTION - ALL OR NOTHING            │      │
│    │        └─────────────────────────────────────────────────────┘      │
│    │                                                    │                  │
│    │  CONFIRMED: Settlement Complete                        │                  │
│    │ ◄──────────────────────────────────────────────────│                  │
│    │                                                    │                  │
│                                                                              │
│  ═══════════════════════════════════════════════════════════════════════    │
│  ON-LEDGER STATE AFTER SETTLEMENT                                        ║
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  HOLDINGS:                                                         │   │
│  │  ┌─────────────────────────┐    ┌─────────────────────────┐        │   │
│  │  │ BEFORE                 │    │ AFTER                   │        │   │
│  │  ├─────────────────────────┤    ├─────────────────────────┤        │   │
│  │  │ Buyer: 10000 CC        │    │ Buyer: 9000 CC         │        │   │
│  │  │ Seller: 5000 CC        │    │ Seller: 6000 CC        │        │   │
│  │  └─────────────────────────┘    └─────────────────────────┘        │   │
│  │                                                                     │   │
│  │  INVOICE:                                                          │   │
│  │  ┌─────────────────────────────────────────────────────────┐      │   │
│  │  │  invoiceId: "INV-123"                                    │      │   │
│  │  │  status: Settled                                         │      │   │
│  │  │  settledTransferId: "TX-abc..."                          │      │   │
│  │  └─────────────────────────────────────────────────────────┘      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Insights

```
┌─────────────────────────────────────────────────────────────────┐
│                    KEY INSIGHTS (CORRECTED)                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. INVOICE IS NOT A SMART CONTRACT HOLDING MONEY               │
│     ─────────────────────────────────────────────────────       │
│     • Invoice is a "promise to pay" agreement                   │
│     • It references the transfer, not holds funds              │
│     • Actual money lives in Holding contracts                     │
│                                                                  │
│  2. THERE IS A LOCKED STATE - BUT NO CUSTODIAL ESCROW         │
│     ─────────────────────────────────────────────────────       │
│     • TransferInstruction DOES hold value temporarily            │
│     • But it's enforced by CODE, not a third party             │
│     • No admin can seize or redirect funds inside it            │
│     • ACCEPT → seller receives, REJECT/WITHDRAW → buyer gets back │
│                                                                  │
│  3. "NO CUSTODIAL ESCROW" IS THE DIFFERENTIATOR               │
│     ─────────────────────────────────────────────────────       │
│     • Not "no locked state" (that would be false)              │
│     • Not "no intermediary" (TransferInstruction IS intermediary) │
│     • DIFFERENT: No third party can touch your money             │
│     • The contract enforces escrow, not a company                 │
│                                                                  │
│  4. HOLDINGS ARE THE MONEY                                       │
│     ─────────────────────────────────────────────────────       │
│     • Not a database record of balance                           │
│     • Not an account with a number                              │
│     • A CONTRACT you own = tokens you have                      │
│     • Transfer = contract ownership change                        │
│                                                                  │
│  5. SETTLEMENT IS ATOMIC (Path A)                              │
│     ─────────────────────────────────────────────────────       │
│     • One Canton transaction moves money AND updates invoice     │
│     • No partial states                                          │
│     • If any step fails, entire transaction rolls back           │
│     • Pending state exists only WITHIN the transaction            │
│                                                                  │
│  6. PATH A ONLY - NO "LEARNING" NEEDED                         │
│     ─────────────────────────────────────────────────────       │
│     • API constructs all commands in one batch                   │
│     • Transfer + Accept + ConfirmSettled are atomic              │
│     • Invoice doesn't need to "learn" about transfer result      │
│     • Ledger guarantees: Settled = Transfer completed            │
│                                                                  │
│  7. FUNDING = GETTING HOLDINGS                                   │
│     ─────────────────────────────────────────────────────       │
│     • Devnet: Faucet gives you test Holdings                   │
│     • Production: Bank transfer → Monoton mints Holdings         │
│     • (Or: Existing business sends you Holdings)                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Comparison: Monoton vs Stripe vs Traditional Wire

```
┌─────────────────────────────────────────────────────────────────┐
│                    FUND FLOW COMPARISON                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  STRIPE:                                                         │
│  ──────                                                          │
│  Buyer ──► Stripe Escrow ──► Seller                             │
│            (Stripe holds)                                        │
│                                                                  │
│  TRADITIONAL WIRE:                                               │
│  ───────────────                                                 │
│  Buyer Bank ──► Correspondent Banks ──► Seller Bank              │
│                (intermediaries)                                  │
│                                                                  │
│  MONOTON (Canton):                                               │
│  ──────────────────                                              │
│  Buyer ──► [NO ESCROW] ──► Seller                               │
│            Direct Holding transfer                               │
│            Canton guarantees atomic settlement                    │
│                                                                  │
│  WHY NO ESCROW?                                                 │
│  ────────────────                                               │
│  Canton IS the trust layer. The ledger is the escrow.           │
│  Canton guarantees:                                              │
│    • If invoice marked Settled, money moved                      │
│    • If money moved, invoice marked Settled                      │
│    • Atomic transaction - can't have one without other           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## What's NOT Built Yet

| Component | Status | Notes |
|-----------|--------|-------|
| Funding mechanism | 🔲 Not built | Devnet faucet only |
| Mint/burn for own instrument | 🔲 Not built | V2 item |
| Bank integration | 🔲 Not built | Production hardening |

---

## Summary

1. **Onboarding** → Creates Canton Party + BusinessRegistration contract
2. **Funding** → Business gets Holdings (via faucet, transfer, or mint)
3. **Invoice Created** → Just a contract, no money involved
4. **Invoice Approved** → Still just a contract
5. **Settlement** → Atomic batch:
   - Archives buyer's Holding
   - Creates new Holdings (buyer change + seller receive)
   - Updates invoice to Settled
6. **Done** → Seller has more CC, Buyer has less, Invoice shows Settled

**No escrow. No intermediary holding funds. Direct P2P transfer via Canton atomic transaction.**
