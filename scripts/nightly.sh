#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# Code Graph Harness — Nightly Unattended Extraction
# 夜间无人值守批量提取入口
# 规则见 harness-conf/workflow/nightly-mode.md
# 用法: bash scripts/nightly.sh [--ai] [--e4] [--auto-promote] [--model <provider/model>] [--ollama-url <url>]
#   --ai             E3 用本地 Ollama 做 AI 归因（不可用自动降级纯本地）
#   --e4             在 --ai 基础上执行 E4 自适应编码（staging 收束，默认只标记待晋级）
#   --auto-promote   全绿交付包自动晋级（默认人工晋级）
#   全量执行 pipeline.sh → 门禁 → 晨检队列 → 摘要。
# ─────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR" || exit 1

# 跨平台 sed 原地编辑（内联：GNU -i / BSD -i ''；机械操作, 无策略）
_SED_TYPE=""
sed_i() {
    [ -z "$_SED_TYPE" ] && { sed --version >/dev/null 2>&1 && _SED_TYPE=gnu || _SED_TYPE=bsd; }
    [ "$_SED_TYPE" = "gnu" ] && sed -i "$1" "$2" || sed -i '' "$1" "$2"
}

TODAY=$(date +"%Y-%m-%d")
NOW=$(date +"%Y-%m-%d %H:%M")
LOCK_FILE=".nightly.lock"
REPO_CONFIG="repos.yaml"
# 项目实例位置（staging/提取器在 project；注入）
PROJECT_DIR="${PROJECT_DIR:-/Users/johnsmith/WorkBench/code-graph/project}"
STATE_FILE="docs/status/state.yaml"
QUEUE_FILE="docs/status/nightly-queue.md"
SUMMARY_DIR="output/nightly"
SUMMARY_FILE="$SUMMARY_DIR/summary-$TODAY.md"
PARTIAL_FILE="$SUMMARY_DIR/partial-$TODAY.md"

# AI 驱动参数（--ai/--e4；Ollama 预检见 0.5）
AI_MODE="off"          # off / analysis / e4
AUTO_PROMOTE=0
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-}"
AI_DEGRADED=""
E3_ATTRIB_FILE=""
E4_INPUT_FILE=""

# ─────────────────────────────────────────────────────────────────────
# 0. 前置检查
# ─────────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --ai) AI_MODE="analysis" ;;
        --e4) AI_MODE="e4" ;;
        --auto-promote) AI_MODE="e4"; AUTO_PROMOTE=1 ;;
        --model) OLLAMA_MODEL="$2"; shift ;;
        --ollama-url) OLLAMA_URL="$2"; shift ;;
        --repos|--skip-calibration) echo "[WARN] $1 在 nightly 模式忽略（全量执行）" ;;
        *) echo "Usage: nightly.sh [--ai] [--e4] [--auto-promote] [--model <provider/model>] [--ollama-url <url>]"; exit 2 ;;
    esac
    shift
done

echo "==== Nightly Extraction $(date -u +"%Y-%m-%dT%H:%M:%SZ") ===="

# 0.1 工具依赖
for tool in git bash node python3; do
    if ! command -v "$tool" &>/dev/null; then
        echo "[FATAL] Missing tool: $tool"
        exit 1
    fi
done

# 0.2 repos.yaml 非空（全量模式必须；grep -c 无匹配时输出 0）
REPO_COUNT=$(grep -vE '^\s*#' "$REPO_CONFIG" 2>/dev/null | grep -c 'url:' || true)
if [ "${REPO_COUNT:-0}" -eq 0 ]; then
    echo "[FATAL] repos.yaml 无仓库条目 — 拒绝执行（不得虚构仓库或伪造执行）"
    exit 1
fi

# 0.3 锁文件（防并发；超时 12h 自动失效）
if [ -f "$LOCK_FILE" ]; then
    if stat -c %Y "$LOCK_FILE" >/dev/null 2>&1; then
        LOCK_MTIME=$(stat -c %Y "$LOCK_FILE")
    else
        LOCK_MTIME=$(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0)
    fi
    LOCK_AGE=$(( $(date +%s) - LOCK_MTIME ))
    if [ "${LOCK_AGE:-0}" -lt 43200 ]; then
        echo "[FATAL] 已有进行中任务（$LOCK_FILE 存在 ${LOCK_AGE}s）— 退出"
        exit 1
    fi
    echo "[WARN] 锁文件超时（${LOCK_AGE}s > 12h），接管并继续"
fi
echo "$$" > "$LOCK_FILE"

# 0.4 状态机互斥检查（orchestrator 进行中任务；非 null 即拦截）
if ! grep -q 'current-change: null' "$STATE_FILE" 2>/dev/null; then
    echo "[FATAL] state.yaml 存在进行中任务（current-change 非 null）— 退出"
    rm -f "$LOCK_FILE"
    exit 1
