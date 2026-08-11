---
title: harness · Nightly 夜间无人值守模式
purpose: 夜间批量提取与 AI 分析/编码的执行规则、硬停闸替代策略、三道防线、安全边界
version: v1.2.0
author: harness
status: Baseline
---

# harness · Nightly 夜间无人值守模式

> **一句话定义**：夜间批量提取跑数据，可选 AI 驱动（`--ai`/`--e4`）跑归因分析与自适应编码；AI 只能产出不能生效（三道防线），发现质量缺口只记录不修复，留给第二天人工消化。
> **执行入口**：`bash scripts/nightly.sh [--ai] [--e4] [--auto-promote]`（cron 定时调用）

## §1 适用场景与触发

| 场景 | 说明 |
|------|------|
| 夜间算力利用 | 全量提取大仓库 + 本地 Ollama 推理（GPU 夜间空闲），白天交互确认 |
| 定时批量 | 多仓库顺序提取，单仓库失败不中断整体 |
| 回归巡检 | 定期重跑验证提取器稳定性（POOR 自动上报） |

**触发方式**：`cron` 调用 `bash scripts/nightly.sh [--ai] [--e4] [--auto-promote] [--model <provider/model>] [--ollama-url <url>]`

| 参数 | 作用 |
|------|------|
| `--ai` | E3 用本地 Ollama 做 AI 归因（后端不可用自动降级纯本地，见 §5.3） |
| `--e4` | 在 `--ai` 基础上执行 E4 自适应编码（staging 收束，默认只标记待晋级） |
| `--auto-promote` | 全绿交付包自动晋级（默认人工晋级，不推荐自动） |
| `--model` | 模型标识（如 `ollama/qwen2.5-coder:14b`），或环境变量 `OLLAMA_MODEL` |
| `--ollama-url` | Ollama 服务地址，默认 `http://localhost:11434`，或环境变量 `OLLAMA_URL` |

## §2 硬停闸替代策略

| 硬停闸 | Interactive | Nightly 替代 |
|--------|------------|-------------|
| E1 需求确认 | User 确认 | 读 `repos.yaml` 自动出计划（全量模式），跳过确认，计划写入 E1-plan.md |
| E5 发布确认 | User 确认 | G-E1/G-E2/G-E3/G-E5 全 Pass → 自动归档 |
| 升级决策（E4 超限/blocker） | User 三选一 | 默认跳过 E4 写入晨检队列；`--e4` 时改为**受限执行**（staging + 门禁自证，禁止直接生效），超限仍记晨检队列 |
| 豁免确认 | User 确认 | **禁止自动豁免**；需要豁免的仓库记入晨检队列 |
| 变更级别升级确认 | User 确认 | 自动接受（仅日志记录） |

## §3 Nightly 执行序列

```
0. 前置检查（nightly.sh）
   - repos.yaml 非空（空则 exit 1，不发通知）
   - 无锁文件 .nightly.lock（防并发，超时 12h 自动失效）
   - git/bash/jq 可用
   - [--ai] AI 后端预检：opencode CLI + Ollama 健康端点（/api/tags）+ OLLAMA_MODEL
        任一不可用 → 降级纯本地（记晨检队列），不中断整体
1. 初始化
   - 写入 state.yaml: execution-mode=nightly, started-at=<now>
   - 创建 output/nightly/ 目录
2. E2 逐仓库执行（pipeline.sh 或单仓库模式）
   - 每个仓库独立执行，失败不中断整体
   - 失败原因记入 summary + 晨检队列
3. E3 校准分析
   - 规则判定：GOOD/FAIR 且无 blocker → 通过
   - POOR / unknown pattern / blocker → 不修复，记入晨检队列
   - [--ai] POOR 时追加 AI 归因：opencode headless 跑 calibration-analyzer
        → output/nightly/e3-attribution-<日期>.md（归因结论）
        → 判定需新提取器时产出 output/nightly/e4-input-<日期>.md（E4 触发信号）
4. 门禁
   - 必跑：G-E1（G0）、G-E2（产物存在）、G-E3（GE3 脚本）、G-E5（schema 校验）
   - 跳过：G-E4（E4 受限执行见下，不直接写脚本）
   - 任一 MUST 失败 → 该仓库记入晨检队列，不归档
5. [--e4] E4 自适应编码（受限执行，三道防线）
   - 有 e4-input 触发信号 → opencode headless 跑 adapter-developer
   - AI 在 .harness/staging/<pattern>/ 产出交付包（脚本+fixtures+期望输出+报告）
   - nightly.sh 对最新交付包跑 e4-verify-bundle.sh（GP1-GP5 + 回归）
   - 全绿 → 默认记"待晋级"进晨检队列；--auto-promote 才执行 promote-extractor.sh
   - 未全绿 → 交付包留在 staging，记晨检队列供次日诊断
6. 归档
   - 全部门禁 Pass 的仓库：归档（图谱快照 + 摘要）
   - 失败仓库：output/nightly/partial-<日期>.md 留证据
7. 产出
   - output/nightly/summary-<YYYY-MM-DD>.md（执行摘要，含 AI 段）
   - docs/status/nightly-queue.md（晨检队列，append-only）
   - state.yaml 收口：execution-mode=interactive, completed-at=<now>
```

## §4 晨检队列

**位置**：`docs/status/nightly-queue.md`（append-only，禁止改写历史条目）

**条目格式**：`- [YYYY-MM-DD HH:MM] <仓库> | <原因> | <建议>`

