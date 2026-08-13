# Code Graph — Knowledge Extraction Workflow

## 1. Architecture Overview

三层提取架构，每一层有明确的输入/输出/验收标准。

```
repos.yaml                        output/nodes/                   output/edges/
┌──────────────┐    ┌─────────────────────────────┐    ┌───────────────────────────┐
│ Git 仓库配置  │───▶│ Layer 1: 节点提取            │───▶│ Layer 2: 边构建             │
│ 协议注解映射  │    │ per-service/per-protocol     │    │ 提供者池 + 消费者匹配       │
│ 非标扫描规则  │    │ {protocol}-{role}.json       │    │ + 未解析报告               │
└──────────────┘    └─────────────────────────────┘    └───────────────────────────┘
                                                                   │
                                                                   ▼
                                              ┌───────────────────────────────┐
                                              │ Layer 3: 校准核验               │
                                              │ 孤儿消费 / 提供者冲突 /         │
                                              │ 完整性评分 / 非标置信度复核     │
                                              └───────────────────────────────┘
                                                                      │
                                                                      ▼
                                                 ┌──────────────────────────────┐
                                                 │ Assemble: 图谱组装             │
                                                 │ output/knowledge-graph/        │
                                                 │ latest.json                   │
                                                 └──────────────────────────────┘
```

### Output Directory Tree

```
output/
├── nodes/{service}/                        # Layer 1
│   ├── dubbo-provider.json
│   ├── dubbo-consumer.json
│   ├── sofarpc-provider.json
│   ├── sofarpc-consumer.json
│   ├── grpc-provider.json
│   ├── grpc-consumer.json
│   ├── rest-provider.json
│   ├── rest-consumer.json
│   ├── nonstandard-http.json
│   ├── nonstandard-mq.json
│   ├── nonstandard-custom.json
│   └── tags.json
├── edges/                                  # Layer 2
│   ├── rpc-edges.json             # RpcEdge[], 已成功匹配
│   ├── nonstandard-edges.json     # NonstandardEdge[], 非标调用
│   ├── unresolved-consumers.json  # 找不到提供者的消费引用
│   └── edge-stats.json            # 匹配率统计
├── calibration/                            # Layer 3
│   └── calibration-report.json    # 5 项检查结果
├── knowledge-graph/                        # Final
│   ├── latest.json                # 最新完整图谱
│   └── v1.0.0-{timestamp}.json   # 历史快照
└── repos/                         # git clone 缓存
```

### Script Roles

```
project/extractors/*/extract.sh   # AI 产出物（提取器）
project/fixtures/                 # 测试样本
scripts/base/                      # 原子能力 SDK（人维护）
scripts/graph/
  ├── build-edges.sh               # Layer 2: 提供者池 → 匹配 → 边 + 未解析
  ├── compute-stats.sh             # Layer 3: 5 项统计（bash 只算数，评级归 D2 AI）
  └── assemble-graph.sh            # 组装: nodes + edges → latest.json
scripts/pipeline.sh                # 主编排 (7 phase)
```

---

## 2. Layer 1 — 节点提取

### 2.1 Goal

扫描一个 Java 服务源码，产生 `InterfaceNode[]` 和 `tags`，**不建立任何边**。

### 2.2 Input

- `output/repos/{service}/` — 已克隆的 Java 服务源码
- `scripts/base/java-parser.sh` — Java 文件扫描函数
- `scripts/base/json-writer.sh` — JSON 节点写入函数

### 2.3 Per-Service Output

每个服务产生最多 12 个文件，全部写入 `output/nodes/{service}/`:

| File | Content | Produced By |
|------|---------|-------------|
| `dubbo-provider.json` | Dubbo 提供侧接口 | `project/extractors/dubbo/extract.sh` |
| `dubbo-consumer.json` | Dubbo 消费侧接口 | `project/extractors/dubbo/extract.sh` |
| `sofarpc-provider.json` | SOFARPC 提供侧接口 | `project/extractors/sofarpc/extract.sh` |
| `sofarpc-consumer.json` | SOFARPC 消费侧接口 | `project/extractors/sofarpc/extract.sh` |
| `grpc-provider.json` | gRPC 提供侧接口 | `project/extractors/grpc/extract.sh` |
| `grpc-consumer.json` | gRPC 消费侧接口 | `project/extractors/grpc/extract.sh` |
| `rest-provider.json` | REST 提供侧接口 | `project/extractors/rest/extract.sh` |
| `rest-consumer.json` | REST 消费侧接口 | `project/extractors/rest/extract.sh` |
| `nonstandard-http.json` | HTTP 客户端调用 | `project/extractors/http-client/extract.sh` |
| `nonstandard-mq.json` | MQ 交互 | `project/extractors/mq/extract.sh` |
| `nonstandard-custom.json` | 自定义协议+未知模式 | `project/extractors/custom/extract.sh` |
| `tags.json` | 业务标签 | `project/extractors/tags/extract.sh` |