fi

mkdir -p "$SUMMARY_DIR"

# 0.5 AI 后端预检（--ai/--e4 时；任一不可用 → 降级纯本地并记晨检队列）
if [ "$AI_MODE" != "off" ]; then
    echo "── AI 后端预检（${OLLAMA_URL}）──"
    if ! command -v opencode &>/dev/null; then
        echo "  [WARN] opencode CLI 不可用 — 降级纯本地"
        AI_DEGRADED="opencode CLI 不可用"; AI_MODE="off"
    elif ! command -v curl &>/dev/null || ! curl -s --max-time 5 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
        echo "  [WARN] Ollama 不可达（${OLLAMA_URL}）— 降级纯本地"
        AI_DEGRADED="Ollama 不可达"; AI_MODE="off"
    elif [ -z "$OLLAMA_MODEL" ]; then
        echo "  [WARN] OLLAMA_MODEL 未配置（--model 或环境变量）— 降级纯本地"
        AI_DEGRADED="OLLAMA_MODEL 未配置"; AI_MODE="off"
    else
        echo "  [OK] Ollama 在线，模型=${OLLAMA_MODEL}，模式=${AI_MODE}"
    fi
fi

# ─────────────────────────────────────────────────────────────────────
# 1. 初始化状态机（execution-mode: nightly）
# ─────────────────────────────────────────────────────────────────────
sed_i "s/^current-change: .*/current-change: nightly-$TODAY/" "$STATE_FILE"
sed_i "s/^current-phase: .*/current-phase: E2/" "$STATE_FILE"
echo "- [$NOW] [E2] [started] nightly 模式启动（repos=${REPO_COUNT} 个）" >> docs/status/progress.md

# ─────────────────────────────────────────────────────────────────────
# 2. E2 全量流水线执行（pipeline.sh 自带单仓库失败容错）
# ─────────────────────────────────────────────────────────────────────
PIPELINE_EXIT=0
if ! bash "$SCRIPT_DIR/pipeline.sh" > "$SUMMARY_DIR/pipeline-$TODAY.log" 2>&1; then
    PIPELINE_EXIT=1
    echo "[WARN] pipeline.sh 退出码=${PIPELINE_EXIT}（部分仓库可能失败）"
fi

# ─────────────────────────────────────────────────────────────────────
# 3. 门禁（跳过 G-E4 — nightly 不写脚本）
# ─────────────────────────────────────────────────────────────────────
echo "── 门禁执行 ──"
G_RESULT="PASS"
G_NOTES=""

# G-E1: 构建/脚本语法
if bash "$SCRIPT_DIR/gates/G0-verify.sh" > /dev/null 2>&1; then
    echo "  [PASS] G-E1 构建通过"
else
    G_RESULT="FAIL"; G_NOTES="${G_NOTES}G-E1构建失败; "
fi

# G-E2: 流水线完整性（pipeline exit 0 且产物存在）
if [ "$PIPELINE_EXIT" -eq 0 ] && [ -f "output/knowledge-graph/latest.json" ] \
   && [ -f "output/calibration/calibration-report.json" ] \
   && [ -f "output/edges/edge-stats.json" ]; then
    echo "  [PASS] G-E2 流水线完整性"
else
    G_RESULT="FAIL"; G_NOTES="${G_NOTES}G-E2流水线不完整; "
fi

# G-E3: 提取质量（POOR 不豁免，记入晨检队列）
GE3_EXIT=1
bash "$SCRIPT_DIR/gates/GE3-extraction-quality.sh" 2>/dev/null | tail -5
GE3_EXIT=${PIPESTATUS[0]}
if [ "$GE3_EXIT" -eq 0 ]; then
    echo "  [PASS] G-E3 提取质量"
else
    G_RESULT="FAIL"; G_NOTES="${G_NOTES}G-E3提取质量POOR; "
fi

# G-E5: 图谱结构（jq 可解析 + 关键字段）
if python3 -c "import json; d=json.load(open('output/knowledge-graph/latest.json')); exit(0 if all(k in d for k in ('stats','nodes','edges')) else 1)" >/dev/null 2>&1; then
    echo "  [PASS] G-E5 图谱发布结构"
else
    G_RESULT="FAIL"; G_NOTES="${G_NOTES}G-E5图谱结构异常; "
fi

