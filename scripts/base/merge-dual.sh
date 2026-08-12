#!/usr/bin/env bash
# merge-dual — 双维度合并（Q1=A 取并集 + 置信度分级 + 协议级加权）
# 用法: bash scripts/base/merge-dual.sh <service-name> <nodes-script-dir> <nodes-ai-dir> <output-dir> [profile.yaml]
#
# 置信度规则（ai-analysis-harness.md §7）:
#   节点级起点: bash∩AI=high / bash only=medium / ai only=medium
#   协议级加权: profile.{proto}=high → +1 (上限 high) / none → -1 (下限 low)
#
# 依赖: python3 (macOS bash 3.2 不支持关联数组, 用 python3 做合并)
set -uo pipefail

SERVICE_NAME="${1:-}"
SCRIPT_DIR_="${2:-}"
AI_DIR_="${3:-}"
OUT_DIR_="${4:-}"
PROFILE_FILE="${5:-}"

if [ -z "$SERVICE_NAME" ] || [ -z "$SCRIPT_DIR_" ] || [ -z "$AI_DIR_" ] || [ -z "$OUT_DIR_" ]; then
    echo "Usage: $0 <service> <nodes-script-dir> <nodes-ai-dir> <output-dir> [profile.yaml]" >&2
    exit 2
fi

if ! command -v python3 &>/dev/null; then
    echo "[ABORT] merge-dual requires python3" >&2
    exit 1
fi

mkdir -p "$OUT_DIR_"
echo "[MERGE-DUAL] $SERVICE_NAME (script=$SCRIPT_DIR_ ai=$AI_DIR_ → $OUT_DIR_)"

python3 - "$SERVICE_NAME" "$SCRIPT_DIR_" "$AI_DIR_" "$OUT_DIR_" "$PROFILE_FILE" <<'PY'
import json, os, sys, glob

service = sys.argv[1]
script_dir = sys.argv[2]
ai_dir = sys.argv[3]
out_dir = sys.argv[4]
profile_file = sys.argv[5] if len(sys.argv) > 5 and os.path.exists(sys.argv[5]) else None

# 解析 profile 协议级权重
prof_weight = {}
if profile_file:
    proto = None
    conf = None
    for line in open(profile_file):
        line = line.strip()
        if line.startswith('- protocol:'):
            proto = line.split('protocol:')[1].strip()
        elif line.startswith('confidence:'):
            conf = line.split('confidence:')[1].strip()
            if proto:
                if conf == 'high':
                    prof_weight[proto] = 1
                elif conf == 'none':
                    prof_weight[proto] = -1
                else:
                    prof_weight[proto] = 0
                proto = None
                conf = None

def bump(conf, delta):
    order = ['low', 'medium', 'high']
    idx = order.index(conf) if conf in order else 1
    idx = max(0, min(2, idx + delta))
    return order[idx]

def normalize(node, source, consistency, base_conf=None):
    """补齐 v2.1 必需字段。仅处理 dict 节点；纯字符串数组（如 tags）原样透传。"""
    if not isinstance(node, dict):
        return node
    conf = node.get('confidence') or base_conf or 'medium'
    ev = node.get('evidence_type') or 'source_reference'
    refs = node.get('evidence_refs')
    if not refs:
        refs = [{'source_path': node.get('path', ''), 'tier': 2}]
    meta = dict(node.get('metadata') or {})
    meta['dual_dimension_consistency'] = consistency
    node['confidence'] = conf
    node['evidence_type'] = ev
    node['evidence_refs'] = refs
    node['source'] = source
    node['metadata'] = meta
    return node

def is_object_array(items):
    return isinstance(items, list) and all(isinstance(x, dict) for x in items)

count = 0
for script_file in sorted(glob.glob(os.path.join(script_dir, '*.json'))):
    base = os.path.basename(script_file)
    ai_file = os.path.join(ai_dir, base)

    # 尝试加载脚本节点与 AI 节点
    try:
        s_nodes = json.load(open(script_file))
    except Exception:
        continue
    a_nodes = []
    if os.path.exists(ai_file):
        try:
            a_nodes = json.load(open(ai_file))
        except Exception:
            a_nodes = []

    if not a_nodes:
        # 无 AI 对应: 脚本单源 → source=bash, 起点 medium
        if is_object_array(s_nodes):
            merged = [normalize(n, 'bash', 'bash_only', 'medium') for n in s_nodes]
        else:
            merged = s_nodes
        json.dump(merged, open(os.path.join(out_dir, base), 'w'), ensure_ascii=False)
        count += 1
        continue

    # 双源合并: 按 id 分组
    by_id = {}
    for n in s_nodes:
        by_id.setdefault(n.get('id'), {}).setdefault('s', n)
    for n in a_nodes:
        by_id.setdefault(n.get('id'), {}).setdefault('a', n)

    merged = []
    for nid, srcs in by_id.items():
        sn = srcs.get('s')
        an = srcs.get('a')
        # 非对象节点（如 tags 纯字符串）直接透传（取脚本侧，避免重复）
        if not isinstance(sn, dict) and not isinstance(an, dict):
            merged.append(sn if isinstance(sn, dict) or sn is not None else an)
            continue
        proto = (sn or an).get('protocol', '') if isinstance(sn or an, dict) else ''
        delta = prof_weight.get(proto, 0)
        if sn and an:
            base_conf = 'high'          # 双维度印证 → high 起点
            consistency = 'both'
            source = 'dual'
            node = dict(an)             # AI 版本优先（含 evidence）
            node.update({k: v for k, v in sn.items() if k not in node})
            node = normalize(node, source, consistency, base_conf)
        elif sn:
            base_conf = 'medium'        # 脚本单源
            consistency = 'bash_only'
            source = 'bash'
            node = normalize(dict(sn), source, consistency, base_conf)
        else:
            base_conf = 'medium'        # AI 单源
            consistency = 'ai_only'
            source = 'ai'
            node = normalize(dict(an), source, consistency, base_conf)
        node['confidence'] = bump(node['confidence'], delta)   # 协议级加权
        merged.append(node)

    json.dump(merged, open(os.path.join(out_dir, base), 'w'), ensure_ascii=False)
    count += 1

# AI 独有文件（脚本目录不存在对应文件）
for ai_file in sorted(glob.glob(os.path.join(ai_dir, '*.json'))):
    base = os.path.basename(ai_file)
    out_file = os.path.join(out_dir, base)
    if os.path.exists(out_file):
        continue
    if base.startswith('round-'):
        try:
            a_nodes = json.load(open(ai_file))
            out_file = os.path.join(out_dir, 'ai-extra.json')
            merged = [normalize(n, 'ai', 'ai_only', 'medium') for n in a_nodes] if is_object_array(a_nodes) else a_nodes
            json.dump(merged, open(out_file, 'w'), ensure_ascii=False)
            count += 1
        except Exception:
            pass
    else:
        try:
            a_nodes = json.load(open(ai_file))
            merged = [normalize(n, 'ai', 'ai_only', 'medium') for n in a_nodes] if is_object_array(a_nodes) else a_nodes
            json.dump(merged, open(out_file, 'w'), ensure_ascii=False)
            count += 1
        except Exception:
            pass

print(f"[MERGE-DUAL] merged {count} file(s) → {out_dir}")
PY
exit 0
