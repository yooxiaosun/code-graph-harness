---
title: harness · 自适应闭环操作手册
purpose: E4 自适应编码的触发条件、执行序列、迭代控制与升级路径
version: v1.0.0
author: harness
status: Baseline
---

# harness · 自适应闭环操作手册

> 本手册指导 adapter-developer 与 orchestrator 执行 E4。技术模板见 `templates/`。

## §1 触发条件矩阵

| 触发信号 | 数据来源 | 动作 |
|---------|---------|------|
| rating == POOR（score < 0.70） | calibration-report.json | E3 判定 E4，附 unresolved 归因 |
| `[AI-REQUIRED]` unknown pattern | output/nodes/*/nonstandard-custom.json | E3 判定 E4，附文件路径 + import 线索 |
| unresolved 主因"非标模式未覆盖" | unresolved-consumers.json + E3 归因 | E3 判定 E4，附缺失协议特征 |
| User 手动 `/adapt` | 用户指令 | 直接进 E4（独立任务编号 ADAPT-*） |
| match_rate 高但特定服务零提取 | edge-stats + nodes 目录 | E3 报告中提示，User 决定是否 /adapt |

## §2 执行序列（adapter-developer 内部）

```
Step 1 模式分析    templates/analyze-pattern.md
  └─ 输出: is_rpc / protocol_type / detection_patterns / confidence / can_automate
  └─ 分流: confidence < 0.6 或 can_automate=false → 记录"需人工标注"后跳过

Step 2 脚本生成    templates/generate-script.md
  └─ 产物: project/staging/<pattern>/extract-{pattern}.sh

Step 3 fixture 验证（GP1-GP5，全绿才继续）
  ├─ 构造样例: fixtures/sample-{pattern}/（最小可触发 Java 代码）
  ├─ 构造期望: fixtures/expected/{pattern}.json
  ├─ GP1 语法 / GP2 执行 / GP3 Schema / GP4 召回 / GP5 回归

Step 4 持久化      templates/persist-rule.md
  ├─ project/patterns/{pattern}.md（含 GP 验证记录）
  ├─ repos.yaml nonstandard.scanners 注册
  ├─ pipeline.sh 按 EXTRACTORS_DIR 扫描 project/extractors/，无需手动接入
  └─ 文档同步: EXTRACTION-WORKFLOW.md §2.4.5 + docs/specs/extraction-scope.md

Step 5 回 E2 重跑验证真实效果
```

## §3 迭代控制

- **迭代上限**：同一模式 3 轮（adaptation-round 记录在任务级 state.yaml）
- **每轮验证**：E4 完成后必须回 E2 重跑（至少单仓库模式），用真实 match_rate / unresolved 变化衡量效果
- **收敛判定**：重跑后 rating 提升或 unknown pattern 清零 → 进 E5；无改善 → 换检测策略重试
- **超限升级**：第 3 轮仍失败 → E4-adapt-report.md 记录失败证据 → orchestrator 升级 User，三选项：
  1. 继续尝试（User 明确放宽上限）
  2. 降级接受当前 rating（记录豁免）
  3. 放弃该模式（登记到 docs/specs/extraction-scope.md 的"已知未覆盖"清单）

## §4 质量红线

1. 未过 GP1-GP5 的脚本**禁止**纳入 EXTRACTORS_DIR 调度（防止污染数据面）
2. GP5 回归必须覆盖既有三个 fixture（http-client / mq / socket）
3. 新脚本不得引入 bash/grep/jq 之外依赖
4. 检测 pattern 宁窄勿宽：误报（false positive）比漏报更伤图谱可信度；宁可低置信度标记交给 E3 的 D 检查复核
5. 每次持久化必须留痕：`project/patterns/{pattern}.md` 的 Verification History 表

## §5 示例：一个新模式的完整生命周期

```
E3 发现: payment-service 中 3 处 import com.example.thrift.TServiceClient
  ↓ analyze-pattern: is_rpc=true, protocol=thrift, confidence=0.8, can_automate=true
  ↓ generate-script: extract-thrift.sh（grep TServiceClient + 方法调用）
  ↓ fixture: sample-thrift/ + expected/thrift.json
  ↓ GP1-GP5 全绿
  ↓ 持久化 + repos.yaml 注册 + pipeline.sh 经 EXTRACTORS_DIR 调度
  ↓ 回 E2 重跑: unresolved 从 8 降到 2, match_rate 0.68 → 0.81 (FAIR)
  ↓ E3 判定 E5 → 发布
```

## §6 三类产物晋级与评审路径（v2）

| 产物类别 | 产出位置 | 自证方式 | 晋级通道 | 评审方式 |
|---------|---------|---------|---------|---------|
| 代码层（提取器） | `project/staging/<pattern>/` | `bash scripts/e4-verify-bundle.sh <pattern>` | `promote-extractor.sh` → `project/extractors/<pattern>/` | GP1-GP5 全绿 |
| 代码层（SDK 扩展） | `project/staging/sdk/<name>/` | `test-<name>.sh` | `promote-sdk.sh` → `scripts/base/` | 测试全绿 + bash -n |
| 分析层（报告） | `docs/changes/<任务>/artifacts/E4-adapt-report.md` | 内容审查 | 无需晋级（直接归档） | orchestrator / gate-reviewer |
| 知识层（规则） | `project/rules/` `project/patterns/` | content review | 直接写入（不入晋级闸门） | gate-reviewer 抽样审查 |
