# gRPC Interface Detector

## Detection Target
从 `.proto` 文件和 Java 源码中提取 gRPC 服务定义和调用关系。

## Detection Rules

### Provider Side — 提供侧

**触发条件（任一满足）:**
1. **Proto 文件检测**: 扫描 `src/main/proto/**/*.proto` 中的 `service` 和 `rpc` 定义
   - 提取 `package` 名 + `service` 名 + `rpc` 方法
   - rpc 方法的 `stream` 修饰（一元 / 服务端流 / 客户端流 / 双向流）
2. **Java 实现检测**: 实现 `io.grpc.BindableService` 接口的类
   - 查找到对应的 `.proto` 定义后提取接口信息
3. **Server 启动检测**: `io.grpc.ServerBuilder` / `Server` 构建和启动代码

**提取内容:**
- 完整 gRPC 服务名 (`package.ServiceName`)
- 每个 rpc 方法名、请求类型、响应类型、stream 模式
- Java 实现类名
- Proto 文件路径 + 行号

### Consumer Side — 消费侧

**触发条件（任一满足）:**
1. **Channel 创建检测**: `io.grpc.ManagedChannel` / `ManagedChannelBuilder` 创建
   - 提取目标地址和端口
2. **Stub 创建检测**: `newBlockingStub` / `newFutureStub` / `newStub` 调用
   - 提取使用的 stub 类型
3. **抽象类引用**: 字段类型为 `AbstractBlockingStub` / `AbstractFutureStub` / `AbstractStub`

**提取内容:**
- 目标 gRPC 服务名
- Stub 类型 (blocking / future / async)
- 调用位置（源码路径 + 行号）

## Proto File Parsing

```
syntax = "proto3";
package com.example.user;

service UserService {
  rpc GetUser (GetUserRequest) returns (GetUserResponse);
  rpc ListUsers (ListUsersRequest) returns (stream User);
  rpc UpdateUsers (stream UpdateUserRequest) returns (UpdateUserResponse);
}
```

解析结果:
- service: `com.example.user.UserService`
- rpc: `GetUser(GetUserRequest) -> GetUserResponse` (unary)
- rpc: `ListUsers(ListUsersRequest) -> stream User` (server-streaming)
- rpc: `UpdateUsers(stream UpdateUserRequest) -> UpdateUserResponse` (client-streaming)

## Output Format
输出到 `output/raw/{service-name}/grpc-provider.json` 和 `grpc-consumer.json`，`protocol` 字段值为 `"grpc"`。
