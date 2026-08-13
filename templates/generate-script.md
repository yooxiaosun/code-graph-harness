# Generate Extraction Script from Pattern Analysis

## Context
你是 Harness 脚本生成专家。根据上一步的模式分析结果，生成一个符合 Harness 工程规范的 bash 提取脚本。
该脚本经 staging 自证与晋级后落位 `project/extractors/{pattern}/extract.sh`，成为 Harness 的一部分。

## Input
### 模式分析结果
```yaml
{pattern_analysis}
```

### Harness 脚本规范
- 使用 `#!/usr/bin/env bash` + `set -euo pipefail`
- 接受 3 个参数: `<service-name> <repo-path> [output-dir]`
- source 基础工具: 通过 `ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"` 定位工程根，source `$ROOT_DIR/scripts/base/java-parser.sh` 和 `$ROOT_DIR/scripts/base/json-writer.sh`
- 输出到 `$OUTPUT_DIR/$SERVICE_NAME/nonstandard-{protocol}.json`
- 每个接口节点使用 `node_interface_json` 函数
- 最后打印 `[NONSTD-{PROTOCOL}] $SERVICE_NAME: N items detected`

## Script Template
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$ROOT_DIR/scripts/base/java-parser.sh"
source "$ROOT_DIR/scripts/base/json-writer.sh"

SERVICE_NAME="${1:-}"
REPO_PATH="${2:-.}"
OUTPUT_DIR="${3:-output/raw}"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> <repo-path> [output-dir]"
    exit 1
fi

OUTPUT_FILE="$OUTPUT_DIR/$SERVICE_NAME/nonstandard-{protocol}.json"
mkdir -p "$(dirname "$OUTPUT_FILE")"

COUNT=0
json_array_init "$OUTPUT_FILE"

# -- 在此编写你的检测逻辑 --
# 使用 base 工具函数:
#   scan_java_files "$REPO_PATH"          — 扫描所有 .java 文件
#   extract_imports "$java_file"          — 提取 import 语句
#   extract_class_name "$java_file"       — 提取全限定类名
#   found_in_file "$java_file" "pattern"  — 检查文件是否包含模式
#   对每个检测到的模式调用 node_interface_json 和 json_array_add

while IFS= read -r java_file; do
    # {detection_logic}
    :
done < <(scan_java_files "$REPO_PATH")

json_array_close "$OUTPUT_FILE"
echo "[NONSTD-{PROTOCOL}] $SERVICE_NAME: $COUNT items detected"
```

## Generation Instructions
1. 在 `# -- 在此编写你的检测逻辑 --` 位置填充实际的检测逻辑
2. 确保能够提取: 服务名、类名、关键方法、源码路径
3. 对非标调用使用 `protocol="{protocol}"`, `role="consumer"` (默认为消费侧)
4. 包括合理的错误处理和边界条件

## Output
只返回完整的 bash 脚本代码（在代码块中）。不要包含任何额外说明。
