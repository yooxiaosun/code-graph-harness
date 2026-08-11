# 夜间模式晨检队列（append-only）
# 条目格式：- [YYYY-MM-DD HH:MM] <任务> | <原因> | <建议>
# 由 scripts/nightly.sh 自动追加，由 orchestrator 在下次 /extract 或 /adapt 时消化
# 处理完成后在条目后追加「✅ 已处理（<方式>）」，禁止改写历史条目

