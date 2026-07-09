# Monoton — Agentic Commerce API

**One settlement API, two callers: AI agents acting directly, and third-party SaaS platforms acting on behalf of their end-businesses.**

No fiat, no on/off-ramp, no bridging in this doc — that's out of scope for the hackathon and isn't being architected here. This is the settlement layer only: an AI agent or another app calls `create_invoice` / `approve_invoice` / `send_payment` / `get_balance` on Canton, on behalf of a business it's acting for.

This doc assumes the revised wallet/invoice design in `monoton-wallet-invoice-lifecycle.md` (Token Standard-based, not a custom wallet template).

---

## 1. Why this is the strongest fit for the hackathon specifically

The Build on Canton brief names "agentic commerce with privacy" and systems where software agents can safely initiate or coordinate commercial actions as a judged theme. The demo narrative writes itself: an agent creates an invoice, the counterparty's agent approves it, funds settle — and no third party, including Monoton, ever sees the amount or terms of the invoice itself (structurally true because of `Invoice`'s signatory/observer scoping — see the companion doc §4).

---

## 2. The core insight: it's one API, not two products

`create_invoice`, `approve_invoice`, `send_payment`, `get_balance` are called by:

1. **An AI agent**, authenticated with its own scoped credentials, acting for the business it represents.
2. **A third-party SaaS platform** (accounting tool, marketplace, ERP), authenticated with credentials issued to *its own* end-business, acting on that business's behalf.

Same endpoints, same underlying `Invoice` template and Token Standard transfer, same auth model (a JWT scoped to `canActAs(party)`). The only thing that differs is *whose credentials are on the other end of the JWT* — an agent's own client credentials, or a SaaS platform's credentials issued per end-business. That's a stronger pitch than treating them as separate products: one settlement API, two go-to-market motions (direct agentic use, and embeddable-in-other-SaaS use).

---

## 3. Endpoint surface

Thin REST service in front of the JSON Ledger API — no new Daml logic beyond what's in the companion doc, just orchestration + auth + (for Path A settlement) command batching.

| Endpoint | Ledger API call(s) underneath | Notes |
|---|---|---|
| `POST /v1/invoices` (`create_invoice`) | `CreateCommand` on `Invoice` | Caller acts as seller; `actAs: [sellerParty]` |
| `POST /v1/invoices/{id}/approve` (`approve_invoice`) | `ExerciseCommand` → `Invoice_Approve` | Caller acts as buyer |
| `POST /v1/invoices/{id}/settle` (`send_payment`) | **Path A:** one `submit-and-wait` call with a `commands` array containing both the transfer-instruction exercise and `Invoice_ConfirmSettled` — one atomic transaction. **Path B:** two separate submissions, reconciled by a matching service. See companion doc §4.2 for the tradeoff and when each applies. | Requires resolving the buyer's/seller's `Holding` contract IDs and the instrument registry's choice context first |
| `GET /v1/invoices/{id}` | `GetActiveContracts` filtered to caller's party | Returns 404, not 403, if caller isn't a stakeholder — don't leak existence |
| `GET /v1/wallet/balance` (`get_balance`) | `GetActiveContracts` filtered to `Holding` interface, summed by instrument | See companion doc §3 |

### Why JSON Ledger API over gRPC, for a JavaScript backend specifically

Everyone on Canton's own tooling defaults to Java/Scala examples, but nothing about the Ledger API requires that. The JSON Ledger API is plain HTTP + JSON, directly consumable from Node without protobuf tooling — and Canton ships a JS/TS codegen path specifically for this:

- **`dpm codegen-js`** generates TypeScript types for every Daml template/choice in your `.dar` — records, variants, and a typed `Template`/`Choice` interface per template (e.g. an `Invoice` type, an `Invoice_Approve` choice type). This gets you compile-time safety on `createArguments`/`choiceArgument` payloads instead of hand-writing raw JSON and hoping the shape matches.
- Wire it into `daml.yaml`:

```yaml
codegen:
  js:
    output-directory: backend/src/daml-codegen
    npm-scope: monoton
```

- Backend command construction becomes: import the generated `Invoice` template object, build a typed `createArguments`, POST it as a `CreateCommand` to `/v2/commands/submit-and-wait`. No manual tracking of `templateId` strings scattered through the codebase — the generated companion object carries it.
- For the Token Standard interfaces themselves (`Holding`, `TransferFactory`, `TransferInstruction`), the reference implementation to copy from is the **Token Standard CLI** (`canton-network/splice` repo, `token-standard/cli`) and the **Wallet SDK** (`canton-network/wallet-gateway`, `sdk/wallet-sdk`) — both TypeScript, both demonstrating exactly the `listContractsByInterface` / `transfer` / `acceptTransferInstruction` patterns Monoton's backend needs. Treat these as the canonical JS reference for Token Standard integration rather than reverse-engineering the OpenAPI spec from scratch.

### Auth for the API layer

