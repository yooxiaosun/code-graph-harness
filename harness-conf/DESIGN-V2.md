---
title: Code Graph · 知识抽取 Harness — 工程设计 v2
purpose: Harness 工程设计的唯一真源文档，定义分层架构、原子能力、AI 决策点、AI 产出范围、目录结构、门禁体系
version: v2.0.0
author: harness
status: Active — Phase A-D 实施完成，Phase E 文档对齐完成
---

# Code Graph · 知识抽取 Harness — 工程设计 v2

> **定位**：本文件是 Harness 工程设计的唯一真源文档。
>
> **历史**：v1 设计分散在 `ARCHITECTURE.md`、`EXTRACTION-WORKFLOW.md`、`gate-criteria.md`、`roles.md` 中，本文件整合并替换这些文档中的过时部分。
>
> **实施**：§9 定义了 5 个实施阶段（Phase A-E）。

---

## §1 Harness 工程哲学

### 1.1 什么是 Harness

Harness 不是一个提取工具，而是一个 **AI 自主执行的治理框架**。

```
传统提取工具:    人写规则 → 工具执行 → 产出结果
Harness:         人定框架 → AI 自主执行 → 门禁验收
```

- 我们定义：「你应该从这些维度思考」、「你不能越过这些边界」、「你的产出必须满足这些标准」
- AI 负责：「怎么做」——分析什么、用什么策略、产出什么代码、记录什么结论
- 门禁负责：「验收」——代码语法对不对、格式合不合法、回归过没过

### 1.2 三根支柱

| 支柱 | 载体 | 职责 |
|------|------|------|
| **① 提示引导** | `templates/*.md` | 告诉 AI 分析什么、从哪些维度思考、产出的格式要求 |
| **② 边界约束** | `HARNESS.md` 硬约束 + 模板内禁止项 + 资源上限 | 告诉 AI 不应做什么、不能越过什么、超时/超量怎么办 |
| **③ 产出标准** | `schemas/*`（格式定义）+ `harness-conf/workflow/gate-criteria.md`（门禁） | 定义可验证的质量标准，作为不可绕过的验收关卡 |

AI 在①②的框架内自主执行，③作为不可绕过的验收关卡。

### 1.3 两层分离架构

| | Harness 框架 | Harness 产出物 |
|------|:---:|:---:|
| **性质** | 不变层 | 可变层 |
| **谁生成** | 我们（人） | AI（在框架引导下自主生成） |
| **职责** | 定义规则、提供工具、验收质量 | 生产代码、产出分析、沉淀知识 |
| **验证方式** | 工程门禁（bash -n / test） | GP1-GP5 fixture 门禁 + G-E 流程门禁 |
| **变更频率** | 低（架构稳定） | 高（新仓库 → 新框架 → 新提取器） |

---

## §2 Bash 原子能力层

### 2.1 定位

Bash 层只做「确定性机械操作」。判断标准：

| 问题 | bash | AI |
|------|:---:|:---:|
| 结果是否唯一确定？ | ✓ | |
| 输入相同输出必然相同？ | ✓ | |
| 可以写成纯数据变换（grep → parse → write）？ | ✓ | |
| 不涉及「要不要 / 好不好 / 为什么」判断？ | ✓ | |
| 需要根据上下文制定策略？ | | ✓ |
| 需要解释原因？ | | ✓ |
| 需要评估质量、决定下一步？ | | ✓ |

### 2.2 能力清单（18 个）

#### 扫描与解析

| # | 能力 | 输入 | 输出 |
|---|------|------|------|
| C1 | `scan_files <dir> <ext>` | 目录路径 + 扩展名 | 文件路径列表 |
| C2 | `extract_methods <file>` | .java 文件 | public 方法签名列表 |
| C3 | `extract_class_name <file>` | .java 文件 | 包名.类名 |
| C4 | `found_in_file <file> <pattern>` | 文件 + 正则模式 | true / false |
| C5 | `extract_annotations <file> <annotation>` | 文件 + 注解名 | 注解出现的行号列表 |

