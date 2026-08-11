# Analyze Unknown RPC Pattern

## Context
你是代码模式分析专家。下面是一段 Java 代码片段，其中包含了一个尚不被 Harness 工程识别的通信模式。
请分析这段代码，判定它是否是一个值得追踪的 RPC/API 调用模式。

## Input
### 代码文件路径
`{file_path}`

### 类名
`{class_name}`

### 可疑的 import 语句
```
{unknown_imports}
```

### 代码上下文（50行）
```java
{code_snippet}
```

## Analysis Instructions
1. **判定通信类型**: 这是 RPC 调用？HTTP 调用？消息队列交互？数据库操作？还是普通的工具类引用？
2. **识别模式特征**: 如果是通信相关，提取其特有的结构特征（类引用 + 方法调用模式）
3. **评估可行性**: 能否用 bash/grep 脚本自动提取这种模式？
   - 如果可以用正则匹配 → 给出匹配表达式
   - 如果需要 AST 解析 → 标记需要 Java 解析工具
   - 如果过于复杂 → 标记为需人工标注
4. **评估置信度**: 给出 0-1 的置信度评分

## Output Format
```yaml
is_rpc: true|false
protocol_type: "http"|"mq"|"socket"|"custom"|"not-rpc"
pattern_name: "简短的模式名"
detection_method: "regex"|"ast"|"manual"
detection_patterns:
  class_ref: "必需引用的类全限定名"
  method_call: "关键方法调用模式"
  target_extraction: "如何提取目标服务/接口名"
confidence: 0.0-1.0
can_automate: true|false
notes: "补充说明"
```