Every caller — human dashboard, AI agent, or embedding SaaS platform — authenticates with OAuth2 client-credentials, gets a short-lived JWT (Canton's own guidance: 5–15 minutes) scoped to `canActAs(theirParty)`, and that JWT is what Monoton's backend forwards as the Bearer token on the underlying Ledger API call. The API layer does no *additional* authorization on top — it inherits exactly what the JWT already grants from the participant's rights table. That's what makes "an agent can only pay invoices within its granted scope" a ledger-enforced fact, not an application-level check Monoton has to be trusted on.

```
Agent or SaaS backend → POST /v1/invoices/{id}/settle  [Bearer: scoped JWT]
  → API layer forwards commands to participant's JSON Ledger API
  → Participant checks canActAs(businessParty) on the token
  → Daml authorization checks run (controller = buyer, etc.)
  → Result returned up the chain
```

### Demo-critical detail (unchanged from original doc)

`GetActiveContracts` and the completion stream both require `canReadAs(p)` *for each party requested* — the API must never let a caller query across a party it doesn't hold rights for, even by accident (a buggy "list all invoices" endpoint that queries multiple parties at once). Worth a deliberate test case in the demo script: it's the concrete proof point that "the API can't leak what the ledger already hides."

---

## 4. Multi-tenant party & credential design

**Decision:** each end-business gets its own Canton party and its own credentials, issued to it *through* whichever platform onboarded it — not one shared JWT that acts across many businesses.

### Why this, not a shared platform-wide JWT

A single JWT scoped to `canActAs` for *all* of a SaaS platform's end-businesses would mean:
- One compromised platform credential exposes every business it has ever onboarded, not just one.
- There's no way to give an individual business its own audit trail, rate limit, or revocation — you'd be revoking the whole platform's access to unwind one bad actor.
- It breaks the privacy pitch at the root: `Invoice`'s signatory/observer model only protects a business's data if that business's *party* is the thing actually calling choices — a shared platform party acting as proxy for everyone re-introduces exactly the "trust the platform not to misuse delegated authority" problem the original doc flagged for agent auth (§2 of the base doc).

### The shape of it

1. **Party per business.** When a SaaS platform onboards a new end-business (or an agent starts acting for a new business), Monoton's onboarding flow creates a new Canton party for that business on Monoton's validator — the same `POST /v2/parties` call used for any internal party, just triggered by the platform's onboarding API call rather than a human signup form.
2. **Credentials issued per business, distributed through the platform.** Monoton issues that business its own OAuth2 client-credentials (or, for the embeddable case, the platform's own backend receives credentials scoped to `canActAs(thatBusinessParty)` specifically — not a blanket grant). Practically: a Keycloak client per business, or a single realm with per-business *users* (mirroring the Quickstart's `AppUser`/`AppProvider` pattern, just with N business-users instead of one).
3. **The platform is a distribution channel for credentials, not a proxy party.** When an accounting tool's backend calls `create_invoice` "for" one of its merchants, it authenticates with *that merchant's* scoped JWT (which the platform stored at onboarding time, per-merchant), not with a platform-wide credential. This means Canton's own authorization table — not Monoton's application code — is what prevents platform A's backend from ever being able to act as platform B's merchant, or one merchant of platform A's from acting as another.
4. **Revocation is per-business.** Because rights are looked up dynamically per participant user (not baked into the JWT itself — the Authorization model explicitly separates "what the token says" from "what the participant's live user-rights table says"), Monoton can revoke or downgrade one business's rights without touching anyone else's tokens or forcing a signing-key rotation.

### What this costs, honestly

More onboarding plumbing than a shared-JWT shortcut: N parties instead of 1, N sets of credentials to issue and rotate, a slightly heavier Keycloak/IDP setup. For a 4-day hackathon build, this is still worth doing over the shortcut, because it's the actual claim in the pitch ("each business's invoices are private, even from other businesses on the same embedding platform") — faking it with a shared party would be a demo that looks right but isn't structurally true, which is exactly the kind of gap the original doc called out for the `operator`-visibility question in §4.

### Open item to resolve before Day 1

Whether business onboarding (party creation + credential issuance) is a synchronous step in the platform's own onboarding flow (platform calls a Monoton `POST /v1/businesses` endpoint, gets back credentials to store) or an asynchronous approval step (Monoton reviews before granting a party). Synchronous is simpler and matches the hackathon demo's needs; note the async/KYC-gated version as the production hardening step, same treatment as external signing in the companion doc.

---

## 5. Build sequence addition (folds into the companion doc's Day 2)

| Day | Addition |
|---|---|
| 1 | Decide sync vs. async business onboarding (§4). Set up per-business Keycloak users/clients pattern. |
| 2 | Wire `dpm codegen-js` output into the backend. Implement `create_invoice` / `approve_invoice` / `send_payment` (Path A combined-batch) / `get_balance` against per-business scoped JWTs — test with at least two distinct "businesses" to prove isolation, not just one happy path. |
| 3 | Scripted agent client + a second scripted "embedding SaaS platform" client hitting the same endpoints with a different business's credentials — this is the demo proof that it's one API, two callers, not two builds. |