### 2.4 Extraction Rules Per Protocol

本节描述每个提取器的检测逻辑。脚本按此编写，**当脚本缺失时按此重建**。

#### 2.4.1 Dubbo

```
查找对象: 所有 *.java 文件 (排除 /.git/ /target/ /build/)

提供侧检测 (project/extractors/dubbo/extract.sh → dubbo-provider.json):
  1. found_in_file "$file" "DubboService|com.alibaba.dubbo.config.annotation.Service|org.apache.dubbo.config.annotation.Service"
     ├─ 命中 → 提取所有 public 方法签名 (extract_methods)
     │        对每个方法生成 InterfaceNode:
     │          id:       "{parent}::{className}.{methodName}"
     │          protocol: "dubbo"
     │          role:     "provider"
     │          className: extract_class_name → 包名.类名
     │          signature: grep 输出行
     │          path:     "{relPath}:{lineNumber}"
     │
     ├─ extract_interface_impl → 获取 implements 接口列表
     └─ 无方法时: 生成一个以类名为粒度的节点

消费侧检测 (project/extractors/dubbo/extract.sh → dubbo-consumer.json):
  1. found_in_file "$file" "DubboReference|com.alibaba.dubbo.config.annotation.Reference|org.apache.dubbo.config.annotation.Reference"
  2. extract_field_annotations "$file" "DubboReference"  /  "Reference"
     → 获取注解所在行的下一行: 字段声明
     → 从字段声明中 grep 接口类型: "private UserService userService" → UserService
     → 生成 InterfaceNode:
         id:       "{parent}::{className}.{interfaceClass}"
         protocol: "dubbo"
         role:     "consumer"
         className: 引用的接口类名
         path:     "{relPath}:{annotationLine}"
```

**示例输入**:
```java
@DubboService
public class OrderServiceImpl implements OrderService {
    public OrderResult createOrder(OrderRequest req) { ... }
    public OrderResult cancelOrder(String orderId) { ... }
}

@Service
public class OrderManager {
    @DubboReference
    private UserService userService;

    @Reference(version = "1.0", timeout = 3000)
    private InventoryService inventoryService;
}
```

**预期输出** (`dubbo-provider.json`):
```json
[
  {"id":"order-service::com.example.OrderServiceImpl.createOrder","type":"interface","name":"createOrder","parent":"order-service","protocol":"dubbo","role":"provider","className":"com.example.OrderServiceImpl","signature":"public OrderResult createOrder(OrderRequest req)","path":"src/main/java/.../OrderServiceImpl.java:12","httpMethod":"","httpPath":"","tags":[]},
  {"id":"order-service::com.example.OrderServiceImpl.cancelOrder","type":"interface","name":"cancelOrder","parent":"order-service","protocol":"dubbo","role":"provider","className":"com.example.OrderServiceImpl","signature":"public OrderResult cancelOrder(String orderId)","path":"src/main/java/.../OrderServiceImpl.java:16","httpMethod":"","httpPath":"","tags":[]}
]
```

**预期输出** (`dubbo-consumer.json`):
```json
[
  {"id":"order-service::com.example.OrderManager.UserService","type":"interface","name":"UserService","parent":"order-service","protocol":"dubbo","role":"consumer","className":"UserService","signature":"private UserService userService","path":"src/main/java/.../OrderManager.java:8","httpMethod":"","httpPath":"","tags":[]},
  {"id":"order-service::com.example.OrderManager.InventoryService","type":"interface","name":"InventoryService","parent":"order-service","protocol":"dubbo","role":"consumer","className":"InventoryService","signature":"private InventoryService inventoryService","path":"src/main/java/.../OrderManager.java:12","httpMethod":"","httpPath":"","tags":[]}
]
```

#### 2.4.2 SOFARPC

