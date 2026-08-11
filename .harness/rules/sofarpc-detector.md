# SOFARPC Interface Detector

## Detection Target
从 Java 源码中提取 SOFARPC (Ant Financial) 服务提供者和消费者的接口定义。

## Detection Rules

### Provider Side — 提供侧

**触发条件（任一满足）:**
1. **注解检测**: 类或接口上存在 SOFARPC 注解
   - `@com.alipay.sofa.runtime.api.annotation.SofaService`
   - `@com.alipay.sofa.runtime.api.annotation.SofaServiceBinding`
   - 实现 `com.alipay.sofa.rpc.api.GenericService` 接口
2. **XML 配置检测**: SOFARPC XML 配置中的 `<sofa:service>` 元素
   - 搜索 `*sofarpc*.xml` / `*sofa-rpc*.xml`
3. **API 编程方式**: `com.alipay.sofa.rpc.config.ServerConfig` + `ServiceConfig` 代码构建

**提取内容:**
- 接口全限定类名
- 方法签名
- 协议类型 (bolt / rest / dubbo / h2c / http)
- 唯一 ID (`uniqueId` 属性)
- 源码路径 + 行号

### Consumer Side — 消费侧

**触发条件（任一满足）:**
1. **注解检测**: 字段上存在 `@SofaReference` / `@SofaReferenceBinding`
2. **XML 配置检测**: `<sofa:reference>` 元素
3. **API 编程方式**: `com.alipay.sofa.rpc.config.ConsumerConfig` + `ReferenceConfig`

**提取内容:**
- 引用的接口全限定类名
- 协议类型
- 唯一 ID (`uniqueId`)
- 调用位置

## Output Format
输出到 `output/raw/{service-name}/sofarpc-provider.json` 和 `sofarpc-consumer.json`，`protocol` 字段值为 `"sofarpc"`。

## Special Notes
- SOFARPC 支持多协议同时暴露，需记录每种协议的 binding
- `uniqueId` 是 SOFARPC 区分同接口多实现的关键字段
- `generic` 调用模式需特别标注
