# 远端 MCP 互通

## 设计原则

- 远端 MCP 是可选能力源，不是启动前置依赖。
- OrbitPilot 不依赖特定 Godot 插件源码，只依赖 HTTP 约定。
- 远端失败时必须自动降级，不影响本地工具与聊天页启动。

## 当前客户端实现

文件：`core/remote/remote_mcp_client.gd`

### 健康检查

- `GET {endpoint}/health`

### 工具发现

- `GET {endpoint}/api/tools`

### 工具调用

- `POST {endpoint}/mcp`
- 请求体使用 JSON-RPC：`tools/call`

## 配置约束

`Remote MCP endpoint` 必须填写服务根地址，而不是 `/mcp` 路径。

正确：

```text
http://127.0.0.1:3000
```

错误：

```text
http://127.0.0.1:3000/mcp
```

错误原因：

- OrbitPilot 会自己拼接 `/health`、`/api/tools`、`/mcp`
- 如果用户输入 `/mcp`，实际请求会变成：
  - `/mcp/health`
  - `/mcp/api/tools`
- 这种路径通常返回 `404`

## 工具统一目录

文件：`core/tools/tool_catalog.gd`

当前规范：

- 本地工具 ID：`local:{tool_name}`
- 远端工具 ID：`remote:{server_id}:{tool_name}`

作用：

- 避免本地与远端工具重名冲突
- 便于日志审计和问题回溯

## 路由策略

文件：`core/tools/tool_router.gd`

当前策略：

- 若模型返回完整前缀 ID，直接执行。
- 若模型只返回短工具名，按路由策略推断。
- 默认策略：
  - 读取类动作优先本地
  - 写入类动作允许优先远端

## 当前兼容性说明

当前推荐互通对象是现有的 Godot .NET MCP HTTP 服务，但 OrbitPilot 不把它当特殊依赖。

只要远端服务满足以下三点即可：

1. `GET /health`
2. `GET /api/tools`
3. `POST /mcp` 支持 `tools/call`

## 失败处理

### 远端 endpoint 为空

行为：

- 清空该 server 的远端工具
- 状态记录为 `remote_endpoint_empty`

### 健康检查失败

行为：

- 写入 `_remote_health`
- 工具发现仍会继续尝试一次，以便获得更具体错误

### 工具发现失败

行为：

- 清空该 server 的远端工具
- 记录 `remote_tools_error:{server_id}:{error}`

### 工具调用失败

行为：

- 将错误结构返回给执行层或 Tools 页面
- 不影响插件存活

## 开发建议

扩展远端互通时优先保持：

- endpoint 语义稳定
- 返回结构容错
- 工具 ID 前缀稳定
- 无远端时的降级体验稳定