```
提供侧:
  found_in_file "$file" "SofaService"
    → extract_methods → provider InterfaceNode (protocol="sofarpc")

  额外检查:
    found_in_file "$file" "com.alipay.sofa.rpc.api.GenericService"
    → 同上 (GenericService 模式)

消费侧:
  found_in_file "$file" "SofaReference"
    → extract_field_annotations "$file" "SofaReference" / "SofaReferenceBinding"
    → consumer InterfaceNode (protocol="sofarpc")
```

#### 2.4.3 gRPC

```
提供侧 (两种来源):

A. found_in_file "$file" "BindableService"
     → extract_methods → provider InterfaceNode (protocol="grpc")

B. find "$repo" -name "*.proto"
     → 解析每个 .proto 文件:
       grep "^package "     → package_name
       grep "service \w+"   → service_name
       grep "rpc \w+"       → rpc_name
       合并: "{package}.{service}.{rpcName}" 作为 className

消费侧:
  found_in_file "$file" "ManagedChannel|AbstractBlockingStub|AbstractFutureStub|AbstractStub"
    → grep 行中提取 stub/Channel 类型 → consumer InterfaceNode (protocol="grpc")
```

#### 2.4.4 REST

```
提供侧:
  found_in_file "$file" "RestController|@Path"
    → extract_methods
    → 对每个方法检查注解行的 HTTP mapping:
      @GetMapping → GET
      @PostMapping → POST
      @PutMapping → PUT
      @DeleteMapping → DELETE
      @PatchMapping → PATCH
      @RequestMapping → REQUEST
    → 提取 path 值: @GetMapping("/api/users/{id}") → /api/users/{id}
    → 拼接 class 级 path: @RequestMapping("/api/services") + 方法 path
    → InterfaceNode (protocol="rest", httpMethod=..., httpPath=...)

消费侧 (三种来源):

A. found_in_file "$file" "FeignClient"
     → 提取 @FeignClient(name=, url=) → 目标服务名
     → extract_methods → consumer InterfaceNode (protocol="rest")
     → httpMethod / httpPath 提取方式同提供侧

B. found_in_file "$file" "RestTemplate"
     → grep '.getForObject|.postForObject|.exchange('
     → 从调用中提取 URL 字符串: "http://user-service/api/..."
     → consumer InterfaceNode (protocol="rest")
     → 包括服务内跨模块调用

C. found_in_file "$file" "WebClient|OkHttpClient"
     → 类似 RestTemplate，探测 HTTP 调用 URL
```

#### 2.4.5 Nonstandard (3 extractors)

```
project/extractors/http-client/extract.sh:
  对每个 java_file:
    if found_in_file "$file" "RestTemplate|OkHttpClient|HttpClient|WebClient":
      grep '.getForObject|.postForObject|.postForEntity|.getForEntity|.exchange|.execute('
      → 从行中提取 URL 字符串 (grep -oE '"(https?://[^"]*)"')
      → 从 URL 解析目标 host: sed 's|https\?://||' | cut -d/ -f1
      → InterfaceNode (protocol="http")

project/extractors/mq/extract.sh:
  对每个 java_file:
    if found_in_file "$file" "KafkaProducer|KafkaConsumer|KafkaTemplate":
      grep '.send|.publish|.subscribe|.poll|.consume('
      → 检测 topic: grep -oE '"(order-topic|payment-topic|[^"]*topic[^"]*)"' 或 'TOPIC_\w+'
      → detect_mq_role: 看方法名含 Consumer/Producer/send/subscribe
      → InterfaceNode (protocol="mq")

    if found_in_file "$file" "rabbitTemplate|RabbitTemplate|AmqpTemplate|Channel":
      grep 'convertAndSend|receiveAndConvert|basicPublish|basicConsume' → 同上

    if found_in_file "$file" "DefaultMQProducer|DefaultMQPushConsumer":
      → 同上

project/extractors/custom/extract.sh:
  对每个 java_file:
    if found_in_file "$file" "io\.netty":
      if found_in_file "ServerBootstrap":
        grep '.bind(' → 提取端口号 → provider InterfaceNode (protocol="socket")
      if found_in_file "Bootstrap" (不是 ServerBootstrap):
        grep '.connect(' → consumer InterfaceNode (protocol="socket")

    if found_in_file "$file" "java\.(net|nio)\.(Socket|ServerSocket)":
      → provider/consumer InterfaceNode (protocol="socket")

    # Unknown pattern detection
    extract_imports → 过滤含 rpc/remote/connect/transport/channel 的非标准导入
    → 生成 InterfaceNode (protocol="custom", role="unknown")
    → [AI-REQUIRED] 标记
    → 触发 templates/analyze-pattern.md 进行 AI 分析
```

