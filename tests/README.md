# OrbitPilot 最小自动回归

## 目标

提供一个可在插件内触发的最小自动回归套件，用于快速确认核心路径没有被 UI 或执行链改动破坏。

## 入口

通过本地工具调用：

- `local:run_regression_suite`

可在 OrbitPilot 的 Tools 页面执行：

- Tool: `local:run_regression_suite`
- Args: `{}`

## 当前覆盖

- `change_set_lifecycle`
- `propose_blocks_mutating`
- `cancel_run_semantics`
- `tool_catalog_prefix`

## 输出结构

返回 JSON：

- `total`
- `passed`
- `failed`
- `items[]`

每个 case 包含：

- `name`
- `passed`
- `elapsed_ms`
- `detail`
- `data`

## 使用建议

适用场景：

- UI 改动后快速冒烟
- Provider / ToolRouter / ChangeSet 修改后先做基础回归
- 启动期验证插件是否还处于可用状态

限制：

- 不依赖远端 MCP
- 不替代完整集成测试
- 不覆盖所有 UI 交互细节
