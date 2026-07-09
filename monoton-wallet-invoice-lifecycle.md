# Monoton — Wallet & Invoice Lifecycle (Revised: Token Standard)

**Decision locked:** extend the Canton Network Token Standard (CIP-0056) instead of rolling a custom `WalletBalance`/`WalletAccount` template. Same reasoning you'd apply on Ethereum — don't hand-roll a token, extend the standard interface and add your own choices/templates on top of it.

This doc supersedes §3 of the original build plan. Party model, invoice template shape, and demo narrative are unchanged; what changes is *how balances and transfers are represented on-ledger*.

---

## 1. Why extend the Token Standard instead of a custom wallet

A custom `WalletAccount` template (owner-signed balance, `Wallet_Credit`/`Wallet_Debit` choices) works, but it means:

- Monoton's balances are invisible to every other Token Standard-aware wallet, registry, or explorer on the network — you'd have to build your own tooling for something the network already standardizes.
- You lose interoperability with Canton Coin and any other CIP-0056 instrument (merging, splitting, transaction history parsing) for free.
- You'd be re-solving UTXO management, transfer authorization, and history-parsing problems the standard already has reference implementations for (the Token Standard CLI, the Wallet SDK).

Extending the standard means: Monoton becomes an *instrument admin* (or just a *wallet integrator* over an existing instrument, e.g. Canton Coin/Amulet, if you don't need your own asset) and business balances are `Holding` contracts, moved via `TransferInstruction`/`TransferFactory` — the same interfaces every other Token Standard wallet understands.

---

## 2. Core interfaces you're building against

| Interface | Purpose | Where it lives |
|---|---|---|
| `Holding` (`splice-api-token-holding-v1`) | The UTXO — a contract representing an amount of an instrument held by a party. This *is* the wallet balance. | Instrument admin's package |
| `TransferFactory` (`splice-api-token-transfer-instruction-v1`) | Factory contract you exercise to *initiate* a peer-to-peer transfer | Registry-provided, per instrument |
| `TransferInstruction` (`splice-api-token-transfer-instruction-v1`) | The pending-transfer contract created by `TransferFactory_Transfer`; exposes `Accept`/`Reject`/`Withdraw` | Registry-provided |
| `Allocation` / `AllocationInstruction` / `AllocationRequest` | Delivery-vs-Payment (DVP) workflow — two legs locked and settled together | Registry-provided, only needed if invoice settlement itself needs a locked two-leg swap (see §5) |

Canton's own UTXO guidance: keep `Holding` count low per party (≲10 on average) — each is a real contract with storage/compute/traffic cost, and transfers cost extra traffic per input `Holding`. For a B2B invoicing wallet this is easy to respect (businesses aren't splitting into hundreds of holdings), but worth stating in the pitch as a deliberate design constraint you're aware of, not an oversight.

---

## 3. Wallet layer, revised

There is no `WalletAccount` template anymore. A business's "wallet" is simply: *the set of active `Holding` contracts where `owner` = that business's party, for the instrument(s) Monoton supports.*

Reading a balance:

```json
POST /v2/state/active-contracts
{
  "filtersByParty": {
    "<BUSINESS_PARTY>": {
      "cumulative": [{
        "identifierFilter": {
          "InterfaceFilter": {
            "value": {
              "interfaceId": "#splice-api-token-holding-v1:Splice.Api.Token.HoldingV1:Holding",
              "includeInterfaceView": true
            }
          }
        }
      }]
    }
  }
}
```

Sum the `amount` fields across returned `Holding` interface views, grouped by `instrumentId`. This is what backs `GET /v1/wallet/balance` in the API layer (§5 of the original doc, unchanged).

