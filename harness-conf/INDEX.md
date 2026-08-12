---
title: harness · 主Agent快速召回入口
purpose: 知识图谱提取流程定位的单一入口
version: v1.0.0
author: harness
status: Baseline
---

# harness · 主Agent快速召回入口

> **职责说明**：本文件是 graph-orchestrator 流程召回入口 + 文档体系导航。
> **Agents架构约束**：见 `harness-conf/ARCHITECTURE.md`
> **工程设计 v2**：见 `harness-conf/DESIGN-V2.md`（新）
> **版本演进**：见 `harness-conf/CHANGELOG.md`
> **提取器实现细节**：见项目根 `EXTRACTION-WORKFLOW.md`

> 接到新任务/跨阶段/上下文远去时，先读本文件。

## §0 极简使用法（30 秒）

1. 看 §1 按触发场景 → 匹配关键词 → 加载对应文件
2. 看 §2 按阶段 → 确认当前阶段定位
3. 看 §3 按角色 → 确认当前角色执行边界

## §1 按触发场景（最常用）

| 触发关键词 | 必读文件 | 优先级 |
|---------|---------|:------:|
| **新提取任务 / /extract** | `workflow/extraction-flow.md`（E1 任务接收） | P0 |
| **增量更新 / /update** | `workflow/extraction-flow.md §E2`（增量模式）+ `EXTRACTION-WORKFLOW.md §6` | P0 |
| **长会话召回 / /status** | `docs/status/state.yaml` + `workflow/state-maintenance.md §5` | P0 |
| **校准失败 / POOR / blocker** | `workflow/extraction-flow.md §E3`（判定表）+ `guides/self-adaptation.md` | P0 |
| **未知模式 / [AI-REQUIRED]** | `guides/self-adaptation.md` + `templates/analyze-pattern.md` | P0 |
| **自适应编码 / /adapt** | `guides/self-adaptation.md` + `templates/generate-script.md` | P1 |
| **门禁评审 / G-E?** | `workflow/gate-criteria.md`（含可执行验证命令） | P1 |
| **发布确认 / 归档** | `workflow/extraction-flow.md §E5`（硬停闸） | P1 |
| **夜间批量 / nightly** | `workflow/nightly-mode.md` + `scripts/nightly.sh`（cron 无人值守） | P1 |

## §2 按阶段（提取运营流 E1-E5）

| 阶段 | 主责角色 | 执行模式 | 末门禁 | User确认 | 交付物 |
|:-:|:-:|:------:|:------:|:--------:|------|
| **E1** | graph-orchestrator | 主Agent执行 | — | 需求确认 | `artifacts/E1-plan.md` |
| **E2** | pipeline-executor | Spawn | G-E2 | — | `artifacts/E2-extraction-report.md` |
| **E3** | calibration-analyzer | Spawn | G-E3 | — | `artifacts/E3-calibration-analysis.md` |
| **E4** | adapter-developer | Spawn | G-E4 | 迭代超限升级 | `artifacts/E4-adapt-report.md` |
| **E5** | gate-reviewer | Spawn | G-E5 | 发布确认（硬停闸） | `artifacts/E5-gate-report.md` |
| **归档** | graph-publisher | Spawn | — | — | `completion-summary.md` |

> **E3 判定表**：GOOD/FAIR 且无 blocker → E5；POOR 或 unknown pattern → E4；blocker 或数据损坏 → 升级 User。详见 `workflow/extraction-flow.md §E3`。

## §3 按角色（Agent 定义内联职责）

| 角色 | Agent 定义 | 职责边界来源 |
|------|-----------|-------------|
| graph-orchestrator（主） | `.opencode/agents/graph-orchestrator.md` | `workflow/roles.md §2.1` |
| pipeline-executor | `.opencode/agents/pipeline-executor.md` | `workflow/roles.md §2.2` |
| calibration-analyzer | `.opencode/agents/calibration-analyzer.md` | `workflow/roles.md §2.3` |
| adapter-developer | `.opencode/agents/adapter-developer.md` | `workflow/roles.md §2.4` |
| gate-reviewer | `.opencode/agents/gate-reviewer.md` | `workflow/roles.md §2.5` |
| graph-publisher | `.opencode/agents/graph-publisher.md` | `workflow/roles.md §2.6` |

