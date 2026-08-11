# REST API Detector

## Detection Target
从 Java Spring MVC / JAX-RS / Spring Cloud Feign 源码中提取 REST API 接口定义和调用关系。包括跨服务调用和服务内部跨模块调用。

## Detection Rules

### Provider Side — 提供侧

**触发条件（任一满足）:**
1. **Spring MVC 注解**: 类上存在 `@RestController` + 方法上存在 HTTP method mapping
   - `@RequestMapping(path="/api/users")`
   - `@GetMapping("/api/users/{id}")`
   - `@PostMapping("/api/users")`
   - `@PutMapping("/api/users/{id}")`
   - `@DeleteMapping("/api/users/{id}")`
   - `@PatchMapping("/api/users/{id}")`
2. **JAX-RS 注解**: 类上存在 `@Path` + 方法上存在 `@GET/@POST/@PUT/@DELETE`
   - `javax.ws.rs.*` 或 `jakarta.ws.rs.*` 包

**提取内容:**
- HTTP 方法 + URL 路径模板
- 方法签名（参数 + 返回类型）
- 类全限定名 + 方法名
- `@RequestMapping` 上的 produces/consumes 媒体类型
- 源码路径 + 行号

### Consumer Side — 消费侧（跨服务 + 内部）

**跨服务调用:**
1. **Feign Client 检测**: `@FeignClient` 注解的接口
   - `@FeignClient(name="user-service", url="http://user-service:8080")`
   - 提取: 服务名 + URL + 接口方法 + HTTP 路径
2. **RestTemplate 调用**: `RestTemplate` 的 HTTP 调用方法
   - `restTemplate.exchange("http://user-service/api/users/{id}", ...)`
   - `restTemplate.getForObject("http://user-service/api/users", ...)`
   - `restTemplate.postForObject("http://user-service/api/users", ...)`
   - 提取: 目标 URL + HTTP 方法 + 调用位置
3. **WebClient 调用**: Spring WebFlux 的 `WebClient`
   - `.get().uri("http://user-service/api/users")`
   - 提取: 目标 URL + HTTP 方法 + 调用位置
4. **OkHttp/Apache HttpClient**: 非 Spring 标准的 HTTP 客户端
   - `okhttp3.OkHttpClient.newCall(...)`
   - `org.apache.http.client.HttpClient.execute(...)`

**内部跨模块调用:**
- 同一服务不同 Maven 模块间的 `@FeignClient` / `RestTemplate` 调用
- 搜索本仓库内其他 module 的 HTTP 调用模式

**提取内容:**
- 目标服务名 / URL 模式
- HTTP 方法
- 调用位置（源码路径 + 行号）
- 是否为内部调用标记

## Output Format
输出到 `output/raw/{service-name}/rest-provider.json` 和 `rest-consumer.json`，`protocol` 字段值为 `"rest"`。

## Special Notes
- `@FeignClient` 的 `name` 字段优先作为目标服务标识
- URL 模板中的变量需保留原始形式（如 `{id}`）
- 内部调用需标记 `metadata.internal=true`