#### 提取器（每协议一个）

| # | 能力 | 输入 | 输出 |
|---|------|------|------|
| C6 | `extract-dubbo <repo> <out>` | 仓库根 + 输出目录 | dubbo-provider.json + dubbo-consumer.json |
| C7 | `extract-sofarpc <repo> <out>` | 同上 | sofarpc-provider.json + sofarpc-consumer.json |
| C8 | `extract-grpc <repo> <out>` | 同上 | grpc-provider.json + grpc-consumer.json |
| C9 | `extract-rest <repo> <out>` | 同上 | rest-provider.json + rest-consumer.json |
| C10 | `extract-http-client <repo> <out>` | 同上 | nonstandard-http.json |
| C11 | `extract-mq <repo> <out>` | 同上 | nonstandard-mq.json |
| C12 | `extract-custom <repo> <out>` | 同上 | nonstandard-custom.json + unknown 标记 |

#### 图谱计算

| # | 能力 | 输入 | 输出 |
|---|------|------|------|
| C13 | `match-providers <nodes> <consumers>` | 提供者池 + 消费节点列表 | matched edges + unresolved 列表 |
| C14 | `compute-stats <nodes> <edges>` | 所有 nodes + edges 数据 | `{"total_providers":N,"total_consumers":M,"matched":K,"unresolved":L}` |
| C15 | `assemble-graph <nodes> <edges> <out>` | 分层数据 | latest.json（最终图谱） |

#### 序列化

| # | 能力 | 输入 | 输出 |
|---|------|------|------|
| C16 | `node_json <fields>` | 结构化字段 | 单行 JSON 节点 |
| C17 | `edge_json <from> <to> <proto>` | 两节点 ID + 协议 | 单行 JSON 边 |
| C18 | `write_json_array <items> <file>` | JSON 对象列表 + 文件路径 | 合法 JSON 数组文件 |

### 2.3 原子能力本身也是 AI 可扩展的

提取器（C6-C12）是 AI 在 E4 中产出的核心产物。SDK 函数（C1-C5、C16-C18）如果当前不满足需求——例如需要扫描 Go 文件、解析 YAML 配置、处理 proto 以外的 IDL 格式——AI 也可以在 E4 中开发并添加到原子能力池。

流程同提取器：

```
模板 templates/generate-script.md 引导
    → AI 编写新能力函数
    → GP1-GP5 fixture 验证
    → 通过 → 持久化到 scripts/base/ 或 .harness/extractors/
```

---

## §3 AI 决策层

### 3.1 三个决策点

| 决策点 | 触发阶段 | AI 输入 | 决策内容 | AI 输出 |
|------|:---:|------|---------|------|
| **D1 · 提取计划** | E2 启动 | profile.yaml + repos.yaml | 这个服务用哪些提取器？哪些协议明确不存在可以跳过？ | `extraction_plan` 提取器列表 |
| **D2 · 质量判定** | E3 校准 | stats 数字 + unresolved 列表 + profile.yaml | 匹配率意味着什么？下一步做什么？ | 归因分析 + 分流判定（E5 / E4 / 升级 User） |
| **D3 · 自适应编码** | E4 | unknown 清单 + profile 完整上下文 + 模板 | 未知模式是什么通信框架？需要什么检测特征？ | 新 extract-*.sh + pattern.md + fixtures |

### 3.2 执行流程

