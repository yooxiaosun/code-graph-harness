# Harness 变更日志

> 本文档记录 harness 框架的版本变更历史。
> 版本号遵循语义化版本规范：`MAJOR.MINOR.PATCH`

---

## [v2.1.0] - 2026-08-12 - 双维度架构（脚本 × AI 交叉印证）

### 核心变更

**1. 双维度提取（build-nodes.sh）**
- 脚本维度：`.harness/extractors/*/extract.sh` 机械基线 → `output/nodes-script/<svc>/`
- AI 维度：AI 直产 → `output/nodes-ai/<svc>/`（自动探测，存在即双轨）
- 合并：`scripts/base/merge-dual.sh` 取并集 + 置信度分级 + 去重 → `output/nodes/<svc>/`
- 向后兼容：无 AI 产出时单轨直写（v2 行为不变）

**2. 置信度模型（Q-Final=A）**
- 节点级印证：bash∩AI=high / 单方=medium / 矛盾=low
- 协议级加权：profile high→+1 / none→-1（profile 非独立印证源，见 ai-analysis-harness.md §7）

**3. 证据底线 C-E1 三级豁免**
- 普通节点：evidence_refs ≥1, tier 1-3（不满足即丢弃）
- 服务边界外（*_only）：上限 medium，进人工确认包
- 技术不可识别（*_unknown/dynamic）：low，进 bail-out 包

**4. AI 分析 Harness 约束（`templates/ai-analysis-harness.md`）**
- 收敛判定 4 条按场景分级：D1=3 / 双维度=4 / 低置信度=2
- 最大轮数：D1=2 / 双维度=3 / 低置信度=2 / E4=3
- Bail-out 严格不猜测（Q-Escape=A）
- `scripts/base/run-ai-analysis.sh` 驱动迭代

**5. 新增 Schema 与模板**
- `schemas/node.schema.json` + `schemas/edge.schema.json`（v2.1 契约，含 evidence_refs/evidence_type/source）
- `templates/dual-pass-review.md`（双维度二轮校准）
- `templates/low-conf-drill.md`（低置信度深挖）
- `templates/generate-human-review.md`（人工确认包）

**6. 门禁双维度（GE3 重写）**
- 脚本维：match_rate / blockers / 节点 schema + C-E1 证据链合规
- AI 维：双维度一致性可解释 + 实质验收
- 低置信度/bail-out 项 → `output/reviews/human-review-<date>.md` 白天人工确认

**7. 新增原子能力（scripts/base/）**
- `scan-files.sh`（文件扫描）/ `merge-json.sh`（JSON 合并）/ `validate-schema.sh`（Schema 校验）/ `merge-dual.sh`（双维度合并）

### 文档对齐
- DESIGN-V2.md 新增 §12 v2.1 双维度架构章节
- gate-criteria.md §G-E3 重写为双维度
- extraction-flow.md E2 双维度 + E3 双维度校准说明
- CLAUDE.md 新增「AI 迭代分析纪律」硬约束

### 向后兼容
- 单轨模式（无 AI 产出）= v2 行为，nightly 零退化
- 现有 3 个 fixture + GP1-GP5 + graph smoke 全部保留

---

## [v2.0.0] - 2026-08-11 - 工程设计 v2（分层架构 + AI 决策 + 框架分析）

### 核心变更

**1. 分层架构（§1-§2）**
- Harness 框架（人维护的不变层）与 Harness 产出物（AI 生成的可变层）明确分离
- Bash 定位为原子能力层：18 个能力单元，不做任何「要不要/好不好/为什么」判断
- AI 定位为决策层：D1 提取计划 / D2 质量判定 / D3 自适应编码 三个决策点

**2. 目录重组（§6）**
- 提取器从 `scripts/extractors/` 迁移至 `.harness/extractors/{proto}/extract.sh`
- 图谱内核从 `scripts/extractors/graph/` 迁移至 `scripts/graph/`
- 基础库从 `scripts/extractors/base/` 迁移至 `scripts/base/`
- GP 门禁从 `scripts/extractors/nonstandard/verify/` 迁移至 `scripts/gates/GP*-verify.sh`
- fixtures 从 `scripts/extractors/nonstandard/fixtures/` 迁移至 `.harness/fixtures/`
- 删除 14 个死门禁（G1/G2/G3/G6/G7/G8/G9/G16-G22）+ dead `build-graph.sh`
- `build-nodes.sh` 改为动态扫描 `.harness/extractors/*/extract.sh`

**3. D2 质量判定（Phase B）**
- `calibrate.sh` 拆分为 `compute-stats.sh`（bash 纯算数，不含 rating）+ D2 AI 判定（calibration-analyzer）
- GE3 门禁适配：移除 rating 检查，保留 match_rate / blockers / overallScore
- 评级规则（GOOD≥0.90 / FAIR≥0.70 / POOR<0.70）移至 D2 AI 决策点

**4. 框架分析层（Phase C）**
- 新增 `templates/analyze-framework.md`：5 维度分析清单（构建依赖/注解/XML/代码/配置）
- 新增 `schemas/profile.schema.yaml`：框架指纹产出格式
- 新增 `scripts/gates/GE2.5-framework-analysis.sh`：三级回退门禁（通过/部分失败/完全失败）
- `build-nodes.sh` 增加 D1 提取计划：按 profile 选择提取器，失败自动回退全量
- pipeline-executor agent 文档更新 D1 职责

**5. E4 产出范围扩展（Phase D）**
- adapter-developer 从「只写提取器」扩展为三类产物：代码层/分析层/知识层
- 新增 `scripts/promote-sdk.sh`：SDK 扩展晋级闸门（staging → scripts/base/）
- 新增 `scripts/gates/GE2.5-framework-analysis.sh`

### 文档对齐

- 新增 `harness-conf/DESIGN-V2.md`：工程设计唯一真源文档
- 更新 7 个文档至 v2 路径与术语：ARCHITECTURE.md / gate-criteria.md / extraction-flow.md / roles.md / nightly-mode.md / CLAUDE.md / INDEX.md / self-adaptation.md
- EXTRACTION-WORKFLOW.md 路径全局刷新

### 向后兼容

- 无 profile 场景自动回退全部提取器（= v1 行为，nightly 零退化）
- 所有 v1 提取能力保留（dubbo/sofarpc/grpc/rest/http-client/mq/custom/tags）

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
