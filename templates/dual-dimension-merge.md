# 双维度合并 — AI 工作模板

## Context
你是 Harness 双维度合并者，在 Phase 2.5（pipeline 退出后由 calibration-analyzer 触发）
合并脚本维度与 AI 维度产出为最终节点集。工作受 `templates/ai-analysis-harness.md` 约束。

> md-first 哲学：合并的**规则**在本模板，**机械执行**用 `scripts/base/merge-json.sh` 等工具。
>
> 关联模板：
> - 前置：`templates/build-nodes-scheduling.md`（决定 nodes-script/nodes-ai 的产生）
> - 后置：`templates/calibration-summary.md`（消费合并后的 output/nodes/ 做汇总）
> - 异常：`templates/dual-pass-review.md` + `templates/low-conf-drill.md`（矛盾/low 项二轮）

## Input
- 脚本维度: `output/nodes-script/<service>/`（bash extractors 机械基线）
- AI 维度:  `output/nodes-ai/<service>/`（AI 语义产出）
- 协议级信号: `output/analysis/<service>-profile.yaml`
- 目标: `output/nodes/<service>/`（最终图谱节点）

## §1 合并规则（Q1=A：取并集）

对每个 node ID（`{parent}::{className}.{methodName}`）：

| 来源 | 置信度起点 | 后续 |
|------|:---------:|------|
| 脚本 + AI 都命中 | **high** | 进入最终图谱 |
| 仅脚本命中 | **medium** | 进入最终图谱（脚本机械基线） |
| 仅 AI 命中 | **medium** | 进入最终图谱（AI 单源） |
| 双方命中但属性矛盾（role/protocol 冲突） | **low** | 不直接入图谱，进 `output/reviews/<service>/contradictions.json` |

## §2 协议级加权（Q-Evidence-3=A，严格分级）

读取 profile.yaml 每个协议的 `confidence`，对同协议节点做档位调整：

```
profile.{proto}.confidence = high → node.confidence +1 档 (上限 high)
profile.{proto}.confidence = low  → node.confidence 保持原档
profile.{proto}.confidence = none → node.confidence 强制 -1 档 (下限 low)
```

> Profile 是协议级印证信号，不是节点级独立印证源（Q-Final=A）。
> 加权重算由 AI 自行完成（策略属 md 领域），不依赖任何脚本算法。

## §3 字段补齐（v2.1 schema 契约）

合并后每个节点必须满足 `schemas/node.schema.json`。**合并是"继承源节点全部字段 + 补算新增字段"，不是重建**。

保留源节点既有字段（从命中来源继承，AI 版优先、脚本版补充缺失）：
- `id` `type` `name` `parent` `protocol` `role` `className` `signature` `path` `httpMethod` `httpPath` `tags`

补算 v2.1 新增字段（§1/§2 决定，schema 必填）：

```yaml
id:              # 保留原 ID
protocol:        # 保留
role:            # 保留
confidence:      # 按 §1 §2 计算
evidence_refs:   # 非空, tier 1-3 (C-E1), 取自命中来源
evidence_type:   # source_reference / *_only / *_unknown 之一
source:          # dual / bash / ai
metadata:
  dual_dimension_consistency: both | bash_only | ai_only | contradiction
  boundary_external: true (evidence_type=*_only 时必填)
```

> 若源节点已含 `metadata`，需与新 metadata 合并而非覆盖；其他 schema 未列出但源节点已有的字段（如 `metadata.detection_evidence`）应一并保留。

## §4 C-E1 证据底线（三级豁免）

见 `templates/ai-analysis-harness.md §2`：
- 普通节点（source_reference / declaration_reference / call_site）必须有 ≥1 条 tier 1-3 证据
- 服务边界外（*_only）允许指向本仓库声明方，confidence 上限 medium
- 技术不可识别（*_unknown / dynamic_dispatch）进 bail-out 包

## §5 工具调用

- 数组合并/去重: `bash scripts/base/merge-json.sh <out> <file1> [file2...]`
- Schema 校验: `bash scripts/base/validate-schema.sh <file> node`
- 字段提取: `bash scripts/base/run-ai-analysis.sh <state.yaml> <field>`

> 加权/合并的策略由 AI 自主计算（本模板的规则），工具只做机械落地。

## §6 产出

1. `output/nodes/<service>/*.json`（符合 node.schema.json）
2. `output/reviews/<service>/contradictions.json`（矛盾节点，供 AI 二轮）
3. 更新 `output/analysis/<service>/round-<N>.state.yaml` 的 findings_count / 置信度分布

## 禁止（MUST NOT）
- 不得把矛盾节点（contradiction）直接入图谱（必须走二轮校准或 bail-out）
- 不得使用 tier 4 证据
- 不得猜测 profile 中不存在的协议加权
- 不得修改源文件 / repos.yaml / harness-conf
