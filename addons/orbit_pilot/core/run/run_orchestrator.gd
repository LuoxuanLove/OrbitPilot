@tool
extends RefCounted
class_name RunOrchestrator

var _settings: Dictionary
var _tool_catalog
var _tool_router
var _change_set_service
var _execution_service
var _ensure_session: Callable
var _sync_session: Callable
var _save_settings: Callable
var _push_log: Callable
var _refresh_dock: Callable
var _active_run_id := ""
var _is_run_active := false
var _stream_preview := ""
var _last_tool_result: Dictionary = {}


func setup(
	settings: Dictionary,
	tool_catalog,
	tool_router,
	change_set_service,
	execution_service,
	ensure_session_callback: Callable,
	sync_session_callback: Callable,
	save_settings_callback: Callable,
	push_log_callback: Callable,
	refresh_dock_callback: Callable
) -> void:
	_settings = settings
	_tool_catalog = tool_catalog
	_tool_router = tool_router
	_change_set_service = change_set_service
	_execution_service = execution_service
	_ensure_session = ensure_session_callback
	_sync_session = sync_session_callback
	_save_settings = save_settings_callback
	_push_log = push_log_callback
	_refresh_dock = refresh_dock_callback


func get_active_run_id() -> String:
	return _active_run_id


func is_run_active() -> bool:
	return _is_run_active


func get_stream_preview() -> String:
	return _stream_preview


func get_last_tool_result() -> Dictionary:
	return _last_tool_result


func build_agent_tools() -> Array:
	var tools: Array = []
	for item in _tool_catalog.get_unified_tools():
		var tool_name := str(item.get("name", ""))
		if tool_name.is_empty():
			tool_name = str(item.get("id", ""))
		tools.append({
			"name": tool_name,
			"description": "[%s] %s" % [str(item.get("id", "")), str(item.get("description", ""))],
			"input_schema": {"type": "object", "properties": {}, "additionalProperties": true}
		})
	return tools


func on_send_prompt_requested(prompt: String, policy: String) -> void:
	if _is_run_active:
		_push_log.call("run_rejected:another_run_active")
		_refresh_dock.call("Run already active")
		return
	_active_run_id = _new_run_id()
	_is_run_active = true
	_stream_preview = ""
	_refresh_dock.call("Run started: %s" % _active_run_id)
	var session: Dictionary = _ensure_session.call().duplicate(true)
	var messages: Array = session.get("messages", [])
	messages.append({"role": "user", "content": prompt})
	session["messages"] = messages
	_sync_session.call(session)
	_save_settings.call()
	_refresh_dock.call("Run started: %s" % _active_run_id)
	var provider_id := str(_settings.get("active_provider", "openai_compatible"))
	var provider_cfg: Dictionary = _settings.get("providers", {}).get(provider_id, {})
	var turn_result: Dictionary = await _execution_service.execute_turn(
		policy, provider_id, provider_cfg, messages, build_agent_tools(), _active_run_id, Callable(self, "on_execution_event")
	)
	if not bool(turn_result.get("success", false)):
		var run_error := _format_run_error(turn_result)
		var error_session: Dictionary = _ensure_session.call().duplicate(true)
		var error_messages: Array = error_session.get("messages", [])
		error_messages.append({"role": "assistant", "content": "Request failed: %s" % run_error})
		error_session["messages"] = error_messages
		_sync_session.call(error_session)
		_save_settings.call()
		_push_log.call("agent_error:%s" % run_error)
		_finish_run("Run cancelled" if run_error == "run_cancelled" else "Agent call failed")
		return
	var assistant_message: Dictionary = turn_result.get("assistant_message", {"role": "assistant", "content": ""})
	messages.append(assistant_message)
	session["messages"] = messages
	_sync_session.call(session)
	_save_settings.call()
	_push_log.call("assistant:%s" % str(assistant_message.get("content", "")))
	for tool_result in turn_result.get("tool_results", []):
		_push_log.call("tool_result:%s" % JSON.stringify(tool_result))
	_finish_run("Prompt executed")


func on_run_tool_requested(tool_id: String, args_json: String) -> void:
	var args: Dictionary = {}
	if not args_json.strip_edges().is_empty():
		var parser := JSON.new()
		if parser.parse(args_json) == OK and parser.get_data() is Dictionary:
			args = parser.get_data()
		else:
			_push_log.call("tool_args_parse_error")
			_refresh_dock.call("Invalid tool args JSON")
			return
	var run_result: Dictionary = await _tool_router.execute(tool_id, args)
	_last_tool_result = {"tool_id": tool_id, "args": args, "result": run_result, "at": Time.get_datetime_string_from_system()}
	_push_log.call("manual_tool:%s:%s" % [tool_id, JSON.stringify(run_result)])
	_refresh_dock.call("Tool executed")


func on_approve_change_set_requested(change_set_id: String, approved: bool) -> void:
	var res: Dictionary = _change_set_service.apply_change_set(change_set_id, approved)
	_push_log.call("change_set:%s:%s" % [change_set_id, JSON.stringify(res)])
	_refresh_dock.call("Change set updated")


