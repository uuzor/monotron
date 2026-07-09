# Monoton — Build Plan
**Private B2B wallet + invoice settlement, exposed as an Agentic Commerce API, with a Stripe-for-Private-B2B-Payments roadmap**

Canton Devnet · Build on Canton Hackathon · Submission deadline Mon Jul 13, 12:59 BST

---

## 1. What we're building (hackathon scope)

Three layers, in build order:

1. **Wallet** — parties hold balances, send/receive between each other on Canton
2. **Invoice lifecycle** — seller creates invoice on-ledger → buyer approves → atomic settlement, privacy-preserving throughout
3. **Agentic Commerce API** — REST wrapper over the above so an AI agent (or any external system) can create, approve, and settle invoices programmatically

"Buy" (fiat on-ramp), swap/bridge, and yield stay out of the hackathon build — documented in §6 as the roadmap, since none of it touches Canton-specific logic or privacy, and it can't be built compliantly in days regardless of chain.

**Demo narrative:** *an AI agent creates an invoice, the counterparty's agent approves it, funds settle atomically — and no third party, including us, ever sees the amount or terms.*

---

## 2. Party & auth model — the decision that shapes everything else

Canton gives you two ways to let a party act on the ledger, and picking wrong here costs you a day of rebuilding, so lock this first.

### Internal parties (validator-managed keys)
The validator's key signs on the party's behalf; the user just authenticates with a JWT. This is the standard web-app pattern — fast to build, no client-side key management. Rights come from **`canReadAs(p)`** / **`canActAs(p)`** claims in the token, checked against the participant's rights table for every Ledger API call.

### External parties (self-custodied keys)
The party owns its own signing key. Submission is a two-step **prepare → sign → execute** flow: the validator interprets the command and returns a transaction hash, the key signs that hash, then the signed transaction is submitted. This is the only model where a party's authority isn't delegated to whoever runs the validator.

### Decision for this build
| Actor | Model | Why |
|---|---|---|
| Human wallet users (web app) | **Internal party**, JWT via Keycloak/OAuth2 | Fast to build, matches every other neobank UX, no seed phrases for SMB users |
| AI agents calling the Agentic Commerce API | **Internal party per business, scoped JWT** for the hackathon; **external signing** flagged as the V2 hardening step | An agent authenticating with a short-lived JWT is fine for a demo. But if an agent is *initiating payments unsupervised*, the business should eventually hold its own key rather than trust Monoton's validator not to misuse delegated signing rights — this is exactly the trust boundary the hackathon's "agentic commerce with privacy" theme is pointing at. Building external signing now would burn a day on openssl key handling and multi-hash signing flows for no demo-visible benefit; note it in the pitch as the deliberate hardening path instead of skipping it silently. |

