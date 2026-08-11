# 任务级审计日志模板 — 复制为 docs/changes/<任务编号>/progress.md 后使用
# append-only，禁止修改历史条目；格式见 harness-conf/workflow/state-maintenance.md §4

事件格式：`- [YYYY-MM-DD HH:MM:SS] [阶段] [状态] 描述`

- [YYYY-MM-DD HH:MM:SS] [E1] [started] 任务创建，模式=<full|incremental|single-repo>，变更级别=<quick|standard>
