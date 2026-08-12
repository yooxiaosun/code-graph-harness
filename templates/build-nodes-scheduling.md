# Layer 1 调度决策 — AI 工作模板

## Context
你是 Harness 调度决策者（pipeline-executor），决定如何调用 `scripts/graph/build-nodes.sh`。
工作受 `templates/ai-analysis-harness.md` 约束。

> md-first 哲学：调度**决策**在本模板（AI 判断），`build-nodes.sh` 是纯参数化执行工具（无判断）。

## Input
- `output/analysis/<service>-profile.yaml`（D1 框架分析产出，若存在）
- `output/nodes-ai/<service>/` 是否存在（AI 直产是否已就绪）
- repos.yaml 提取器清单

## §1 决策 1：调用模式

```
IF output/nodes-ai/<service>/ 存在（AI 直产就绪）:
    mode = DUAL
    → 调 build-nodes.sh --plan <P> 写到 output/nodes-script/<service>/
    → 按 templates/dual-dimension-merge.md 自行合并到 output/nodes/<service>/

ELSE:
    mode = SINGLE
    → 调 build-nodes.sh 写到 output/nodes/<service>/（默认全量或按 --plan）
```

## §2 决策 2：--plan 选择（协议级）

读 `profile.yaml`，按 G-E2.5 结果（`scripts/gates/GE2.5-framework-analysis.sh` 退出码）：

| G-E2.5 退出码 | 动作 |
|:---:|------|
| 0（通过） | 按 `extraction_plan.extractors` 传 `--plan "dubbo rest mq"` 给 build-nodes.sh |
| 2（部分失败） | 警告 + 传全量（不传 --plan） |
| 1 / 无 profile | 传全量（不传 --plan），等同 v1 行为 |

## §3 决策 3：是否跑 tags

- 默认跑（`tags` 加入 plan 或省略 `--no-tags`）
- 若任务明确"仅协议提取"或 tags 上次已跑 → `--no-tags`

## §4 工具调用

```bash
# 单轨全量
bash scripts/graph/build-nodes.sh <service> <repo> output/nodes

# 单轨指定计划
bash scripts/graph/build-nodes.sh <service> <repo> output/nodes --plan "dubbo rest"

# 双轨（脚本维度落 nodes-script，合并由 AI 按 dual-dimension-merge.md 完成）
bash scripts/graph/build-nodes.sh <service> <repo> output/nodes-script --plan "dubbo rest" 
```

## §5 产出

- 记录决策到 E2-extraction-report.md：mode（single/dual）、plan、tags 开关、理由
- 决策依据必须引用 profile.yaml 的实际内容（不得凭印象）

## 禁止（MUST NOT）
- 不得在 build-nodes.sh 内做决策（它不接受策略参数之外的任何判断）
- 不得在 profile 缺失时猜测 plan（用全量）
- 不得修改 build-nodes.sh 来"加决策逻辑"
