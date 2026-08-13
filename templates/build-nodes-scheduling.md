# Layer 1 调度决策 — AI 工作模板

## Context
你是 Harness 调度决策者（pipeline-executor），决定如何调用 `scripts/pipeline.sh` 的 Layer 1 节点提取。
工作受 `templates/ai-analysis-harness.md` 约束。

> md-first 哲学：调度**决策**在本模板（AI 判断），`pipeline.sh` 是纯参数化执行工具（无判断）。
> v3.0 变更：原 `build-nodes.sh` 已删除，提取器遍历内联进 `pipeline.sh`，通过 `EXTRACTORS_DIR` 定位项目实例。
>
> 关联模板：
> - 输入来源：`templates/analyze-framework.md`（D1 产出 profile.yaml）
> - 前置校验：`scripts/gates/GE2.5-framework-analysis.sh`（G-E2.5 门禁）
> - 后置：`templates/dual-dimension-merge.md`（双轨时合并）

## Input
- `output/analysis/<service>-profile.yaml`（D1 框架分析产出，若存在）
- `project/extractors/`（项目实例提取器，通过 `EXTRACTORS_DIR` 定位）
- repos.yaml 提取器清单

## §1 决策 1：调用模式

```
IF output/nodes-ai/<service>/ 存在（AI 直产就绪）:
    mode = DUAL
    → 调 pipeline.sh（EXTRACTORS_DIR 指向 project/extractors）写到 output/nodes-script/<service>/
    → 按 templates/dual-dimension-merge.md 自行合并到 output/nodes/<service>/

ELSE:
    mode = SINGLE
    → 调 pipeline.sh 写到 output/nodes/<service>/（默认全量或按 EXTRACTION_PLAN）
```

## §2 决策 2：--plan 选择（协议级，经 EXTRACTION_PLAN 环境变量）

读 `profile.yaml`，按 G-E2.5 结果（`scripts/gates/GE2.5-framework-analysis.sh` 退出码）：

| G-E2.5 退出码 | 动作 |
|:---:|------|
| 0（通过） | 按 `extraction_plan.extractors` 设 `EXTRACTION_PLAN="dubbo rest mq"` 传给 pipeline.sh |
| 2（部分失败） | 警告 + 传全量（不设 EXTRACTION_PLAN） |
| 1 / 无 profile | 传全量（不设 EXTRACTION_PLAN），等同 v1 行为 |

## §3 决策 3：是否跑 tags

- 默认跑（pipeline.sh 内联的 tags 提取器会执行）
- 若任务明确"仅协议提取"或 tags 上次已跑 → 临时移出 EXTRACTORS_DIR 的 tags/ 或人工指定

## §4 工具调用

```bash
# 单轨全量
PROJECT_DIR=/path/to/project bash scripts/pipeline.sh

# 单轨指定计划（EXTRACTION_PLAN 环境变量）
PROJECT_DIR=/path/to/project EXTRACTION_PLAN="dubbo rest" bash scripts/pipeline.sh

# 双轨（脚本维度落 nodes-script，合并由 AI 按 dual-dimension-merge.md 完成）
# pipeline.sh 内联提取到 output/nodes-script/<service>/ 后，AI 按 dual-dimension-merge.md 合并
```

## §5 产出

- 记录决策到 E2-extraction-report.md：mode（single/dual）、plan、tags 开关、理由
- 决策依据必须引用 profile.yaml 的实际内容（不得凭印象）

## 禁止（MUST NOT）
- 不得在 pipeline.sh 内做决策（它只读 EXTRACTORS_DIR/EXTRACTION_PLAN 环境变量）
- 不得在 profile 缺失时猜测 plan（用全量）
- 不得修改 pipeline.sh 来"加决策逻辑"
