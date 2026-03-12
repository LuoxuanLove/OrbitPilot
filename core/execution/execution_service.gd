@tool
extends RefCounted

const OrbitTypes = preload("res://addons/orbit_pilot/core/types.gd")

var _providers: Dictionary = {}
var _tool_router
var _cancelled_runs: Dictionary = {}


func setup(providers: Dictionary, tool_router) -> void:
	_providers = providers
	_tool_router = tool_router


func execute_turn(
	policy: String,
	provider_id: String,
	provider_config: Dictionary,
	messages: Array,
	available_tools: Array,
	run_id: String = "",
	event_callback: Callable = Callable()
) -> Dictionary:
	if not _providers.has(provider_id):
		return {"success": false, "error": "provider_not_found"}

	var provider = _providers[provider_id]
	_emit_event(event_callback, run_id, "status", {"message": "provider_request_started"})
	var provider_result: Dictionary = await provider.send_chat_stream(
		provider_config,
		messages,
		available_tools,
		Callable(self, "_on_provider_stream_event").bind(event_callback, run_id),
		Callable(self, "_is_cancelled").bind(run_id)
	)
	if not bool(provider_result.get("success", false)):
		var stream_error := str(provider_result.get("error", ""))
		if stream_error == "cancelled" or stream_error == "run_cancelled":
			_clear_cancel(run_id)
			return {"success": false, "error": "run_cancelled"}
		if _is_cancelled(run_id):
			_clear_cancel(run_id)
			return {"success": false, "error": "run_cancelled"}
		# Stream path failed, fallback to non-streaming once.
		provider_result = await provider.send_chat(provider_config, messages, available_tools)
	if not bool(provider_result.get("success", false)):
		return provider_result
	if _is_cancelled(run_id):
		_clear_cancel(run_id)
		return {"success": false, "error": "run_cancelled"}

	var assistant_message_raw: Variant = provider_result.get("assistant_message", {"role": "assistant", "content": ""})
	var assistant_message: Dictionary = assistant_message_raw if assistant_message_raw is Dictionary else {"role": "assistant", "content": ""}
	var tool_calls: Array = provider_result.get("tool_calls", [])
	var tool_results: Array[Dictionary] = []
	var streamed := bool(provider_result.get("streamed", false))
	if not streamed:
		var content := str(assistant_message.get("content", ""))
		for chunk in _chunk_text(content, 120):
			if _is_cancelled(run_id):
				_clear_cancel(run_id)
				return {"success": false, "error": "run_cancelled"}
			_emit_event(event_callback, run_id, "message_delta", {"delta": chunk})

	if policy != OrbitTypes.RUN_POLICY_ANALYZE:
		for call_item in tool_calls:
			if not (call_item is Dictionary):
				continue
			var tool_name := _extract_tool_name(call_item)
			var args := _extract_tool_args(call_item)
			if tool_name.is_empty():
				continue
			if _is_cancelled(run_id):
				_clear_cancel(run_id)
				return {"success": false, "error": "run_cancelled"}
			_emit_event(event_callback, run_id, "tool_call", {"tool": tool_name, "args": args})

			var is_mutating := _is_mutating_tool(tool_name)
			if policy == OrbitTypes.RUN_POLICY_PROPOSE and is_mutating:
				tool_results.append({
					"tool": tool_name,
					"skipped": true,
					"reason": "mutating_tool_blocked_in_propose_mode",
				})
				_emit_event(event_callback, run_id, "tool_result", {
					"tool": tool_name,
					"skipped": true,
					"reason": "mutating_tool_blocked_in_propose_mode",
				})
				continue

			var run_result: Dictionary = await _tool_router.execute(tool_name, args)
			if _is_cancelled(run_id):
				_clear_cancel(run_id)
				return {"success": false, "error": "run_cancelled"}
			tool_results.append({
				"tool": tool_name,
				"args": args,
				"result": run_result,
			})
			_emit_event(event_callback, run_id, "tool_result", {
				"tool": tool_name,
				"result": run_result,
			})

	_emit_event(event_callback, run_id, "status", {"message": "turn_completed"})
	return {
		"success": true,
		"assistant_message": assistant_message,
		"tool_results": tool_results,
		"raw": provider_result.get("raw", {}),
	}


func cancel_run(run_id: String) -> void:
	if run_id.strip_edges().is_empty():
		return
	_cancelled_runs[run_id] = true


func _is_cancelled(run_id: String) -> bool:
	if run_id.strip_edges().is_empty():
		return false
	return _cancelled_runs.has(run_id)


func _clear_cancel(run_id: String) -> void:
	if run_id.strip_edges().is_empty():
		return
	_cancelled_runs.erase(run_id)


func _emit_event(event_callback: Callable, run_id: String, kind: String, payload: Dictionary) -> void:
	if not event_callback.is_valid():
		return
	event_callback.call({
		"run_id": run_id,
		"kind": kind,
		"payload": payload,
	})


func _on_provider_stream_event(provider_event: Dictionary, event_callback: Callable, run_id: String) -> void:
	var kind := str(provider_event.get("kind", ""))
	match kind:
		"message_delta":
			_emit_event(event_callback, run_id, "message_delta", {"delta": str(provider_event.get("delta", ""))})
		"tool_call_delta":
			_emit_event(event_callback, run_id, "tool_call_delta", {
				"tool": str(provider_event.get("tool", "")),
				"arguments_delta": str(provider_event.get("arguments_delta", "")),
			})
		_:
			pass


func _chunk_text(text: String, max_chunk_len: int) -> Array[String]:
	var out: Array[String] = []
	var normalized := text
	if normalized.is_empty():
		return out
	var cursor := 0
	while cursor < normalized.length():
		var remain := normalized.length() - cursor
		var step := mini(remain, max_chunk_len)
		out.append(normalized.substr(cursor, step))
		cursor += step
	return out


func _extract_tool_name(tool_call: Dictionary) -> String:
	if tool_call.has("function") and tool_call["function"] is Dictionary:
		return str(tool_call["function"].get("name", ""))
	if tool_call.has("name"):
		return str(tool_call.get("name", ""))
	return ""


func _extract_tool_args(tool_call: Dictionary) -> Dictionary:
	if tool_call.has("function") and tool_call["function"] is Dictionary:
		var fn: Dictionary = tool_call["function"]
		var args = fn.get("arguments", {})
		if args is Dictionary:
			return args
		if args is String:
			var parser := JSON.new()
			if parser.parse(args) == OK and parser.get_data() is Dictionary:
				return parser.get_data()
	if tool_call.has("input") and tool_call["input"] is Dictionary:
		return tool_call["input"]
	return {}


func _is_mutating_tool(tool_id: String) -> bool:
	if tool_id.find("apply_change_set") >= 0:
		return true
	if tool_id.find("create_change_set") >= 0:
		return true
	if tool_id.find("set_") >= 0:
		return true
	if tool_id.find("write") >= 0:
		return true
	if tool_id.find("create_") >= 0:
		return true
	if tool_id.find("delete") >= 0:
		return true
	if tool_id.find("move") >= 0:
		return true
	if tool_id.find("copy") >= 0:
		return true
	return false
