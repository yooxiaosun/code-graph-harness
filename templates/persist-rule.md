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
`.harness/extractors/{pattern_name}/extract.sh`

### 验证结果
- GP1 (Syntax): {pass/fail}
- GP2 (Execution): {pass/fail}
- GP3 (Schema): {pass/fail}
- GP4 (Recall): {pass/fail}
- GP5 (Regression): {pass/fail}

## Persistence Steps

### 1. Copy Script to Canonical Location
```bash
# 唯一晋级通道：bash scripts/promote-extractor.sh {pattern_name}
# 晋级后落位 .harness/extractors/{pattern_name}/extract.sh
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
.harness/extractors/{pattern_name}/extract.sh

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

### 4. Pipeline Integration
`scripts/graph/build-nodes.sh` 自动扫描 `.harness/extractors/*/extract.sh`，晋级后无需手工接入；
如需 tags 类串行行为等特殊调度，由人工评审后修改 build-nodes.sh。

## After Persistence
- Delete temporary test output from `output/raw/test-service/`
- Run `bash scripts/pipeline.sh` to verify integration
- Commit all changes to the harness repository