Practical implication: every party (business, buyer, agent-on-behalf-of-business) gets an **internal party** hosted on your validator, authenticated via **user access tokens** (JWTs, OAuth2-style, 5–15 min expiry per Canton's own recommendation). Set up two Keycloak-style realms or a single realm with per-business users — mirrors the Quickstart's `AppUser`/`AppProvider` split, which is a reasonable template to copy for buyer vs. seller roles.

---

## 3. Wallet layer — SUPERSEDED, see `monoton-agentic-commerce-stripe-api.md`

**Decision reversed:** extending the Canton Token Standard (CIP-0056) rather than rolling a custom `WalletBalance` template. Full rationale, Daml interface work, and the JavaScript/TypeScript integration path are written up in the companion doc — this section is kept only for the historical record of the tradeoff.

### Daml sketch

```haskell
module Monoton.Wallet where

template WalletAccount
  with
    owner    : Party      -- the business
    operator : Party      -- Monoton's operator party, for platform-level visibility/audit
    balance  : Decimal
  where
    signatory owner
    observer operator
    ensure balance >= 0.0

    key owner : Party
    maintainer key

    nonconsuming choice Wallet_Credit : ContractId WalletAccount
      with amount : Decimal
      controller operator
      do
        assert (amount > 0.0)
        archive self
        create this with balance = balance + amount

    nonconsuming choice Wallet_Debit : ContractId WalletAccount
      with amount : Decimal
      controller owner
      do
        assert (amount > 0.0 && amount <= balance)
        archive self
        create this with balance = balance - amount
```

Notes tying back to the docs:
- `owner` is the **sole signatory** — no counterparty needs to co-authorize a balance existing. `operator` is an **observer only**, giving Monoton platform-level audit visibility without granting it any control (mirrors the "only stakeholders see the contract" privacy model).
- `key owner : Party` gives O(1) lookup of a business's wallet via `fetchByKey`/`exerciseByKey` instead of scanning the ACS — matters once the API layer needs to resolve "this business's wallet" on every request.
- Real transfer (not just credit/debit) should be a single atomic choice spanning both parties' `WalletAccount`s, authorized by both — see the `Invoice_Settle` choice in §4, which does exactly this instead of two separate debit/credit calls (avoids a state where a debit succeeds but the paired credit fails).

---

## 4. Invoice lifecycle

### Daml sketch

```haskell
module Monoton.Invoice where

data InvoiceStatus = Created | Approved | Settled | Rejected
  deriving (Eq, Show)

template Invoice
  with
    seller      : Party
    buyer       : Party
    operator    : Party
    amount      : Decimal
    description : Text
    dueDate     : Date
    status      : InvoiceStatus
  where
    signatory seller
    observer buyer, operator   -- ONLY seller, buyer, operator ever see this contract
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

    choice Invoice_Settle : (ContractId Invoice, ContractId WalletAccount, ContractId WalletAccount)
      with
        buyerWalletCid  : ContractId WalletAccount
        sellerWalletCid : ContractId WalletAccount
      controller buyer  -- buyer triggers payment; could also be operator-triggered on approval
      do
        assert (status == Approved)
        buyerWallet  <- fetch buyerWalletCid
        sellerWallet <- fetch sellerWalletCid
        assert (buyerWallet.owner == buyer && sellerWallet.owner == seller)
        newBuyerCid  <- exercise buyerWalletCid  Wallet_Debit  with amount
        newSellerCid <- exercise sellerWalletCid Wallet_Credit with amount
        newInvoiceCid <- create this with status = Settled
        return (newInvoiceCid, newBuyerCid, newSellerCid)
```

Key privacy point, straight from the language reference: **`signatory` parties are automatically added as observers, and only signatories + observers can ever see a contract.** Because only `seller`, `buyer`, and `operator` appear anywhere in this template, no other party on the network — not even other Monoton users — can query, list, or infer this invoice exists. That's the whole pitch, enforced structurally rather than by access control on top.

`Invoice_Settle` exercising both `Wallet_Debit` and `Wallet_Credit` **inside one choice body** is what makes settlement atomic — either both wallet updates happen or the whole transaction (including the status change to `Settled`) aborts. This is the "atomic settlement" line in the pitch deck, and it's a direct consequence of Daml's transaction model, not something you have to build separately.

**Note:** the `Invoice_Settle` choice above calls the now-superseded `Wallet_Debit`/`Wallet_Credit` choices. With the Token Standard decision, settlement instead orchestrates a `TransferFactory_Transfer` (or accepts a pending `TransferInstruction`) tagged with the invoice ID as transfer metadata — see the companion doc for the revised choice body and the off-ledger matching logic that ties a completed transfer back to an `Invoice` contract.

### Open design decision to resolve before building (carried over from earlier contracts)
Whether `operator` should be a required observer on every `Invoice`/`WalletAccount`, or whether that visibility should be opt-in per business. Full operator visibility is simpler to build and demo (you can show a platform dashboard), but it's a real privacy tradeoff worth stating explicitly in the pitch rather than glossing over — "only the two parties see it" is a stronger claim if it's literally true, including from you.

---

## 5. Agentic Commerce API

This is a thin REST service in front of the JSON Ledger API — no new Daml logic, just orchestration + auth.

### Why JSON Ledger API over gRPC
Same functionality, HTTP semantics, directly consumable from a Node/Python backend or an LLM agent's tool-calling layer without protobuf tooling. All the command patterns below map onto `/v2/commands/submit-and-wait` and `/v2/state/active-contracts`.

### Endpoint surface

| Endpoint | Ledger API call underneath | Notes |
|---|---|---|
| `POST /v1/invoices` | `CreateCommand` on `Invoice` template | Agent acting as seller; `actAs: [sellerParty]` |
| `POST /v1/invoices/{id}/approve` | `ExerciseCommand` → `Invoice_Approve` | Agent acting as buyer |
| `POST /v1/invoices/{id}/settle` | `ExerciseCommand` → `Invoice_Settle` | Requires both wallet contract IDs — API layer resolves these via `fetchByKey`-equivalent query first |
| `GET /v1/invoices/{id}` | `GetActiveContracts` filtered to caller's party | Returns 404 (not 403) if caller isn't a stakeholder — don't leak existence |
| `GET /v1/wallet/balance` | `GetActiveContracts` filtered to `WalletAccount` by key | |
| `POST /v1/wallet/transfer` | Same pattern as `Invoice_Settle`, standalone | For non-invoice-linked payments |

### Auth for the API layer
Every API caller (human dashboard or agent) authenticates with **OAuth2 client-credentials**, gets a short-lived JWT scoped to `canActAs(theirParty)`, and that JWT is what the backend forwards as the Bearer token on the underlying Ledger API call. The API layer itself does no additional authorization — it inherits whatever the JWT already grants, which means a compromised API key can't do more than a compromised Ledger API token could. This is the cleanest way to make "agent can pay invoices up to its granted scope" a ledger-enforced fact rather than an application-level check you have to trust yourselves on.

```
Agent → POST /v1/invoices/{id}/settle  [Bearer: agent-scoped JWT]
  → API layer forwards commands to participant's JSON Ledger API
  → Participant checks canActAs(businessParty) on the token
  → Daml authorization checks run (controller = buyer, etc.)
  → Result returned up the chain
```

### Demo-critical detail
`GetActiveContracts` and the completion stream both require `canReadAs(p)` **for each party requested** — so the API must never let an agent query with a party it doesn't hold rights for, even by accident (e.g. a buggy "list all invoices" endpoint that queries across parties). This is worth a deliberate test case in the demo script, since it's the concrete proof point for "the API can't leak what the ledger already hides."

---

## 6. Stripe for Private B2B Payments (roadmap, not hackathon build)

Not built for the hackathon — this section exists so the pitch deck has a credible "how this becomes a company" slide, and so the API design above doesn't accidentally foreclose it.

**Shape of it:** Monoton becomes an embeddable payments API other SaaS products (accounting tools, marketplaces, ERPs) call instead of building their own Canton integration — same relationship Stripe has to e-commerce platforms. Concretely:

- The `POST /v1/invoices` endpoint already accepts a caller party, which is what makes this swappable from "your business calling on its own behalf" to "a third-party SaaS calling on behalf of its merchant" — no architectural change needed, just a permissions/onboarding layer on top (API keys mapped to parties, rate limits, webhook callbacks on `Settled`/`Rejected`).
- Fiat on/off-ramp ("buy" from the original roadmap) plugs in here as a funding source for `Wallet_Credit` — Stripe/Paystack webhook → backend calls `Wallet_Credit` — rather than as a Daml-level concern. This is why "buy" was correctly identified as out of scope for the Canton build itself: it's an integration, not ledger logic.
- Credit/proof-of-payment attestations (from the earlier financing-marketplace discussion) become a natural extension of `GET /v1/invoices/{id}` — a third-party lender could be granted `canReadAs` scoped to a specific settled invoice's *status* without ever seeing amount or terms, if `status` were split into a separately-observable contract. Worth a one-line mention in the deck as the V3 yield/financing hook, not worth building now.

---

## 7. Build sequence (4 days)

| Day | Deliverable |
|---|---|
| 1 | `WalletAccount` + `Invoice` Daml templates written, tested via Daml Script locally, deployed to Devnet. Keycloak/OAuth2 realms set up for seller/buyer/operator parties. |
| 2 | Agentic Commerce API — `POST /invoices`, `/approve`, `/settle`, `GET /invoices/{id}`, `GET /wallet/balance`. Manual curl-tested against Devnet. |
| 3 | Frontend: create/send/approve/settle flow (human path) + a scripted "agent" client hitting the same API (agent path) for the demo. Wire up wallet funding via manual top-up (no real "buy"). |
| 4 | Deploy verification on Devnet (not LocalNet/Seaport), record 3-min demo video, repo cleanup, deck, submit. |

## 8. Submission checklist (from hackathon brief)
- [ ] Public repository
- [ ] Presentation deck
- [ ] 3-minute video pitch w/ demo
- [ ] Link to live product
- [ ] **Confirmed deployed on Canton Devnet** (not LocalNet/sandbox/Seaport mock)

---

## Open questions to resolve before Day 1 starts
1. Does `operator` (Monoton) get default observer rights on every invoice/wallet, or is that opt-in? (§4)
2. Single Keycloak realm with per-business users, vs. AppUser/AppProvider split like the Quickstart? Affects how much of the Quickstart's existing auth scaffolding you can copy directly.
3. For the agent demo path — scripted agent client calling the API directly, or an actual LLM tool-calling loop? The latter is a stronger demo of "agentic commerce" but adds a dependency; scripted-but-labeled-as-agent is a reasonable fallback if Day 3 runs short.
