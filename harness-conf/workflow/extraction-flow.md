---
title: harness · 提取运营流定义
purpose: E1-E5 阶段定义、流转判定、回退规则的单一真源
version: v1.0.0
author: harness
status: Baseline
---

# harness · 提取运营流（E1-E5）

## §1 阶段编号对照表

| 编号 | 名称 | 主责角色 | 执行模式 | 末门禁 | 备注 |
|------|------|---------|:--------:|:------:|------|
| **E1** | 任务接收 | graph-orchestrator | 主Agent执行 | — | 解析配置 + 执行计划 + User确认 |
| **E2** | 流水线执行 | pipeline-executor | Spawn | G-E2 | 全量/增量/单仓库三种模式 |
| **E3** | 校准分析 | calibration-analyzer | Spawn | G-E3 | 判定分流：E5 / E4 / 升级 User |
| **E4** | 自适应编码 | adapter-developer | Spawn | G-E4 | 仅 E3 判定触发；完成后回 E2 |
| **E5** | 发布门禁 | gate-reviewer | Spawn | G-E5 | Pass 后 User 发布确认（硬停闸） |
| **归档** | 发布归档 | graph-publisher | Spawn | — | 快照 + completion-summary + 状态收口 |

> **Nightly 模式**：无人值守批量提取，硬停闸全部自动化替代，跳过 E4，发现缺口记入晨检队列。详见 `nightly-mode.md`。

## §2 E1 任务接收

**执行角色**：graph-orchestrator 主执行（不 spawn）

**核心活动**：
1. 接收任务输入：`/extract <模式>` / `/update` / `/adapt` 或 User 自然语言
2. 读取全局 state.yaml 检查无进行中任务（有则先处理）
3. 创建任务目录 `docs/changes/<任务编号>/`，初始化任务级 state.yaml + progress.md
4. 解析 `repos.yaml`：仓库清单、协议范围、非标扫描器配置；repos 为空时提醒 User 先配置
5. 判定**变更级别**：
   - **快速变更**：纯数据提取/增量刷新，不改任何脚本与配置
   - **标准变更**：预计或已确认涉及脚本/配置修改（E4 触发时自动升级）
   - 存疑向上取级
6. 产出 `artifacts/E1-plan.md`：提取范围 / 执行模式 / 变更级别 / 预计 E4 触发点 / 风险项
7. 向 User 请求**需求确认**（硬停闸之一）

**关键约束**：
- E1 未完成（User 未确认）不得启动 E2
- repos.yaml 为空时不得虚构仓库或伪造执行
- **Nightly 模式**：跳过 User 确认，自动出全量计划（见 `nightly-mode.md §2`）

## §3 E2 流水线执行

**执行角色**：graph-orchestrator spawn pipeline-executor

**D1 框架分析（v2 新增，克隆后、提取前）**：
1. pipeline-executor 按 `templates/analyze-framework.md` 对每个仓库做框架指纹分析
2. 产出 `output/analysis/<service>-profile.yaml` + `<service>-profile-review.md`
3. G-E2.5 验收（`scripts/gates/GE2.5-framework-analysis.sh`）三级回退：
   - 通过 → 按 extraction_plan 精准提取（build-nodes.sh 自动读取）
   - 部分失败 → 警告 + 回退全部提取器
   - 完全失败 / 无 profile → 静默回退全部提取器（= v1 行为，nightly 无 AI 场景零退化）

**执行模式**：

| 模式 | 命令 | 适用 |
|------|------|------|
| 全量 | `bash scripts/pipeline.sh` | 首次提取 / 配置变更 / 脚本变更 |
| 增量 | pipeline.sh + 变更检测（见 `EXTRACTION-WORKFLOW.md §6`） | 日常更新 |
| 单仓库 | `build-nodes.sh <service> <path>` + 后续 layers | 调试 / 局部重提取 |

**交接块内容**：执行模式、任务编号、交付物路径要求、失败上报要求。

**G-E2 门禁**：见 `gate-criteria.md §G-E2`；**G-E2.5 门禁**：见 `gate-criteria.md §G-E2.5`。

## §4 E3 校准分析（D2 质量判定决策点）

**执行角色**：graph-orchestrator spawn calibration-analyzer

