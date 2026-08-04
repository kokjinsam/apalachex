# Changelog

## 0.1.1 - 2026-08-04

- Adopt the shared CodeStyle and Styler policy.
- Add repository-owned asdf toolchain and Justfile workflows.
- Standardize CI on the repository's public Justfile commands.
- Add a guarded local workflow for Hex publication and GitHub releases.
- Move the standalone consumer-smoke fixture under `test/support`.

## 0.1.0 - 2026-07-31

- Add validated TLA+ specification references.
- Add deterministic run-directory and Apalache plan construction.
- Add exact Apalache 0.58.3 discovery, version probing, and execution.
- Support POSIX execution only; reject Windows after option validation and
  before executable discovery, version probing, or run-directory allocation.
- Add retained lifecycle manifests and ordered ITF artifact discovery.
