# DESIGN — Client Intake & Agent Workflows: Build Plan

> **Status**: Draft for review — not approved, nothing implemented.
> **Version**: v5.1.1.1 (#WeOwnVer)
> **Date**: 2026-09-17
> **Source**: Internal agent review thread (stakeholder feedback, 2026-09), plus the
> follow-up on client-side document intake. Open questions answered 2026-09-17.
> **Scope**: everything required to deliver the review thread in full. Pure
> prompt/copy edits appear in Phase 0 as prerequisites; everything else is a build.

---

## 0. Vocabulary

The review thread was conducted against a tax/accounting instance, so its examples
are tax-shaped. **The product is not tax-specific, and nothing here should be built
tax-specific.** The same workflow serves every professional-services vertical — and
per the source thread, secure document handling is precisely what opens those
markets.

| Term | Means | Examples |
|---|---|---|
| **AOP** (Agent Operator) | The business or professional using WeOwnChat. Owns the instance, authenticates to the dashboard. **Canonical term.** | CPA, financial advisor, mortgage lender, attorney |
| **Client** | The AOP's own end user. Anonymous visitor on the AOP's public website. | A taxpayer, a borrower, a prospective client |
| **Vertical** | The AOP's domain. Determines authoritative sources, disclaimer wording, document types — all **per-instance configuration**. | tax, advisory, lending, legal |

**Terminology reconciliation**: the code predates the term AOP and calls this role
*"customer"* and *"PRACTICE OWNER"* (`template/dashboard/server.js`). Those are the
same entity. New code and docs should say **AOP**; existing code comments are not
worth churning.

**This resolves an apparent ambiguity in the thread.** The request to *"email the CPA
and the AOP"* names **one role twice** — "CPA" is the tax-vertical instance of AOP.
Phase 3 therefore has a **single notification recipient**, not two. If a second,
WeOwn-side recipient was actually intended, that is a new requirement and is not
built here.

Where a tax example appears below it is labelled a **worked example** of a general
mechanism, never the mechanism itself.

---

## 1. Why this document exists

The thread mixes four kinds of work under one heading:

| Kind | Example | Where it lands |
|---|---|---|
| Copy/prompt wording | Replace the "not from your internal files" boilerplate | Workspace config (runtime DB) |
| Retrieval behaviour | Cite the authoritative source instead of guessing | MCP tool pack + KB |
| New product surface | Client sends a document, AOP is notified | New service + portal + dashboard |
| Compliance decision | "can they analyse it securely?" | Procurement, then config |

Treating these as one backlog is how the estimate goes wrong.

**Placeholder policy**: this repo is public. Real AOP booking/portal URLs are **not**
written here or into any template. They are per-instance configuration
(`INTAKE_PORTAL_URL`, `BOOKING_URL`).

---

## 2. Traceability — every thread item

Closes the "10 changes" question: nothing was lost in the paste; the thread's ten
map to six behaviour changes, two capability questions, and two cross-cutting
requirements.

| # | Thread item | Plan item | Type |
|---|---|---|---|
| 1 | Document upload → tell client where to upload + booking link | 0.1 + Phase 4 | Change |
| 2 | "Can the AOP run this on the backend?" (analyse client docs) | Phase 4 + Phase 5 | Capability |
| 3 | Unanswered question → email AOP + prompt at next login → add to KB | Phase 3 | Build |
| 4 | Authoritative source citation ("According to irs.gov…") | Phase 2 | Build |
| 5 | Kill the repetitive "not from your internal files" boilerplate | 0.2 | Change |
| 6 | Public vs private persona split | 0.3 | Change |
| 7 | Better follow-up question (fiscal vs calendar year) | 0.4 | Change |
| 8 | "Learn to clarify" whenever a question needs clarification | 0.4 | Change |
| 9 | Secure document analysis → unlocks all verticals | Phase 5 | Capability |
| 10 | Some items deferred until after buildathon | §6 sequencing | Scheduling |

---

## 3. What already exists — do not rebuild

Verified by reading the code 2026-09-17. **Roughly half the requested workflow is
already built.**

| Capability | Status | Location |
|---|---|---|
| AOP authenticated surface | ✅ Built | `template/dashboard/server.js` (1058 lines, zero npm deps) |
| Password auth (scrypt) + OIDC/Keycloak SSO | ✅ Built | `/api/login`, `/oidc/login`, `/oidc/callback` |
| Document upload, type allowlist, size cap | ✅ Built | `uploadRejection()`, `UPLOAD_ALLOWED_EXT`, `UPLOAD_MAX_BYTES` (25 MB; pdf, md, markdown, txt, csv, docx) |
| Document library + full text preview | ✅ Built | `/api/documents`, `/api/documents/content`, `/api/upload-policy` |
| AOP analyses a document privately | ✅ Built | `WS_PRIVATE_SLUG` |
| **Public / private lane separation** | ✅ **Already structural** | `WS_PUBLIC_SLUG` grounds the widget; `WS_PRIVATE_SLUG` is private chat |
| Declarative MCP tool pack (IaC) | ✅ Built | `template/storage/mcp/` — registered and `enabled: true` in `storage/plugins/anythingllm_mcp_servers.json` |
| Agent skills exist in-product | ✅ Built | `AGENT_SEARCH_PROVIDER: searxng-engine` |
| Reasoning-leak strip on public embed | ✅ Built | `template/embed-filter/server.js` |
| Transactional email (SMTP) | ⚠️ **Elsewhere** | `billing-docker` — pattern to port |
| **Client-facing intake portal** | ❌ **Does not exist at all** | Phase 4.0 |
| Client (unauthenticated) upload | ❌ Missing | Phase 4.1 |
| "Client" as an entity, with notes | ❌ Missing | Phase 4.4 |
| Agent-triggered workflows | ❌ Missing | Phase 4.6 |
| Version-controlled system prompts | ⚠️ **Fleet tenants: already built** — `weown-fleet` `prompts/ws-{public,private}.tmpl`, versioned marker, applied by `apply-product-config.sh`. This repo's own sites: mechanism only, no content synced yet | Phase 1 |

None of the built capabilities are vertical-specific. The foundation is already
general; only the *content* loaded into it is domain-shaped.

---

## 4. Non-negotiable constraints

### C1 — Client documents must never reach the public workspace

`WS_PUBLIC_SLUG` grounds the public chat widget. Any document embedded there becomes
retrievable context for *any anonymous visitor* — one client's document answerable
to the next stranger. Severity scales with vertical (financial records, privileged
legal material, lending files); the mechanism is identical in all.

Client uploads land in **quarantine storage that is never embedded into any
workspace**, promoted into `WS_PRIVATE_SLUG` only by explicit authenticated AOP
action. Highest-severity failure mode in this plan, and easy to hit by accident
because the *existing* upload path ingests straight into the library.

### C2 — `embed-filter` holds no secrets, ever

It sits in front of the AOP's public widget so an internal credential failure cannot
take their website down. Upload handling needs storage credentials. **Upload
handling does not go in `embed-filter`.**

### C3 — The current upload policy assumes an authenticated uploader

`server.js`: *"The uploader is the authenticated PRACTICE OWNER uploading their OWN
grounding [documents]"*, under a `locked-down release` header. Phase 4 deliberately
reopens that assumption — explicitly, with compensating controls, not silently.

### C4 — System prompt contents are not secret-safe

Reproduced live 2026-09-01: unauthenticated `POST /api/embed/<id>/stream-chat`
returned 1,445 characters of reasoning quoting the workspace system prompt verbatim.
Assume anything in the public prompt is disclosable.

### C5 — Repo hygiene

Public repo. No real customer URLs, emails, PII, private IPs. Secrets via Infisical.
Branches match `^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$`.

### C6 — No build may hardcode a vertical

Sources, disclaimer wording, document types, referral language are per-instance
config. A `tax`-shaped conditional in shared code is a defect.

---

## 5. Phases

**S** ≈ under a day · **M** ≈ 2–4 days · **L** ≈ 1–2 weeks · **XL** ≈ needs a
decision outside engineering.

---

### Phase 0 — Prompt and copy changes · **S** · no code

| # | Change | Workspace |
|---|---|---|
| 0.1 | Upload refusal gains two links: intake portal + booking. Keep the refusal — rejecting the file *is* the security behaviour. | Public |
| 0.2 | Replace the long "not from your internal files" boilerplate with one short line. | Both |
| 0.3 | Split personas. The private agent stops referring the AOP to the professional they *are*; it offers to do the work. The public agent offers help and booking. | Per workspace |
| 0.4 | Clarify before answering when the answer is conditional. | Both |

**Wording is per-vertical config, not a constant.** The thread's string —
*"…discuss with your tax advisor"* — is the **tax worked example**. General form:
*"…discuss with your \<PRACTITIONER_NOUN\>"*, set per instance.

0.3 is the more interesting bug: the private agent told a professional to consult a
professional. Vertical-independent; recurs identically on a legal instance.

**0.1 is blocked on Phase 4.0** — the portal does not exist (confirmed). Until it
ships, 0.1 goes to demo instances only, pointed at a staged page. **A production bot
must not hand clients a dead link for sensitive documents** — that is worse than
today's honest refusal.

**Acceptance**: replay the thread's prompts on both lanes; no "consult a
\<practitioner\>" survives on the private lane; boilerplate gone; no vertical noun
hardcoded in shared config.

---

### Phase 1 — System prompts under version control · **M** · foundational

The agent's entire behaviour lives only in the AnythingLLM runtime DB, while
everything around it is strict IaC. Phase 0 makes six changes to an artifact with no
review, no CI, no rollback, no drift detection. It compounds per vertical: four
verticals means four hand-maintained prompt pairs and no way to diff them.

- **Registry tenants are already covered**: `weown-fleet` renders per-tenant
  prompts from versioned templates (`prompts/ws-{public,private}.tmpl`, a
  `[weown-chat prompt vN …]` marker) and `apply-product-config.sh --apply`
  re-stamps them. Phase 1 here is for the sites in *this* repo that the
  registry does not manage; do not build a second template system for tenants.
- Store: `sites/<name>/prompts/{public,private}.md`
- Shared base + per-vertical overlay, so **C6 is structurally enforced**
- Apply: a `scripts/` helper in the style of `allm-admin-account.sh`, run by a
  human holding the admin key — not wired into `deploy.yml.jinja` yet (see status)
- Drift detection: compare live vs committed; report, don't auto-fix

**Acceptance**: prompt changes require a PR; `deploy.sh` makes live match committed;
fleet drift is detectable from a script.

**Before Phase 3**: the gap loop writes to the KB. Adding an automated writer to an
unversioned artifact compounds the problem.

**Status (this PR)**: ships the mechanism only —
[`scripts/allm-prompt-sync.sh`](../../anythingllm-docker/scripts/allm-prompt-sync.sh)
(`discover` / `pull` / `diff` / `push`, admin key via `read -rs`, never through an
agent) and the convention scaffolding for `dev-weown-anythingllm`, the lowest-risk
target. **No prompt content is committed yet** — bootstrapping requires the live
admin key, which per `AGENTS.md` must be run by a human, not an agent; see that
site's `prompts/README.md` for the exact steps. Deliberately **not** wired into
`deploy.yml.jinja` in this pass: the mechanism needs to prove itself against one
live instance first. Extending the convention to the other three sites
(`ai.weown.agency`, `beta-weown-chat`, `s004.ccc.bot`) and wiring drift-checking
into deploy are follow-up changes once this is proven.

**One assumption this script makes and cannot verify from this repo**: AnythingLLM's
system-prompt field is `openAiPrompt` on `POST /api/v1/workspace/:slug/update`, per
AnythingLLM's documented API — no AnythingLLM source is vendored here to confirm it
against. The script's `discover` mode is a read-only GET built specifically to
verify this before `pull`/`push` are trusted on a real instance.

---

### Phase 2 — Authoritative-source citation · **M**

Cite the authoritative body with a link instead of hedging. Surfaced by a
mileage-rate answer that was both hedged and undated.

Build a **per-instance source registry** (domain, display name, citation phrasing),
not an IRS integration. Seeded for the confirmed target verticals:

| Vertical | Authoritative sources |
|---|---|
| Tax / accounting | irs.gov, state revenue departments |
| Advisory / securities | SEC, FINRA |
| Lending / mortgage | CFPB, HUD, Fannie Mae / Freddie Mac |
| Legal | state bar, court rules, statute repositories |

Retrieval design:

| | **A — Live retrieval** | **B — Curated facts doc** |
|---|---|---|
| Mechanism | `fetch` / `searxng` MCP (deployed) | Committed markdown in KB |
| Accuracy | Current by construction | Correct until the cycle turns |
| Failure mode | Cites wrong page confidently | Silently stale |
| Latency | Seconds, user-visible | None |

**Recommendation: B for known-volatile figures, A as fallback.** Every vertical has a
small enumerable set of high-traffic figures on a known schedule (tax: mileage rate,
standard deduction; lending: conforming loan limits). A curated dated table is
deterministic, citable, reviewable.

**Every answer must carry its effective period.** A rate without a year is wrong half
the time by construction; same for a loan limit.

**Hard requirement**: citation phrasing fires only on facts *actually retrieved*. A
model that picks up "According to \<source\>" as a stylistic tic over its own
recollection is worse than hedging — it launders a guess as a citation. Couple
citation string and retrieval **in code**, not in prose.

**Acceptance**: worked-example query returns the correct dated figure, citation, and
working link; no citation phrasing on any answer without retrieval behind it; adding
a vertical's sources is config-only.

---

### Phase 3 — Knowledge-gap capture loop · **M**

When the bot can't answer, email the **AOP** and prompt them at next login:
*"the bot couldn't answer this — add it to the knowledge base?"*

**Single recipient** (see §0). Fully vertical-independent.

**3.1 Gap detection** — the model emits a structured no-answer marker (prompt-level;
needs Phase 1 to be safe). The `embed-filter` proxy is the alternative interception
seam — it already parses every SSE `textResponse` on the public lane — but per C2 it
may only *emit an event*, never send mail.

**If the `embed-filter` seam is used, its hand-off must be specified before build.**
`embed-filter` is public-facing, stateless and secret-free (C2), and a visitor can
make it fire, so "emit an event" alone is either spoofable or lossy, and the
"exactly one gap" acceptance below cannot be met. The hand-off must define:

- **Transport and authentication**: an endpoint on the internal compose network
  only — never published, never routed by Caddy. With no shared secret allowed
  (C2), that network position is the authentication, so it must be stated and
  tested (unreachable from outside the droplet).
- **Idempotency**: a key derived from embed id + chat session + the question
  (e.g. a hash), deduplicated on insert, so a retry or a replay is one gap.
- **Retry**: bounded retries with backoff from `embed-filter`; dedupe makes them
  safe. What happens after the retry budget (drop and count, no content per R3)
  is stated, not left implicit.

If any of these cannot be met, drop the `embed-filter` seam and use only the
structured-marker path.

**Prefer the structured marker over phrase-matching.** Phrase-matching breaks the
moment Phase 0 rewords the fallback, and again for every vertical that words it
differently.

**3.2 Notification** — port the SMTP pattern from `billing-docker`.
⚠️ **DigitalOcean blocks outbound 587**; that compose defaults `SMTP_PORT` to 2525.

**3.3 Review queue** — dashboard section listing gaps with one-click "add answer to
KB". Dashboard already has authenticated document write; new view + persistence in
`dashboard_state`.

**Rate limiting is required.** An unauthenticated public endpoint that triggers email
to the AOP is a spam cannon pointed at your customer. Digest, cap per hour,
deduplicate.

**Acceptance**: one unanswerable question → exactly one queued gap and one (possibly
digested) email; answerable into the KB without leaving the dashboard; 100 junk
questions do not produce 100 emails.

---

### Phase 4 — Client document intake · **L** · the main build

Client on the AOP's public website wants to send a document → agent recognises intent
→ client uploads via a secure link → AOP notified → document appears against that
client in the dashboard → client books a session.

**This is the horizontal.** Intake is the common shape of professional services: a
tax client sends a return, a borrower sends pay stubs, a legal client sends a
contract, an advisory client sends statements. Built domain-neutral it is the
product's core capability, not a tax feature. Document types are already config.

#### 4.0 Client-facing intake portal · **M** · NEW — does not exist

Confirmed: there is no portal today, nor any third-party one to link to. We build it.

- **Host it on the instance**, on a path or subdomain Caddy already terminates TLS
  for. The AOP links to it from their own site. Hosting on the AOP's website would
  put an upload form outside our control and outside our TLS/CSP posture.
- Minimal scope: branded page, token validation, file picker, progress, confirmation,
  booking link. No account creation, no client login.
- Must state plainly what happens to the document and who sees it.
- Per C6, branding and vertical copy are per-instance config.

#### 4.1 Tokenised upload service · **M**

**Not** in `embed-filter` (C2). Either a new container or a narrowly scoped public
route on the dashboard — noting the latter gives the dashboard an unauthenticated
attack surface it does not have today, a threat-model change to decide consciously.

- Single-use, expiring, unguessable tokens minted per chat session
- **The token is a bearer credential and never appears in a URL path or query.**
  Caddy access logs record request URLs and the fleet exports them (OTel), and a
  URL also lands in browser history and `Referer` headers. Carry it in the URL
  **fragment** (never sent to the server) and exchange it by `POST`, or in an
  `Authorization` header. The portal sends `Referrer-Policy: no-referrer` and
  `Cache-Control: no-store`, and a Caddy log filter redacts the token if it is
  ever present. Single-use narrows the window but does not close it before
  first use.
- **Each token is bound to one client record at mint time** (see 4.4): an
  AOP-created client record, or an anonymous record keyed by that token. An
  upload attaches only to the record its token was minted for, and nothing is
  promoted out of quarantine without AOP review of that record.
- Reuse existing `uploadRejection()` allowlist and size cap
- Rate limiting per IP and per token, **plus an instance-wide quarantine quota**
  (total bytes and object count): per-IP and per-token limits alone do not bound
  growth across many sessions and addresses.
- **Order: write to non-indexed quarantine (4.2) → malware scan, failing closed
  → only then eligible for promotion.** Scanning needs a holding area, so "scan
  before anything is stored" means *before anything is promotable*, never before
  the quarantine write. A file that fails or times out the scan is never promoted.

#### 4.2 Quarantine storage · **M**

Per **C1**, the load-bearing control. Encrypted at rest, **outside any workspace
document library**, not embedded, not indexed, unreachable by any agent until
promoted. DO Spaces (S3-compatible, already used for backups) is the store, but
**not the backup target or its credentials**. The design must specify, before R4
can be marked delivered:

- **Separation**: a separate quarantine bucket, or a prefix with its own
  least-privilege key scoped to that prefix. The internet-facing uploader never
  holds backup-scope credentials.
- **Encryption and key ownership**: per-instance client-side encryption of each
  object before upload (the backups' GPG `--recipient-file` pattern, private key
  off the droplet), with key access and rotation stated. "S3-compatible" is not
  an encryption control, and backups are encrypted only when
  `BACKUP_GPG_PUBLIC_KEY` is set.
- **Retention and deletion**: per instance and independent of the backup GFS
  schedule, so a quarantined object is not kept for backup retention, and
  deletion is provable. Obligations differ by vertical and are config.

#### 4.3 AOP notification · **S** (after 3.2)

**Send a link, not an attachment.** Deliberate change to the thread's spec.

Emailing a sensitive client document puts it in an inbox, auto-forwards, phone syncs,
and at rest on the relay — converting "we handled your documents securely" into "we
emailed your client's private records around." It contradicts the claim being sold,
and in regulated verticals it is the specific thing the regime prohibits.
Notification plus authenticated dashboard link is safer *and* less work.

#### 4.4 Dashboard: clients, documents, notes · **L**

Genuinely new — no client/contact model exists. Client record, linked documents,
notes, promote-to-private-workspace action. Multi-tenancy is simple: each AOP has
their own droplet, so clients are always one practice's.

**Minimum client identity**: since clients have no accounts or logins (4.0), a
client record is either created by the AOP or an anonymous record keyed by the
upload token. The token is bound to exactly one record when it is minted (4.1);
"appears against that client" means that binding, never a name or email the
uploader types. Promotion out of quarantine requires the AOP to review the record.

#### 4.5 Booking handoff · **S**

Configured `BOOKING_URL`. Prefill parameters possible but add coupling — defer.

#### 4.6 Agent trigger · **M** — see §6 probe

Detect intent with the model; **execute deterministically**. The model classifies
"this person wants to send a document"; the widget renders a real UI card with the
tokenised link and booking button.

Never let the model emit the URL as text — it will eventually hallucinate a
near-miss, and that is a link to a document drop-box.

Architecture depends on the agent-mode probe in §6. If agent mode is unavailable on
the embed path, fall back to widget-side intent handling; the deterministic-execution
requirement is unchanged either way.

**Acceptance**: a client sends a document without authenticating; it never becomes
retrievable by the public agent (**test explicitly** by querying the public bot for
its contents); the AOP sees it against the client record; the client can book; an
expired or reused token fails closed; nothing in the implementation names a vertical.

---

### Phase 5 — No-leak, no-retention inference · **XL** · decision, then config

**"Secure" is now defined**: *client data is not leaked and not retained by the
agents or the model.* That is a testable requirement, not a slogan.

The mechanical capability already exists — the AOP can upload to the private
workspace and analyse today (§3). What does not exist is this posture.

**Requirements**

| # | Requirement | Status |
|---|---|---|
| R1 | Inference provider retains no prompt or completion content | ❌ Unverified — see below |
| R2 | No customer data used for model training | ❌ Unverified |
| R3 | No content in application or proxy logs | ⚠️ Audit needed |
| R4 | Encrypted in transit and at rest | ⚠️ Partly — 4.2 completes it once its key model is specified |
| R5 | Tenant isolation | ✅ Per-droplet by construction |
| R6 | Not retrievable by the public agent | ⚠️ C1 + 4.2 deliver this |
| R7 | Reasoning/prompt cannot leak to visitors | ⚠️ `embed-filter` mitigates; C4 is model-level |

**R1/R2 are the blocker.** `LLM_PROVIDER` is **OpenRouter**, which routes to upstream
providers whose retention policies differ *per provider and per model*. This has a
sharp consequence worth stating plainly:

> **Provider routing stops being a quality knob and becomes a compliance
> control.** The route determines which third party sees client documents and
> under what retention policy. It must be restricted to verified zero-retention
> providers and changed only through review — today it can be changed like any
> other setting.

**A model slug is not that control.** `OPENROUTER_MODEL_PREF` names a model; it
does not choose the upstream provider, and OpenRouter can route or fall back across
providers for one model. The control is **provider routing**: OpenRouter provider
preferences (an allowed-provider list with `allow_fallbacks: false`, and
`data_collection: "deny"` / ZDR-only), or the account-level ZDR setting — **checked
at runtime** against the provider each response reports — or self-hosted inference.

**Chat is not the only route to OpenRouter.** Two live paths send customer text
there without consulting any chat-model setting, and R1/R2 cover them too:

- the **`rag-memory` MCP server** embeds knowledge-base text through
  `EMBED_API_BASE`, set to `https://openrouter.ai/api/v1` in
  `template/storage/plugins/anythingllm_mcp_servers.json.jinja` (and the default
  in `template/storage/mcp/lancedb/index.js`);
- **`EMBEDDING_ENGINE=openrouter`**, an accepted setting
  (`template/terraform/terraform.tfvars.example.jinja`), sends document embeddings
  to OpenRouter.

**Any route not verified fails closed**: it is disabled or pointed at a verified
provider, never left on a default.

**Existing claims this reopens.** `docs/CUSTOMER_INSTANCE_PROVISIONING.md`
(Compliance facts, *LLM processing*) states that routing is restricted to ZDR-only
endpoints by an account-level guardrail, and `scripts/provision-openrouter-key.sh`
tells the operator every per-customer key inherits it. This plan marks R1/R2
unverified because the evidence behind that claim is not recorded anywhere:

- the account setting itself, captured (who checked, when);
- written zero-retention / no-training terms for each upstream provider in use;
- coverage of the embedding paths above, which that claim does not mention;
- a runtime check that the provider serving each response is on the verified list.

Until those exist, both statements are pending verification, and the customer-facing
one is marked so.

**Verification tasks** (none are code):

1. Enumerate which upstream providers the chat model **and both embedding routes**
   (`rag-memory` `EMBED_API_BASE`, `EMBEDDING_ENGINE`) actually route to
2. Confirm zero-retention / no-training terms in writing for each
3. Restrict provider routing (chat and embeddings) to that verified set with
   fallbacks off, check the serving provider at runtime, and document the
   constraint; disable or repoint any route not verified
4. Audit R3 across AnythingLLM, `embed-filter`, Caddy access logs, and OTel export
5. Decide whether contractual assurance suffices or self-hosted inference is required
   (`llm-d/` exists in this repo)

**Do not market "securely analyse your confidential documents" until R1–R3 are
evidenced.** That sentence is a compliance claim, and a different one per vertical —
attorneys bring privilege, lenders bring GLBA, advisory brings SEC/FINRA
recordkeeping.

---

## 6. Open item — agent-mode probe · **S** · do this first

**Question**: is AnythingLLM agent mode (and therefore MCP tool-calling) available on
the **unauthenticated embed path**? Decides 4.6's architecture.

Known from the code: agent skills exist in-product (`AGENT_SEARCH_PROVIDER:
searxng-engine`) and the MCP pack is registered `enabled: true`. Neither establishes
that the *embed* handler can invoke them — agent invocation is conventionally a
workspace-chat affordance, and the embed handler is a different code path.

**Prior expectation**: likely unavailable on the embed path. Treat this as a
hypothesis to disprove, not a finding.

**Procedure** — run against the **dev instance only**, never production:

1. **Baseline.** In the dashboard private chat, invoke an agent action that
   demonstrably uses a tool (e.g. a web search via the searxng skill). Confirm it
   works authenticated. This proves the probe itself is valid.
2. **Embed path.** Send the same agent-invoking message to
   `POST /api/embed/<embed-id>/stream-chat` with an allowlisted `Origin` header.
   On production this sits behind `embed-filter`; on dev, hit AnythingLLM directly so
   the filter is not a variable.
3. **Compare.** Does the response show tool use, or a plain LLM answer that merely
   *describes* searching? The difference is the whole question.
4. **Confirm server-side.** Check AnythingLLM container logs for agent/MCP invocation
   during the embed request. **The response text alone is not evidence** — a model
   will happily narrate a tool call it never made.

**Method warning**, learned expensively on this stack (see `embed-filter` header):
do not accept a plausible-looking response as proof. Verify at the server, and do not
probe with a greeting — fallback paths behave differently and will "prove" whichever
answer you hoped for.

**Outcome**: if available → 4.6 uses an MCP tool (`request_document_upload`). If not
→ widget-side intent handling. Either way, deterministic execution stands.

---

## 7. Sequencing

```
§6 agent probe  ──> run first; cheap, unblocks 4.6's design

Phase 0 (config)      ──┐
                        ├─> 0.2/0.3/0.4 ship now; 0.1 waits on 4.0
Phase 1 (prompt VCS)  ──┘
        │
        ├──> Phase 2 (source citation)   — independent after P1
        │
        ├──> Phase 3 (gap capture)       — needs SMTP from 3.2
        │         │
        │         └── shares email transport with ──┐
        │                                           │
        └──> Phase 4 (client intake)  <─────────────┘
                  4.0 portal → 4.1 upload → 4.2 quarantine
                             → 4.3 notify → 4.4 dashboard → 4.5/4.6
                  │
                  └──> Phase 5 (no-leak/no-retention)
                       gates the marketing claim and the vertical
                       expansion, not the build
```

The thread defers some items until after buildathon; placement in the original
message is ambiguous, so **confirm which** before sequencing to it.

---

## 8. Explicitly out of scope

- Reading or analysing documents inside the *public* agent — the refusal is correct
  and stays, in every vertical
- Automated professional advice — every path routes to a human
- Cross-instance or shared client data — instances stay isolated
- Client accounts/logins on the intake portal — token-scoped upload only

---

## 9. For implementers

- Branch: `<type>/<dev>-<description>`, CI-enforced
- Repo-level changes → `/CHANGELOG.md` `[Unreleased]`; per-app → the app's CHANGELOG
- Version per `#WeOwnVer` (`docs/VERSIONING_WEOWNVER.md`)
- Compose changes satisfy the §3.8 hardening checklist in
  `.github/copilot-instructions.md`
- Secrets via Infisical at runtime; never on disk, never in agent context
- **Per C6**: no vertical-specific literals in shared code or shared prompts
