# Nalori Agent Instructions

Scope: work only in this repository unless the user explicitly asks for outside inspection.

## Project Rules

- Keep app source clean and scoped to the requested change.
- Do not touch release signing, keystores, or Play Store signing files unless the user explicitly asks.
- Do not push or commit unless the user explicitly asks.
- Prefer existing Flutter/Dart patterns in this repo over adding new tooling or abstractions.
- Validate important assumptions against current source files before editing.

## Shell Tooling

- `rtk` is optional token-saving shell tooling. Use it when available for routine shell commands.
- Do not add local `RTK.md` copies to the repo.
- If `rtk` is unavailable, use normal shell commands.

## Graphify

- Graphify is optional agentic coding support, not app runtime code.
- Use Graphify output only as a first-pass retrieval aid for architecture lookup, codebase questions, and feature discovery.
- Treat `graphify-out/` and `.graphify_*` files as local cache/output. Do not commit them.
- Validate Graphify claims against live source files before making edits.
- Regenerate Graphify only when it materially helps the task; avoid adding generated graph artifacts to source control.

## Codex Skills

- Keep reusable Codex skills outside this app repo, under the user's Codex/agent skills directories.
- Do not vendor skills, generated skill caches, or agent configuration folders into Nalori unless the user explicitly asks.
