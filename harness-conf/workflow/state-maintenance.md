---
title: harness · 状态机维护规则
purpose: 两层状态机 + 审计日志的写入规则与召回降级策略
version: v1.0.0
author: harness
status: Baseline
---

# harness · 状态机维护规则

## §1 三层状态架构

```
全局状态机 docs/status/state.yaml
  ├─ current-change / current-phase / gate-status / gate-confirm-mode / history
  │
  └─ 关联 → 任务级状态机 docs/changes/<任务编号>/state.yaml
              ├─ change-id / change-level / current-phase / gate-status / adaptation-round
              │
              └─ 补充 → 审计日志 progress.md（全局 + 任务级各一份，append-only）
```

## §2 全局 state.yaml 字段

```yaml
version: "1.0"
project: code-graph-harness
current-change: EXT-20260810-01        # 当前任务编号，无任务时为 null
current-phase: E2                       # E1-E5 / ARCHIVED / null
gate-status: pending                    # pending / passed / rejected / exempted
gate-confirm-mode: auto                 # auto（自动推进）/ strict（每门禁等 User）
adaptation-round: 0                     # 当前任务 E4 迭代轮次（上限 3）
history:                                # 最近 10 条任务记录
  - change: EXT-20260810-01
    result: completed
    score: 0.85
    completed-at: 2026-08-10T12:00:00Z
```

## §3 任务级 state.yaml 字段

```yaml
change-id: EXT-20260810-01
change-level: quick                     # quick / standard（E4 触发自动升级 standard）
extraction-mode: full                   # full / incremental / single-repo
current-phase: E3
gate-status: pending
adaptation-round: 0
escalations: []                         # 升级 User 事件记录
started-at: 2026-08-10T02:00:00Z
completed-at: null
```

## §4 写入规则

1. **原子刷新**：阶段切换时整体重写 state.yaml（不做行内修补），随后追加 progress.md 事件
2. **append-only**：progress.md 只追加不修改；事件格式：
   ```
   - [2026-08-10 10:44:12] [E2] [passed] pipeline exit 0, artifacts written
   ```
3. **写权限**：正常流程仅 graph-orchestrator 写；归档时 graph-publisher 做收口刷新
4. **同步要求**：全局与任务级 state.yaml 的 current-phase 必须一致；不一致时以任务级为准并修复全局
5. **豁免与升级**：所有 User 豁免、升级决策必须同时记入 state.yaml（gate-status/escalations）与 progress.md

## §5 召回与降级策略

| 失败场景 | 降级策略 |
|---------|---------|
| 任务级 state.yaml 缺失但 progress.md 存在 | 从 progress.md 事件序列重建 state.yaml |
| state.yaml 与 progress.md 矛盾 | 以 state.yaml 为准，progress.md 追加 errata 说明 |
| 全局 state.yaml 缺失 | 从 docs/changes/ 目录扫描最近任务重建；仍失败则询问 User |
| 上下文完全丢失 | 返回 E1 重新开始（历史任务视为中止，登记 history） |

## §6 召回触发条件

| 触发条件 | 判定标准 | 优先级 |
|---------|---------|:------:|
| 跨阶段切换 | E? → G-E? 或 G-E? → E? | P0 |
| 轮数阈值 | 对话轮次 ≥ 30 轮 | P0 |
| subagent 切换 | spawn 新 subagent 前 | P1 |

召回动作：读全局 state.yaml → 任务级 state.yaml → progress.md 最近事件 → 输出上下文检查点（格式见 `INDEX.md §6`）→ 继续执行。