#### 2.4.6 Business Tags

```
project/extractors/tags/extract.sh:
  5 条并行链路:

  链 1: 自定义注解
    extract_class_annotations → 匹配 annotation_prefixes → 注解名转标签

  链 2: 包名推断
    extract_package → 匹配 package_domain_mapping
    例: com.example.order.service → "order-domain"

  链 3: Javadoc
    grep '@since|@author' → 关键词提取

  链 4: 方法名
    extract_methods → 驼峰拆分 → 去 get/set/is 前缀 → 关键词
    例: createOrder → [create, order]

  链 5: 配置文件
    grep application.yml: spring.application.name
    grep pom.xml: artifactId

  输出: tags.json (string[])
```

### 2.5 Decision Trees

#### Q: Extractors produce empty output?

```
├─ 服务中确实没有该协议? → OK, 生成空数组 []
├─ repo_path 不正确? → 检查 clone 路径
├─ Java source 不是标准目录结构? → 检查 scan_java_files 排除规则
└─ 注解命名方式不同? → 修改 found_in_file 的 grep pattern
```

#### Q: Custom annotation not matched?

```
├─ annotation_prefixes 配置包含此包? → NO → 添加
├─ 注解包没有 import? → 注解是简单名而非全限定名
│   → found_in_file 匹配 "@{SimpleName}" (不带包前缀)
└─ 其他 → 标记 [UNCERTAIN]，人工确认
```

---

## 3. Layer 2 — 边构建

### 3.1 Goal

读取 Layer 1 的所有 InterfaceNode，通过 **提供者池 + 消费者匹配** 建立调用边，同时输出未解析引用。

### 3.2 Input

- `output/nodes/*/` 下所有 `*-provider.json` 和 `*-consumer.json`
- `output/nodes/*/nonstandard-*.json`

### 3.3 Algorithm

```
Phase A: 构建提供者池

  provider_pool = {}
  for each file in output/nodes/*/{dubbo,sofarpc,grpc,rest}-provider.json:
    for each node in file:
      class_name = node.className
      if class_name is empty → skip
      if class_name not in provider_pool:
        provider_pool[class_name] = []
      provider_pool[class_name].push({
        node_id:     node.id,
        service:     node.parent,
        protocol:    node.protocol,
        method_name: node.name
      })

Phase B: 消费者匹配

  rpc_edges = []
  unresolved = []
  matched_count = 0
  total_count = 0

  for each file in output/nodes/*/{dubbo,sofarpc,grpc,rest}-consumer.json:
    for each consumer in file:
      total_count += 1
      target = consumer.className

      # Direct match
      if target in provider_pool:
        for provider in provider_pool[target]:
          if consumer.parent != provider.service:
            rpc_edges.push({
              from:        consumer.id,
              to:          provider.node_id,
              type:        "rpc_call",
              protocol:    consumer.protocol,
              fromService: consumer.parent,
              toService:   provider.service
            })
            matched_count += 1
            break  # one edge per consumer

      # Partial match: className substring
      elif target is not empty:
        partial_found = false
        for pool_class in provider_pool keys:
          if pool_class contains target:
            (same logic as above, matched)
            partial_found = true
            break

        if not partial_found:
          unresolved.push({
            consumer_node_id: consumer.id,
            class_name:       target,
            from_service:     consumer.parent,
            source_path:      consumer.path,
            reason:           "provider_not_found"
          })

Phase C: 非标边

  nonstandard_edges = []
  for each file in output/nodes/*/nonstandard-*.json:
    for each node in file:
      if node.role == "consumer":
        target_host = extract from node.httpPath or node.signature
        # Parse host from URL
        target_host = target_host | sed 's|https\?://||' | cut -d/ -f1

        nonstandard_edges.push({
          from:         node.id,
          to:           target_host || "unknown",
          type:         "nonstandard_call",
          protocol:     node.protocol,
          confidence:   estimate_confidence(node),
          fromService:  node.parent,
          pattern:      node_pattern_from_signature(node),
          sourcePath:   node.path
        })

  Confidence estimation:
    - URL contains known service name → 0.9
    - URL is IP:port → 0.7
    - Topic name matches convention → 0.8
    - Socket connect() with host:port → 0.6
    - Marked "unknown" by custom extractor → 0.4

Phase D: Edge stats

  match_rate = matched_count / total_count
  write edge-stats.json:
  {
    "total_consumers": {total_count},
    "matched": {matched_count},
    "unresolved": {length(unresolved)},
    "match_rate": {match_rate},
    "nonstandard_edges": {length(nonstandard_edges)}
  }
```

