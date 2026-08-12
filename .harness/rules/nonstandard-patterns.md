# Nonstandard RPC Pattern Detector

## Detection Target
识别标准注解/配置无法覆盖的非标 RPC 调用模式。本规则定义基础探测框架，具体新模式由 AI 发现并持久化。

## Base Scanners

### 1. HTTP Client Scanner
探测通过 HTTP 客户端库进行的非标准 HTTP 调用。

**触发类引用:**
- `org.springframework.web.client.RestTemplate`
- `okhttp3.OkHttpClient`
- `org.apache.http.client.HttpClient`
- `org.springframework.web.reactive.function.client.WebClient`

**触发方法调用:**
- `execute`, `exchange`, `getForObject`, `postForObject`, `newCall`

### 2. Message Queue Scanner
探测通过消息队列进行的异步调用。

**触发类引用:**
- `org.apache.kafka.clients.producer.KafkaProducer`
- `org.apache.kafka.clients.consumer.KafkaConsumer`
- `com.rabbitmq.client.Channel`
- `org.apache.rocketmq.client.producer.DefaultMQProducer`
- `org.apache.rocketmq.client.consumer.DefaultMQPushConsumer`
- `org.springframework.kafka.core.KafkaTemplate`
- `org.springframework.amqp.rabbit.core.RabbitTemplate`

**触发方法调用:**
- `send`, `publish`, `basicPublish`, `basicConsume`, `subscribe`, `convertAndSend`

### 3. Custom Socket/Netty Scanner
探测自定义 TCP/UDP 通信协议。

**触发类引用:**
- `io.netty.channel.Channel`
- `io.netty.bootstrap.ServerBootstrap`
- `io.netty.bootstrap.Bootstrap`
- `java.net.Socket`
- `java.nio.channels.SocketChannel`

**触发方法调用:**
- `connect`, `bind`, `writeAndFlush`, `read`

## Unknown Pattern Discovery (AI-Driven)

当基扫描器无法匹配但仍检测到代码引用了不确定的 RPC 库时，触发 AI 模式发现流程:

1. **代码片段提取**: 截取引用点上下文 50 行
2. **AI 分析** (`templates/analyze-pattern.md`): 判定是否为 RPC 调用，识别模式特征
3. **脚本生成** (`templates/generate-script.md`): 生成 bash 提取脚本
4. **验证门禁 GP1-5**: 沙箱执行 + 输出校验 + 召回率 + 回归检测
5. **持久化** (`templates/persist-rule.md`): 通过后写入 `.harness/extractors/<pattern>/` 和 `.harness/patterns/`

## Output Format
输出到 `output/raw/{service-name}/nonstandard.json`，使用 `NonstandardEdge` schema:
- `confidence` 字段标记识别置信度 (0-1)
- `pattern` 字段记录匹配到的代码模式描述
- `metadata.topic` 记录 MQ topic（如有）
- `metadata.hostPattern` 记录目标 URL 模式（如有）

## Acceptance Criteria
- 非标 RPC 输出为**服务级**粒度（无法保证方法级精度）
- 置信度由 AI 评估，低于 0.5 的标记为 `[UNCERTAIN]`
