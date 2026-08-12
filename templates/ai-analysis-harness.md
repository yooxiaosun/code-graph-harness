# AI 分析 Harness 约束（v2.1 核心模板）

## §1 适用范围

本约束适用于 Harness 工程中所有需要 AI **迭代分析**的场景。

| 场景 | 入口模板 | 最大轮数（Q-Round=B） | 收敛判定条数（Q-Conv=C） |
|------|---------|:---:|:---:|
| 框架指纹分析 (D1) | `analyze-framework.md` | 2 | 3 (C-E1/C-E2/C-E4, 去 C-E3) |
| 双维度二轮校准 | `dual-pass-review.md` | 3 | 4 (全部) |
| 低置信度深度调查 | `low-conf-drill.md` | 2 | 2 (C-E1/C-E3) |
| E4 自适应编码 | `analyze-pattern.md` + `generate-script.md` | 3 | 沿用既有规则 |

> 每个 AI 迭代任务的轮数上限、判定条数均由本表**硬约束**定义，模板内不得放宽。

## §2 收敛判定（按场景分级）

### C-E1 证据底线（按场景豁免）

```yaml
C_E1 证据底线（按场景分级）:

  普通节点 (evidence_type 为 source_reference / declaration_reference / call_site):
    required: evidence_refs.length >= 1
    证据 tier: 必须包含 tier 1-3 (tier 4 不允许)
    fail_action: 直接丢弃该节点，不写入 output/nodes/（C_E1 fail）

  服务边界外节点 (evidence_type 为 *_only 三类之一):
    判定前提：Q-Evidence-1 = C (混合模式)
      - AI 在分析阶段先判定"消费/提供方不在仓库范围"
      - E5/review 时人工校对
    required: evidence_refs.length >= 1, 指向本仓库内的声明方
    证据 tier: 允许 tier 1-3
    特殊处理:
      - 节点 confidence 上限 = medium (永不 high)
      - 必须写入 metadata.boundary_external = true
      - 强制进入人工确认包 (daytime review)
    fail_action: 丢弃

  技术不可识别节点 (evidence_type 为 *_unknown 或 dynamic_dispatch):
    判定前提：Q-Evidence-2 = C (按 .harness/rules/ 规则库识别 ESB client)
    required: evidence_refs.length = 0 允许 (但强制标注)
    特殊处理:
      - 节点 confidence 强制 = low
      - 强制进入 bail-out 包
      - 不写入最终图谱, 仅作为 human-review 条目
    fail_action: 进入 bail-out, 不丢弃 (保留给人工)

  代码确实漏检:
    required: evidence_refs.length >= 1
    fail_action: 拒绝写入图谱, C-E1 直接 fail, 计入 round-N.state.yaml 的 evidence_missing 计数
```

### C-E2 分类稳定

```yaml
C_E2 分类稳定:
  定义: 与上一轮对比, 每个 item 的 confidence 分类不变 (无 flip-flop)
  验证方式: bash 校验 diff round_N.json round_N-1.json 在 classification 字段上无变化
  适用场景: 双维度二轮校准 / E4 自适应
  豁免场景: D1 (2 轮过短, 不强加) / 低置信度调查 (轮数太少, 不强加)
```

### C-E3 收益递减

```yaml
C_E3 收益递减:
  定义: 本轮新增 findings < 上一轮的 20% 或绝对数 < 2
  验证方式: bash 计算 count(round_N) - count(round_N-1)
  适用场景: 双维度二轮校准 / 低置信度调查
  豁免场景: D1 (仅 2 轮, 不强加)
```

### C-E4 置信度收敛

```yaml
C_E4 置信度收敛:
  定义: 没有 high↔low 跨档跃迁 (medium→high 或 high→medium 允许)
  验证方式: bash diff 每个 item 的 confidence 跨轮变化 ≤ 1 档
  适用场景: 双维度二轮校准
  豁免场景: D1 / 低置信度调查 / E4
```

## §3 Hard Cap（绝对限制）