### 3.4 Output

| File | Schema |
|------|--------|
| `output/edges/rpc-edges.json` | `RpcEdge[]` |
| `output/edges/nonstandard-edges.json` | `NonstandardEdge[]` |
| `output/edges/unresolved-consumers.json` | `{consumer_node_id, class_name, from_service, source_path, reason}[]` |
| `output/edges/edge-stats.json` | `{total_consumers, matched, unresolved, match_rate, nonstandard_edges}` |

### 3.5 Decision Tree

#### Q: Consumer not matched?

```
├─ Provider service not in repos.yaml? → add or mark EXTERNAL
├─ Provider service cloned but extraction empty? → check Layer 1 output
├─ className uses short name vs full qualified? → try partial match
├─ Called via reflection/proxy? → cannot match statically, needs runtime tracing
└─ None of above → record in unresolved-consumers.json
```

#### Q: One consumer matches multiple providers?

```
├─ Same interface, different services (version coexistence)
│   → create edge to each, calibration will flag CONFLICT
├─ Same service, different modules → skip (same parent.id)
└─ False positive due to common class name → tighten match
```

---

## 4. Layer 3 — 校准核验

### 4.1 Goal

对 Layer 2 的输出进行 5 项质量检查，产生校准报告。不合格项阻断裂谱组装或标记降级。

### 4.2 Input

- `output/nodes/*/` — 所有 Layer 1 节点
- `output/edges/rpc-edges.json` — Layer 2 匹配结果
- `output/edges/unresolved-consumers.json` — Layer 2 未解析
- `output/edges/nonstandard-edges.json` — Layer 2 非标边

### 4.3 Five Checks

#### Check A: 孤儿消费检测

```
检查: unresolved-consumers.json 中的每个条目
输出:
  orphans = unresolved-consumers grouped by class_name
  report:
    "org.example.UserService referenced by [order-service, payment-service] but NOT found in provider pool"
    → possible causes: external service / extraction gap / interface renamed
```

#### Check B: 提供者冲突

```
检查:
  provider_pool 中同一 key (className) 被多个 service 声明
  例: "com.example.AuthService" → [auth-service, auth-v2-service]

判定:
  - different service names → CONFLICT (version coexistence, service split in progress)
  - same service, different protocols → ALLOW (protocol diversification)

输出:
  conflicts = [
    {class_name, providers: [{service, node_id, protocol}]}
  ]
```

#### Check C: 孤儿提供者

```
检查:
  所有 provider InterfaceNode 中，有哪些没有被任何 RpcEdge.to 引用

原因可能:
  - 消费者在外部服务 (不在 repos.yaml 范围内)
  - 死代码 (没有消费者)
  - Layer 1 提取遗漏了消费者

输出:
  orphan_providers = [
    {node_id, className, service, method}
  ]
```

#### Check D: 非标置信度复核

```
检查: nonstandard-edges.json 中每条边的 confidence

分级:
  confidence < 0.5  → [NEEDS-REVIEW]  需要人工确认
  confidence 0.5-0.7 → [LOW-CONFIDENCE] 标记但不阻断
  confidence ≥ 0.7   → [ACCEPTED]      接受

输出:
  nonstandard_review = {
    needs_review: [{edge, confidence}],
    low_confidence: [{edge, confidence}],
    accepted: count
  }
```

#### Check E: 完整性评分

```
计算:
  score = edge-stats.json.matched / edge-stats.json.total_consumers

评级:
  score ≥ 0.90 → "GOOD"    完整，可用于架构决策
  score 0.70-0.89 → "FAIR"  主要关系已覆盖，建议人工补充缺失
  score < 0.70 → "POOR"    大量缺失，需 AI 介入 (templates/analyze-pattern.md)

缺失归因:
  1. 提供者服务不在 repos.yaml 中
  2. 非标 RPC 未被覆盖
  3. 反射/动态代理运行时绑定
  4. 接口别名 (import 中使用简单名而非全限定名)
```