```
E1: graph-orchestrator 主执行
    解析 repos.yaml → 创建任务 → User 确认计划

E2: pipeline-executor spawn
    ├── D1 · AI 决策: 读 profile → 选择提取器
    ├── Bash 执行: 对 extraction_plan 中的每个提取器调用原子能力
    ├── Bash 执行: match-providers → compute-stats
    └── Bash 执行: assemble-graph → latest.json
    ▶ G-E2 门禁

E3: calibration-analyzer spawn
    ├── D2 · AI 决策: 读 stats + unresolved + profile → 归因 + 分流
    ├── GOOD / FAIR 且无 blocker ──→ E5
    ├── POOR / unknown pattern ──→ E4
    └── blocker / 数据损坏 ──→ 升级 User
    ▶ G-E3 门禁

E4: adapter-developer spawn（仅 E3 判定触发）
    ├── D3 · AI 决策: 分析未知模式 → 生成代码/分析/知识
    ├── Bash 验证: GP1-GP5
    └── 通过 → persist → 回 E2 重跑（迭代上限 3 次）
    ▶ G-E4 门禁

E5: gate-reviewer spawn
    ▶ G-E5 门禁 → User 发布确认（硬停闸） → 归档
```

---

## §4 AI 产出全景

AI 不只能写提取器。AI 可以产出架构中所有可变层的东西——代码产物、分析产物、知识产物三个层级，共 14 种产出类型。

### 4.1 代码层

| 产物 | 存放位置 | 触发时机 | 验收门禁 |
|------|---------|---------|:---:|
| 提取器脚本 `extract-*.sh` | `.harness/extractors/{proto}/` | E3 发现覆盖缺口 | GP1-GP5 |
| SDK 扩展 `scan_*.sh / parse_*.sh` | `scripts/base/` | 当前 SDK 不支持的语言/格式 | GP1-GP5 |
| 验证脚本新门禁 | `scripts/gates/GP-*.sh` | 新协议需要新的验证标准 | GP1-GP5 |
| 测试样本 `fixtures/*.java` | `.harness/fixtures/` | 新提取器需要测试数据 | GP4-GP5 |

### 4.2 分析层

| 产物 | 存放位置 | 触发时机 | 验收标准 |
|------|---------|---------|:---:|
| 框架指纹 `{service}-profile.yaml` | `output/analysis/` | 每次克隆新仓库后 | G-E2.5 |
| 分析自审 `{service}-profile-review.md` | `output/analysis/` | 同上 | G-E2.5 |
| 质量归因 `E3-calibration-analysis.md` | `docs/changes/<任务>/artifacts/` | E3 校准阶段 | G-E3 |
| 自适应报告 `E4-adapt-report.md` | `docs/changes/<任务>/artifacts/` | E4 编码完成 | G-E4 |
| 门禁报告 `E5-gate-report.md` | `docs/changes/<任务>/artifacts/` | E5 发布审核 | G-E5 |

### 4.3 知识层

| 产物 | 存放位置 | 触发时机 | 验收标准 |
|------|---------|---------|:---:|
| 规则文档 `{proto}-detector.md` | `.harness/rules/` | E4 持久化新协议 | content review |
| 发现模式 `{pattern}.md` | `.harness/patterns/` | 发现值得复用的策略 | content review |
| 提取范围更新 | `docs/specs/extraction-scope.md` | E4 持久化后 | E4 流程约束 |
| 配置演进 | `repos.yaml` 协议段 | 新框架的特征注册 | YAML 合法性 |
| 变更日志追加 | `harness-conf/CHANGELOG.md` | 自适应完成后 | E4 流程约束 |

### 4.4 模板驱动的闭环

```
templates/analyze-framework.md   → AI 分析   → profile.yaml
templates/analyze-pattern.md     → AI 分析   → rules / patterns
templates/generate-script.md     → AI 编码   → extractor.sh
templates/persist-rule.md        → AI 归档   → rules + CHANGELOG
```

---

## §5 Harness 不可变核心

不论怎么演进，以下 6 项为人类维护、永远不变的框架资产：

