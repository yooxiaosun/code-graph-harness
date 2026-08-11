# Business Tag Detector

## Detection Target
从多项代码来源中提取业务领域标签，附加到服务节点和接口节点。

## Tag Sources（5 链并行提取）

### 1. Custom Annotations — 自定义注解
扫描类和方法上的自定义注解，提取业务语义。

**匹配规则:**
- 注解包路径匹配 `annotation_prefixes` 配置（`com.*.annotation.*`）
- 注解类名作为标签（如 `@OrderBiz` → `order-biz`）
- 注解中的 `value` / `tag` 属性值直接作为标签

### 2. Package Names — 包名推断领域
从 Java 包路径中推断业务领域归属。

**匹配规则:**
- 匹配 `package_domain_mapping` 配置
- 例如: `com.example.order.service` → `order-domain`
- 多级匹配优先级: 深层包名 > 浅层包名

### 3. Javadoc — 注释关键词
从类和方法的 Javadoc 注释中提取业务关键词。

**提取策略:**
- 提取 `@since`、`@author`、`@see` 标签内容
- 提取第一句自然语言描述中的关键名词
- 过滤通用词（如 "the", "this", "class", "method"）
- 对中文注释进行关键词分词

### 4. Method/Class Names — 命名语义
从类名和方法名中推断业务语义。

**提取规则:**
- 驼峰命名拆分: `createOrder` → `["create", "order"]`
- 类名后缀映射: `*Service` → 服务, `*Controller` → 控制器
- 包名 + 类名组合: `order.controller.OrderController` → `order`

### 5. Configuration Files — 配置文件
从 `application.yml` / `.properties` / XML 配置中提取业务标识。

**提取来源:**
- `application.yml`: `spring.application.name`
- `pom.xml`: `artifactId`、`name`
- XML: `<dubbo:application name="...">`
- `.properties`: `app.biz.tag=...`

## Tag Merging Rules
- 5 链并行提取 → 汇总 → 去重
- 同义合并: `order` / `order-domain` / `order-module` → `order-domain`
- 优先级: 自定义注解 > 配置文件 > 包名 > 方法名 > Javadoc

## Output Integration
标签写入节点的 `tags` 数组字段:
```json
{"id": "order-service", "tags": ["order-domain", "e-commerce", "high-throughput"]}
```