### 4.4 Output

```json
// output/calibration/calibration-report.json
{
  "generatedAt": "2026-08-07T12:00:00Z",
  "overallScore": 0.85,
  "rating": "FAIR",
  "checks": {
    "A_orphanConsumers": {
      "count": 3,
      "pass": false,
      "details": [...]
    },
    "B_providerConflicts": {
      "count": 0,
      "pass": true,
      "details": []
    },
    "C_orphanProviders": {
      "count": 5,
      "pass": true,
      "details": [...]
    },
    "D_nonstandardConfidence": {
      "needsReview": 2,
      "lowConfidence": 4,
      "accepted": 15
    },
    "E_completenessScore": {
      "score": 0.85,
      "matched": 68,
      "total": 80,
      "rating": "FAIR"
    }
  },
  "blockers": [],
  "warnings": [
    "3 consumers have no matching provider (external service?)",
    "2 nonstandard edges need manual review"
  ]
}
```

### 4.5 Gating

```
阻断条件 (blockers — 组装前必须解决):
  - B_providerConflicts: count > 0 AND 不是 protocol diversification
  - D_nonstandardConfidence: needsReview 中有 security-sensitive 模式

警告条件 (warnings — 组装继续但标注):
  - A_orphanConsumers: count > 0
  - C_orphanProviders: count > 0
  - E_completenessScore: rating == "POOR"
```

---

## 5. Assemble — 图谱组装

### 5.1 Goal

将 Layer 1 节点 + Layer 2 边 + Layer 3 校准结果组装为最终图谱。

### 5.2 Algorithm

```
1. 读取 output/nodes/*/tags.json → service_tags
2. 读取 output/nodes/*/ 所有 InterfaceNode → 去重 → nodes[]
3. 对每个 service 创建 ServiceNode:
   {id, type:"service", name, repo, tags: service_tags}
4. 读取 output/edges/rpc-edges.json → edges[].push(all)
5. 读取 output/edges/nonstandard-edges.json → edges[].push(all)
6. 读取 output/calibration/calibration-report.json → stats
7. 验证 nodes.edges 中所有引用 id 存在 → 完整性检查
8. 输出 latest.json:
   {version, generatedAt, calibrationScore, stats, nodes, edges}
9. 如果已有 latest.json: 复制为 v1.0.0-{timestamp}.json
```

### 5.3 Output

```json
// output/knowledge-graph/latest.json
{
  "version": "1.0",
  "generatedAt": "2026-08-07T12:00:00Z",
  "calibrationScore": 0.85,
  "calibrationRating": "FAIR",
  "stats": {
    "totalServices": 5,
    "totalInterfaces": 120,
    "totalEdges": 68,
    "byProtocol": {"dubbo": 45, "sofarpc": 0, "grpc": 0, "rest": 23, "nonstandard": 12}
  },
  "nodes": [...],
  "edges": [...]
}
```

---

## 6. Incremental Update Strategy

### 6.1 Change Detection

```
1. 对每个已克隆 repo: git -C $repo rev-parse HEAD → new_hash
2. 对比 $repo/.last_commit_hash → old_hash
3. old_hash != new_hash → [CHANGED]

仅重提取变更的服务:
  → nodes/{changed_service}/ 重新生成
  → edges/ 全量重建 (因为边可能跨服务)
  → calibration/ 全量重校验
  → assemble → latest.json

合并:
  → 复制旧 latest.json 为版本快照
  → 用新 latest.json 覆盖
```

---

## 7. Pipeline Execution Order

```
bash scripts/pipeline.sh

Phase 0: Dependency Check
  → git, bash, jq available?

Phase 1: Repository Preparation
  → repos.yaml → git clone/update → output/repos/{service}/

Phase 2: Node Extraction (Layer 1)
  → per service, parallel:
    project/extractors/dubbo/extract.sh, sofarpc/, grpc/, rest/
    project/extractors/http-client/extract.sh, mq/, custom/
  → project/extractors/tags/extract.sh (serial, after all extractors)
  → D1: 按 output/analysis/<service>-profile.yaml 选择提取器（无 profile 则全量）
  → [AI-REQUIRED] if unknown patterns detected

Phase 3: Edge Building (Layer 2)
  → build-edges.sh
    → provider_pool
    → consumer matching → rpc-edges.json + unresolved-consumers.json
    → nonstandard → nonstandard-edges.json
    → stats → edge-stats.json

Phase 4: Compute Stats (Layer 3)
  → compute-stats.sh → 5 checks numbers only → calibration-report.json（无 rating 字段）
  → if blockers → abort with report
  → D2 AI（calibration-analyzer）→ 评级（GOOD/FAIR/POOR）+ 分流判定

Phase 5: Graph Assembly
  → assemble-graph.sh → output/knowledge-graph/latest.json

Phase 6: Incremental Merge
  → save snapshot + update latest.json

Phase 7: Summary
  → print stats + calibration score
```

