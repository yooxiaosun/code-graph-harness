# Dubbo RPC Interface Detector

## Detection Target
从 Java 源码中提取 Dubbo 服务提供者和消费者的接口定义及调用关系。

## Detection Rules

### Provider Side — 提供侧
提取本服务对外暴露的 Dubbo 接口。

**触发条件（任一满足）:**
1. **注解检测**: 类或接口上存在 Dubbo `@Service` / `@DubboService` 注解
   - `@com.alibaba.dubbo.config.annotation.Service`
   - `@org.apache.dubbo.config.annotation.Service`
   - `@org.apache.dubbo.config.annotation.DubboService`
2. **XML 配置检测**: `dubbo-provider.xml` / `dubbo.xml` 中的 `<dubbo:service>` 元素
3. **接口继承检测**: 接口继承路径上存在 Dubbo 注解，且该类实现了该接口

**提取内容:**
- 接口全限定类名 (`interface` / `ref` 属性)
- 方法签名（方法名 + 参数类型 + 返回类型）
- 版本号 (`version` 属性)
- 超时 (`timeout` 属性)
- 分组 (`group` 属性)
- 源码文件路径 + 行号

### Consumer Side — 消费侧
提取本服务引用的外部 Dubbo 接口。

**触发条件（任一满足）:**
1. **注解检测**: 字段或 setter 方法上存在 `@Reference` / `@DubboReference` 注解
   - `@com.alibaba.dubbo.config.annotation.Reference`
   - `@org.apache.dubbo.config.annotation.Reference`
   - `@org.apache.dubbo.config.annotation.DubboReference`
2. **XML 配置检测**: `dubbo-consumer.xml` 中的 `<dubbo:reference>` 元素
3. **运行时引用检测**: `DubboReferenceConfig` 代码构建

**提取内容:**
- 引用的接口全限定类名
- 引用字段名 / 变量名
- 版本号 / 超时 / 分组
- 调用位置（源码文件路径 + 行号）

## Output Format
输出到 `output/raw/{service-name}/dubbo-provider.json` 和 `dubbo-consumer.json`，格式符合 `knowledge-graph.schema.json` 中 `InterfaceNode` 定义。

## Cross-Reference Matching
消费侧提取的 className 与提供侧的 className 匹配时，生成 `RpcEdge`。

## Known Edge Cases
- 同一个接口被多个服务引用时，需分别记录调用关系
- `version` 和 `group` 用于区分同名接口的不同实现
- 接口继承链可能存在多层，需递归解析
