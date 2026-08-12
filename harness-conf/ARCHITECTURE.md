---
title: harness · Agents架构约束
purpose: 主Agent+5角色协作约束 + 术语规范单一真源
version: v1.0.0
author: harness
status: Baseline
---

# harness · Agents架构约束

> **职责说明**：本文件定义 Agents 协作约束 + 术语规范。
> **角色职责边界**：见 `workflow/roles.md`（单一真源，RACI矩阵）
> **流程定义**：见 `workflow/extraction-flow.md`（单一真源，阶段定义）
> **Agent定义**：见 `.opencode/agents/*.md`（权限约束在frontmatter + 正文）

---

## §1 Agents 协作模式

### 主Agent调度流程图

```
User提出提取需求（/extract | /update | /adapt）
    ↓
graph-orchestrator（主Agent）接收 → 创建任务目录 → 初始化 state.yaml → 进入 E1
    ↓
E1(orchestrator主执行) → User确认执行计划
    ↓
E2(pipeline-executor) → G-E2
    ↓
E3(calibration-analyzer) → G-E3 → 判定表分流
    ├─ GOOD/FAIR 且无 blocker ────────────────┐
    ├─ POOR / unknown pattern → E4            │
    │      (adapter-developer) → G-E4         │
    │      → 回 E2 重跑（迭代上限 3 次）       │
    └─ blocker / 数据损坏 → 升级 User          │
                                              ↓
                                E5(gate-reviewer) → G-E5
                                              ↓
                            User发布确认（硬停闸） → 归档(graph-publisher)
```

### 强制spawn规则

| 场景 | 强制spawn的agent | 原因 |
|------|-----------------|------|
| E2 流水线执行 | pipeline-executor | 执行与调度分离，证据独立 |
| E3 校准分析 | calibration-analyzer | 质量判定需独立视角 |
| E4 自适应编码 | adapter-developer | 唯一授权写脚本的角色 |
| E5 发布门禁 | gate-reviewer | 评审需独立视角 |
| 归档 | graph-publisher | 归档与调度分离 |

**E1 例外**：E1 为任务接收与计划，orchestrator 主执行，不 spawn。

## §2 术语规范（单一真源）

| 术语 | 规范写法 | 禁止写法 | 说明 |
|------|---------|---------|------|
| **subagent** | 小写 | SubAgent, subAgent | Agent执行模式之一 |
| **User** | 大写 | user, users | 表示用户（业务方） |
| **harness** | 小写 | Harness | 体系名称（文档标题除外） |
| **E1-E5** | 大写E+数字 | e1, phase1 | 提取运营流阶段编号 |
| **G-E1 至 G-E5** | 大写 | gate-e1 | 提取流程门禁编号 |
| **GP1-GP5** | 大写 | gp1 | 自适应脚本 fixture 验证门禁 |
| **匹配率** | match_rate | — | edge-stats.json 字段名保持英文 |

## §3 Agents 定义文件位置

| Agent | 定义文件 | 模式 |
|-------|---------|:----:|
| graph-orchestrator | `.opencode/agents/graph-orchestrator.md` | primary |
| pipeline-executor | `.opencode/agents/pipeline-executor.md` | subagent |
| calibration-analyzer | `.opencode/agents/calibration-analyzer.md` | subagent |
| adapter-developer | `.opencode/agents/adapter-developer.md` | subagent |
| gate-reviewer | `.opencode/agents/gate-reviewer.md` | subagent |
| graph-publisher | `.opencode/agents/graph-publisher.md` | subagent |

## §4 自适应闭环架构

本工程区别于普通提取工具的核心能力：**Agent 可自行扩展提取能力**。

```
数据面（只增不改）                 能力面（可自我演化）
output/nodes/edges/calibration     .harness/extractors/
        │                                  ▲
        │  E3 发现覆盖缺口                  │ E4 持久化新提取器
        ▼                                  │
   calibration-analyzer ──线索清单──▶ adapter-developer
                                           │
                                     GP1-GP5 fixture 门禁
                                     （未过禁止集成）
```

**安全边界**：
1. 能力面修改只允许 adapter-developer 执行，且必须过 GP1-GP5
2. GP5 回归（`bash scripts/tests/run.sh`）保证既有提取能力不被破坏
3. 每次能力扩展都留下可追溯记录：`.harness/patterns/{pattern}.md` + E4-adapt-report.md
4. 迭代上限 3 次 + User 升级通道，防止无限自我重试

## §5 治理域边界

**`harness-conf` 是本工程唯一活跃的治理层**，定义提取运营流程（阶段 E1-E5、角色、状态机、领域门禁 G-E1 至 G-E5）。

- **工程门禁**：位于 `scripts/gates/G*-verify.sh`，为可运行的 bash 检查脚本。Gate profile 通过 `scripts/gates/all.sh` 调用，与 harness-conf 协作。完整门禁清单：G0/G4/G5（工程默认）+ GE2.5（框架分析）+ GE3（提取质量）+ GP1-GP5（提取脚本 fixture 验证）。
- **复用关系**：G0 被 `gate-criteria.md` 引用复用（G-E1 构建门禁）。
- **曾经存在的 `.scale/`**：SCALE OS 配置器生成的通用工程治理层（governance.yaml / workflow.json / quality-contract.json），面向 Python 工具链假设（ruff/pytest/mypy），对当前 Bash 项目不适用，已删除；其治理内容已迁移至 `docs/standards/ENGINEERING_RULES.md`（工程红线）与 `docs/workflow/QUALITY_CONTRACT.md`（任务分级与交付物契约）。

> 其余参考：`SCALE-PROMPT.md` 为 Agent 行为纪律，对所有角色生效；`EXTRACTION-WORKFLOW.md` 为三层提取技术真相源，E4 持久化后同步更新。