| # | 资产 | 为什么不变 |
|---|------|-----------|
| 1 | `templates/*.md` 提示模板 | AI 的分析框架——模板定义了 AI 从哪些维度思考、产出什么格式 |
| 2 | `schemas/*.yaml` 格式定义 | 产出的契约——AI 的任何产出都必须符合对应 Schema |
| 3 | `scripts/` 中图谱内核脚本 | `match-providers` / `compute-stats` / `assemble-graph`——纯机械变换，定义了什么合成什么 |
| 4 | `scripts/gates/` 门禁框架 | 验收标准——门禁体系的结构和验证逻辑是人维护的不变框架；具体的门禁脚本（G0/G4/G5/GE2.5/GE3/GP1-5）作为框架实例存在，AI 不可修改 |
| 5 | `harness-conf/` 运营治理 | 流程 / 角色 / 阶段 / 门禁定义——AI 的工作流 |
| 6 | `HARNESS.md` + `SCALE-PROMPT.md` | Agent 行为纪律 + 硬约束 |

---

## §6 目录结构（v2.2 刷新）

```
harness/
│
├── HARNESS.md                       # Agent 入口 + 硬约束
├── DEVELOPMENT_STANDARD.md          # 开发规范（md-first 唯一真源）
├── SCALE-PROMPT.md                  # Agent 行为纪律
├── repos.yaml                       # 仓库 + 协议配置
├── tools/                           # 工程自带工具（内网无外网环境）
│   └── jq                           # Linux x86-64 静态二进制（jq-bootstrap.sh 自动发现）
│
├── templates/                       # ① 提示引导 + 策略层（人维护 md，AI 读后自主执行）
│   ├── analyze-framework.md         # D1 框架分析
│   ├── build-nodes-scheduling.md    # Layer 1 调度决策（v2.2）
│   ├── dual-dimension-merge.md      # 双维度合并规则（v2.2）
│   ├── calibration-summary.md       # 校准汇总（v2.2）
│   ├── ai-analysis-harness.md       # AI 迭代约束（收敛/Hard Cap/Bail-out）
│   ├── dual-pass-review.md          # 双维度二轮校准
│   ├── low-conf-drill.md            # 低置信度深挖
│   ├── generate-human-review.md     # 人工确认包
│   ├── analyze-pattern.md           # 模式分析（E4）
│   ├── generate-script.md           # 代码生成（E4）
│   └── persist-rule.md              # 规则持久化（E4）
│
├── schemas/                         # ③ 产出格式标准（人维护）
│   ├── knowledge-graph.schema.json  # 图谱 Schema
│   ├── profile.schema.yaml          # 框架分析格式（D1）
│   ├── node.schema.json             # 节点契约（v2.1）
│   └── edge.schema.json             # 边契约（v2.1）
│
├── scripts/                         # bash 机械工具层（人维护）
│   ├── pipeline.sh                  # 主编排（8 阶段骨架，无策略）
│   ├── nightly.sh                   # 夜间无人值守入口
│   ├── e4-verify-bundle.sh          # E4 交付包验证
│   ├── promote-extractor.sh         # 提取器晋级闸门
│   ├── promote-sdk.sh               # SDK 扩展晋级闸门
│   ├── graph/
│   │   ├── build-nodes.sh           # Layer 1 执行（--plan 参数化，无判断）
│   │   ├── build-edges.sh           # Layer 2 提供者池匹配 + 边产出
│   │   ├── compute-stats.sh         # Layer 3 算统计数（无 rating）
│   │   ├── assemble-graph.sh        # 图谱拼装
│   │   └── merge-graphs.sh          # 增量合并
│   ├── gates/
│   │   ├── G0-verify.sh             # 构建/依赖
│   │   ├── G4-verify.sh             # Lint
│   │   ├── G5-verify.sh             # Test
│   │   ├── GE2.5-framework-analysis.sh # 框架分析门禁（三级回退）
│   │   ├── GE3-extraction-quality.sh   # 提取质量门禁（双维度）
│   │   ├── GP1-GP5-verify.sh        # 提取脚本 fixture 验证
│   │   ├── all.sh                   # 门禁调度器
│   │   └── status.sh                # 门禁目录
│   ├── base/                        # 原子能力工具（可被 AI 扩展）
│   │   ├── jq-bootstrap.sh          # jq PATH 引导（系统无 jq 时启用 tools/jq）
│   │   ├── scan-files.sh            # 文件扫描
│   │   ├── merge-json.sh            # JSON 数组合并 + 去重
│   │   ├── validate-schema.sh       # Schema 校验 + C-E1 证据链
│   │   ├── run-ai-analysis.sh       # state.yaml 字段提取（无判断）
│   │   ├── java-parser.sh           # Java 文件扫描/解析
│   │   ├── json-writer.sh           # JSON 序列化（含 edge v2.1 字段）
│   │   └── repo-manager.sh          # git clone/update
│   └── tests/
│       └── run.sh                   # 测试套件（GP1-5 + graph smoke）
│
├── .harness/                        # AI 产出物
│   ├── extractors/                  # 提取器基线（每协议一个目录）
│   │   ├── dubbo/  sofarpc/  grpc/  rest/
│   │   ├── http-client/  mq/  custom/  tags/
│   │   └── each: extract.sh + pattern.md
│   ├── fixtures/                    # 测试样本
│   │   ├── sample-http-client/  sample-mq/  sample-socket/
│   │   └── expected/
│   ├── rules/                       # 检测规则知识库
│   ├── patterns/                    # 发现的模式
│   └── staging/                     # E4 开发暂存 → 验收后迁移
│
├── harness-conf/                    # 运营治理（人维护）
│   ├── DESIGN-V2.md                 # ← 本文件
│   ├── ARCHITECTURE.md              # Agent 协作约束
│   ├── CHANGELOG.md                 # 版本演进
│   ├── INDEX.md                     # 快速召回入口
│   ├── workflow/
│   │   ├── extraction-flow.md       # E1-E5 流程
│   │   ├── gate-criteria.md         # 门禁标准
│   │   ├── roles.md                 # 角色职责
│   │   ├── state-maintenance.md     # 状态维护
│   │   └── nightly-mode.md          # 夜间模式
│   └── guides/
│       └── self-adaptation.md       # 自适应手册
│
├── docs/                            # 项目文档
│   ├── status/                      # state.yaml + progress.md
│   ├── changes/                     # 任务流水
│   ├── specs/                       # 提取范围
│   ├── workflow/                    # QUALITY_CONTRACT 等
│   └── archive/                     # 归档
│
├── output/                          # 运行时产物
│   ├── analysis/                    # 框架分析 + round-*.state.yaml
│   ├── nodes/                       # 最终节点（合并后）
│   ├── nodes-script/                # 脚本维度中间产物（双轨时）
│   ├── nodes-ai/                    # AI 维度中间产物（双轨时）
│   ├── edges/                       # 边
│   ├── calibration/                 # 校准 + dual-summary.json
│   ├── reviews/                     # 矛盾清单 + 人工确认包
│   └── knowledge-graph/             # 最终图谱
│
└── EXTRACTION-WORKFLOW.md           # 提取器技术真相源
```