| 原因类别 | 写入时机 | 建议（供次日 orchestrator 参考） |
|---------|---------|-------------------------------|
| POOR（match_rate < 0.70） | GE3 FAIL | 进 E4 自适应或人工评估模式覆盖 |
| [AI-REQUIRED] unknown pattern | E3 归因判定 | 进 E4 分析未知模式 |
| E4 交付包待晋级 | e4-verify-bundle 全绿 | 白天运行 `promote-extractor.sh <pattern>` |
| E4 交付包未过验证 | e4-verify-bundle FAIL | 查看 e4-agent/e4-bundle 日志，人工诊断 staging |
| AI 降级 | 预检失败 | 检查 Ollama 服务与 OLLAMA_MODEL 后重试 --ai |
| blocker（提供者冲突等） | E3 判定 | 人工决策：补 repos.yaml / 豁免 / 终止 |
| 门禁 Reject（数据问题） | G-E2/E-E5 FAIL | 回 E2 重跑或人工检查数据 |
| 仓库 clone/构建失败 | E2 异常 | 检查网络/凭证/仓库地址 |
| 需要豁免 | nightly 禁止自动豁免 | 人工确认豁免 |

**消化方式**：次日 User 或 orchestrator 以 `/adapt` 或 `/extract` 按队列逐项处理，处理完在条目后追加 `✅ 已处理（<方式>）`。

## §5 AI 驱动模式（--ai / --e4）

### 5.1 三道防线（E4 可靠编码的核心）

| 防线 | 机制 | 效果 |
|------|------|------|
| **1. 权限收束** | opencode.json 给 `adapter-developer` 配 Agent 级 permission：edit 仅 `.harness/staging/**`；bash 仅验证脚本；`promote-extractor.sh`、`scripts/extractors/**`、`repos.yaml`、`output/**` 全部 deny | 权限层面不存在写坏正式目录的可能 |
| **2. 产物自证** | 交付包强制三件套（脚本+样例+期望输出）；`scripts/e4-verify-bundle.sh` 一键跑 GP1-GP5 + 既有提取器回归 | AI 必须自证正确，门禁不过产物不离开 staging |
| **3. 晋级闸门** | `scripts/promote-extractor.sh` 是唯一能写正式目录的通道（再次全量自证 + 防覆盖冲突 + 记录 progress + staging 归档）；夜间默认只标记待晋级 | 生效动作可追溯、可回退 |

### 5.2 算力策略

- 夜间窗口：pipeline 吃本地 CPU/网络；E3 归因与 E4 编码吃本地 GPU（Ollama 推理），是**夜间 AI 算力的主要消耗**
- GPU 消耗自调节：提取质量好 → POOR 少 → 归因/编码触发少
- 白天 GPU ≈ 0：只做摘要阅读、晨检队列处理、`promote-extractor.sh` 晋级
- 首轮接入大量新仓库或非标 pattern 多时，夜间 GPU 会接近跑满（正常现象）

### 5.3 降级策略

`--ai`/`--e4` 时任一后端不可用 → **自动降级纯本地**（不中断整体执行），原因记入晨检队列与摘要：

| 降级原因 | 判定 |
|---------|------|
| opencode CLI 不存在 | `command -v opencode` |
| Ollama 不可达 | `curl /api/tags` 超时 5s |
| OLLAMA_MODEL 未配置 | 环境变量或 `--model` 均为空 |

### 5.4 产物路径

| 产物 | 路径 |
|------|------|
| E3 AI 归因结论 | `output/nightly/e3-attribution-<日期>.md` |
| E4 触发信号（模式线索） | `output/nightly/e4-input-<日期>.md` |
| E3/E4 agent 会话日志 | `output/nightly/e3-agent-<日期>.log` / `e4-agent-<日期>.log` |
| E4 交付包验证日志 | `output/nightly/e4-bundle-<日期>.log` |
| E4 交付包（AI 唯一可写区） | `.harness/staging/<pattern>/` |

## §6 安全边界（nightly 绝对不做）

1. **不直接写** `scripts/extractors/`（E4 产物限 `.harness/staging/`，晋级仅经 promote-extractor.sh）
2. **不修改** `repos.yaml`
3. **不修改** `harness-conf/` 任何文件
4. **不自动豁免**任何门禁
5. **不删除**任何历史产物（output/ 只增，由外部策略清理）
6. **E4 未过 e4-verify-bundle.sh（GP1-GP5 + 回归）不得晋级**；`--auto-promote` 不绕过任何门禁
7. **不执行 git 写操作**（commit/push/reset）；E4 Agent 权限已 deny
8. **不修改** `output/knowledge-graph/**` 与 `output/calibration/**`（图谱只由 pipeline/publisher 产出）

## §7 通知与日志

- 执行摘要：`output/nightly/summary-<YYYY-MM-DD>.md`（含各仓库结果矩阵 + AI 驱动段）
- 失败留证：`output/nightly/partial-<YYYY-MM-DD>.md`（门禁失败仓库的完整输出）
- AI 会话：`output/nightly/e3-agent-<日期>.log` / `e4-agent-<日期>.log`
- cron 输出：`output/nightly/cron.log`（追加）
- 可选通知：cron 第二行调用 `cat docs/status/nightly-queue.md | curl -X POST <webhook>`（User 自配）

## §8 与 Interactive 模式的互斥

- 同一时刻只允许一个执行模式：nightly 运行期间 state.yaml `current-change` 非空，orchestrator 的 `/extract` 应发现进行中任务并拒绝启动
- nightly 结束（completed-at 落盘）后恢复 `execution-mode: interactive`
- 状态机维护规则完全复用 `state-maintenance.md`（无独立状态机）
