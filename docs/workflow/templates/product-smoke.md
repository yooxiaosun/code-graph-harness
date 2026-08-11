# Product Smoke

## Real Product Path

Describe the smallest end-to-end path that proves the change works through the real product boundary.

## What To Record
- input description
- expected vs actual output
- trace of command executions and exit codes
- evidence location (logs, screenshots, output files)

## Smoke Checklist
- [ ] Pipeline runs end-to-end: `bash scripts/pipeline.sh`
- [ ] Graph artifact produced: `output/knowledge-graph/latest.json`
- [ ] Graph JSON is valid: `jq empty output/knowledge-graph/latest.json`
- [ ] Calibration report no blockers: `jq .blockers output/calibration/calibration-report.json`
- [ ] Syntax check all scripts: `find scripts -name '*.sh' -exec bash -n {} \;`
- [ ] Test suite passes: `bash scripts/tests/run.sh`

## Evidence
Record command output for each checklist item. Mark any [UNCERTAIN] items with missing evidence.