| 约束 | 上限 | 违反时动作 |
|------|------|-----------|
| 最大轮数 | 见 §1 场景表 | 强制 bail-out |
| 单任务耗时 | 30 秒 | bail-out 当前任务, 其余继续 |
| C-E1 违反 | 任何普通节点未达证据底线 | 整个任务 bail-out, 进入人工 |
| flip-flop 次数 | 单项 ≤ 1 次 | ≥ 2 次则 bail-out 至人工 |
| evidence_refs tier=4 | 0 条 (不允许) | 发现 1 条即 C-E1 fail |

## §4 Funnel 策略（按轮次收束）

| 轮次 | 范围 | 深度 | 模板差异 |
|:---:|------|------|---------|
| Round 1 | 全量按标准模板 | 浅 (每类型 top-N) | 标准模板 |
| Round 2 | 聚焦 low/medium 项 | 深 (针对性) | Round 1 的 low/medium 子集 |
| Round 3 | 仅残余未收敛 | 极深 | Round 2 残余清单, 必须明确 bail-out 标记 |

> 不是重跑同样提示词，是漏斗式缩小范围。

## §5 Bail-out 处理

触发条件与动作 (Q-Escape=A, 严格不猜测):

| 触发条件 | 动作 |
|---------|------|
| 达到最大轮数 | 输出 `bail-out: max-rounds`, 加入人工确认包 |
| 单项 flip-flop ≥ 2 | 输出 `bail-out: flip-flop`, 加入人工确认包 |
| AI 主动报无法确定 (`confidence: none` 在模板输出) | 输出 `bail-out: self-reported`, 加入人工确认包 |
| 超时 | 输出 `bail-out: timeout`, 加入人工确认包 |

**所有 bail-out 必须包含**:
1. 触发的具体条件 (enum 之一)
2. 已完成轮数 + 状态
3. 建议的人工审查入口 (哪些 item / 哪段代码 / 哪条规则库待补充)
4. **不猜测的最终分类**: 留空或明确标记 `unknown`, 严禁 AI 在 bail-out 状态下产出 confidence 判断

## §6 State 追踪（bash 可验证）

每轮分析必须产出 `output/analysis/<service>/round-<N>.state.yaml`:

```yaml
round: 2
service: order-service
scenario: dual_pass_review        # 场景标识 (对应 §1 表格)
findings_count: 47
delta_from_previous: +3           # 对比上一轮
items_changed_class: 2            # C-E2 用
items_evidence_missing: 0         # C-E1 fail 计数
items_flip_flop: 0                # C-E2 用: flip-flop ≥ 2 的 item 数
evidence_quality_distribution:
  tier_1_strong: 38
  tier_2_medium: 7
  tier_3_weak: 2
  tier_4_none: 0
confidence_distribution:
  high: 35
  medium: 10
  low: 2
bail_outs: []                     # 触发 bail-out 时填此列表
converged:
  C_E1_evidence_floor: true
  C_E2_stability: true
  C_E3_diminishing: false         # 本轮 +3, 超过 20% 阈值
  C_E4_no_jump: true
overall_status: continue          # continue / pass / bail-out
```

## §7 Profile 作为协议级印证信号 (Q-Final=A)

核心原则: **profile 不是节点级独立印证源, 仅作为协议级加权信号**。

```
协议级加权规则 (Q-Evidence-3=A 严格分级):
  profile.{proto}.confidence = high → node.confidence +1 档 (上限 = high)
  profile.{proto}.confidence = low  → node.confidence 保持原档
  profile.{proto}.confidence = none → node.confidence 强制 -1 档 (下限 = low)

节点级印证 (节点 confidence 起点):
  双方 (bash ∩ AI) 命中 → 起点 = high
  单方命中 (bash only 或 AI only) → 起点 = medium
  双方矛盾 (一方有、一方无且证据冲突) → 强制 low
```

**为什么不是独立印证源**:
- profile 从 pom.xml + Java 代码扫描推断
- bash 提取器从 pom.xml + Java 代码 grep 匹配
- AI 也是读同一份仓库文件
- 三者同源, profile 只是二次总结, 不能作为独立信息源

## §8 Gate 集成

- 单轮 state.yaml 由 `scripts/base/run-ai-analysis.sh` (M2) 校验
- 所有判定项的 `converged: true` 必须全部满足才算该轮 "收束"
- `converged: false` 时根据场景表的最大轮数决定是否继续
- 任何 Hard Cap 违反 → 立即 bail-out
