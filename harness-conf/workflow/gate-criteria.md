---
title: harness · 门禁标准
purpose: G-E1 至 G-E5（含 G-E2.5）门禁检查项的单一真源（每项含可执行验证命令）
version: v1.0.0
author: harness
status: Baseline
---

# harness · 门禁标准（G-E1 至 G-E5，含 G-E2.5）

> 所有门禁结论必须附实际执行的命令与输出。未运行的验证不得描述为通过。
> 豁免规则：任一门禁豁免必须 User 明确确认，并记录在任务级 progress.md（硬停闸之一）。
> **Nightly 模式**：必跑 G-E1/G-E2/G-E3/G-E5，跳过 G-E4（不写脚本）；门禁失败不豁免，记入晨检队列（见 `nightly-mode.md §3-4`）。

## §G-E1 构建通过（E2 前置）

| 检查项 | 级别 | 验证命令 |
|--------|:----:|---------|
| 基础构建/脚本语法可用 | MUST | `bash scripts/gates/G0-verify.sh` |
| 依赖工具齐全 | MUST | `for t in git bash jq; do command -v $t; done`（全部有输出） |
| repos.yaml 可解析且非空仓库清单 | MUST | `grep -vE '^\s*#' repos.yaml \| grep -c 'url:'` ≥ 1（全量模式；注释行不计入） |

## §G-E2 流水线完整性（E2 末）

| 检查项 | 级别 | 验证命令 |
|--------|:----:|---------|
| pipeline 退出码为 0 | MUST | E2 报告中的执行记录（引自 pipeline-executor 实测） |
| 图谱产物存在 | MUST | `test -f output/knowledge-graph/latest.json && echo OK` |
| 校准报告存在 | MUST | `test -f output/calibration/calibration-report.json && echo OK` |
| 边统计存在 | MUST | `test -f output/edges/edge-stats.json && echo OK` |
| 节点目录非空 | SHOULD | `ls output/nodes/ \| wc -l` ≥ 1 |

## §G-E2.5 框架分析质量（E2 中，D1 产出验收，v2 新增）

| 检查项 | 级别 | 验证命令 |
|--------|:----:|---------|
| profile 存在且 YAML 可解析 | MUST（否则完全失败） | `bash scripts/gates/GE2.5-framework-analysis.sh output/analysis/<service>-profile.yaml` 退出码非 1 |
| 必填字段齐全（service/framework_signals/extraction_plan/unknowns） | MUST（否则完全失败） | 同上 |
| confidence 枚举合法（high/medium/low/none） | MUST（否则完全失败） | 同上 |
| medium+ 信号均有 ≥1 条 review_basis | SHOULD（缺失为部分失败） | 同上，退出码 0 |
| 自审报告产出 `<service>-profile-review.md` | SHOULD（缺失为部分失败） | 同上 |

> **三级回退（不阻断流水线）**：exit 0 → 按 extraction_plan 精准提取；exit 2 → 警告 + 回退全部提取器；exit 1 / 无 profile → 静默回退全部提取器（= v1 行为）。
> Schema 定义见 `schemas/profile.schema.yaml`；分析模板见 `templates/analyze-framework.md`。

## §G-E3 提取质量（E3 末，v2.1 双维度）

| 检查项 | 级别 | 验证命令 |
|--------|:----:|---------|
| 提取质量门禁脚本通过 | MUST | `bash scripts/gates/GE3-extraction-quality.sh`（exit 0） |
| 匹配率达标（≥0.70 FAIR 线） | MUST | `jq '.match_rate' output/edges/edge-stats.json` |
| blocker 为空 | MUST | `jq '.blockers' output/calibration/calibration-report.json` == `[]` |
| unknown pattern 已处置 | MUST | E3 报告中 unknown pattern 清单为空或已转入 E4 |
| 节点 schema + 证据链合规（C-E1） | MUST（双轨模式） | `bash scripts/gates/GE3-extraction-quality.sh` 的 [AI维] 部分 exit 0 |
| 双维度一致性可解释（无未归因 contradiction） | SHOULD（双轨模式） | 同上 [AI维] 部分 |

> POOR（<0.70）不可豁免通过，必须进 E4 或由 User 显式降级接受（记录豁免）。
> **双维度语义（v2.1, Q-Final=A）**：脚本维（match_rate/blockers/schema）是确定性验收；AI 维（C-E1 证据底线 + contradiction 归因）是实质验收。评级（GOOD/FAIR/POOR）与分流由 D2 AI（calibration-analyzer）决策，bash 只算数不评级。
> AI 迭代分析约束见 `templates/ai-analysis-harness.md`；双维度校准模板见 `templates/dual-pass-review.md`。

## §G-E4 自适应代码质量（E4 末，本次无新脚本时标 N/A）

| 检查项 | 级别 | 验证命令 |
|--------|:----:|---------|
| 新脚本语法 | MUST | `bash -n project/staging/<pattern>/extract-{pattern}.sh` |
| GP1-GP5 fixture 验证 | MUST | `bash scripts/gates/GP1-verify.sh` … `GP5-verify.sh` 依次 exit 0 |
| 全量回归 | MUST | `bash scripts/tests/run.sh`（exit 0） |
| 既有 fixture 不受影响 | MUST | `bash scripts/tests/run.sh` 输出中 http-client/mq/socket 样例通过 |
| 持久化完整性 | MUST | `project/patterns/{pattern}.md` 存在 + `repos.yaml` scanner 已注册 + `EXTRACTION-WORKFLOW.md` 章节已更新 |
| 新脚本注释含检测逻辑说明 | SHOULD | 人工审查 |

## §G-E5 图谱发布（E5 末）

| 检查项 | 级别 | 验证命令 |
|--------|:----:|---------|
| G-E1 至 G-E4 均已通过或 N/A | MUST | 引自各阶段报告与任务级 state.yaml |
| 图谱 JSON 可解析 | MUST | `jq '.stats' output/knowledge-graph/latest.json` |
| 图谱结构符合 schema | MUST | `jq` 校验 latest.json 含 version/generatedAt/stats/nodes/edges 字段（完整校验见 `schemas/knowledge-graph.schema.json`） |
| 边引用完整性 | MUST | edges 中 from/to 节点 id 存在于 nodes（引自 assemble-graph.sh 的完整性检查输出） |
| 非标 needs_review 清零 | MUST | `jq '.checks.D_nonstandardConfidence.needsReview' output/calibration/calibration-report.json` == 0（或 User 豁免在案） |
| artifacts 链完整 | MUST | E1-plan / E2-report / E3-analysis /（E4-report）/ E5-report 齐全 |
| 校准评分记录 | SHOULD | latest.json calibrationScore 与 calibration-report overallScore 一致 |

## §结论规则（gate-reviewer）

- **Pass**：全部 MUST 满足
- **Conditional Pass**：MUST 全满足且 ≤2 项 SHOULD 不足，列限期整改项
- **Reject**：任一 MUST 不满足，列必改项并建议回退路径（见 `extraction-flow.md §7`）
- 结论必须三选一明示，禁止"基本通过"之类模糊表述
