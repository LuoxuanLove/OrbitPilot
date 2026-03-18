@tool
extends RefCounted

const ADAPTER_SCRIPT_PATH := "res://addons/orbit_pilot/core/provider/provider_adapter.gd"

var _adapter = null


func setup(host_node: Node) -> void:
	_ensure_adapter()
	if _adapter != null and _adapter.has_method("setup"):
		_adapter.call("setup", host_node)


func get_id() -> String:
	return "anthropic"


func send_chat(provider_config: Dictionary, messages: Array, tools: Array) -> Dictionary:
	if not _ensure_adapter():
		return {"success": false, "error": "adapter_unavailable"}
	var api_key := _resolve_api_key(provider_config)
	if api_key.is_empty():
		return {"success": false, "error": "missing_api_key"}

	var base_url := str(provider_config.get("base_url", "https://api.anthropic.com")).trim_suffix("/")
	var payload := {
		"model": str(provider_config.get("model", "claude-3-5-sonnet-latest")),
		"max_tokens": 1024,
		"messages": _convert_messages(messages),
	}
	if not tools.is_empty():
		payload["tools"] = _convert_tools(tools)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-api-key: %s" % api_key,
		"anthropic-version: %s" % str(provider_config.get("anthropic_version", "2023-06-01")),
	])
	var result_raw: Variant = await _adapter.call("_request_json", "%s/v1/messages" % base_url, HTTPClient.METHOD_POST, headers, JSON.stringify(payload))
	if not (result_raw is Dictionary):
		return {"success": false, "error": "invalid_adapter_response"}
	var result: Dictionary = result_raw
	if not bool(result.get("success", false)):
		return result

	var body: Variant = result.get("body", {})
	if not (body is Dictionary):
		return {"success": false, "error": "invalid_response_shape", "body": body}
	if not body.has("content") or not (body["content"] is Array):
		return {"success": false, "error": "missing_content", "body": body}

	var text_parts: Array[String] = []
	var tool_calls: Array[Dictionary] = []
	for part in body["content"]:
		if not (part is Dictionary):
			continue
		var part_type := str(part.get("type", ""))
		if part_type == "text":
			text_parts.append(str(part.get("text", "")))
		elif part_type == "tool_use":
			tool_calls.append({
				"id": str(part.get("id", "")),
				"type": "function",
				"function": {
					"name": str(part.get("name", "")),
					"arguments": JSON.stringify(part.get("input", {})),
				}
			})

	return {
		"success": true,
		"assistant_message": {"role": "assistant", "content": "\n".join(text_parts)},
		"tool_calls": tool_calls,
		"raw": body,
		"streamed": false,
	}


func send_chat_stream(
	provider_config: Dictionary,
	messages: Array,
	tools: Array,
	event_callback: Callable,
	cancel_callback: Callable
) -> Dictionary:
	if not _ensure_adapter():
		return {"success": false, "error": "adapter_unavailable"}
	var api_key := _resolve_api_key(provider_config)
	if api_key.is_empty():
		return {"success": false, "error": "missing_api_key"}

	var base_url := str(provider_config.get("base_url", "https://api.anthropic.com")).trim_suffix("/")
	var payload := {
		"model": str(provider_config.get("model", "claude-3-5-sonnet-latest")),
		"max_tokens": 1024,
		"messages": _convert_messages(messages),
		"stream": true,
	}
	if not tools.is_empty():
		payload["tools"] = _convert_tools(tools)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-api-key: %s" % api_key,
		"anthropic-version: %s" % str(provider_config.get("anthropic_version", "2023-06-01")),
	])
	var state := {
		"assistant_content": "",
		"tool_blocks": {},
	}
	var sse_raw: Variant = await _adapter.call(
		"_stream_sse_json",
		"%s/v1/messages" % base_url,
		headers,
		JSON.stringify(payload),
		Callable(self, "_on_sse_event").bind(state, event_callback),
		cancel_callback,
		60.0
	)
	if not (sse_raw is Dictionary):
		return {"success": false, "error": "invalid_adapter_stream_response"}
	var sse_res: Dictionary = sse_raw
	if not bool(sse_res.get("success", false)):
		return sse_res

	var tool_blocks: Dictionary = state.get("tool_blocks", {})
	var tool_calls := _finalize_tool_calls(tool_blocks)
	return {
		"success": true,
		"assistant_message": {"role": "assistant", "content": str(state["assistant_content"])},
		"tool_calls": tool_calls,
		"raw": {},
		"streamed": true,
	}


