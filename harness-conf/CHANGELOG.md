# Harness 变更日志

> 本文档记录 harness 框架的版本变更历史。
> 版本号遵循语义化版本规范：`MAJOR.MINOR.PATCH`

---

## [v1.2.0] - 2026-08-10 - Nightly AI 驱动模式（E4 三道防线）

### 核心变更

**1. E4 三道防线（AI 写提取器的可靠性方案）**

目标：让 AI 在夜间（或交互中）编写新提取器，但禁止直接写入正式目录。

解决方案：
- `.harness/staging/README.md`：E4 交付包暂存区规范（AI 唯一可写区）
- `scripts/e4-verify-bundle.sh`：交付包一键自证（GP1 语法 / GP2 执行 / GP3 JSON / GP4 召回 / GP5 既有提取器回归）
- `scripts/promote-extractor.sh`：晋级闸门（唯一写正式目录的通道：再次全量自证 + 防覆盖冲突 + progress 记录 + staging 归档）
- opencode.json 增加 Agent 级权限：`adapter-developer` edit 仅限 `.harness/staging/**`、bash 仅限验证脚本；`calibration-analyzer` 仅可写归因报告

设计原则：
- 写与生效分离：AI 只能产出交付包，晋级必须过闸门
- 默认人工晋级（夜间只标记待晋级），`--auto-promote` 不绕过任何门禁

**2. nightly.sh AI 驱动参数**

- `--ai`：E3 AI 归因（本地 Ollama 推理，产出 e3-attribution / e4-input）
- `--e4`：E4 自适应编码（staging 收束执行，默认只标记待晋级）
- `--auto-promote`：全绿交付包自动晋级
- 后端预检与降级：opencode CLI / Ollama 健康端点 / OLLAMA_MODEL 任一不可用 → 自动降级纯本地并记晨检队列
- 摘要新增「AI 驱动」段（模式/模型/降级原因/产物路径）

### 设计决策

- 权限收束采用 opencode `agent.<name>.permission`（Agent 级覆盖），交互与夜间同一套收束规则
- E4 回归采用既有提取器重跑（http-client/mq/socket 三套 fixtures），比检查基线文件更严格

---

## [v1.1.0] - 2026-08-10 - Nightly 夜间无人值守模式 + 治理层重构

### 核心变更

**1. Nightly 无人值守模式**

目标：利用夜间算力批量提取，无人值守自动执行。

解决方案：
- `harness-conf/workflow/nightly-mode.md`：夜间模式规则（硬停闸替代策略、晨检队列、安全边界）
- `scripts/nightly.sh`：包装脚本（前置检查 → 锁文件防并发 → pipeline → 门禁 → 晨检队列 → 摘要 → 状态收口）
- `docs/status/nightly-queue.md`：晨检队列（append-only，POOR/异常留给次日人工消化）

设计原则：
- 夜间跑提取不跑自适应编码（E4 跳过，缺口只记录不修复）
- 5 个硬停闸全部自动化替代，但禁止自动豁免门禁
- 空 repos.yaml 拒绝执行（不虚构仓库）

**2. 运行时切换：Claude Code → OpenCode**

- `.claude/` → `.opencode/`（agents/ 6 个 + commands/ 4 个 + opencode.json 配置）
- 全部文档引用同步更新

**3. 治理层重构（上承 v1.0.0 双轨并存）**

- 删除 `.scale/`，治理内容迁移至 `docs/standards/ENGINEERING_RULES.md` + `docs/workflow/QUALITY_CONTRACT.md` + `docs/workflow/templates/`
- 项目目录改名：`scale-os-config-claude-code/` → `harness/`
- ARCHITECTURE.md §5 重写为治理域边界（G0 被 gate-criteria.md 复用，冲突以 gate-criteria.md 为准）

### 修复

- `scripts/nightly.sh`：bash 3.2 全角字符粘连变量名解析 bug（`$VAR）` → `${VAR}）`）；REPO_COUNT 双行输出导致整数比较失败；互斥检查 `[^n]` 漏检 nightly- 前缀任务

### 验证证据

- 空 repos.yaml：正确 FATAL exit 1 且零污染
- 本地 fixture 仓库全链路：pipeline exit 0 → G-E1/G-E2/G-E5 PASS → G-E3 FAIL（POOR）→ 晨检队列 2 条 → 摘要生成 → state.yaml 收口 → 锁清理
- G0 门禁：exit 0

