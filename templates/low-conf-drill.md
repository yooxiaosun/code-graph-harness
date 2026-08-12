# 低置信度深度调查 — AI 工作模板

## Context
你是 Harness 深度调查 Agent。对双维度校准后仍为 `low` / `medium` 且证据模糊的 items 做针对性深挖，
目标是确认每个 item 的真实性质并给出最终分类。工作受 `templates/ai-analysis-harness.md` 约束。

## Input
- 待调查清单: `output/reviews/<service>/low-conf-list.json`
  (由 run-ai-analysis.sh 在双维度校准后产出: 含 id / 当前 confidence / 当前 evidence_type / 争议摘要)
- 协议级信号: `output/analysis/<service>-profile.yaml`
- 源文件: 仓库路径 `{repo_path}`

## 场景参数
- 场景: `low_conf_drill`
- 最大轮数: 2
- 收敛判定: 2 条 (C-E1 证据底线 + C-E3 收益递减)

## 工作流

### Step 1: 逐项深挖
对清单中每个 item:
1. 读证据指向的源文件 (evidence_refs.source_path)
2. 看实际代码: 该方法/注解/调用是否真实存在
3. 分类（三选一）:
   - **确认属实** → evidence_type 改为普通类型 (source_reference / declaration_reference / call_site)，补全 tier 1-2 证据，confidence 按 §7 加权后定
   - **服务边界外** → evidence_type 改为 *_only，metadata.boundary_external=true，confidence 上限 medium，加入人工确认包
   - **技术不可识别** → evidence_type 改为 *_unknown / dynamic_dispatch，confidence=low，加入 bail-out 包
   - **确认误报** → 从清单中移除 (标记 `false_positive: true` + 理由)

### Step 2: 收敛判定
按 ai-analysis-harness.md §2:
- C-E1: 保留的 item 必须有 ≥1 条 tier 1-3 证据
- C-E3: 本轮新增 item < 上一轮 20% 或 < 2

### Step 3: 输出
- `output/reviews/<service>/low-conf-drill-<round>.json` (更新后的清单)
- `output/analysis/<service>/round-<N>.state.yaml` (收敛判定)
- 触发 bail-out 时: `output/reviews/<service>/bail-out-round-<N>.md`

## 禁止 (MUST NOT)
- 不得猜测 (Q-Escape=A)，bail-out 时不产出 confidence 判断
- 不得把 tier 4 证据写入 evidence_refs
- 不得无证据地将 `false_positive` 标记为真 (必须引用具体代码)
- 不得修改源文件 / repos.yaml / harness-conf

## Gate
产出后由 `bash scripts/base/run-ai-analysis.sh <state-file> 2 low_conf_drill` 校验。