---

## §7 架构分析层

### 7.1 定位

在仓库克隆和提取器执行之间插入一个 AI 分析阶段。AI 按 `templates/analyze-framework.md` 模板自主分析每个仓库的框架指纹，产出 `{service}-profile.yaml` 和自审报告 `{service}-profile-review.md`。

### 7.2 流程

```
E2 执行:
  克隆仓库完成
      │
      ▼
  AI 框架分析（按 analyze-framework.md 模板，自主决定分析策略）
      │
      ├── 产出: output/analysis/{service}-profile.yaml
      │          framework_signals: [{protocol, confidence, declaration_style, review_basis}, ...]
      │          extraction_plan: {extractors: [...], skip_reason: "..."}
      │          unknowns: [{signal, files, risk}, ...]
      │
      ├── 产出: output/analysis/{service}-profile-review.md
      │          分析范围 / 决策记录 / 覆盖完整度自评
      │
      └── G-E2.5 门禁验证
              │
    ┌─────────┼─────────┐
    ▼         ▼         ▼
   通过      部分失败    完全失败
   按 plan   警告      回退到
   精准提取   + 回退    全部提取器
            全部提取   (= 当前行为)
```

### 7.3 三根支柱在分析层的体现

| 支柱 | 载体 | 内容 |
|------|------|------|
| ① 提示引导 | `templates/analyze-framework.md` | 5 维度分析清单（构建依赖 / 声明注解 / XML 配置 / 代码模式 / 配置文件）、置信度评级规则（high/medium/low/none）、声明风格分类（annotation/xml/code/config） |
| ② 边界约束 | 模板内禁止项 + 资源限制 | 不得修改文件、不得解析业务逻辑、不得猜测（must have evidence）、单仓库 ≤500 文件 ≤30 秒、无信号标记 UNKNOWN-STACK |
| ③ 产出标准 | `schemas/profile.schema.yaml` + G-E2.5 门禁 | 必填字段：service / framework_signals[*].confidence / extraction_plan / unknowns[*].risk；每个 medium+ 信号 ≥1 条 review_basis |