func on_cancel_run_requested() -> void:
	if _active_run_id.is_empty():
		_refresh_dock.call("No active run")
		return
	_execution_service.cancel_run(_active_run_id)
	_push_log.call("run_cancel_requested:%s" % _active_run_id)
	_refresh_dock.call("Cancel requested: %s" % _active_run_id)


func on_execution_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	var payload := event.get("payload", {})
	match kind:
		"status":
			_push_log.call("run_status:%s" % _format_status_payload(payload))
		"message_delta":
			_stream_preview += str(payload.get("delta", ""))
		"tool_call":
			_push_log.call("tool_call:%s" % JSON.stringify(payload))
		"tool_call_delta":
			_push_log.call("tool_call_delta:%s" % JSON.stringify(payload))
		"tool_result":
			_push_log.call("tool_event_result:%s" % JSON.stringify(payload))
	_refresh_dock.call("Run active: %s" % _active_run_id if _is_run_active else "OrbitPilot ready")


func _finish_run(status_text: String) -> void:
	_is_run_active = false
	_active_run_id = ""
	_stream_preview = ""
	_refresh_dock.call(status_text)


func _new_run_id() -> String:
	return "run_%s_%s" % [str(Time.get_unix_time_from_system()), str(randi())]


func _format_run_error(result: Dictionary) -> String:
	var error_code := str(result.get("error", "unknown"))
	var response_code := int(result.get("response_code", 0))
	var result_code := int(result.get("result_code", 0))
	var local_code := int(result.get("code", 0))
	var result_name := str(result.get("result_name", "")).strip_edges()
	var status_name := str(result.get("status_name", "")).strip_edges()
	var phase := str(result.get("phase", "")).strip_edges()
	var transport := str(result.get("transport", "")).strip_edges()
	var unsafe_tls_flag := ""
	if result.has("unsafe_tls"):
		unsafe_tls_flag = "unsafe_tls=%s" % str(bool(result.get("unsafe_tls", false)))
	var body: Variant = result.get("body", {})
	var detail := ""
	if body is Dictionary:
		var body_dict: Dictionary = body
		if body_dict.has("error"):
			var error_item: Variant = body_dict.get("error")
			detail = str((error_item as Dictionary).get("message", "")) if error_item is Dictionary else str(error_item)
		elif body_dict.has("message"):
			detail = str(body_dict.get("message", ""))
		elif body_dict.has("detail"):
			detail = str(body_dict.get("detail", ""))
	elif body is String:
		detail = str(body)
	if result_code > 0 and not detail.is_empty():
		return "%s (%s)" % [error_code, _join_run_error_parts([
			"result:%d" % result_code,
			"result_name=%s" % result_name,
			"status:%d" % response_code,
			phase,
			"transport=%s" % transport,
			unsafe_tls_flag,
			detail,
		])]
	if result_code > 0:
		return "%s (%s)" % [error_code, _join_run_error_parts([
			"result:%d" % result_code,
			"result_name=%s" % result_name,
			"status:%d" % response_code,
			phase,
			"transport=%s" % transport,
			unsafe_tls_flag,
		])]
	if local_code > 0 and not detail.is_empty():
		return "%s (%s)" % [error_code, _join_run_error_parts([
			"code:%d" % local_code,
			status_name,
			phase,
			"transport=%s" % transport,
			unsafe_tls_flag,
			detail,
		])]
	if local_code > 0:
		return "%s (%s)" % [error_code, _join_run_error_parts([
			"code:%d" % local_code,
			status_name,
			phase,
			"transport=%s" % transport,
			unsafe_tls_flag,
		])]
	if response_code > 0 and not detail.is_empty():
		return "%s (%s)" % [error_code, _join_run_error_parts([
			"http:%d" % response_code,
			phase,
			"transport=%s" % transport,
			unsafe_tls_flag,
			detail,
		])]
	if response_code > 0:
		return "%s (%s)" % [error_code, _join_run_error_parts([
			"http:%d" % response_code,
			phase,
			"transport=%s" % transport,
			unsafe_tls_flag,
		])]
	if not detail.is_empty():
		return "%s (%s)" % [error_code, _join_run_error_parts([phase, "transport=%s" % transport, unsafe_tls_flag, detail])]
	return error_code


func _format_status_payload(payload: Dictionary) -> String:
	var message := str(payload.get("message", "")).strip_edges()
	var parts := PackedStringArray()
	if not message.is_empty():
		parts.append(message)
	var provider_id := str(payload.get("provider_id", "")).strip_edges()
	if not provider_id.is_empty():
		parts.append("provider=%s" % provider_id)
	var model := str(payload.get("model", "")).strip_edges()
	if not model.is_empty():
		parts.append("model=%s" % model)
	var base_url := str(payload.get("base_url", "")).strip_edges()
	if not base_url.is_empty():
		parts.append("base_url=%s" % base_url)
	var details := str(payload.get("details", "")).strip_edges()
	if not details.is_empty():
		parts.append(details)
	return ", ".join(parts)


func _join_run_error_parts(parts: Array[String]) -> String:
	var out := PackedStringArray()
	for part in parts:
		var value := str(part).strip_edges()
		if not value.is_empty():
			out.append(value)
	return ", ".join(out)
