---
description: 长会话状态召回（从状态机恢复上下文并继续任务）
---

以 graph-orchestrator 身份执行状态召回。

## 执行步骤

1. 读取全局状态机 `docs/status/state.yaml`：获取 current-change / current-phase / gate-status
2. 读取变更级状态机 `docs/changes/<current-change>/state.yaml` 与审计日志 `progress.md`
3. 读取全局审计日志 `docs/status/progress.md` 最近 20 条事件
4. 输出上下文检查点：

```
📌 上下文检查点
- 当前任务：<current-change>（变更级别：<level>）
- 当前阶段：<E?>（来自变更级 state.yaml）
- 门禁状态：<gate-status>
- 最近事件：<progress.md 最后 3 条>
- 未完成事项：<当前阶段待办清单>
```

5. 按 `harness-conf/workflow/state-maintenance.md §5` 处理异常：
   - state.yaml 缺失但 progress.md 存在 → 从日志重建
   - 两者矛盾 → 以 state.yaml 为准，progress.md 追加 errata
   - 完全丢失 → 询问 User 确认当前状态
6. 检查点输出后，询问 User 是否从中断点继续执行
