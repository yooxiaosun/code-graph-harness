---
title: harness · 角色职责边界
purpose: 6 角色 RACI + 行为边界 + 自动委派规则 + 冲突仲裁
version: v1.0.0
author: harness
status: Baseline
---

# harness · 角色职责边界

> 本文件是角色职责的单一真源。职责约束已内联到 `.opencode/agents/*.md`。

## §1 全流程 RACI 矩阵

> R = Responsible 主责执行；A = Accountable 最终签字人；C = Consulted；I = Informed

| 阶段 | orchestrator | executor | analyzer | adapter | gate-reviewer | publisher |
|------|:--:|:--:|:--:|:--:|:--:|:--:|
| **E1** | **R** | I | I | I | I | I |
| **E2** | A | **R** | I | I | I | I |
| **G-E2** | A | C | I | I | I | I |
| **E3** | A | I | **R** | C | I | I |
| **G-E3** | A | I | **R** | I | I | I |
| **E4** | A | I | C | **R** | I | I |
| **G-E4** | A | I | I | C | I | I |
| **E5** | A | I | I | C | **R** | I |
| **归档** | A | I | I | I | I | **R** |

说明：
- orchestrator 作为 A 贯穿所有阶段——负责签字、调度、推动门禁
- E1 由 orchestrator 主责执行（R）；G-E2/G-E3 由 orchestrator 形式校验（产物存在性），质量结论归各阶段 subagent
- E4 仅在 E3 判定或 `/adapt` 触发时激活

## §2 角色行为边界（MUST / MUST NOT）

### 2.1 graph-orchestrator（主Agent）

- **MUST**：维护 `docs/status/state.yaml` + `docs/status/progress.md`；E1 主执行；按强制 spawn 规则推进 E2-E5；Auto-Relay；User 确认代理；归档调度
- **MUST NOT**：不得直接跑 pipeline/提取器；不得解读校准数据；不得写提取器脚本；不得出具门禁技术结论；不得自动执行发布确认

### 2.2 pipeline-executor

- **MUST**：真实运行 `scripts/pipeline.sh` 与前置检查；收集退出码与产物证据；失败如实上报（重试 ≤2 次）
- **MUST NOT**：不得解读质量评级；不得修改 scripts/repos.yaml；产物缺失不得报成功
- **写入边界**：`output/**`、E2 报告

### 2.3 calibration-analyzer

- **MUST**：基于 calibration-report.json + edge-stats.json 做 5 项检查解读；unresolved 归因；输出唯一流转判定（E5/E4/升级 User）
- **MUST NOT**：不得修改 output/**（严格只读）；不得凭印象评级；不得写脚本
- **写入边界**：仅 E3 报告

### 2.4 adapter-developer

- **MUST**：按三模板（analyze-pattern / generate-script / persist-rule）完成分析→生成→GP1-GP5 验证→持久化→文档同步；迭代上限 3 次
- **MUST NOT**：未过 GP1-GP5 禁止持久化/集成；不得改标准提取器检测逻辑（除非交接块明确）；不得引入新依赖（除非 User 批准）
- **写入边界**：`scripts/**`、`repos.yaml`、`project/patterns/**`、fixtures、`EXTRACTION-WORKFLOW.md`、`docs/specs/extraction-scope.md`、E4 报告

### 2.5 gate-reviewer

- **MUST**：逐项真实执行 gate-criteria.md 验证命令并记录输出；出具 Pass/Conditional Pass/Reject 三选一；复核 artifacts 链
- **MUST NOT**：不得修改任何被评审对象（严格只读）；不得以承诺替代验证；准入不满足不得 Pass；不得自行派发整改
- **写入边界**：仅 E5 报告

### 2.6 graph-publisher

- **MUST**：E5 Pass + User 确认后归档：图谱快照 + completion-summary.md + 移入 archive + 状态机收口 + specs 同步核对
- **MUST NOT**：未确认不得归档；不得修改脚本/配置/原始产物；不得删除 artifacts
- **写入边界**：`output/knowledge-graph/**`（仅快照）、`docs/archive/**`、`docs/status/**`

## §3 自动委派规则

| 触发场景 | 自动委派对象 |
|---------|-------------|
| E1 任务接收 | orchestrator 主 Agent 直接执行（不 spawn） |
| E2 流水线执行 | spawn pipeline-executor |
| E3 校准分析 | spawn calibration-analyzer |
| E4 自适应编码 | spawn adapter-developer |
| E5 发布门禁 | spawn gate-reviewer |
| 归档执行 | spawn graph-publisher |

**关键约束**：
1. orchestrator 不得在任何门禁未通过时启动下游阶段
2. orchestrator 不得代替 subagent 执行其专属任务
3. E4→E2 回环必须重新走 G-E2/G-E3

## §4 冲突仲裁

| 冲突类型 | 仲裁者 |
|---------|--------|
| 提取范围争议（哪些仓库/协议） | User（经 orchestrator 转达） |
| E3 判定分歧（是否触发 E4） | 以 calibration-report.json 数据为准 |
| 门禁结论争议 | gate-reviewer 结论终局，仅 orchestrator 可发起豁免（需 User 确认） |
| 变更级别争议 | orchestrator 判定，User 在需求确认时一并确认 |
| 新提取器检测逻辑分歧 | adapter-developer 提案 + GP4 召回证据裁决 |

## §5 角色 ↔ Agent 定义映射

| 角色 | Agent 定义文件 |
|------|--------------|
| graph-orchestrator | `.opencode/agents/graph-orchestrator.md` |
| pipeline-executor | `.opencode/agents/pipeline-executor.md` |
| calibration-analyzer | `.opencode/agents/calibration-analyzer.md` |
| adapter-developer | `.opencode/agents/adapter-developer.md` |
| gate-reviewer | `.opencode/agents/gate-reviewer.md` |
| graph-publisher | `.opencode/agents/graph-publisher.md` |