### 7.4 价值

| 受益方 | 价值 |
|--------|------|
| E2 提取 | 只跑匹配的提取器，不浪费算力 |
| E3 校准 | 拿到完整框架上下文，归因更准确 |
| E4 自适应 | 不再只拿到零散 unknown import，而是完整的框架指纹 + 依赖树 + peer protocols |
| 可观测性 | `/status` 一眼看清每个仓库的技术栈 |

---

## §8 E1-E5 流程演进

| 阶段 | v1.x | v2 |
|:---:|------|------|
| **E1** | 解析 repos.yaml → User 确认 | 不变 |
| **E2** | 克隆 → 7 提取器全跑 | 克隆 → **D1: AI 框架分析** → 按 plan 选提取器 → bash 执行原子能力 |
| **E3** | bash calibrate.sh 算分 + 硬编码 POOR/FAIR/GOOD | bash compute-stats **只算数** → **D2: AI 归因 + 分流判定** |
| **E4** | AI 只写提取器 | **D3: AI 产出代码/分析/知识三类产物**（不再限制于提取器） |
| **E5** | 门禁评审 → User 确认 | 不变 |

---

## §9 实施阶段

| 阶段 | 内容 | 核心变更 | 预计变更文件数 |
|:---:|------|---------|:---:|
| **Phase A** | 目录重组 + 精简 | 提取器 `scripts/extractors/` → `.harness/extractors/`；剥离死脚本（22 个 gate 脚本 + `build-graph.sh` + 废弃工具） | ~10 |
| **Phase B** | 拆出 compute-stats | `calibrate.sh` 拆为 `compute-stats.sh`（bash 纯统计）+ AI 决策 D2（质量判定归因） | 2 |
| **Phase C** | 框架分析层 | 新增 `analyze-framework.md` + `profile.schema.yaml` + `GE2.5-verify.sh` + AI 决策 D1（提取计划）+ pipeline 集成 | 4 |
| **Phase D** | E4 范围扩展 | adapter-developer 从「只写提取器」升级为「可产出代码/分析/知识三类产物」 | 2 |
| **Phase E** | 存量文档刷新 | ARCHITECTURE.md / EXTRACTION-WORKFLOW.md / gate-criteria.md / CHANGELOG 全局对齐 v2 | ~5 |

---

## §10 门禁体系

### 10.1 门禁全景

