# Provider 层

## 目标

Provider 层负责把不同大模型厂商的协议差异收敛成 OrbitPilot 可消费的统一结构。

执行层只关心：

- assistant 文本
- tool calls
- 原始响应
- 流式是否成功
- 失败码与响应体

## 当前 Provider 结构

### OpenAI Compatible Provider

文件：`core/provider/openai_provider.gd`

当前承载：

- OpenAI 兼容接口
- DeepSeek（作为 OpenAI Compatible 预设）

请求特征：

- Endpoint: `{base_url}/chat/completions`
- Header: `Authorization: Bearer <api_key>`
- Body: `model / messages / tools / stream`

解析重点：

- 从 `choices[0].message` 提取 assistant 文本。
- 从 `tool_calls` 提取函数调用。
- 流式场景下从 `choices[0].delta` 提取：
  - `content`
  - `tool_calls`

### Anthropic Provider

文件：`core/provider/anthropic_provider.gd`

请求特征：

- Endpoint: `{base_url}/v1/messages`
- Header: `x-api-key`、`anthropic-version`
- Body: `model / messages / tools / stream`

解析重点：

- 从 `content[]` 提取 `text` 与 `tool_use`。
- 流式场景下消费 `content_block_*` 事件。

## DeepSeek 接入方式

DeepSeek 当前不是独立 Provider，而是一个预设 Provider 配置。

默认配置定义在：`core/types.gd`

字段：

- `id`: `deepseek`
- `base_url`: `https://api.deepseek.com/v1`
- `model`: `deepseek-chat`
- `api_key_env`: `DEEPSEEK_API_KEY`

执行层映射：

- `plugin.gd` 中把 `deepseek` 映射到 `_openai_provider`

这意味着：

- UI 里选择 `deepseek`
- 执行时实际调用 `openai_provider.gd`
- 但配置来源、默认模型、环境变量读取是 DeepSeek 专属

## 统一接口

### 非流式

`send_chat(provider_config, messages, tools) -> Dictionary`

统一字段：

- `success`: `bool`
- `assistant_message`: `{ role, content }`
- `tool_calls`: `Array<Dictionary>`
- `raw`: 原始响应体
- `response_code`: HTTP 状态码（若可用）
- `body`: 失败时的响应体（若可用）

### 流式

`send_chat_stream(provider_config, messages, tools, event_callback, cancel_callback) -> Dictionary`

统一约束：

- Provider 层只负责协议解析与增量事件发出。
- UI 不直接消费 Provider，而是通过执行层事件回调消费。

## API Key 解析规则

1. 先读 Provider 配置中的 `api_key`
2. 若为空，读取 `api_key_env` 指定环境变量
3. 若仍为空，返回 `missing_api_key`

当前默认环境变量：

- OpenAI Compatible: `OPENAI_API_KEY`
- DeepSeek: `DEEPSEEK_API_KEY`
- Anthropic: `ANTHROPIC_API_KEY`

## 工具定义映射

当前执行链会把统一工具目录转换为 Provider 可接受的工具定义。

当前约束：

- 传给模型的 `tool.name` 使用短名，不直接使用 `local:...` 或 `remote:...` 完整 ID
- 完整工具 ID 放到 description 中辅助调试

原因：

- 某些 OpenAI Compatible 服务对函数名字符有更严格限制
- 直接把 `local:search_files` 这类 ID 作为函数名，可能触发 `400`

## 流式与回退

- 默认优先走流式。
- 流式失败且不是取消时，执行层允许回退到非流式一次。
- 流式完成后，主控必须清空 `_stream_preview`，避免 UI 出现重复 assistant 回复。

## 调试建议

当 UI 出现 `Request failed: http_error_status` 时，优先检查：

1. Provider 选择是否正确。
2. `base_url` 是否符合厂商要求。
3. `model` 是否存在。
4. API Key 是否有效。
5. 失败响应体里是否返回了厂商 message / detail 字段。
