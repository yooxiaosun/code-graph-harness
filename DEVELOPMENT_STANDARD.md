# Harness 工程开发规范（v2.2）

## §1 根本原则：md-first 哲学

> Harness 工程的核心资产是 `.md` 模板与 `.yaml/.json` Schema，
> bash 脚本只承担确定性的机械操作。
>
> 定义：我们给出 AI 自由分析的能力，AI 在 md 模板的约束下自主执行；
> 我们只对结果质量进行管理和验收。策略、判断、决策属于 md；机械、确定属于 bash。

### §1.1 判定标准

| 问题 | 答案=bash | 答案=md |
|------|:---------:|:------:|
| 结果唯一确定（输入 X 输出 Y，永远一样） | ✓ |  |
| 不涉及"要不要 / 为什么 / 如何选" | ✓ |  |
| 可以写成纯数据变换（grep/parse/copy） | ✓ |  |
| AI 需要读规则后自主执行 |  | ✓ |
| 涉及策略、判断、决策 |  | ✓ |
| 需要根据上下文调整行为 |  | ✓ |
| 未来可能因经验调整 |  | ✓ |

### §1.2 反模式（违反本规范的设计）

- ❌ 把"加权算法"写在 bash 里（应由 AI 读 md 规则自主加权）
- ❌ 把"收敛判断"写在 bash 里（应由 AI 读约束 md 判断）
- ❌ 把"调度模式探测"写在 bash 里（应由 AI 读调度 md 选模式）
- ❌ 把"合并策略"写在 bash 里（应由 AI 读合并 md 合并）
- ❌ 把"自动探测 / 自动回退"逻辑写在 bash 里（应由 AI 决策后显式传参）

### §1.3 正模式（符合规范的设计）

- ✅ bash 提供 `merge-json.sh`（纯工具），AI 读 `dual-dimension-merge.md` 后决定何时、怎么调
- ✅ bash 提供 `run-ai-analysis.sh <state.yaml>`（只打印字段值），AI 读 `ai-analysis-harness.md` 后判断是否收束
- ✅ bash 提供 `validate-schema.sh`（纯校验工具），AI 读 md 决定校验后的处理

---

## §2 资产分层规范

### §2.1 md 层（AI 工作指令，核心资产）

| 类别 | 位置 | 职责 |
|------|------|------|
| AI 工作模板 | `templates/*.md` | 各场景下 AI 的读取规则 → 自主执行 → 产出 |
| 数据契约 | `schemas/*.yaml / *.json` | AI 产出的格式定义（含验证规则） |
| 流程与角色 | `harness-conf/workflow/*.md` | 阶段/角色/门禁定义 |
| 专题指导 | `harness-conf/guides/*.md` | 自适应手册等 |
| 开发规范 | `DEVELOPMENT_STANDARD.md` | 本文件 |
| Agent 入口 | `HARNESS.md` | 硬约束 + 项目定位 |

### §2.2 bash 层（机械工具）

| 工具 | 职责 | 判定标准 |
|------|------|---------|
| `base/scan-files.sh` | 扫描文件列表 | 机械 find |
| `base/merge-json.sh` | JSON 数组合并 + 去重 | 机械 jq |
| `base/validate-schema.sh` | Schema 校验 + 路径存在 | 机械校验 |
| `base/repo-manager.sh` | git clone/update | 机械 |
| `base/json-writer.sh` | JSON 序列化 | 机械 |
| `base/run-ai-analysis.sh` | 提取 state.yaml 字段 | 机械读 YAML（**不含判断**） |
| `graph/compute-stats.sh` | 算统计数 | 机械算术 |
| `graph/assemble-graph.sh` | JSON 拼装 | 机械合并 |
| `gates/GE*.sh / GP*.sh / G*.sh` | 门禁校验 | 确定性规则 |
| `.harness/extractors/*/extract.sh` | 提取器基线 | 保留作为双轨对比基线 |

### §2.3 禁止区（不该存在的东西）

- ❌ bash 脚本内的"if condition → 选 A 还是 B"（调度决策）
- ❌ bash 脚本内的"读 profile.yaml 然后决策"（策略判断）
- ❌ bash 脚本内的"判断是否收束 / 是否 bail-out"（收敛判断）
- ❌ bash 脚本承担本应 AI 做的策略工作

---

## §3 开发工作流

1. 新增 AI 能力时，先问：**这能写成 md 模板让 AI 自己执行吗？**
2. 如果能，写 md；bash 只提供纯工具支撑
3. 只有当需求满足 §1.1 判定表全部 bash 列时，才允许新建 bash
4. 每次提交前对照本规范自检：新增的 bash 是否含任何"判定/选择"逻辑？
5. 若未来经验表明某条策略该调整，**直接改 md**，不动 bash

---

## §4 评审 checklist（每次提交前核对）

- [ ] 新增的 bash 内无 `if/when` 之外的策略判断（门禁脚本的阈值判定除外，属确定性规则）
- [ ] 新增的 md 模板已明确：输入、输出、规则、边界
- [ ] 新增的 Schema 字段有 description 和 validation
- [ ] 不违反 `HARNESS.md`（硬约束）中的任何条目
- [ ] bash 工具的输入/输出与调用方（AI/md 规则）明确一致

---

## §5 术语一致性

- 项目 Agent 入口文件统一称为 **`HARNESS.md`**（vendor-neutral，内网不使用 claude 命名）
- AI 产出物落在 `.harness/` 与 `output/`；框架资产落在 `scripts/` `templates/` `schemas/` `harness-conf/`
- 涉及"决策/策略/判断"的文档一律使用 `.md`；涉及"机械执行"的一律使用 `.sh`

---

## §6 变更记录

| 版本 | 日期 | 变更 |
|:---:|:---:|------|
| v2.2.0 | 2026-08-12 | 首次发布。确立 md-first 哲学，bash 只留机械工具；CLAUDE.md 更名 HARNESS.md |
