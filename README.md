# OrbitPilot

OrbitPilot 是一个运行在 Godot 编辑器内部的独立 Agent 工作台插件，目标是在编辑器内提供类 Codex / Claude Code 的开发体验，同时通过可选远端 MCP 与外部工具互通。

## 当前实现状态

当前版本已经落地的能力：

- 独立插件入口、独立设置持久化、独立 Dock 工作台。
- Provider 接入：OpenAI Compatible、DeepSeek（走 OpenAI Compatible 协议）、Anthropic。
- 远端 MCP Client：HTTP `GET /health`、`GET /api/tools`、`POST /mcp`。
- 本地工具：文件检索、文本检索、文件读取、上下文聚合、回归测试、ChangeSet 管理。
- 执行链：`analyze`、`propose`、`apply_with_approval`。
- ChangeSet 审批：创建、预览、审批应用、拒绝。
- 会话管理：独立 Sessions 页面、Active / Archived 分组、归档、删除归档、重命名。
- 最小自动回归：`local:run_regression_suite`。

## 当前运行时入口

当前实际运行时入口是：

- [plugin.gd](/e:/Project/Mechoes/addons/orbit_pilot/plugin.gd)
- [orbit_dock.tscn](/e:/Project/Mechoes/addons/orbit_pilot/ui/orbit_dock.tscn)

说明：

- `orbit_dock.tscn` 当前作为纯 UI 场景使用。
- Dock 的 UI 控制逻辑当前内联在 `plugin.gd` 内部的 `DockController` 中。
- `ui/orbit_dock.gd` 与 `ui/orbit_dock_controller.gd` 保留在仓库中，但不是当前主运行路径，后续若清理需先核对引用链。

## 安装

将目录放入：

```text
addons/orbit_pilot
```

然后在 `Project Settings > Plugins` 启用 `OrbitPilot`。

## Provider 配置

### OpenAI Compatible

默认：

- Base URL: `https://api.openai.com/v1`
- Model: `gpt-4.1-mini`
- Env: `OPENAI_API_KEY`

### DeepSeek

默认：

- Base URL: `https://api.deepseek.com`
- Model: `deepseek-chat`
- Env: `DEEPSEEK_API_KEY`

说明：

- DeepSeek 在 OrbitPilot 中按 OpenAI Compatible Provider 处理。
- 仅需在界面里选择 `deepseek`，其余调用链与 OpenAI Compatible 共用实现。

### Anthropic

默认：

- Base URL: `https://api.anthropic.com`
- Model: `claude-3-5-sonnet-latest`
- Env: `ANTHROPIC_API_KEY`

## 远端 MCP 配置约束

OrbitPilot 的 Remote MCP endpoint 必须填写“服务根地址”，而不是 `/mcp` 路径。

正确示例：

```text
http://127.0.0.1:3000
```

错误示例：

```text
http://127.0.0.1:3000/mcp
```

原因：

- 健康检查会自动请求 `{endpoint}/health`
- 工具发现会自动请求 `{endpoint}/api/tools`
- 工具调用会自动请求 `{endpoint}/mcp`

如果配置成 `/mcp`，最终会请求 `/mcp/health` 和 `/mcp/api/tools`，通常返回 `404`。

## 文档入口

- [docs/README.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/README.md)
- [docs/概述.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/概述.md)
- [docs/架构/总体架构.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/架构/总体架构.md)
- [docs/架构/分层职责.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/架构/分层职责.md)
- [docs/模块/Provider层.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/模块/Provider层.md)
- [docs/模块/远端MCP互通.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/模块/远端MCP互通.md)
- [docs/模块/本地工具与上下文索引.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/模块/本地工具与上下文索引.md)
- [docs/模块/执行链与审批.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/模块/执行链与审批.md)
- [docs/协议/事件模型.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/协议/事件模型.md)
- [docs/协议/流式通道.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/协议/流式通道.md)
- [docs/开发/扩展指南.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/开发/扩展指南.md)
- [docs/测试/测试策略.md](/e:/Project/Mechoes/addons/orbit_pilot/docs/测试/测试策略.md)
- [tests/README.md](/e:/Project/Mechoes/addons/orbit_pilot/tests/README.md)