| 层级 | 门禁 | 验证内容 | 验证方式 |
|------|------|---------|---------|
| 工程 | G0 | 构建/语法 | `bash -n scripts/**/*.sh` |
| 工程 | G4 | Lint | 同上 |
| 工程 | G5 | 测试 | `bash scripts/tests/run.sh` |
| 流程 | G-E1 | 构建通过 | repos.yaml 可解析 + 依赖工具齐全 |
| 流程 | G-E2 | 流水线完整性 | pipeline exit 0 + 产物存在 |
| 流程 | **G-E2.5** | **框架分析质量（新）** | profile.yaml 格式 + evidence 完整性 + unknown 标记 |
| 流程 | G-E3 | 提取质量 | match_rate + blockers + unknown 处置 |
| 流程 | G-E4 | 自适应代码质量 | GP1-GP5 + 全量回归 |
| 流程 | G-E5 | 发布门禁 | 报告存在 + User 确认 |
| 自适应 | GP1 | 语法正确 | `bash -n` |
| 自适应 | GP2 | 可执行性 | 实际运行不崩溃 |
| 自适应 | GP3 | 产出格式 | JSON Schema 验证 |
| 自适应 | GP4 | 数据合理性 | 字段非空 + 结构完整 |
| 自适应 | GP5 | 回归 | 既有 fixtures 不退化 |

### 10.2 门禁决策矩阵

| 场景 | 门禁失败 | 行为 |
|------|---------|------|
| G-E2.5 通过 | — | 按 extraction_plan 精准提取 |
| G-E2.5 部分失败 | evidence 缺失 / review 未产出 | 警告 + 回退到全部提取器 |
| G-E2.5 完全失败 | profile 不存在 / YAML 无法解析 | 静默回退到全部提取器（= 当前行为） |
| G-E3 POOR | match_rate < 0.70 | 进入 E4，不可豁免 |
| G-E3 blocker | 数据损坏 / 提供者冲突 | 升级 User |
| G-E4 失败 | GP 任一未通过 | 迭代（上限 3 次），超限升级 User |
| G-E5 失败 | 报告缺失 | 回退 E5 重新评审 |

---

## §11 术语对照

| 术语 | 定义 | 首次出现 |
|------|------|:---:|
| Harness 框架 | 人维护的不变层：模板、Schema、图谱内核、门禁、运营文档 | §1.3 |
| Harness 产出物 | AI 生成的可变层：提取器、规则、模式、分析、知识 | §1.3 |
| 原子能力 | Bash 脚本定义的最小可组合能力单元，确定性、无判断逻辑 | §2.1 |
| AI 决策层 | 三个 AI 自主判断的决策点：D1 提取计划 / D2 质量判定 / D3 自适应编码 | §3 |
| 框架分析 | 仓库克隆后、提取前的 AI 分析阶段，产出 profile + review | §7 |
| 双维度提取 | 脚本维度(bash) ∩ AI 维度 并行提取，交叉印证定置信度 | §12 |
| 协议级印证信号 | profile 的角色：非独立印证源，仅做协议级置信度加权 | §12 |
| AI 分析 Harness | AI 迭代分析的收敛判定/Hard Cap/Bail-out 约束 | §12 |

---

## §12 v2.1 双维度架构（Q1-Q5 决策落地）

### 12.1 核心哲学

> **不信任单一来源，信任交叉验证**。

- 脚本 = 机械可复现的事实基线（可能漏报误报）
- AI = 语义理解（可能幻觉）
- 两者的不一致 = 最有价值的信号源 → 归因 → 双轨升级

### 12.2 置信度模型（Q-Final=A, Q-Evidence-3=A）

```
节点级印证（起点）:
  bash ∩ AI 双方命中 → high
  单方命中           → medium
  双方矛盾           → low

协议级加权（profile 角色）:
  profile.{proto}=high → node +1 档 (上限 high)
  profile.{proto}=low  → node 保持原档
  profile.{proto}=none → node 强制 -1 档 (下限 low)

为什么 profile 不是独立印证源:
  profile / bash extractor / AI 都读同一份仓库 (pom.xml + Java 代码),
  profile 只是二次总结, 不能作为独立信息源。
```

### 12.3 证据底线 C-E1 三级豁免（Q-Conv=C, Q-Evidence-1=C, Q-Evidence-2=C）

