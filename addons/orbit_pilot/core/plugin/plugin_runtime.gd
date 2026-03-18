@tool
extends RefCounted

var _settings_store
var _settings: Dictionary = {}
var _tool_catalog
var _tool_router
var _remote_client
var _change_set_service
var _regression_runner
var _session_manager
var _run_orchestrator
var _logs: Array[String] = []
var _validation_summary: Dictionary = {}
var _remote_health: Dictionary = {}

func setup(settings_store, settings: Dictionary, tool_catalog, tool_router, remote_client, change_set_service, regression_runner, session_manager, run_orchestrator) -> void:
	_settings_store = settings_store
	_settings = settings
	_tool_catalog = tool_catalog
	_tool_router = tool_router
	_remote_client = remote_client
	_change_set_service = change_set_service
	_regression_runner = regression_runner
	_session_manager = session_manager
	_run_orchestrator = run_orchestrator

func get_settings() -> Dictionary:
	return _settings

func save_settings() -> void:
	var res := _settings_store.save_settings(_settings)
	if not bool(res.get("success", false)):
		push_log("save_settings_failed")

func push_log(line: String) -> void:
	var ts := Time.get_datetime_string_from_system()
	_logs.append("[%s] %s" % [ts, line])
	var limit := int(_settings.get("log_limit", 300))
	while _logs.size() > limit:
		_logs.pop_front()

func apply_settings_payload(payload: Dictionary) -> void:
	var active_provider := str(payload.get("active_provider", ""))
	if not active_provider.is_empty():
		_settings["active_provider"] = active_provider
		var providers: Dictionary = _settings.get("providers", {})
		providers[active_provider] = payload.get("provider_config", {})
		_settings["providers"] = providers
	var remote_servers := payload.get("remote_servers", {})
	if remote_servers is Dictionary:
		_settings["remote_servers"] = remote_servers
	_tool_router.set_remote_servers(_settings.get("remote_servers", {}))
	_tool_router.set_route_strategy(_settings.get("route_strategy", {}))

func select_provider(provider_id: String) -> Dictionary:
	if provider_id.is_empty():
		return {"success": false, "status_text": "Unknown provider"}
	var providers: Dictionary = _settings.get("providers", {})
	if not providers.has(provider_id):
		push_log("provider_unknown:%s" % provider_id)
		return {"success": false, "status_text": "Unknown provider"}
	_settings["active_provider"] = provider_id
	save_settings()
	return {"success": true, "status_text": "Provider switched: %s" % provider_id}

func refresh_remote_tools() -> void:
	var remote_servers: Dictionary = _settings.get("remote_servers", {})
	for server_id in remote_servers.keys():
		var cfg: Dictionary = remote_servers[server_id]
		if not bool(cfg.get("enabled", false)):
			_tool_catalog.clear_remote_tools(server_id)
			continue
		var endpoint := str(cfg.get("endpoint", ""))
		if endpoint.is_empty():
			_tool_catalog.clear_remote_tools(server_id)
			_remote_health[server_id] = {"success": false, "error": "remote_endpoint_empty"}
			continue
		_remote_health[server_id] = await _remote_client.health_check(endpoint, float(cfg.get("timeout_sec", 8.0)))
		var result: Dictionary = await _remote_client.fetch_tools(endpoint, float(cfg.get("timeout_sec", 10.0)))
		if bool(result.get("success", false)):
			_tool_catalog.set_remote_tools(server_id, result.get("tools", []))
			push_log("remote_tools_loaded:%s" % server_id)
		else:
			_tool_catalog.clear_remote_tools(server_id)
			push_log("remote_tools_error:%s:%s" % [server_id, str(result.get("error", "unknown"))])

func run_startup_validation() -> void:
	var provider_checks: Array[Dictionary] = []
	var providers: Dictionary = _settings.get("providers", {})
	for provider_id in providers.keys():
		var cfg: Dictionary = providers[provider_id]
		var has_direct := not str(cfg.get("api_key", "")).strip_edges().is_empty()
		var env_name := str(cfg.get("api_key_env", "")).strip_edges()
		var has_env := not env_name.is_empty() and not OS.get_environment(env_name).strip_edges().is_empty()
		provider_checks.append({"id": provider_id, "ready": has_direct or has_env, "mode": "direct" if has_direct else ("env" if has_env else "missing")})
	var suite_result: Dictionary = await _regression_runner.run_minimal_suite()
	_validation_summary = {"providers": provider_checks, "regression": suite_result, "remote_health": _remote_health.duplicate(true), "updated_at": Time.get_datetime_string_from_system()}
	if bool(suite_result.get("success", false)):
		push_log("validation_suite:%s/%s" % [str(suite_result.get("passed", 0)), str(suite_result.get("total", 0))])
	else:
		push_log("validation_suite_failed")

func build_dock_model(status_text: String = "") -> Dictionary:
	var session: Dictionary = _session_manager.ensure_session()
	var pending: Dictionary = _change_set_service.list_pending()
	return {
		"status_text": status_text if not status_text.is_empty() else "OrbitPilot ready",
		"active_provider": str(_settings.get("active_provider", "openai_compatible")),
		"active_session_id": str(session.get("id", "")),
		"provider_map": _settings.get("providers", {}),
		"remote_servers": _settings.get("remote_servers", {}),
		"remote_health": _remote_health,
		"tools": _tool_catalog.get_unified_tools(),
		"pending_change_sets": pending.get("items", []),
		"logs": _logs,
		"active_run_id": _run_orchestrator.get_active_run_id(),
		"is_run_active": _run_orchestrator.is_run_active(),
		"stream_preview": _run_orchestrator.get_stream_preview(),
		"validation_summary": _validation_summary,
		"last_tool_result": _run_orchestrator.get_last_tool_result(),
		"sessions": _settings.get("sessions", []),
		"session": session,
	}
