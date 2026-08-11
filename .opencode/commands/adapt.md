---
description: 手动触发 E4 自适应编码（分析未知模式并生成新提取器）
---

以 graph-orchestrator 身份手动触发 E4 自适应编码阶段。

## 任务输入

$ARGUMENTS

（示例：`分析 payment-service 的未知 import` / `为 gRPC-Web 模式生成提取器` / 留空则自动从最近一次 E3 报告取线索）

## 执行要求

1. 线索获取：优先使用参数指定的线索；否则读取最近一次 `docs/changes/*/artifacts/E3-calibration-analysis.md` 的 unknown pattern 清单与 `output/nodes/` 中的 `[AI-REQUIRED]` 标记
2. 若当前无进行中的任务目录，创建独立变更目录（任务编号格式 `ADAPT-YYYYMMDD-NN`），变更级别判定为**标准变更**（涉及脚本代码）
3. spawn adapter-developer，交接块包含：线索清单（文件路径 + import 语句）、`harness-conf/guides/self-adaptation.md`、三个 templates 路径
4. 门禁 G-E4：新脚本 `bash -n` + fixture GP1-GP5 全绿 + `bash scripts/tests/run.sh` 全绿，任一失败退回整改
5. 完成后询问 User：是否立即触发一次 `/update` 增量重提取以验证新提取器的真实效果
