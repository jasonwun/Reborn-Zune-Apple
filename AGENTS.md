# Reborn Zune Apple

## Language conventions

- Communicate with the user in **Chinese** (简体中文).
- Write **code, comments, commit messages, issues, and documentation** (including files under `docs/`) in **English**.

## Workflow

New work runs through the installed engineering skills: `/grill-with-docs` → `/to-spec` → `/to-tickets` (GitHub issues with blocking edges) → `/implement` per ticket (driving `/tdd`) → `/code-review` → `/retro`.

`specs/` and `reports/` are the historical record of the old milestone/executor/evaluator flow — keep them as primary sources to reference, but do not add new milestone specs or executor/evaluator reports there. Hard-to-reverse decisions live in `docs/adr/` (seeded from `specs/PROJECT_SPEC.md`); coding standards, including the build commands of record and the visual-verification requirements, live in `CODING_STANDARDS.md` and are enforced by `/code-review`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on this repo (jasonwun/Reborn-Zune-Apple); use the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
