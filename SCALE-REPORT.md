# Harness Build Report

- Project: Code Graph Harness
- Stack: shell
- Extraction pipeline: 3-layer (Nodes → Edges → Calibration)

## Must Run
- `bash scripts/tests/run.sh`
- `bash scripts/validate-config.sh`
- `bash scripts/gates/all.sh --dry-run`
- `bash scripts/pipeline.sh`

## Quality Governance
- Contract: `harness-conf/workflow/gate-criteria.md`
- State Machine: `docs/status/state.yaml`
- Audit Log: `docs/status/progress.md`
- Template: `templates/analyze-pattern.md`
- Template: `templates/generate-script.md`
- Template: `templates/persist-rule.md`

## Honest Delivery
- Do not claim tests passed unless the command was actually run and exited 0
- Dry-run does not prove quality gates passed
- Skipped or missing tools must be listed as unverified items
