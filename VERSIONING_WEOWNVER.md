# VERSIONING_WEOWNVER.md

> Official version nomenclature for ♾️ WeOwnNet 🌐

## Document Info

| Field | Value |
|-------|-------|
| Title | #WeOwnVer Specification |
| Version | v2.5.0 |
| Status | ✅ APPROVED |
| Approved by | yonks.box｜🤖🏛️🪙｜Jason Younker ♾️ |
| Effective | Season 2 Week 5 (Jan 2026) |

---

## 1. FORMAT

SEASON.WEEK.DAY.VERSION

| Position | Name | Range | Description |
|----------|------|-------|-------------|
| 1st | SEASON | 1+ | Ecosystem season number |
| 2nd | WEEK | 1-17 | Week within season |
| 3rd | DAY | 0-7 | 0=summary, 1=Mon → 7=Sun |
| 4th | VERSION | 0+ | Release within day |

---

## 2. DAY VALUES

| Value | Day | Note |
|-------|-----|------|
| 0 | Summary | Week rollup / no daily |
| 1 | Monday | |
| 2 | Tuesday | |
| 3 | Wednesday | |
| 4 | Thursday | |
| 5 | Friday | |
| 6 | Saturday | |
| 7 | Sunday | |

---

## 3. EXAMPLES

| Version | Decode |
|---------|--------|
| 3.1.1.1 | Season 3, Week 1, Monday, 1st release |
| 3.2.2.2 | Season 3, Week 2, Tuesday, 2nd release |
| 3.3.3.3 | Season 3, Week 3, Wednesday, 3rd release |
| 3.4.0 | Season 3, Week 4, summary |
| 3.2.5.3 | Season 3, Week 2, Friday, 3rd release |

---

## 4. MULTIPLE RELEASES (SAME DAY)

| Release | Version | Decode |
|---------|---------|--------|
| 1st | 3.2.2.1 | Season 3, Week 2, Tuesday, 1st |
| 2nd | 3.2.2.2 | Season 3, Week 2, Tuesday, 2nd |
| 3rd | 3.2.2.3 | Season 3, Week 2, Tuesday, 3rd |

---

## 5. SEASON CALENDAR

| Season | Start | End | ISO Weeks | Months |
|--------|-------|-----|-----------|--------|
| 1 | 2025-06-01 | 2025-09-30 | W23-W40 | Jun-Sep 2025 |
| 2 | 2025-10-01 | 2026-01-31 | W40-W05 | Oct 2025-Jan 2026 |
| 3 | 2026-02-01 | 2026-05-31 | W06-W22 | Feb-May 2026 |
| 4 | 2026-06-01 | 2026-08-31 | W23-W35 | Jun-Aug 2026 |

### ISO Week Reference (2026)

| ISO Week | Dates |
|----------|-------|
| W03 | Jan 12-18, 2026 |
| W04 | Jan 19-25, 2026 |
| W05 | Jan 26-Feb 1, 2026 |
| W06 | Feb 2-8, 2026 |
| W07 | Feb 9-15, 2026 |

---

## 6. ARTIFACT SCOPE

| Artifact Type | Apply #WeOwnVer | Example |
|---------------|-----------------|---------|
| #SharedKernel | ✅ YES | SHARED-KERNEL_v3.1.1.1.md |
| GUIDES | ✅ YES | GUIDE_GAME-MECHANICS_v3.1.1.1.md |
| GOV policies | ✅ YES | GOV-001_v3.1.1.1.md |
| TEMPLATES | ✅ YES | TEMPLATE_ADD-CONTEXT_v3.1.1.1.md |
| RAG uploads | ✅ YES | filename_v3.1.1.1.md |
| Code releases | ✅ YES | v3.1.1.1 tag |
| Helm charts | ✅ YES | Chart version: 2.5.0 (Season 2, Week 5, summary) |
| CCC-IDs | ❌ NO | Keep `CCC_YYYY-WXX_NNN` |
| Session logs | ❌ NO | Keep timestamp-based |

---

## 7. FILENAME CONVENTION

### Pattern

<NAME>_v<SEASON>.<WEEK>.<DAY>.<VERSION>.md

### Examples

| Filename | Decode |
|----------|--------|
| SHARED-KERNEL_v3.1.1.1.md | Season 3, Week 1, Monday, 1st |
| GUIDE_GAME-MECHANICS_v3.2.0.md | Season 3, Week 2, summary |
| GOV-001_v3.3.5.2.md | Season 3, Week 3, Friday, 2nd |

---

## 8. HELM CHART VERSIONING

For Helm charts and code releases, use simplified format for weekly releases:

| Format | Example | Meaning |
|--------|---------|---------|
| SEASON.WEEK.0 | 2.5.0 | Season 2, Week 5, summary |
| SEASON.WEEK.DAY.VERSION | 2.5.7.1 | Season 2, Week 5, Sunday, 1st release |

**When to use 3-digit vs 4-digit:**
- **3-digit (SEASON.WEEK.0)**: Weekly rollup releases, no specific day
- **4-digit (SEASON.WEEK.DAY.VERSION)**: Multiple releases in same day

---

## 9. TRANSITION PLAN

| Phase | When | Version Format |
|-------|------|----------------|
| LEGACY | W03-W04 (Jan 2026) | v2.4.x (SemVer) |
| CURRENT | W05 (Jan 25-31, 2026) | 2.5.0 (#WeOwnVer) |
| ONGOING | W06+ (Feb 2026+) | All new = #WeOwnVer |

---

## 10. COMPARISON

| System | Format | Example | Notes |
|--------|--------|---------|-------|
| SemVer | MAJOR.MINOR.PATCH | 2.4.1 | No time context |
| CalVer | YYYY.MM.DD | 2026.01.16 | No semantic meaning |
| **#WeOwnVer** | SEASON.WEEK.DAY.VER | 3.1.4.2 | Time + rhythm + semantic |

---

## 11. SPECIAL CASES

| Pattern | Meaning |
|---------|---------|
| `x.x.0` | Week summary (3 digits) |
| `x.x.x.0` | Day summary (4 digits) |
| `x.x.x.1` | First release of day |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v2.4.0 | 2026-01-16 | Initial #WeOwnVer specification |
| v2.5.0 | 2026-01-25 | Added Helm chart versioning, transitioned to #WeOwnVer |
