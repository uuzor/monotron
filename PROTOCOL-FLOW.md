# Monoton: Full Protocol Flow Sketch

**How money moves on Canton: Holdings, not accounts. Direct transfer, not escrow.**

---

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
│    Bank intermediates. Money sits in escrow.                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│            Canton Token Standard (Holding Model)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│    ┌─────────────────┐              ┌─────────────────┐            │
│    │ Holding (UTXO) │  ─────────► │ Holding (UTXO) │            │
│    │                 │   transfer   │                 │            │
│    │ owner: Buyer    │  (atomic)   │ owner: Seller  │            │
│    │ amount: 1000    │              │ amount: 1000    │            │
│    │ instrument: CC  │              │ instrument: CC  │            │
│    └─────────────────┘              └─────────────────┘            │
│           BEFORE                          AFTER                   │
│                                                                  │
│    No escrow. No intermediate contract holding funds.            │
│    Money = contract ownership. Transfer = contract movement.       │
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

## Phase 4: Detailed Settlement Transaction

```
┌─────────────────────────────────────────────────────────────────┐
│              PATH A BATCH TRANSACTION (The Actual Commands)            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  API Call: POST /v2/commands/submit-and-wait                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  {                                                       │    │
│  │    "commands": [                                         │    │
│  │                                                           │    │
│  │      // Step 1: Buyer creates TransferInstruction        │    │
│  │      {                                                    │    │
│  │        "commandType": "create",                          │    │
│  │        "templateId": "TransferFactory:...",               │    │
│  │        "argument": {                                     │    │
│  │          "transfer": {                                    │    │
│  │            "sender": "BobCo::participant1",              │    │
│  │            "receiver": "AliceCorp::participant1",      │    │
│  │            "amount": 1000.00,                            │    │
│  │            "instrumentId": { "id": "CC", ... }           │    │
│  │          }                                                │    │
│  │        }                                                  │    │
│  │      },                                                    │    │
│  │                                                           │    │
│  │      // Step 2: Accept the transfer (moves Holdings)     │    │
│  │      {                                                    │    │
│  │        "commandType": "exercise",                        │    │
│  │        "templateId": "TransferInstruction:...",          │    │
│  │        "choice": "TransferInstruction_Accept"             │    │
│  │      },                                                    │    │
│  │                                                           │    │
│  │      // Step 3: Mark invoice as settled                   │    │
│  │      {                                                    │    │
│  │        "commandType": "exercise",                        │    │
│  │        "templateId": "Invoice:...",                       │    │
│  │        "choice": "Invoice_ConfirmSettled",                │    │
│  │        "argument": { "settledTransferId": "TX-123" }     │    │
│  │      }                                                     │    │
│  │    ],                                                      │    │
│  │    "actAs": ["BobCo", "Monoton::participant1"]           │    │
│  │  }                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  WHAT HAPPENS ON THE LEDGER:                                    │
│                                                                  │
│  1. TransferInstruction created (pending)                        │
│  2. TransferInstruction_Accept exercised:                        │
│     - Archives: BobCo's Holding(10000 CC)                      │
│     - Creates: BobCo's Holding(9000 CC) - change               │
│     - Creates: AliceCorp's Holding(6000 CC) - received        │
│  3. Invoice status → Settled                                    │
│                                                                  │
│  ATOMICITY: All 3 steps succeed or all 3 fail.                 │
│  No state where Bob paid but Alice didn't receive.             │
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
│                    KEY INSIGHTS                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. INVOICE IS NOT A SMART CONTRACT HOLDING MONEY               │
│     ─────────────────────────────────────────────────────       │
│     • Invoice is a "promise to pay" agreement                   │
│     • It references the transfer, not holds funds              │
│     • Actual money lives in Holding contracts                     │
│                                                                  │
│  2. MONEY MOVES DIRECTLY, NOT THROUGH ESCROW                   │
│     ─────────────────────────────────────────────────────       │
│     • Before: Buyer Holding(10000) → Seller Holding(5000)       │
│     • After:  Buyer Holding(9000)  → Seller Holding(6000)      │
│     • No intermediate contract holding funds                     │
│                                                                  │
│  3. HOLDINGS ARE THE MONEY                                       │
│     ─────────────────────────────────────────────────────       │
│     • Not a database record of balance                           │
│     • Not an account with a number                              │
│     • A CONTRACT you own = tokens you have                      │
│     • Transfer = contract ownership change                        │
│                                                                  │
│  4. SETTLEMENT IS ATOMIC                                         │
│     ─────────────────────────────────────────────────────       │
│     • One Canton transaction moves money AND updates invoice     │
│     • No partial states                                          │
│     • If any step fails, entire transaction rolls back           │
│                                                                  │
│  5. FUNDING = GETTING HOLDINGS                                   │
│     ─────────────────────────────────────────────────────       │
│     • Devnet: Faucet gives you test Holdings                    │
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
