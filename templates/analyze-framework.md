# Framework Analysis — 仓库框架指纹分析（D1 决策点）

## Context
你是 Harness 框架分析者，承担 v2 架构的 **D1 决策点**：仓库克隆完成后、提取器执行前，
按本模板自主分析仓库的框架指纹，产出提取计划。产出物受 `schemas/profile.schema.yaml`
约束，并由 `scripts/gates/GE2.5-framework-analysis.sh` 验收（G-E2.5）。

## Input
- 仓库路径：`{repo_path}`
- 服务名：`{service_name}`
- 可用提取器清单（extraction_plan 只能从中选择）：
  `dubbo / sofarpc / grpc / rest / http-client / mq / custom / tags`

## 五维度分析清单（MUST 逐一过一遍，无信号也要记录）

| # | 维度 | 检查对象 | 典型信号示例 |
|---|------|---------|-------------|
| 1 | 构建依赖 | pom.xml / build.gradle / go.mod | dubbo、sofa-rpc、grpc、spring-web、netty、rocketmq/kafka 客户端 |
| 2 | 声明注解 | Java 源码注解扫描 | @DubboService/@Service(dubbo)、@SofaService、@GrpcService、@RestController/@RequestMapping |
| 3 | XML 配置 | spring/*.xml、META-INF | `<dubbo:service>`、`<sofa:service>`、bean 暴露配置 |
| 4 | 代码模式 | import 与调用模式 | OkHttp/HttpClient/RestTemplate 调用、MQ Producer/Consumer、Netty ServerBootstrap |
| 5 | 配置文件 | application.yml/properties、bootstrap.yml | 注册中心配置、协议端口、MQ broker 配置 |

## 置信度评级规则（MUST）

| confidence | 判定标准 |
|------------|---------|
| high | ≥2 个独立维度命中（如依赖 + 注解同时命中） |
| medium | 单维度命中，但证据直接明确（如 pom.xml 明确引入 dubbo） |
| low | 仅间接信号（如只有注册中心配置，无服务声明） |
| none | 该协议确认不存在（明确排除，可作为 skip 依据） |

## 声明风格分类（declaration_style）

`annotation`（注解声明）/ `xml`（XML 配置声明）/ `code`（纯代码 API）/ `config`（配置文件驱动）

## 禁止（MUST NOT）

- 不得修改仓库内任何文件（严格只读分析）
- 不得解析业务逻辑（只识别框架信号，不读业务语义）
- 不得猜测——每个 medium+ 信号必须附 ≥1 条 review_basis（文件路径 + 具体证据）
- 资源上限：单仓库分析 ≤500 文件、≤30 秒；超限以已扫描证据为准并记录
- 无任何框架信号时不得虚构，标记 `UNKNOWN-STACK` 并全部进入 unknowns

## Output 1 — `output/analysis/{service_name}-profile.yaml`

```yaml
service: {service_name}
analyzed_at: {ISO8601}
framework_signals:
  - protocol: dubbo            # 协议名（提取器清单内）或 UNKNOWN-STACK
    confidence: high           # high / medium / low / none
    declaration_style: annotation   # annotation / xml / code / config
    review_basis:
      - "pom.xml:L42 引入 org.apache.dubbo:dubbo:3.x"
      - "com/example/OrderService.java:L12 @DubboService"
extraction_plan:
  extractors: [dubbo, rest, http-client, custom, tags]   # 只列置信度 medium+ 的协议对应提取器 + 恒跑项（custom/tags）
  skip_reason: "sofarpc/grpc/mq 无依赖与注解信号（confidence=none）"
unknowns:
  - signal: "import io.xxx.unknown.RpcClient"
    files: ["com/example/LegacyClient.java"]
    risk: "可能存在未覆盖的 RPC 框架，建议 E4 关注"
```

## Output 2 — `output/analysis/{service_name}-profile-review.md`（自审报告）

必含三节：
1. **分析范围**：扫描了哪些维度、文件数、是否触及资源上限
2. **决策记录**：每个协议的置信度结论与依据（对应 review_basis）
3. **覆盖完整度自评**：未覆盖的盲区与风险

## Profile 在 v2.1 架构中的角色 (Q-Final=A)

本模板产出的 profile.yaml 是**协议级印证信号**, 不是节点级独立印证源：
- 节点级印证 (node.confidence 起点) = bash ∩ AI 两方独立获取信息后取交集
- 协议级加权 = profile.{proto}.confidence 在节点级起点上做档位调整

具体加权规则见 `templates/ai-analysis-harness.md §7`。

本模板无需修改产出格式, 但分析时需注意：
- 当 `confidence: none` 时, 后续任何节点若仍被 bash 或 AI 找到, 将被强制降级
- 当 `confidence: high` 时, 后续节点可被协议级加权 +1 档

## Gate
产出后运行：`bash scripts/gates/GE2.5-framework-analysis.sh output/analysis/{service_name}-profile.yaml output/analysis/{service_name}-profile-review.md`
- exit 0 → 按 extraction_plan 精准提取
- exit 2 → 部分失败，警告 + 回退全部提取器
- exit 1 → 完全失败，静默回退全部提取器（= 当前行为）
