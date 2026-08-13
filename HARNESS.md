# Code Graph · 知识抽取 Harness

## 项目定位

本工程是一个**代码知识图谱提取 Harness**，作为 Code Graph 平台的知识抽取模块：AI Agent 在此工程下自动化克隆 Java 微服务仓库、提取 RPC 接口与调用关系、校准质量并组装知识图谱（`output/knowledge-graph/latest.json`）。当遇到无法识别的通信模式时，Agent 具备自适应能力——自行分析模式、编写新的提取器脚本并持久化到工程中。

## 极简使用法（30 秒）

1. 接到新任务 / 跨阶段 / 上下文远去时 → 先读 `harness-conf/INDEX.md`（快速召回入口）
2. 按阶段确认当前定位 → `harness-conf/workflow/extraction-flow.md`（E1-E5 单一真源）
3. 按角色确认执行边界 → `harness-conf/workflow/roles.md`（RACI + MUST/MUST NOT）
4. 门禁标准 → `harness-conf/workflow/gate-criteria.md`（每项含可执行验证命令）
5. 提取器实现细节 → `EXTRACTION-WORKFLOW.md`（三层提取架构单一真源）

## Slash 命令

| 命令 | 用途 |
|------|------|
| `/extract` | 启动 E1-E5 完整提取流程 |
| `/adapt` | 手动触发自适应编码（E4） |
| `/update` | 增量更新（仅变更仓库重提取） |
| `/status` | 长会话状态召回 |

## 硬约束（不可违反）

### Anti-Hallucination
- 没有读取文件、运行命令或获得输出时，不得声称事实成立
- 未运行的命令不得描述为通过；dry-run 只能证明可调度，不代表门禁通过
- 不确定事实必须标注 `[UNCERTAIN]` 并说明缺失证据

### 验证即证据
- 所有门禁结论必须附可执行的验证命令及其实际输出
- `output/calibration/calibration-report.json` 是 E3 判定的唯一数据源，禁止凭印象评级

### 自适应编码纪律（E4）
- AI 自行编写的提取器脚本**必须先过 GP1-GP5 fixture 验证门禁**，才能持久化与集成
- 新脚本必须遵守 `templates/generate-script.md` 的规范（参数、base 工具、输出格式）
- 持久化后必须同步更新 `EXTRACTION-WORKFLOW.md` 对应章节与 `docs/specs/extraction-scope.md`
- 自适应迭代上限 3 次，超限必须升级 User 决策，禁止无限重试

### 流程纪律
- orchestrator 不得代替 subagent 执行 E2/E3/E4/E5 一线任务（强制 spawn 规则见 `harness-conf/ARCHITECTURE.md`）
- 任何回退必须重新执行对应门禁，禁止跳门禁推进
- 发布确认是硬停闸，必须 User 确认后才能归档

### AI 迭代分析纪律（v2.1 新增，对应 `templates/ai-analysis-harness.md`）
- 任何涉及多轮 AI 分析的场景（D1 框架分析 / 双维度二轮校准 / 低置信度调查 / E4 自适应），必须遵循 `templates/ai-analysis-harness.md` 中的约束
- 任何模板定义的 Hard Cap 不得放宽：最大轮数、单任务耗时、flip-flop 次数、C-E1 证据底线
- Bail-out 时严格不给出 confidence 判断，留给人工确认
- Profile 是协议级印证信号，不是节点级独立印证源（Q-Final=A，详见 ai-analysis-harness.md §7）

### 开发方法论纪律（v2.2 新增，md-first 哲学）
- Harness 工程的核心资产是 md 模板与 Schema，bash 只承担确定性的机械操作
- 详见 `DEVELOPMENT_STANDARD.md`（开发规范唯一真源）
- 任何 bash 脚本不得承担策略判断（要不要 / 为什么 / 如何选）
- AI 能力新增时优先写成 md 模板；只有"输入 X 输出 Y 永远一样"的操作才用 bash
- 未来策略调整只改 md，不动 bash

## 关键路径速查

| 资源 | 路径 |
|------|------|
| 工程设计 v2 | `harness-conf/DESIGN-V2.md` |
| 开发规范 | `DEVELOPMENT_STANDARD.md` |
| 环境准备 | `docs/SETUP.md` |
| 内网 jq | `project/tools/jq`（静态二进制，见 SETUP.md §2.6） |
| 主编排脚本 | `scripts/pipeline.sh` |
| 仓库与协议配置 | `repos.yaml` |
| 全局状态机 | `docs/status/state.yaml` |
| 全局审计日志 | `docs/status/progress.md` |
| 图谱产物 | `output/knowledge-graph/latest.json` |
| 统计报告 | `output/calibration/calibration-report.json` |
| 图谱 Schema | `schemas/knowledge-graph.schema.json` |
| 框架分析格式 | `schemas/profile.schema.yaml` |
| AI 介入模板 | `templates/{analyze-framework,analyze-pattern,generate-script,persist-rule}.md` |
| AI 迭代约束 | `templates/ai-analysis-harness.md` |
| 双维度模板 | `templates/{dual-pass-review,dual-dimension-merge,build-nodes-scheduling,calibration-summary,low-conf-drill,generate-human-review}.md` |
