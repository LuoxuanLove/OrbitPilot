# OrbitPilot 文档索引

本文档索引用于描述当前 `addons/orbit_pilot` 的真实实现，而不是早期规划草案。

## 建议阅读顺序

1. `docs/概述.md`
2. `docs/架构/总体架构.md`
3. `docs/架构/分层职责.md`
4. `docs/模块/*`
5. `docs/协议/*`
6. `docs/开发/扩展指南.md`
7. `docs/测试/测试策略.md`
8. `tests/README.md`

## 文档结构

| 路径 | 说明 |
|---|---|
| `docs/概述.md` | 产品定位、版本边界、当前能力与非目标 |
| `docs/架构/总体架构.md` | 当前运行时入口、对象关系、主数据流 |
| `docs/架构/分层职责.md` | Workbench / Provider / Tool / Execution / Change 五层职责 |
| `docs/模块/Provider层.md` | OpenAI Compatible、DeepSeek、Anthropic 适配细节 |
| `docs/模块/远端MCP互通.md` | Remote MCP 的端点约定、工具发现、降级策略 |
| `docs/模块/本地工具与上下文索引.md` | Local Tools、Context Index、最小回归入口 |
| `docs/模块/执行链与审批.md` | 执行链、流式预览、ChangeSet 审批、取消语义 |
| `docs/协议/事件模型.md` | 执行事件结构与 UI 消费规则 |
| `docs/协议/流式通道.md` | SSE 实现、Provider 增量事件、回退与取消 |
| `docs/开发/扩展指南.md` | 扩展 Provider、工具、UI、会话管理的实施路径 |
| `docs/测试/测试策略.md` | 启动、Provider、MCP、审批、会话管理测试策略 |
| `tests/README.md` | 插件内最小自动回归说明 |

## 当前实现特别说明

当前文档中“实际生效”的 UI 入口为：

- `plugin.gd`
- `ui/orbit_dock.tscn`

说明：

- `plugin.gd` 是装配根，并内联了 `DockController`。
- `ui/orbit_dock.tscn` 当前是纯 UI 场景。
- `ui/orbit_dock.gd` 与 `ui/orbit_dock_controller.gd` 保留在仓库中，但不是当前主运行路径。

后续若要清理或重构 UI，先以 `plugin.gd` 中的 `DockController` 为准更新文档与代码。