---

## [v1.0.0] - 2026-08-10 - 提取运营流 E1-E5 初版

### 核心变更

**1. 提取运营流 E1-E5 建设**

目标：
- 参照 harness-demo 机制（主 Agent 调度 + subagent 角色 + 门禁 + 状态机 + 长会话召回），为代码知识图谱场景建设专用 harness 工程

解决方案：
- E1 任务接收（orchestrator 主执行，User 确认）
- E2 流水线执行（pipeline-executor）
- E3 校准分析（calibration-analyzer）
- E4 自适应编码（adapter-developer，3 次迭代上限）
- E5 发布门禁（gate-reviewer，硬停闸）
- 归档（graph-publisher）

**2. 6 角色 Agent 体系**

| Agent | 模式 | 职责 |
|-------|------|------|
| graph-orchestrator | primary | 调度、状态机维护、E1 主执行、归档 |
| pipeline-executor | subagent | E2：跑 pipeline.sh、收集证据 |
| calibration-analyzer | subagent | E3：解读 5 项校准 |
| adapter-developer | subagent | E4：唯一可写脚本的角色 |
| gate-reviewer | subagent | E5：门禁评审 |
| graph-publisher | subagent | 归档、快照、报告合并 |

**3. 门禁体系（双轨并存）**

- **工程门禁**：G0-G22 通用门禁，位于 `scripts/gates/G*-verify.sh`
- **运营门禁（harness-conf）**：G-E1 至 G-E5 提取流程门禁，每项含可执行验证命令
- **自适应门禁（GP）**：GP1-GP5 fixture 验证门禁，确保新提取器质量

**4. 自适应闭环架构**

- 数据面（output/）只增不改，能力面（scripts/extractors/）可自我演化
- E3 发现 unknown pattern → E4 分析模式 → 生成提取器 → GP1-GP5 验证 → 持久化
- 3 次迭代上限，超限升级 User

**5. 状态机与长会话召回**

- 全局：`docs/status/state.yaml`（current-change / current-phase / gate-status）
- 任务级：`docs/changes/<任务编号>/state.yaml`
- 审计日志：append-only progress.md
- 中断后可经 `/status` + state.yaml 召回续跑

**6. 4 个 slash 命令**

| 命令 | 职责 |
|------|------|
| `/extract` | 启动 E1-E5 全流程 |
| `/adapt` | 手动触发 E4 自适应 |
| `/update` | 增量更新 |
| `/status` | 状态召回 |

### 交付物清单

**入口**：`CLAUDE.md`（项目定位 + 硬约束）

**Agent 定义**：`.opencode/agents/` 6 个 Agent

**命令定义**：`.opencode/commands/` 4 个 slash 命令

**流程文档**：`harness-conf/`
- INDEX.md（召回入口）
- ARCHITECTURE.md（协作约束 + 术语规范 + §5 治理域边界）
- CHANGELOG.md（本文档）
- workflow/extraction-flow.md（E1-E5 单一真源）
- workflow/gate-criteria.md（G-E1 至 G-E5 可执行标准）
- workflow/roles.md（RACI 矩阵）
- workflow/state-maintenance.md（状态机维护规则）
- guides/self-adaptation.md（自适应闭环操作手册）

**状态区**：`docs/`
- status/state.yaml（全局状态机初始模板）
- status/progress.md（全局审计日志）
- specs/extraction-scope.md（提取范围真相源）
- changes/_template/state.yaml（任务级状态机模板）
- changes/_template/progress.md（任务级审计日志模板）

**门禁脚本**：`scripts/gates/GE3-extraction-quality.sh`（提取质量门禁）

### 修复

- `scripts/extractors/nonstandard/extract-http-client.sh`：变量形式 URL 回溯 + 多行调用兜底（GP4 拦截后修复）
- `scripts/extractors/graph/calibrate.sh`：空 blockers/warnings 数组序列化为 `[""]` 修正为 `[]`
- `.opencode/opencode.json`：权限配置与入口指令

### 验证证据

- G0 构建门禁：exit 0
- GP1-GP5 fixture 门禁：修复后全绿
- 端到端走查：3 个 fixture 样例仓库提取 → 3 服务 / 9 接口 / 4 非标边组装成功
- GE3 提取质量门禁：空图谱下正确 FAIL（POOR），证明门禁非摆设
- E4 闭环演示：GP4 拦截 → 修复 → GP1-GP5 复验全绿
