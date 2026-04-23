# VERSIONING_WEOWNVER.md

> Official version nomenclature for ♾️ WeOwnNet 🌐

## Document Info

| Field | Value |
|-------|-------|
| Title | #WeOwnVer Specification (L-094 REVISED) |
| Version | v3.3.4.1 |
| Status | ✅ ACTIVE — calendar-driven methodology |
| Approved by | yonks.box｜🤖🏛️🪙｜Jason Younker ♾️ |
| Effective | Season 3 (Feb 2026+) |

---

## 1. FORMAT (L-094 REVISED)

**Season 3+ uses calendar-driven 4-part versioning:** `vSEASON.MONTH.WEEK.ITERATION`

```
vSEASON.MONTH.WEEK.ITERATION
v3.3.4.1
│ │ │ │
│ │ │ └── ITERATION — Nth version of this artifact this week
│ │ └──── WEEK      — offset within month (1-based, ISO-week based)
│ └────── MONTH     — ordinal month of the season (1-based)
└──────── SEASON    — ecosystem season number (1+)
```

| Position | Name | Range | Description |
|----------|------|-------|-------------|
| 1st | SEASON | 1+ | Ecosystem season number (see §4 Season Calendar) |
| 2nd | MONTH | 1-4 | Ordinal month within season (1 = first month of season) |
| 3rd | WEEK | 1+ | ISO-week offset within the month (see §3) |
| 4th | ITERATION | 1+ | Nth iteration of this artifact this week |

### Season-to-format history

| Season | Version Format | Example | Notes |
|--------|----------------|---------|-------|
| #WeOwnSeason001 | v1.X.X | v1.4.18 | SemVer-style (legacy) |
| #WeOwnSeason002 | v2.X.X | v2.4.18 | SemVer-style (legacy) |
| **#WeOwnSeason003+** | **vS.M.W.I** | **v3.3.4.1** | Calendar-driven (L-094 REVISED) |
| #WeOwnSeason004 | v4.X.X.X | v4.1.0.0 | Calendar-driven continues |

---

## 2. VERSION COMPONENTS — CALENDAR-DRIVEN

| Component | Meaning | How to Calculate |
|-----------|---------|------------------|
| Major (v**3**.x.x.x) | Season number | Determined by Season Calendar (§4) |
| Minor (v3.**3**.x.x) | Ordinal month of season | Feb of S3 = 1, Mar = 2, Apr = 3, May = 4 |
| Patch (v3.3.**4**.x) | Week offset within month | ISO-week math (§3) |
| Hotfix (v3.3.4.**1**) | Iteration within week | 1st release this week = 1, 2nd = 2, etc. |

---

## 3. WEEK OFFSET CALCULATION (L-115)

**Week offset within month = (current ISO week) − (first ISO week of month) + 1**

### Step-by-step

| Step | Action | Example (today = 2026-04-23) |
|------|--------|------------------------------|
| 1 | Current ISO week | W17 |
| 2 | First ISO week of current month | Apr 2026 = W14 |
| 3 | Offset = Current − First + 1 | 17 − 14 + 1 = **4** |
| 4 | Version (Season 3, April = month 3) | **v3.3.4.N** |

### Week offset examples — Season 3 (Feb-May 2026)

| ISO Week | Month | Offset | Version |
|----------|-------|--------|---------|
| W06 | Feb 2026 | 1 | v3.1.1.N |
| W07 | Feb 2026 | 2 | v3.1.2.N |
| W08 | Feb 2026 | 3 | v3.1.3.N |
| W09 | Feb/Mar | 4/1 | v3.1.4.N or v3.2.1.N (depends on date) |
| W10 | Mar 2026 | 1 | v3.2.1.N |
| W14 | Apr 2026 | 1 | v3.3.1.N |
| W17 | Apr 2026 | 4 | v3.3.4.N ← today |
| W22 | May 2026 | 4 | v3.4.4.N |

### Boundary rule

When ISO week spans two calendar months, the week belongs to the calendar month containing **its Thursday** (ISO 8601 convention). This matches how ISO weeks are defined.

---

## 4. SEASON CALENDAR

Each season is 4 calendar months.