# ─────────────────────────────────────────────────────────────────────
# 3.5 E3 AI 归因（仅 G-E3 POOR 且 AI 模式启用；本地 Ollama 推理）
# ─────────────────────────────────────────────────────────────────────
if [ "$GE3_EXIT" -ne 0 ] && [ "$AI_MODE" != "off" ]; then
    echo "── E3 AI 归因（${OLLAMA_MODEL}）──"
    E3_ATTRIB_FILE="$SUMMARY_DIR/e3-attribution-$TODAY.md"
    E4_INPUT_FILE="$SUMMARY_DIR/e4-input-$TODAY.md"
    rm -f "$E4_INPUT_FILE"
    if opencode run --agent calibration-analyzer --model "$OLLAMA_MODEL" \
        "夜间无人值守 E3 归因（--ai 模式）。读取 output/calibration/calibration-report.json 与 output/edges/edge-stats.json，按 calibration-analyzer 角色规则做 5 项检查解读与 unresolved 归因。将完整归因结论写入 ${E3_ATTRIB_FILE}；若判定需要新提取器（[AI-REQUIRED]），必须同时将模式线索（文件路径+import/类名+建议 pattern 名）写入 ${E4_INPUT_FILE}，该文件存在即 E4 触发信号；无需新提取器则不得创建 ${E4_INPUT_FILE}。除上述两文件外不得修改 output/ 任何内容。" \
        > "$SUMMARY_DIR/e3-agent-$TODAY.log" 2>&1; then
        echo "  [OK] E3 归因完成 → ${E3_ATTRIB_FILE}"
    else
        echo "  [WARN] E3 归因 agent 失败（见 e3-agent-$TODAY.log）"
        echo "- [$NOW] nightly-$TODAY | E3 AI 归因失败 | 查看 output/nightly/e3-agent-$TODAY.log" >> "$QUEUE_FILE"
    fi
fi

# ─────────────────────────────────────────────────────────────────────
# 3.6 E4 自适应编码（--e4 且 E3 判定 [AI-REQUIRED]；staging 收束，防线 1）
# ─────────────────────────────────────────────────────────────────────
if [ "$AI_MODE" = "e4" ] && [ -n "$E4_INPUT_FILE" ] && [ -f "$E4_INPUT_FILE" ]; then
    echo "── E4 自适应编码（staging 收束）──"
    if opencode run --agent adapter-developer --model "$OLLAMA_MODEL" \
        "夜间无人值守 E4（--e4 模式）。依据 ${E4_INPUT_FILE} 的模式线索，在 project/staging/<pattern>/ 下产出完整交付包：extract-<pattern>.sh + fixtures/sample-<pattern>/ + fixtures/expected/<pattern>.json + E4-REPORT.md。完成后运行 bash scripts/e4-verify-bundle.sh <pattern> 自证，直至全绿或迭代上限 3 次。禁止调用 project/promote-extractor.sh；禁止写 staging 之外任何目录。" \
        > "$SUMMARY_DIR/e4-agent-$TODAY.log" 2>&1; then
        echo "  [OK] E4 agent 完成"
    else
        echo "  [WARN] E4 agent 失败（见 e4-agent-$TODAY.log）"
    fi

    NEW_PATTERN=$(ls -t "$PROJECT_DIR/staging/" 2>/dev/null | grep -v '^README.md$' | grep -v '^archived$' | head -1)
    if [ -n "$NEW_PATTERN" ] && bash scripts/e4-verify-bundle.sh "$NEW_PATTERN" > "$SUMMARY_DIR/e4-bundle-$TODAY.log" 2>&1; then
        echo "  [OK] 交付包 ${NEW_PATTERN} 验证全绿"
        if [ "$AUTO_PROMOTE" -eq 1 ]; then
            if bash "$PROJECT_DIR/promote-extractor.sh" "$NEW_PATTERN"; then
                echo "  [OK] 自动晋级 ${NEW_PATTERN}"
            else
                echo "  [WARN] 自动晋级失败（见上方输出）"
                echo "- [$NOW] nightly-$TODAY | E4 自动晋级失败（${NEW_PATTERN}）| 人工检查后运行 project/promote-extractor.sh" >> "$QUEUE_FILE"
            fi
        else
            echo "  [INFO] 已标记待晋级 → ${NEW_PATTERN}"
            echo "- [$NOW] nightly-$TODAY | E4 交付包 ${NEW_PATTERN} 验证全绿 | 白天运行 bash ${PROJECT_DIR}/promote-extractor.sh ${NEW_PATTERN} 晋级" >> "$QUEUE_FILE"
        fi
    else
        echo "  [WARN] staging 无有效交付包（或验证未全绿，见 e4-bundle-$TODAY.log）"
        echo "- [$NOW] nightly-$TODAY | E4 交付包未过验证 | 查看 output/nightly/e4-agent-$TODAY.log 与 e4-bundle-$TODAY.log" >> "$QUEUE_FILE"
    fi
fi

