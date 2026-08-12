#!/usr/bin/env bash
set -euo pipefail

# Gates Status — read-only catalog report (does NOT execute gates).
# v2 门禁体系：工程门禁 G0/G4/G5 + 流程门禁 G-E1..G-E5 + 自适应门禁 GP1-GP5

JSON=0
[ "${1:-}" = "--json" ] && JSON=1

if [ "$JSON" -eq 1 ]; then
  cat <<'EOF'
{
  "version": "3.0",
  "engineering_gates": ["G0", "G4", "G5"],
  "flow_gates": ["G-E1", "G-E2", "G-E2.5", "G-E3", "G-E4", "G-E5"],
  "adaptation_gates": ["GP1", "GP2", "GP3", "GP4", "GP5"],
  "gates": [
    {"id":"G0","name":"Build","scope":"engineering","blocking":true,"script":"scripts/gates/G0-verify.sh"},
    {"id":"G4","name":"Lint","scope":"engineering","blocking":true,"script":"scripts/gates/G4-verify.sh"},
    {"id":"G5","name":"Test","scope":"engineering","blocking":true,"script":"scripts/gates/G5-verify.sh"},
    {"id":"G-E1","name":"BuildPass","scope":"flow","blocking":true,"script":"见 gate-criteria.md §G-E1"},
    {"id":"G-E2","name":"PipelineIntegrity","scope":"flow","blocking":true,"script":"见 gate-criteria.md §G-E2"},
    {"id":"G-E2.5","name":"FrameworkAnalysis","scope":"flow","blocking":false,"script":"scripts/gates/GE2.5-framework-analysis.sh"},
    {"id":"G-E3","name":"ExtractionQuality","scope":"flow","blocking":true,"script":"scripts/gates/GE3-extraction-quality.sh"},
    {"id":"G-E4","name":"AdaptationQuality","scope":"flow","blocking":true,"script":"GP1-GP5 + scripts/tests/run.sh"},
    {"id":"G-E5","name":"Release","scope":"flow","blocking":true,"script":"见 gate-criteria.md §G-E5"},
    {"id":"GP1","name":"Syntax","scope":"adaptation","blocking":true,"script":"scripts/gates/GP1-verify.sh"},
    {"id":"GP2","name":"Execution","scope":"adaptation","blocking":true,"script":"scripts/gates/GP2-verify.sh"},
    {"id":"GP3","name":"Schema","scope":"adaptation","blocking":true,"script":"scripts/gates/GP3-verify.sh"},
    {"id":"GP4","name":"Recall","scope":"adaptation","blocking":true,"script":"scripts/gates/GP4-verify.sh"},
    {"id":"GP5","name":"Regression","scope":"adaptation","blocking":true,"script":"scripts/gates/GP5-verify.sh"}
  ],
  "default_set": {"gates": ["G0", "G4", "G5"]}
}
EOF
  exit 0
fi

cat <<'EOF'
=== Harness Gate Catalog (v3.0) ===

Engineering Gates — 工程门禁（all.sh 默认集）
  G0  Build                blocking   bash -n 全部脚本
  G4  Lint                 blocking   脚本规范检查
  G5  Test                 blocking   bash scripts/tests/run.sh

Flow Gates — 提取流程门禁（见 harness-conf/workflow/gate-criteria.md）
  G-E1    BuildPass            blocking   E2 前置
  G-E2    PipelineIntegrity    blocking   E2 末
  G-E2.5  FrameworkAnalysis    advisory   E2 框架分析质量（三级回退）
  G-E3    ExtractionQuality    blocking   E3 末（GE3-extraction-quality.sh）
  G-E4    AdaptationQuality    blocking   E4 末（GP1-GP5 + 全量回归）
  G-E5    Release              blocking   E5 末 + User 硬停闸

Adaptation Gates — 自适应脚本 fixture 验证（scripts/gates/GP*-verify.sh）
  GP1 Syntax / GP2 Execution / GP3 Schema / GP4 Recall / GP5 Regression

Usage
  bash scripts/gates/all.sh                          # 默认集 G0 G4 G5
  bash scripts/gates/all.sh --dry-run                # check which scripts exist, don't run
  bash scripts/gates/all.sh --gate G4                # run a single gate
  bash scripts/gates/status.sh                       # this catalog (read-only)
  bash scripts/gates/status.sh --json                # machine-readable catalog

Reference: harness-conf/workflow/gate-criteria.md
EOF