**v2 分工**：bash 层 `scripts/graph/compute-stats.sh` 只算数（5 项检查数值 + blockers，无 rating 字段）；
评级（score ≥0.90 GOOD / ≥0.70 FAIR / 其余 POOR）与分流判定由 calibration-analyzer 的 D2 决策完成。

**判定表**（唯一数据源：`output/calibration/calibration-report.json` + `output/edges/edge-stats.json`，若存在另读 `output/analysis/<service>-profile.yaml`）：

| 条件 | 判定 | 后续 |
|------|------|------|
| blockers 非空（提供者冲突等） | **升级 User** | 附证据与处理选项（优先于其他判定） |
| 校准数据文件缺失/损坏 | **升级 User** | 退回 E2 或人工介入 |
| D2 评级 ∈ {GOOD, FAIR} 且无 unknown pattern | **E5** | 进入发布门禁 |
| D2 评级 == POOR | **E4** | 附 unresolved 归因清单 |
| 存在 `[AI-REQUIRED]` unknown pattern | **E4** | 附模式线索清单（文件路径 + import） |
| unresolved 主因为“非标模式未覆盖” | **E4** | 附缺失协议特征 |

**G-E3 门禁**：见 `gate-criteria.md §G-E3`。

## §5 E4 自适应编码

**执行角色**：graph-orchestrator spawn adapter-developer

**触发来源**：E3 判定 / User 手动 `/adapt`。

**执行序列**：模式分析（analyze-pattern.md）→ 脚本生成（generate-script.md）→ GP1-GP5 fixture 验证 → 持久化（persist-rule.md）→ 同步 EXTRACTION-WORKFLOW.md 与 docs/specs/extraction-scope.md。

**迭代控制**：
- 同一模式迭代上限 3 次；每轮 E4 完成后回 E2 重跑以验证真实效果
- 第 3 次仍 POOR / 未解决 → 在 E4-adapt-report.md 记录失败证据 → 升级 User（附：继续尝试 / 降级接受 FAIR / 放弃该模式 三选项）
- E4 将任务变更级别自动升级为**标准变更**

**G-E4 门禁**：见 `gate-criteria.md §G-E4`。详细操作见 `guides/self-adaptation.md`。

## §6 E5 发布门禁与归档

**执行角色**：graph-orchestrator spawn gate-reviewer；归档 spawn graph-publisher

**E5 活动**：
1. gate-reviewer 按 `gate-criteria.md` 执行 5 项门禁，出具 Pass / Conditional Pass / Reject
2. Pass → orchestrator 向 User 请求**发布确认**（硬停闸）
3. User 确认 → spawn graph-publisher 归档：图谱快照 + completion-summary.md + 移入 archive + 状态机收口
4. Conditional Pass → 限期整改项登记后同 Pass 路径（整改项写入 completion-summary 遗留项）
5. Reject → 按 §7 回退

## §7 回退铁律

**核心原则**：禁止跳门禁回退；任何回退必须重新执行对应门禁。

| 场景 | 回退路径 |
|------|---------|
| E2 执行失败（clone 失败/脚本异常） | E2 内部重试 ≤2 次 → 失败升级 User |
| E3 判定 blocker | 升级 User 决策（补充 repos.yaml / 豁免 / 终止） |
| E4 脚本 GP 验证失败 | E4 内部整改 → 3 次上限后升级 User |
| E5 Reject（数据问题） | → E2 重跑 → E3 重新判定 |
| E5 Reject（脚本问题） | → E4 整改 → E2 重跑 |
| 归档前发现计划错误 | → E1 重新确认 |

## §8 Auto-Relay 与硬停闸

**Auto-Relay**：门禁 Pass 后 orchestrator 自动推进下一阶段（受 state.yaml `gate-confirm-mode` 配置：auto=自动推进，strict=每门禁等 User）。

**5 个硬停闸**（任何模式下必须等 User）：
1. **需求确认**：E1 执行计划产出后
2. **发布确认**：E5 Pass 后、归档前
3. **升级决策**：E4 迭代超限 / E3 blocker
4. **豁免确认**：任一门禁申请豁免时
5. **变更级别升级确认**：快速变更因 E4 升级为标准变更时（首次 E4 触发时一并确认）

> **Nightly 例外**：无人值守模式下 5 个硬停闸按 `nightly-mode.md §2` 策略替代（跳过 E4/豁免，POOR 记入晨检队列），其余规则不变。