---

## Appendix A: Schema Reference

See `schemas/knowledge-graph.schema.json` for full JSON Schema definitions.

Key types:
- **ServiceNode**: `{id, type:"service", name, repo, branch, buildTool, tags, metadata}`
- **InterfaceNode**: `{id, type:"interface", name, parent, protocol, role, className, signature, path, httpMethod, httpPath, tags, metadata}`
- **RpcEdge**: `{from, to, type:"rpc_call", protocol, fromService, toService}`
- **NonstandardEdge**: `{from, to, type:"nonstandard_call", protocol, confidence, pattern, sourcePath, metadata}`

## Appendix B: Common Issue Decision Trees

```
Q: Duplicate node ids?
   → check if same className.methodName extracted from multiple files
   → solution: use id = "{parent}::{className}.{methodName}_{lineNumber}"

Q: Consumer className is simple name (e.g., "UserService") vs provider has full qualified (e.g., "com.example.UserService")?
   → Layer 2 matching: try exact match first, then contains match
   → Layer 1: ensure extract_class_name returns from "import" statements

Q: Calibration score is POOR (< 0.70)?
   → check unresolved-consumers.json for dominant missing provider
   → check if services not in repos.yaml
   → run AI analysis on unknown custom patterns
   → consider adding new nonstandard scanner in repos.yaml

Q: Nonstandard extraction produces too many false positives?
    → raise confidence threshold in D2 AI attribution (calibration-analyzer)
    → tighten grep patterns in extraction scripts
    → use AI (templates/analyze-pattern.md) for problem patterns
```

## Appendix C: Script File Index

| Script | Role | Layer |
|--------|------|-------|
| `scripts/pipeline.sh` | Main orchestrator | All |
| `scripts/base/repo-manager.sh` | Git clone/update/change detection | 0 |
| `scripts/base/java-parser.sh` | Java file scanning functions (atomic capability) | 1 |
| `scripts/base/json-writer.sh` | JSON node/edge writing functions (atomic capability) | 1-3 |
| `project/extractors/dubbo/extract.sh` | Dubbo interface extraction | 1 |
| `project/extractors/sofarpc/extract.sh` | SOFARPC interface extraction | 1 |
| `project/extractors/grpc/extract.sh` | gRPC interface extraction | 1 |
| `project/extractors/rest/extract.sh` | REST API extraction | 1 |
| `project/extractors/http-client/extract.sh` | HTTP client call extraction | 1 |
| `project/extractors/mq/extract.sh` | MQ interaction extraction | 1 |
| `project/extractors/custom/extract.sh` | Custom protocol + unknown detection | 1 |
| `scripts/gates/GP1-5-verify.sh` | Nonstandard script verification | 1-validate |
| `project/extractors/tags/extract.sh` | Business tag extraction | 1 |
| `scripts/pipeline.sh`（内联提取器遍历，EXTRACTORS_DIR） | Coordinate all Layer 1 extractors + D1 | 1 |
| `scripts/graph/build-edges.sh` | Provider pool + consumer matching | 2 |
| `scripts/graph/compute-stats.sh` | 5 stats checks (no rating, D2 AI rates) | 3 |
| `scripts/graph/assemble-graph.sh` | Final graph assembly | Assemble |
| `scripts/graph/merge-graphs.sh` | Incremental update | Merge |
| `templates/analyze-framework.md` | AI D1: framework fingerprint analysis | 1 AI |
| `templates/analyze-pattern.md` | AI D3: unknown RPC pattern analysis | 1 AI |
| `templates/generate-script.md` | AI D3: extractor/SDK script generation | 1 AI |
| `templates/persist-rule.md` | AI: pattern rule persistence | 1 AI |
