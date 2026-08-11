---
description: 启动 E1-E5 完整知识图谱提取流程（全量 / 增量 / 单仓库）
---

以 graph-orchestrator 身份启动一次完整的提取运营流。

## 任务输入

$ARGUMENTS

（示例：`全量` / `增量` / `单仓库 order-service` / 留空则默认全量）

## 执行要求

1. 先读 `docs/status/state.yaml`：若存在进行中的任务，先完成或经 User 确认中止，禁止并行开启第二个任务
2. 按 `harness-conf/INDEX.md` 召回流程定位，按 `harness-conf/workflow/extraction-flow.md` 执行：
   - E1：解析 `repos.yaml`，创建任务目录 `docs/changes/<任务编号>/`，初始化变更级 state.yaml，产出 `artifacts/E1-plan.md`（范围 / 模式 / 变更级别 / 预计触发点），向 User 确认
   - E2：spawn pipeline-executor，门禁 G-E2
   - E3：spawn calibration-analyzer，按判定表流转（E5 / E4 / 升级 User）
   - E4（如触发）：spawn adapter-developer，门禁 G-E4，完成后回 E2 重跑
   - E5：spawn gate-reviewer，Pass 后向 User 请求发布确认（硬停闸）
   - 归档：spawn graph-publisher
3. 每次阶段切换刷新两层 state.yaml 并追加 progress.md
4. 结束时输出诚实交付总结：完成内容 / 已验证项（附命令与输出）/ 未验证项
