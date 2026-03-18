@tool
extends RefCounted

const ADAPTER_SCRIPT_PATH := "res://addons/orbit_pilot/core/provider/provider_adapter.gd"

var _adapter = null


func setup(host_node: Node) -> void:
	_ensure_adapter()
	if _adapter != null and _adapter.has_method("setup"):
		_adapter.call("setup", host_node)


func get_id() -> String:
	return "openai_compatible"


func send_chat(provider_config: Dictionary, messages: Array, tools: Array) -> Dictionary:
	if not _ensure_adapter():
		return {"success": false, "error": "adapter_unavailable"}
	var api_key := _resolve_api_key(provider_config)
	if api_key.is_empty():
		return {"success": false, "error": "missing_api_key"}

	var base_url := _normalize_chat_base_url(str(provider_config.get("base_url", "https://api.openai.com/v1")))
	var payload := {
		"model": str(provider_config.get("model", "gpt-4.1-mini")),
		"messages": messages,
		"stream": false,
	}
	if not tools.is_empty():
		payload["tools"] = _convert_tools(tools)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])
	var result_raw: Variant = await _adapter.call("_request_json", "%s/chat/completions" % base_url, HTTPClient.METHOD_POST, headers, JSON.stringify(payload))
	if not (result_raw is Dictionary):
		return {"success": false, "error": "invalid_adapter_response"}
	var result: Dictionary = result_raw
	if not bool(result.get("success", false)):
		return result

	var body: Variant = result.get("body", {})
	if not (body is Dictionary):
		return {"success": false, "error": "invalid_response_shape", "body": body}
	if not body.has("choices") or not (body["choices"] is Array) or body["choices"].is_empty():
		return {"success": false, "error": "missing_choices", "body": body}

	var first_choice: Dictionary = body["choices"][0]
	var message: Dictionary = first_choice.get("message", {})
	var assistant_content := str(message.get("content", ""))
	var tool_calls: Variant = message.get("tool_calls", [])
	return {
		"success": true,
		"assistant_message": {"role": "assistant", "content": assistant_content},
		"tool_calls": tool_calls if tool_calls is Array else [],
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

	var base_url := _normalize_chat_base_url(str(provider_config.get("base_url", "https://api.openai.com/v1")))
	var payload := {
		"model": str(provider_config.get("model", "gpt-4.1-mini")),
		"messages": messages,
		"stream": true,
	}
	if not tools.is_empty():
		payload["tools"] = _convert_tools(tools)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])

	var state := {
		"assistant_content": "",
		"tool_calls": [],
	}
	var sse_raw: Variant = await _adapter.call(
		"_stream_sse_json",
		"%s/chat/completions" % base_url,
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

	return {
		"success": true,
		"assistant_message": {"role": "assistant", "content": str(state["assistant_content"])},
		"tool_calls": state["tool_calls"],
		"raw": {},
		"streamed": true,
	}


func _on_sse_event(event: Dictionary, state: Dictionary, event_callback: Callable) -> void:
	var payload_raw: Variant = event.get("json", {})
	if not (payload_raw is Dictionary):
		return
	var payload: Dictionary = payload_raw
	var choices_raw: Variant = payload.get("choices", [])
	if not (choices_raw is Array):
		return
	var choices: Array = choices_raw
	if choices.is_empty():
		return
	var first_raw: Variant = choices[0]
	if not (first_raw is Dictionary):
		return
	var first: Dictionary = first_raw
	var delta_raw: Variant = first.get("delta", {})
	if not (delta_raw is Dictionary):
		return
	var delta: Dictionary = delta_raw

	var text_delta := str(delta.get("content", ""))
	if not text_delta.is_empty():
		state["assistant_content"] += text_delta
		if event_callback.is_valid():
			event_callback.call({"kind": "message_delta", "delta": text_delta})

	var tool_deltas: Variant = delta.get("tool_calls", [])
	if tool_deltas is Array:
		for tool_delta in tool_deltas:
			if tool_delta is Dictionary:
				_merge_tool_delta(state, tool_delta, event_callback)


func _merge_tool_delta(state: Dictionary, tool_delta: Dictionary, event_callback: Callable) -> void:
	if not (tool_delta is Dictionary):
		return
	var index := int(tool_delta.get("index", 0))
	var tool_calls: Array = state["tool_calls"]
	while tool_calls.size() <= index:
		tool_calls.append({
			"id": "",
			"type": "function",
			"function": {"name": "", "arguments": ""},
		})
	var target: Dictionary = tool_calls[index]
	if tool_delta.has("id"):
		target["id"] = str(tool_delta.get("id", ""))
	if tool_delta.has("type"):
		target["type"] = str(tool_delta.get("type", "function"))
	var fn_delta: Variant = tool_delta.get("function", {})
	var fn: Dictionary = target.get("function", {})
	if fn_delta is Dictionary:
		if fn_delta.has("name"):
			fn["name"] = str(fn_delta.get("name", ""))
		if fn_delta.has("arguments"):
			fn["arguments"] = str(fn.get("arguments", "")) + str(fn_delta.get("arguments", ""))
		target["function"] = fn
	target["index"] = index
	tool_calls[index] = target
	state["tool_calls"] = tool_calls
	if event_callback.is_valid():
		var fn_name := str(fn.get("name", ""))
		var args_delta := ""
		if fn_delta is Dictionary:
			args_delta = str(fn_delta.get("arguments", ""))
		event_callback.call({
			"kind": "tool_call_delta",
			"tool": fn_name,
			"arguments_delta": args_delta,
		})


func _convert_tools(tools: Array) -> Array:
	var out: Array = []
	for tool in tools:
		if not (tool is Dictionary):
			continue
		if str(tool.get("type", "")) == "function":
			out.append(tool)
			continue
		out.append({
			"type": "function",
			"function": {
				"name": str(tool.get("name", "")),
				"description": str(tool.get("description", "")),
				"parameters": tool.get("input_schema", {"type": "object", "properties": {}}),
			}
		})
	return out


func _resolve_api_key(config: Dictionary) -> String:
	var direct := str(config.get("api_key", "")).strip_edges()
	if not direct.is_empty():
		return direct
	var env_key := str(config.get("api_key_env", "OPENAI_API_KEY")).strip_edges()
	if env_key.is_empty():
		return ""
	return OS.get_environment(env_key).strip_edges()


func _normalize_chat_base_url(raw_url: String) -> String:
	var base_url := raw_url.strip_edges().trim_suffix("/")
	if base_url.is_empty():
		base_url = "https://api.openai.com/v1"
	if base_url.ends_with("/chat/completions"):
		base_url = base_url.trim_suffix("/chat/completions")
	if base_url == "https://api.deepseek.com":
		return "%s/v1" % base_url
	return base_url


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