**MergeDelegation:** as balances accumulate small `Holding`s (every incoming invoice payment creates a new one), set up a `MergeDelegation` contract per business at onboarding, and run a background `BatchMergeUtility_MergeHoldings` job (Splice's own recommended pattern) to keep each business under ~10 holdings. This is a real operational piece, not a nice-to-have — skipping it means UTXO count grows unbounded and transfer traffic cost grows with it.

### Should Monoton be its own instrument admin, or ride on an existing instrument?

Two paths, both compatible with the same `Invoice` template downstream:

1. **Ride on Canton Coin (Amulet)** — no registry to build, immediate interoperability with the whole network's Token Standard tooling, but you don't control instrument-level policy (fees, minting).
2. **Mint your own instrument** (a stablecoin-style unit representing fiat-equivalent value, e.g. `MonotonUSD`) — you become the registry, implement `TransferFactory`/`TransferInstruction` yourselves per CIP-0056, and control mint/burn. More work, but it's the only path if the roadmap eventually needs an instrument Monoton itself issues against fiat reserves.

**For the hackathon:** ride on an existing Devnet instrument (Canton Coin on Devnet, or whatever test instrument the hackathon provides) so Day 1 isn't spent implementing a registry. Note the "mint our own instrument" path explicitly as the V2 step in the pitch — it's a real architectural fork, not a detail.

---

## 4. Invoice lifecycle, revised

The `Invoice` template itself is **unchanged in spirit** — it's still Monoton's own Daml code, still privacy-scoped to `seller`/`buyer`/`operator` as signatory/observers, still the thing that makes "no other party can even see this invoice exists" a structural fact rather than an access-control policy. What changes is the `Invoice_Settle` choice body: it no longer calls your own `Wallet_Debit`/`Wallet_Credit`, it orchestrates the Token Standard's transfer interfaces instead.

```haskell
module Monoton.Invoice where

data InvoiceStatus = Created | Approved | AwaitingSettlement | Settled | Rejected
  deriving (Eq, Show)

template Invoice
  with
    seller      : Party
    buyer       : Party
    operator    : Party
    amount      : Decimal
    instrumentAdmin : Party      -- which Token Standard registry/instrument this invoice settles in
    description : Text
    dueDate     : Date
    status      : InvoiceStatus
  where
    signatory seller
    observer buyer, operator
    ensure amount > 0.0

    choice Invoice_Approve : ContractId Invoice
      controller buyer
      do
        assert (status == Created)
        create this with status = Approved

    choice Invoice_Reject : ContractId Invoice
      controller buyer
      do
        assert (status == Created)
        create this with status = Rejected

    -- Buyer-side: initiates the transfer instruction against the invoice amount.
    -- This does NOT settle the invoice by itself -- see §4.1 for why.
    nonconsuming choice Invoice_InitiateSettlement : ContractId Invoice
      with
        transferInstructionCid : ContractId TransferInstruction  -- created off-ledger via TransferFactory_Transfer
      controller buyer
      do
        assert (status == Approved)
        create this with status = AwaitingSettlement

    -- Confirms settlement once the transfer has actually landed with the seller.
    -- Controller is `operator` (or `seller`) because it's asserting a fact about
    -- something that happened on the token registry's side, not authorizing a debit.
    choice Invoice_ConfirmSettled : ContractId Invoice
      controller operator
      do
        assert (status == AwaitingSettlement)
        create this with status = Settled
```

### 4.1 The atomicity tradeoff — explained plainly

**Old design (custom wallet):** `Invoice_Settle` was one Daml choice whose body directly called `Wallet_Debit` on the buyer's `WalletAccount` and `Wallet_Credit` on the seller's, both templates Monoton itself wrote. Daml's transaction model guarantees a choice body's entire node tree commits or aborts together — so "debit happened but credit didn't" was structurally impossible. One choice, one ledger transaction, one atomic fact.

**New design (Token Standard):** the transfer itself is executed via interfaces Monoton doesn't own — `TransferFactory`/`TransferInstruction`, implemented by whichever party administers the instrument (could be Monoton if you mint your own instrument, or a third party like the Canton Coin registry). Two things follow from that:

1. **An off-ledger step now sits in front of the ledger transaction.** Before you can even construct the `ExerciseCommand` for `TransferFactory_Transfer`, you must call the instrument's *registry HTTP API* to fetch `factoryId`, `disclosedContracts`, and `choiceContextData` — these aren't things Daml code can look up on its own, they come from an off-ledger service. This is a network round-trip your backend makes before building the ledger submission; it doesn't itself break atomicity, but it does mean "settle an invoice" is no longer a single self-contained Daml choice — it's "call registry → build command → submit to ledger."

2. **The transfer's authorization may genuinely require the receiver's own signature, not just the buyer's.** Many Token Standard transfer flows follow a propose→accept pattern: `TransferFactory_Transfer` creates a pending `TransferInstruction`, and a separate `TransferInstruction_Accept` choice (controlled by the receiver, or per the instrument's own rules) is what actually moves the `Holding`. If the seller's acceptance has to come from the seller's *own* session — e.g. their agent independently reviews and accepts an incoming payment — then the "debit" and "credit-confirmed" facts land in two genuinely separate ledger transactions, submitted at different times by different actors. That's not a Daml limitation, it's what multi-party authorization for a transfer *should* require: nobody should be able to unilaterally push tokens into your `Holding` and call it final without your side of the ledger agreeing, any more than a bank transfer should be uncancellable-and-final before the receiving bank posts it.

So the honest framing for the pitch: the custom-wallet design got atomicity "for free" because Monoton controlled every party's authority inside one choice body. The Token Standard design is *more correct* about who gets to authorize what, but that correctness is exactly what reintroduces the two-transaction shape — and Monoton's job becomes closing that gap explicitly (via combined batching where possible, or a small matching service where not — see below) rather than getting it for free.

### 4.2 Does this mean the API has to make two calls to settle an invoice?

**Not necessarily from the caller's perspective — it depends on whether both sides' authorization can be gathered in the same request.**

Canton's JSON Ledger API lets a single `submit-and-wait` call carry an *array* of commands under `"commands": [...]`, and — this is the part worth being precise about — **all commands in that array execute as one Canton transaction: all of them commit, or none do.** This is exactly the mechanism Splice's own `BatchMergeUtility_MergeHoldings` uses to bundle up to ~100 merge choices into a single atomic call. So "batch transactions" on Canton aren't a special feature you have to opt into — they're just multiple `ExerciseCommand`/`CreateCommand` entries in one `commands` array, submitted under one `actAs` covering every party whose authority any of those commands need.

