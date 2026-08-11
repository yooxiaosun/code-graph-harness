---
description: 增量更新图谱（仅重提取有变更的仓库）
---

以 graph-orchestrator 身份执行增量更新任务。

## 任务输入

$ARGUMENTS

（留空则自动检测所有已克隆仓库的 commit 变更）

## 执行要求

1. 变更检测：spawn pipeline-executor 对 `output/repos/` 下每个仓库执行 `git rev-parse HEAD` 并与 `.last_commit_hash` 对比，产出变更仓库清单；若无变更，报告"无需更新"并结束
2. 创建任务目录（任务编号格式 `UPD-YYYYMMDD-NN`），变更级别默认**快速变更**（纯数据刷新，不改脚本）；若 User 参数指定了额外脚本修复诉求则升级为标准变更
3. 增量执行：仅重提取变更服务的 Layer 1 节点；edges / calibration / assemble 全量重建（边可能跨服务，依据 `EXTRACTION-WORKFLOW.md §6`）
4. E3-E5 与 `/extract` 相同：calibration-analyzer 判定 → 必要时 E4 → gate-reviewer 门禁 → User 发布确认 → graph-publisher 归档
5. 全程刷新 state.yaml + progress.md
