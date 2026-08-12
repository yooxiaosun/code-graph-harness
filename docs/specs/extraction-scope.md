---
title: 提取范围真相源
purpose: 已纳入图谱的仓库清单语义 + 已支持协议模式清单（E4 持久化后同步更新）
version: v1.0.0
author: harness
status: Baseline
---

# 提取范围真相源

> 本文件是"图谱覆盖了什么"的真相源。机器配置在 `repos.yaml`，本文件记录其语义与演化历史。

## §1 仓库清单

| 服务 | 仓库地址 | 分支 | 协议范围 | 状态 |
|------|---------|------|---------|------|
| （暂无） | — | — | — | 待配置：请向 `repos.yaml` 的 `repos:` 段添加仓库 |

## §2 已支持协议模式

### 标准协议（静态注解/配置检测）

| 协议 | 提供侧特征 | 消费侧特征 | 提取器 |
|------|-----------|-----------|--------|
| dubbo | @DubboService / @Service | @DubboReference / @Reference | `.harness/extractors/dubbo/extract.sh` |
| sofarpc | @SofaService / GenericService | @SofaReference | `.harness/extractors/sofarpc/extract.sh` |
| grpc | BindableService / .proto | ManagedChannel / *Stub | `.harness/extractors/grpc/extract.sh` |
| rest | @RestController / @Path | @FeignClient / RestTemplate / WebClient | `.harness/extractors/rest/extract.sh` |

### 非标协议（模式扫描）

| 模式 | 检测特征 | 提取器 | 登记日期 |
|------|---------|--------|---------|
| http-client | RestTemplate/OkHttpClient/HttpClient/WebClient 调用 | `.harness/extractors/http-client/extract.sh` | 基线 |
| mq | Kafka/RabbitMQ/RocketMQ 生产消费 | `.harness/extractors/mq/extract.sh` | 基线 |
| socket | Netty ServerBootstrap/Bootstrap、java.net Socket | `.harness/extractors/custom/extract.sh` | 基线 |
| custom-unknown | 含 rpc/remote/connect/transport 的非标 import | `.harness/extractors/custom/extract.sh`（标记 [AI-REQUIRED]） | 基线 |

## §3 已知未覆盖（E4 放弃或待支持）

| 模式 | 原因 | 决策记录 |
|------|------|---------|
| （暂无） | — | — |

## §4 演化历史

| 日期 | 变更 | 任务编号 |
|------|------|---------|
| 2026-08-10 | 初始化真相源（基线 = repos.yaml 现有配置） | — |