## §4 文档体系导航

### 四层文档架构

| 目录 | 用途 | 生命周期 |
|------|------|---------|
| `docs/specs/` | 提取范围真相源（仓库清单语义 + 已支持模式） | 长期维护 |
| `docs/changes/` | 任务流水（过程产物） | 完成后归档 |
| `docs/archive/` | 归档历史（已完成任务） | 永久保留 |
| `docs/status/` | 项目进度（state.yaml + progress.md） | 持续更新 |

### 任务目录结构

```
docs/changes/<任务编号>/
├── state.yaml      ← 任务级状态机（初始模板: docs/changes/_template/state.yaml）
├── progress.md     ← 任务级审计日志（初始模板: docs/changes/_template/progress.md）
└── artifacts/
    ├── E1-plan.md
    ├── E2-extraction-report.md
    ├── E3-calibration-analysis.md
    ├── E4-adapt-report.md      （仅 E4 触发时）
    └── E5-gate-report.md
```

### 命名规则

- 任务编号（即任务目录名）：`EXT-YYYYMMDD-NN`（全量/单仓库）、`UPD-YYYYMMDD-NN`（增量）、`ADAPT-YYYYMMDD-NN`（纯自适应），NN 为当日序号
- 归档目录：`docs/archive/<任务编号>/<YYYY-MM-DD>-变更简述/`

### 权限矩阵

| 目录 | graph-orchestrator | 其他角色 | User |
|------|------|---------|------|
| `docs/specs/` | 合并写入（E4 后同步） | adapter-developer 可更新模式清单 | 只读 + 审批 |
| `docs/changes/` | 归档移动 | 按阶段写入对应 artifacts | — |
| `docs/archive/` | graph-publisher 写入 | 只读查询 | — |
| `docs/status/` | 原子刷新 | graph-publisher 收口刷新 | — |

## §5 关键机制速查

- **Auto-Relay**：门禁 Pass 后 orchestrator 自动推进（受 state.yaml `gate-confirm-mode` 约束），5 个硬停闸见 `workflow/extraction-flow.md §6`
- **自适应闭环**：E3 → E4 → E2 自动迭代，上限 3 次，见 `guides/self-adaptation.md`
- **回退铁律**：任何回退必须重新执行对应门禁，禁止跳门禁推进
- **状态机**：`docs/status/state.yaml` 为权威状态，`progress.md` 为审计日志

## §6 长会话召回机制

### 快速自检清单

```
📌 上下文检查点
- 当前任务：<任务编号>（来自全局 state.yaml）
- 当前阶段：<E?/G-E?>（来自任务级 state.yaml）
- 门禁状态：<gate-status>
- 全局索引：docs/status/state.yaml
- 任务级状态机：docs/changes/<任务编号>/state.yaml
- 未完成任务：<当前阶段待办清单>
```

### 触发条件

| 触发条件 | 判定标准 | 优先级 |
|---------|---------|:------:|
| **跨阶段切换** | E? → G-E? 或 G-E? → E? | P0 |
| **轮数阈值** | 对话轮次 ≥ 30 轮 | P0 |
| **subagent 切换** | spawn 新 subagent 前 | P1 |

### 召回失败降级

| 失败场景 | 降级策略 |
|---------|---------|
| 任务级 state.yaml 缺失但 progress.md 存在 | 从 progress.md 重建 state.yaml |
| state.yaml 与 progress.md 矛盾 | 以 state.yaml 为准，progress.md 追加 errata |
| 全局 state.yaml 缺失 | 询问 User 确认当前状态 |
| 上下文完全丢失 | 返回 E1 重新开始 |