| Season | Start | End | Months (month-of-season) |
|--------|-------|-----|--------------------------|
| 1 | 2025-06-01 | 2025-09-30 | Jun(1) / Jul(2) / Aug(3) / Sep(4) |
| 2 | 2025-10-01 | 2026-01-31 | Oct(1) / Nov(2) / Dec(3) / Jan(4) |
| **3** | **2026-02-01** | **2026-05-31** | **Feb(1) / Mar(2) / Apr(3) / May(4)** |
| 4 | 2026-06-01 | 2026-09-30 | Jun(1) / Jul(2) / Aug(3) / Sep(4) |

### Month-of-season mapping (#WeOwnSeason003)

| Calendar Month | Month-of-Season (Minor) |
|----------------|--------------------------|
| February | 1 |
| March | 2 |
| April | 3 |
| May | 4 |

---

## 5. EXAMPLES

| Version | Decode |
|---------|--------|
| v3.1.1.1 | Season 3, Feb 2026, Week 1 of Feb, 1st iteration |
| v3.2.3.2 | Season 3, Mar 2026, Week 3 of Mar, 2nd iteration |
| **v3.3.4.1** | **Season 3, Apr 2026, Week 4 of Apr, 1st iteration (today, 2026-04-23)** |
| v3.4.1.1 | Season 3, May 2026, Week 1 of May, 1st iteration |
| v4.1.1.1 | Season 4, Jun 2026, Week 1 of Jun, 1st iteration |

### Multiple iterations the same week

| Iteration | Version | Decode |
|-----------|---------|--------|
| 1st | v3.3.4.1 | Apr W4 of Apr, 1st release |
| 2nd | v3.3.4.2 | Apr W4 of Apr, 2nd release |
| 3rd | v3.3.4.3 | Apr W4 of Apr, 3rd release |

---

## 6. ARTIFACT SCOPE

| Artifact Type | Apply #WeOwnVer | Example |
|---------------|-----------------|---------|
| #SharedKernel | ✅ YES | `SHARED-KERNEL_v3.3.4.1.md` |
| GUIDES | ✅ YES | `GUIDE_GAME-MECHANICS_v3.3.4.1.md` |
| GOV policies | ✅ YES | `GOV-001_v3.3.4.1.md` |
| TEMPLATES | ✅ YES | `TEMPLATE_ADD-CONTEXT_v3.3.4.1.md` |
| RAG uploads | ✅ YES | `filename_v3.3.4.1.md` |
| Code releases | ✅ YES | Git tag `v3.3.4.1` |
| Helm charts | ✅ YES | `Chart.yaml` → `version: 3.3.4-1` (1st iter), `3.3.4-2` (2nd), `3.3.4-3` (3rd); optional rollup `3.3.4`; see §8 |
| Docs in this repo | ✅ YES | Document `Version` field uses `v3.3.4.1` |
| CHANGELOG entries | ✅ YES | `## [v3.3.4.1] — 2026-04-23` |
| CCC-IDs | ❌ NO | Keep `CCC_YYYY-WXX_NNN` |
| Session logs | ❌ NO | Keep timestamp-based |

---

## 7. FILENAME CONVENTION

### Pattern

`NAME_vSEASON.MONTH.WEEK.ITERATION.md` (uppercase tokens are placeholders)

### Examples

| Filename | Decode |
|----------|--------|
| `SHARED-KERNEL_v3.3.4.1.md` | Season 3, Apr, W4 of Apr, 1st iteration |
| `GUIDE_GAME-MECHANICS_v3.2.3.1.md` | Season 3, Mar, W3 of Mar, 1st iteration |
| `GOV-001_v3.4.1.2.md` | Season 3, May, W1 of May, 2nd iteration |

---

## 8. HELM CHART VERSIONING

Helm's `Chart.yaml` `version` field must be SemVer-compatible (MAJOR.MINOR.PATCH[-PRERELEASE]). Map #WeOwnVer onto SemVer as follows:

| Scenario | Chart version | Meaning |
|----------|---------------|---------|
| Iteration 1 (first release of the week) | `3.3.4-1` | Season 3, Apr, W4 — 1st iteration |
| Iteration 2 | `3.3.4-2` | 2nd iteration same week |
| Iteration 3 | `3.3.4-3` | 3rd iteration same week |
| Optional weekly rollup (strictly > every iteration) | `3.3.4` | Weekly "stable" rollup, published after all iterations settle |
| First release of a month | `3.3.1-1` | Season 3, Apr, W1, iter 1 |