func _on_sse_event(event: Dictionary, state: Dictionary, event_callback: Callable) -> void:
	var payload_raw: Variant = event.get("json", {})
	if not (payload_raw is Dictionary):
		return
	var payload: Dictionary = payload_raw
	var event_type := str(payload.get("type", ""))
	match event_type:
		"content_block_delta":
			_handle_delta(payload, state, event_callback)
		"content_block_start":
			_handle_block_start(payload, state)
		_:
			pass


func _handle_delta(payload: Dictionary, state: Dictionary, event_callback: Callable) -> void:
	var delta_raw: Variant = payload.get("delta", {})
	if not (delta_raw is Dictionary):
		return
	var delta: Dictionary = delta_raw
	var delta_type := str(delta.get("type", ""))
	if delta_type == "text_delta":
		var text := str(delta.get("text", ""))
		state["assistant_content"] += text
		if event_callback.is_valid() and not text.is_empty():
			event_callback.call({"kind": "message_delta", "delta": text})
	elif delta_type == "input_json_delta":
		var idx := int(payload.get("index", 0))
		var blocks: Dictionary = state.get("tool_blocks", {})
		if not blocks.has(idx):
			blocks[idx] = {"id": "", "name": "", "arguments_json": ""}
		var blk: Dictionary = blocks[idx]
		blk["arguments_json"] = str(blk.get("arguments_json", "")) + str(delta.get("partial_json", ""))
		blocks[idx] = blk
		state["tool_blocks"] = blocks
		if event_callback.is_valid():
			event_callback.call({
				"kind": "tool_call_delta",
				"tool": str(blk.get("name", "")),
				"arguments_delta": str(delta.get("partial_json", "")),
			})


func _handle_block_start(payload: Dictionary, state: Dictionary) -> void:
	var block_raw: Variant = payload.get("content_block", {})
	if not (block_raw is Dictionary):
		return
	var block: Dictionary = block_raw
	if str(block.get("type", "")) != "tool_use":
		return
	var idx := int(payload.get("index", 0))
	var blocks: Dictionary = state.get("tool_blocks", {})
	blocks[idx] = {
		"id": str(block.get("id", "")),
		"name": str(block.get("name", "")),
		"arguments_json": "",
	}
	state["tool_blocks"] = blocks


func _finalize_tool_calls(tool_blocks: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for idx in tool_blocks.keys():
		var blk: Dictionary = tool_blocks[idx]
		out.append({
			"id": str(blk.get("id", "")),
			"type": "function",
			"function": {
				"name": str(blk.get("name", "")),
				"arguments": str(blk.get("arguments_json", "{}")),
			}
		})
	return out


func _convert_messages(messages: Array) -> Array:
	var out: Array = []
	for msg in messages:
		if not (msg is Dictionary):
			continue
		var role := str(msg.get("role", "user"))
		var content: Variant = msg.get("content", "")
		out.append({
			"role": role,
			"content": [{"type": "text", "text": str(content)}],
		})
	return out


func _convert_tools(tools: Array) -> Array:
	var out: Array = []
	for tool in tools:
		if not (tool is Dictionary):
			continue
		out.append({
			"name": str(tool.get("name", "")),
			"description": str(tool.get("description", "")),
			"input_schema": tool.get("input_schema", {"type": "object", "properties": {}}),
		})
	return out


func _resolve_api_key(config: Dictionary) -> String:
	var direct := str(config.get("api_key", "")).strip_edges()
	if not direct.is_empty():
		return direct
	var env_key := str(config.get("api_key_env", "ANTHROPIC_API_KEY")).strip_edges()
	if env_key.is_empty():
		return ""
	return OS.get_environment(env_key).strip_edges()


func _ensure_adapter() -> bool:
	if _adapter != null:
		return true
	var script_res: Variant = load(ADAPTER_SCRIPT_PATH)
	if not (script_res is Script):
		return false
	var script_obj: Script = script_res
	if not script_obj.can_instantiate():
		return false
	_adapter = script_obj.new()
	return _adapter != null