That gives you two real options for `POST /v1/invoices/{id}/settle`:

**Path A — single atomic call (preferred, when possible).** If Monoton's backend already holds (or can obtain in that moment) authorization for *both* buyer and seller — e.g. the seller has granted Monoton's operator a standing `canActAs` for accepting incoming invoice-tagged transfers, similar to how a `MergeDelegation` lets Monoton act on a user's behalf for merges — then one API call can submit **one** `commands` array containing both the `TransferFactory_Transfer` (or `TransferInstruction_Accept`) exercise *and* the `Invoice_ConfirmSettled` exercise. One ledger transaction, one atomic outcome, and the API's external contract ("one call settles the invoice") stays true. This is the version worth building for the demo — it's the strongest answer to "is settlement atomic."

**Path B — two transactions + a matching service (fallback, when receiver consent can't be pre-delegated).** If the seller's acceptance genuinely has to come from an independent action — their own agent decides, on its own schedule, to accept the incoming transfer — then you get two separate ledger transactions: the buyer's `TransferFactory_Transfer` (or `Invoice_InitiateSettlement`), and later the seller's `TransferInstruction_Accept`. A small backend service (not a smart contract) watches the completion/transaction stream for a `TransferInstruction` accept event tagged with the invoice's ID in transfer metadata, and — on seeing it — submits the `Invoice_ConfirmSettled` command. The API can still expose a single `/settle` endpoint that *kicks off* Path B, but it should return `AwaitingSettlement`, not `Settled`, and the caller (agent or SaaS platform) needs a way to poll or subscribe for the follow-up state change — this is the honest version of "yes, under the hood this can be two ledger transactions," and it should be documented as such rather than glossed over.

**Recommendation for the hackathon demo:** build Path A. Pre-authorize the operator to accept on the seller's behalf (documented explicitly as a scoped, revocable delegation — the same trust-boundary conversation already had in §2 of the original doc about internal parties). This keeps the demo narrative ("agent creates invoice, counterparty's agent approves, funds settle atomically") literally true, and lets you note Path B in the pitch as the V2 hardening step for when receiver-side independent consent is a hard requirement (e.g. once external signing lands).

### 4.3 Metadata linking a transfer back to an invoice

Whichever path you pick, tag the transfer with the invoice ID so the matching (or combined-batch) logic has something to key on. The Token Standard's own transfer metadata convention (`splice.lfdecentralizedtrust.org/reason`, plus your own custom key) is the right place — e.g. a `monoton.example/invoiceId` key in the `TransferFactory_Transfer` choice argument's `meta`. The transaction-history parser already knows to surface `Transfer`/`Accept` nodes with their meta key/values, so this is "free" observability once wired up, and it's what your matching service (Path B) actually filters on when watching the transaction stream.

---

## 5. Open question carried over: does full DVP (Allocation) fit better than plain Transfer?

The Token Standard also defines an `Allocation`/`AllocationInstruction`/`AllocationRequest` triad specifically for **Delivery-vs-Payment** — two legs that lock and settle together, which is structurally closer to "invoice approved, now both legs (payment leg + status leg) must land together" than a plain one-directional `Transfer`. Worth a short spike on Day 1: if `AllocationRequest` gives you a cleaner single-settlement-point than combining `TransferInstruction_Accept` + `Invoice_ConfirmSettled` by hand, it may collapse the Path A/Path B distinction above into something closer to the old design's atomicity guarantee. Not committing to it here because it adds a second interface family to learn under a 4-day clock — flagged as the first thing to prototype, not something to design blind.

---

## 6. Party & auth model — unchanged from the original doc

Internal parties (validator-managed keys, JWT-based `canActAs`/`canReadAs`) for every actor — human wallet users, businesses, and AI agents acting on their behalf — for the hackathon. External signing (self-custodied keys, prepare→sign→execute) stays the documented V2 hardening step for agents that should hold their own authority rather than trust Monoton's validator. See the companion Agentic Commerce API doc for the full multi-tenant party/credential design.

## 7. Build sequence, revised

| Day | Deliverable |
|---|---|
| 1 | Confirm instrument choice (ride on existing Devnet instrument vs. mint own). `Invoice` template (revised, above) written, tested via Daml Script locally against a mocked `TransferFactory`/`TransferInstruction`, deployed to Devnet. Keycloak/OAuth2 realms for seller/buyer/operator. Spike: is `Allocation`/DVP a better fit than plain `Transfer` (§5)? |
| 2 | Agentic Commerce API — `create_invoice`, `approve_invoice`, `send_payment` (wraps Path A combined-batch settlement), `get_balance`. Manual curl-tested against Devnet, including the registry HTTP calls needed to fetch `TransferFactory` choice context. |
| 3 | Frontend human path + scripted agent client. Set up `MergeDelegation` for demo businesses so UTXO count stays sane during repeated demo runs. |
| 4 | Deploy verification on Devnet, demo video, repo cleanup, deck, submit. |