### Why iteration 1 is `3.3.4-1` (not `3.3.4`)

SemVer precedence rules: `3.3.4-2` **sorts BELOW** `3.3.4` because ANY pre-release is considered less than the associated release. If iteration 1 were published as `3.3.4` and iteration 2 as `3.3.4-2`, Helm / OCI / `semver` tooling would treat iteration 2 as a **downgrade**, which breaks `helm upgrade`, `helm search repo --versions` ordering, container-tag semver sort, and any Renovate/Dependabot comparisons.

By giving every iteration a `-N` prerelease suffix, ordering stays strictly monotonic:

```
3.3.4-1  <  3.3.4-2  <  3.3.4-3  <  3.3.4   (optional rollup — strictly greater)
```

Rationale: preserves #WeOwnVer semantics (SEASON.MONTH.WEEK in SemVer MAJOR.MINOR.PATCH; ITERATION in SemVer prerelease), while guaranteeing SemVer-compliant monotonic ordering for all tooling.

---

## 9. CI/CD & GIT TAG USAGE

- **Git tags**: use the full `v3.3.4.1` form (all 4 components) — Git tags have no SemVer sorting semantics
- **Docker image tags**: use `3.3.4.1` for specific iterations or `3.3.4` for weekly rollups
- **OCI artifacts (Helm / SemVer-ordered)**: iteration 1 = `3.3.4-1`, iterations 2+ = `3.3.4-2`, `3.3.4-3`, … ; optional weekly rollup = plain `3.3.4` (strictly > every iteration). Rationale: SemVer precedence requires prerelease suffix for strict monotonic ordering — see §8.
- **PR bodies / CHANGELOG**: use the full `v3.3.4.1` #WeOwnVer form

---

## 10. COMPARISON

| System | Format | Example | Notes |
|--------|--------|---------|-------|
| SemVer | MAJOR.MINOR.PATCH | 2.4.1 | No calendar context |
| CalVer | YYYY.MM.DD | 2026.04.23 | No ordinal rhythm |
| **#WeOwnVer** | vSEASON.MONTH.WEEK.ITERATION | **v3.3.4.1** | Calendar-aligned + ordinal rhythm + iteration-aware |

---

## 11. RULES (ENFORCEABLE)

| ID | Rule |
|----|------|
| L-094 | #WeOwnVer is **calendar-driven**: Major=Season, Minor=Month-of-Season, Patch=WeekOffset, Hotfix=Iteration. NOT feature-driven versioning. |
| L-115 | #WeOwnVer WEEK component MUST match the current ISO-week offset within the calendar month. Agents MUST calculate the correct offset before assigning a version. Wrong week offset = **#BadAgent**. |
| L-116 | ITERATION resets to `1` each new week. Never reuse an iteration number from a prior week. |
| L-117 | When Season or Month rolls over, reset the lower components (`MONTH→1`, `WEEK→1`, `ITERATION→1`) as appropriate for the calendar boundary. |

---

## 12. CALCULATION CHEAT SHEET

Given a date `D`:

1. **SEASON**: look up in §4 Season Calendar
2. **MONTH**: (calendar month of `D`) − (first calendar month of the season) + 1
3. **WEEK**: (ISO week of `D`) − (ISO week of the 1st of `D`'s calendar month, adjusted by ISO Thursday rule) + 1
4. **ITERATION**: `N + 1` where `N` = count of artifacts released in the same week at the same scope

Example (today = **2026-04-23**):
- SEASON = 3 (Feb-May 2026)
- MONTH = Apr = 3rd month of Season 3 → `3`
- WEEK = W17 − W14 + 1 = `4`
- ITERATION = first artifact this week → `1`
- **Result: `v3.3.4.1`**

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v2.4.0 | 2026-01-16 | Initial #WeOwnVer specification (legacy SemVer-style) |
| v2.5.0 | 2026-01-26 | Added Helm chart versioning, transitioned to early #WeOwnVer |
| **v3.3.4.1** | **2026-04-23** | **L-094 REVISED: calendar-driven `vSEASON.MONTH.WEEK.ITERATION`, L-115 ISO-week offset rule, L-116/L-117 reset rules, Season Calendar finalized** |
