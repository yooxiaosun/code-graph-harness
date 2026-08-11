# Persist Learned RPC Pattern Rule

## Context
新发现的非标 RPC 模式已通过全部 5 个验证门禁 (GP1-GP5)。
现在需要将其持久化为 Harness 工程的正式组成部分。

## Input
### 模式元数据
```yaml
pattern_name: "{name}"
protocol_type: "{http|mq|socket|custom}"
discovered_at: "{ISO8601_timestamp}"
source_service: "{service_name}"
confidence: 0.0-1.0
```

### 生成脚本
`scripts/extractors/nonstandard/extract-{pattern_name}.sh`

### 验证结果
- GP1 (Syntax): {pass/fail}
- GP2 (Execution): {pass/fail}
- GP3 (Schema): {pass/fail}
- GP4 (Recall): {pass/fail}
- GP5 (Regression): {pass/fail}

## Persistence Steps

### 1. Copy Script to Canonical Location
```bash
# Already in place at scripts/extractors/nonstandard/extract-{pattern_name}.sh
```

### 2. Register Pattern in .harness/patterns/
Create `.harness/patterns/{pattern_name}.md` with:
```markdown
# Pattern: {pattern_name}

## Metadata
- Protocol: {protocol_type}
- Discovered: {discovered_at}
- Source: {source_service}
- Confidence: {confidence}

## Detection Rules
{summarized_from_analysis}

## Extraction Script
scripts/extractors/nonstandard/extract-{pattern_name}.sh

## Verification History
| Gate | Result | Date |
|------|--------|------|
| GP1 | {pass/fail} | {date} |
| GP2 | {pass/fail} | {date} |
| GP3 | {pass/fail} | {date} |
| GP4 | {pass/fail} | {date} |
| GP5 | {pass/fail} | {date} |
```

### 3. Update repos.yaml Scanner Config
Add to `nonstandard.scanners`:
```yaml
    - name: {pattern_name}
      description: "{brief_description}"
      class_patterns:
        - "{required_class}"
      method_patterns:
        - "{key_method_call}"
```

### 4. Add to Pipeline Phase 4
In `scripts/pipeline.sh` Phase 4, add:
```bash
bash "$EXTRACTORS_DIR/nonstandard/extract-{pattern_name}.sh" "$SERVICE_NAME" "$REPO_PATH" "$OUTPUT_DIR/raw" &
```

## After Persistence
- Delete temporary test output from `output/raw/test-service/`
- Run `bash scripts/pipeline.sh` to verify integration
- Commit all changes to the harness repository
