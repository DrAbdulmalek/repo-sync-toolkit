# Ecosystem State — Source of Truth

> Snapshot date: 2026-07-31
> Maintained alongside `GOVERNANCE.md`. Update on every repo-level decision.

## Purpose

This document records the **verified state** of all repositories under
`DrAbdulmalek/`, the **canonical relationships** between them, and the
**product identity boundaries** that must not be crossed.

It exists to prevent:

- README/release claims that do not match the actual repo state.
- Product scope drift (e.g. medical logic leaking into a general file
  manager, or general file-manager logic leaking into the medical suite).
- Silent duplication of functionality across support repos.
- Ambiguous archival status for legacy repos.

---

## Repositories (9 total)

### Primary products

| Repo | Role | Status | Latest tag |
|------|------|--------|------------|
| `intelli-file-manager` | Local-first desktop file manager for personal use | active | `v2.1.0` |
| `omni-medical-suite` | Medical OCR/NLP platform (medical scope only) | active, stable | `v1.2.0` |

### Support / data layer

| Repo | Role | Status | Latest tag |
|------|------|--------|------------|
| `repo-sync-toolkit` | Security-sensitive git sync utility | active | (none) |
| `arabic-medical-glossary` | Arabic medical glossary data | active | `v1.0.0-rc1` |
| `glossary-api` | API layer for the glossary | active | (none) |
| `dictionaries-csv` | CSV dictionaries (data only) | active | (none) |
| `telegram-tools` | Training-data feeder for Omni | active | `v1.2.1` |

### Archive / under review

| Repo | Role | Status | Latest tag |
|------|------|--------|------------|
| `OmniFile_Processor` | Legacy — superseded by omni-medical-suite | README deprecated, GitHub archive flag pending | (none) |
| `sync-github` | Legacy — superseded by repo-sync-toolkit | README archived, GitHub archive flag pending | (none) |

---

## Product Identity Rules (strict)

- **IntelliFile** is a **general local-first desktop file manager** for
  personal use. Any "medical" expansion is a bug in product scope, not a
  feature. (Known issue: `src/core/smart_tagger.py` contains Arabic
  medical classification logic — tracked in a separate PR, do not
  touch in cleanup PRs.)
- **Omni** is a **medical OCR/NLP platform** only. Any "general file
  manager" expansion is a bug in product scope.
- **telegram-tools** is a **training-data feeder** for Omni, not a
  competing medical NLP product. Its scope is: extract → align → split
  → publish to HuggingFace Hub. Optional training helper scripts are
  allowed as convenience utilities but should not duplicate Omni's
  training pipelines.
- **dictionaries-csv** is a **data/support repo**, not a product core.
- **repo-sync-toolkit** is a **security-sensitive utility**, not a
  product core.
- **sync-github** is **legacy/archival**.
- **OmniFile_Processor** is **deprecated/under archival review**, not a
  primary active product.

---

## Canonical Relationships

```
                    +-----------------------------+
                    |      omni-medical-suite     |
                    |   (medical OCR/NLP consumer) |
                    +--------------+--------------+
                                   |
                                   | consumes
                                   | (HuggingFace datasets)
                                   v
                    +-----------------------------+
                    |       telegram-tools        |
                    | (training-data feeder:      |
                    |  extract → align → publish) |
                    +--------------+--------------+
                                   |
                                   | optional lookup
                                   v
        +----------------------+   |   +----------------------+
        | arabic-medical-      |   |   | glossary-api         |
        |   glossary           |<--+-->| (REST API for the    |
        | (data)               |       |  glossary)           |
        +----------------------+       +----------------------+
                                   |
                                   v
                    +-----------------------------+
                    |       dictionaries-csv      |
                    | (CSV dictionaries: data)    |
                    +-----------------------------+

                    +-----------------------------+
                    |     intelli-file-manager    |
                    | (general file manager —     |
                    |  NO medical scope)          |
                    +-----------------------------+

                    +-----------------------------+
                    |     repo-sync-toolkit       |
                    | (git sync utility —         |
                    |  security-sensitive)        |
                    +-----------------------------+
                                   ^
                                   | supersedes
                                   |
                    +-----------------------------+
                    |       sync-github           |
                    | (LEGACY — archived)         |
                    +-----------------------------+

                    +-----------------------------+
                    |    OmniFile_Processor       |
                    | (LEGACY — superseded by     |
                    |  omni-medical-suite)        |
                    +-----------------------------+
```

**Boundary rules:**

- No cross-repo coupling except via import/export, REST API, or
  plugin boundary.
- No monorepo. No repo merges.
- telegram-tools publishes datasets to HuggingFace Hub → Omni downloads
  them. This is the only data-flow direction.
- glossary-api serves arabic-medical-glossary data over HTTP. No
  reverse dependency.
- intelli-file-manager has no upstream or downstream dependency on any
  medical repo.

---

## Known Gaps (tracked, not blocking)

| Gap | Repo | Status |
|-----|------|--------|
| `smart_tagger.py` contains medical classification logic | intelli-file-manager | tracked in separate PR — do not compete |
| `mobile/main.py` + `buildozer.spec` at root (Kivy/Android) | intelli-file-manager | decision needed: quarantine as experimental |
| README badges claim v1.1.0 but latest tag is v1.2.0 | omni-medical-suite | to be fixed in cleanup PR |
| README claims v2.2.0 but no v2.2.0 tag exists | intelli-file-manager | to be fixed in cleanup PR |
| README says "Archived" but GitHub archive flag is off | sync-github | to be normalized in archival PR |
| README says "LEGACY (Deprecated)" but GitHub archive flag is off | OmniFile_Processor | to be normalized in archival PR |
| `training/` directory in feeder repo | telegram-tools | OK as optional helper; document boundary |

---

## Verification Discipline

- README/release/version claims MUST match the latest git tag.
- "Archived" claims in README MUST be backed by the GitHub archive flag.
- Security-sensitive repos MUST NOT commit `.env`, `*.session`, or
  token literals. `.gitignore` MUST cover them.
- Any new cross-repo integration MUST go through a clearly defined
  boundary (HTTP API, file export, or plugin interface) — never through
  direct imports across repos.

---

## Update Protocol

When a repo changes identity, archival status, or canonical
relationship:

1. Update the relevant row in this document.
2. Update `GOVERNANCE.md` if policies are affected.
3. Open a small PR titled `docs(ecosystem): update state after <change>`.
4. Do NOT bundle ecosystem-state updates with feature work.