| 级别 | evidence_type | 要求 | 处理 |
|------|---------------|------|------|
| 普通节点 | source_reference / declaration_reference / call_site | evidence_refs ≥1, tier 1-3 | 不满足即丢弃 (C-E1 fail) |
| 服务边界外 | *_only (provider/consumer/endpoint) | 本仓库声明方证据 + boundary_external=true | confidence 上限 medium, 进人工确认包 |
| 技术不可识别 | *_unknown / dynamic_dispatch | 允许 0 证据但强制标注 | confidence=low, 进 bail-out 包 |

### 12.4 AI 分析 Harness 约束（收敛判定）

约束文件：`templates/ai-analysis-harness.md`

| 场景 | 最大轮数 | 收敛判定条数 |
|------|:---:|:---:|
| D1 框架分析 | 2 | C-E1/C-E2/C-E4 (去 C-E3) |
| 双维度二轮校准 | 3 | C-E1/C-E2/C-E3/C-E4 (全部) |
| 低置信度调查 | 2 | C-E1/C-E3 |
| E4 自适应 | 3 | 沿用既有 |

Bail-out 严格不猜测（Q-Escape=A）：达上限/flip-flop≥2/自报/超时 → 加入人工确认包，不产出 confidence 判断。

### 12.5 双维度流程（v2.2 md-first：策略在 md，bash 只机械）

```
D1 框架分析 (profile.yaml)
    → AI 调度决策 (templates/build-nodes-scheduling.md):
        build-nodes.sh 参数化调用（--plan 由 AI 决策传入）
        单轨 → output/nodes/<svc>/ 直写
        双轨 → 脚本维度落 output/nodes-script/<svc>/
    → AI 双维度合并 (templates/dual-dimension-merge.md):
        合并 nodes-script + nodes-ai → output/nodes/<svc>/   (置信度分级+去重)
        矛盾节点 → output/reviews/<svc>/contradictions.json
    → AI 校准汇总 (templates/calibration-summary.md):
        产出 output/calibration/dual-summary.json
    → GE3 双维度门禁:
        脚本维: match_rate/blockers/schema/C-E1
        AI 维: 双维度一致性可解释 + 实质验收
    → 人工确认包 (output/reviews/human-review-<date>.md)
```

### 12.6 新增资产清单（v2.2 md-first 重构后）

| 资产 | 位置 | 层 |
|------|------|:---:|
| **开发规范（md-first）** | `DEVELOPMENT_STANDARD.md` | 规范 |
| 节点 Schema | `schemas/node.schema.json` | 契约 |
| 边 Schema | `schemas/edge.schema.json` | 契约 |
| AI 分析 Harness 约束 | `templates/ai-analysis-harness.md` | md |
| 双维度二轮校准模板 | `templates/dual-pass-review.md` | md |
| 低置信度调查模板 | `templates/low-conf-drill.md` | md |
| 人工确认包模板 | `templates/generate-human-review.md` | md |
| **双维度合并模板** | `templates/dual-dimension-merge.md` | md |
| **调度决策模板** | `templates/build-nodes-scheduling.md` | md |
| **校准汇总模板** | `templates/calibration-summary.md` | md |
| 文件扫描原子能力 | `scripts/base/scan-files.sh` | bash |
| JSON 合并原子能力 | `scripts/base/merge-json.sh` | bash |
| Schema 校验原子能力 | `scripts/base/validate-schema.sh` | bash |
| state 字段提取工具 | `scripts/base/run-ai-analysis.sh` | bash |

> **v2.2 变更**：原 `scripts/base/merge-dual.sh`（策略硬编码）已删除，合并策略移至
> `templates/dual-dimension-merge.md`（AI 自主执行）；`build-nodes.sh` 改为纯参数化
> 机械工具（调度决策在 `templates/build-nodes-scheduling.md`）；`pipeline.sh` Phase 2.5
> 改为占位（校准汇总由 calibration-analyzer 按 md 后驱）。详见 `DEVELOPMENT_STANDARD.md`。

---

> **状态**：Phase A-D 实施完成，Phase E 文档对齐完成。v2.0.0 激活，v2.1 双维度架构落地，v2.2 md-first 重构完成。