# ─────────────────────────────────────────────────────────────────────
# 4. 晨检队列（append-only）
# ─────────────────────────────────────────────────────────────────────
[ -f "$QUEUE_FILE" ] || { echo "# 夜间模式晨检队列（append-only）" > "$QUEUE_FILE"; echo "" >> "$QUEUE_FILE"; }

if [ "$GE3_EXIT" -ne 0 ]; then
    echo "- [$NOW] nightly-$TODAY | G-E3 POOR | 进 E4 自适应或人工评估模式覆盖" >> "$QUEUE_FILE"
fi
if [ "$PIPELINE_EXIT" -ne 0 ]; then
    echo "- [$NOW] nightly-$TODAY | 仓库提取异常 | 检查 output/nightly/pipeline-$TODAY.log" >> "$QUEUE_FILE"
fi
if [ "$G_RESULT" != "PASS" ]; then
    echo "- [$NOW] nightly-$TODAY | 门禁未全过（${G_NOTES}）| 人工检查后重跑" >> "$QUEUE_FILE"
fi
if [ -n "$AI_DEGRADED" ]; then
    echo "- [$NOW] nightly-$TODAY | AI 降级（${AI_DEGRADED}）| 检查 Ollama 服务与 OLLAMA_MODEL 后重试 --ai" >> "$QUEUE_FILE"
fi

# ─────────────────────────────────────────────────────────────────────
# 5. 摘要产出
# ─────────────────────────────────────────────────────────────────────
{
    echo "# Nightly 执行摘要 $TODAY"
    echo ""
    echo "| 项 | 结果 |"
    echo "|----|------|"
    echo "| 仓库数 | $REPO_COUNT |"
    echo "| pipeline | exit $PIPELINE_EXIT |"
    echo "| 门禁结论 | $G_RESULT |"
    echo "| 晨检队列 | $(grep -c "nightly-$TODAY" "$QUEUE_FILE" 2>/dev/null || echo 0) 条 |"
    echo ""
    echo "## 门禁明细"
    echo "- G-E1: $(bash "$SCRIPT_DIR/gates/G0-verify.sh" > /dev/null 2>&1 && echo PASS || echo FAIL)"
    echo "- G-E2: $([ "$PIPELINE_EXIT" -eq 0 ] && [ -f output/knowledge-graph/latest.json ] && echo PASS || echo FAIL)"
    echo "- G-E3: $([ "$GE3_EXIT" -eq 0 ] && echo PASS || echo FAIL)"
    echo "- G-E5: $(python3 -c "import json; d=json.load(open('output/knowledge-graph/latest.json')); exit(0 if all(k in d for k in ('stats','nodes','edges')) else 1)" >/dev/null 2>&1 && echo PASS || echo FAIL)"
    echo ""
    echo "## 图谱统计"
    python3 -c "import json; d=json.load(open('output/knowledge-graph/latest.json')); print(d.get('stats', '（无 stats）'))" 2>/dev/null || echo "（无 stats）"
    if [ "$AI_MODE" != "off" ] || [ -n "$AI_DEGRADED" ]; then
        echo ""
        echo "## AI 驱动"
        echo "- 模式: ${AI_MODE}（后端 ${OLLAMA_URL}，模型 ${OLLAMA_MODEL:-未配置}）"
        if [ -n "$AI_DEGRADED" ]; then
            echo "- 降级: ${AI_DEGRADED}（纯本地执行，未用 AI 算力）"
        fi
        if [ -n "$E3_ATTRIB_FILE" ] && [ -f "$E3_ATTRIB_FILE" ]; then
            echo "- E3 归因: ${E3_ATTRIB_FILE}"
        fi
        if [ -n "$E4_INPUT_FILE" ] && [ -f "$E4_INPUT_FILE" ]; then
            echo "- E4 线索: ${E4_INPUT_FILE}"
        fi
    fi
} > "$SUMMARY_FILE"

[ "$G_RESULT" != "PASS" ] && cp "$SUMMARY_DIR/pipeline-$TODAY.log" "$PARTIAL_FILE"

# ─────────────────────────────────────────────────────────────────────
# 6. 状态收口
# ─────────────────────────────────────────────────────────────────────
sed_i "s/^current-change: .*/current-change: null/" "$STATE_FILE"
sed_i "s/^current-phase: .*/current-phase: null/" "$STATE_FILE"
echo "- [$NOW] [归档] [completed] nightly 完成（门禁=${G_RESULT}），摘要见 $SUMMARY_FILE" >> docs/status/progress.md
rm -f "$LOCK_FILE"

echo "==== Nightly Complete ===="
echo "  摘要: $SUMMARY_FILE"
echo "  门禁: $G_RESULT"
echo "  队列: $(grep -c "nightly-$TODAY" "$QUEUE_FILE" 2>/dev/null || echo 0) 条待晨检"
