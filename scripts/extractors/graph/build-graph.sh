#!/usr/bin/env bash
# DEPRECATED — Replaced by 3-layer architecture. See EXTRACTION-WORKFLOW.md.
# Use: build-edges.sh (L2) → calibrate.sh (L3) → assemble-graph.sh (Assemble)
# This script is kept as a backward-compatible wrapper.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPRECATED] build-graph.sh is superseded by 3-layer architecture"
echo "  Layer 2: bash scripts/extractors/graph/build-edges.sh"
echo "  Layer 3: bash scripts/extractors/graph/calibrate.sh"
echo "  Assemble: bash scripts/extractors/graph/assemble-graph.sh"
echo ""
echo "[COMPAT] Running new pipeline instead..."
bash "$SCRIPT_DIR/build-edges.sh" "${1:-output/nodes}" "${2:-output/edges}"
bash "$SCRIPT_DIR/calibrate.sh" "${1:-output/nodes}" "${2:-output/edges}" "${3:-output/calibration}" || true
bash "$SCRIPT_DIR/assemble-graph.sh" "${1:-output/nodes}" "${2:-output/edges}" "${3:-output/calibration}" "${4:-output/knowledge-graph/latest.json}"
