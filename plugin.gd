@tool
extends EditorPlugin

const OrbitSettingsStore = preload("res://addons/orbit_pilot/core/settings_store.gd")
const OpenAIProvider = preload("res://addons/orbit_pilot/core/provider/openai_provider.gd")
const AnthropicProvider = preload("res://addons/orbit_pilot/core/provider/anthropic_provider.gd")
const RemoteMcpClient = preload("res://addons/orbit_pilot/core/remote/remote_mcp_client.gd")
const LocalTools = preload("res://addons/orbit_pilot/core/tools/local_tools.gd")
const ToolCatalog = preload("res://addons/orbit_pilot/core/tools/tool_catalog.gd")
const ToolRouter = preload("res://addons/orbit_pilot/core/tools/tool_router.gd")
const ContextIndexService = preload("res://addons/orbit_pilot/core/context/context_index_service.gd")
const OrbitRegressionRunner = preload("res://addons/orbit_pilot/core/testing/regression_runner.gd")
const ChangeSetService = preload("res://addons/orbit_pilot/core/changes/change_set_service.gd")
const ExecutionService = preload("res://addons/orbit_pilot/core/execution/execution_service.gd")
const SessionManager = preload("res://addons/orbit_pilot/core/session/session_manager.gd")
const RunOrchestrator = preload("res://addons/orbit_pilot/core/run/run_orchestrator.gd")
const DockController = preload("res://addons/orbit_pilot/ui/dock_controller.gd")
const DOCK_SCENE_PATH := "res://addons/orbit_pilot/ui/orbit_dock.tscn"

var _dock
var _dock_controller
var _dock_controller_ready := false
var _settings_store := OrbitSettingsStore.new()
var _settings: Dictionary = {}
var _logs: Array[String] = []
var _validation_summary: Dictionary = {}
var _remote_health: Dictionary = {}
var _openai_provider
var _anthropic_provider
var _remote_client
var _local_tools
var _tool_catalog
var _tool_router
var _context_index_service
var _regression_runner
var _change_set_service
var _execution_service
var _session_manager
var _run_orchestrator

func _enter_tree() -> void:
	if not _init_services():
		push_error("[OrbitPilot] Service initialization failed. Check script parse errors.")
		return
	_settings = _settings_store.load_settings()
	_openai_provider.setup(self)
	_anthropic_provider.setup(self)
	_remote_client.setup(self)
	_regression_runner.setup(self, get_editor_interface())
	_local_tools.setup(get_editor_interface(), _change_set_service, _context_index_service, _regression_runner)
	_tool_catalog.set_local_tools(_local_tools.get_definitions())
	_tool_router.setup(_local_tools, _remote_client, _tool_catalog)
	_tool_router.set_remote_servers(_settings.get("remote_servers", {}))
	_tool_router.set_route_strategy(_settings.get("route_strategy", {}))
	_execution_service.setup({_openai_provider.get_id(): _openai_provider, "deepseek": _openai_provider, _anthropic_provider.get_id(): _anthropic_provider}, _tool_router)
	_session_manager.setup(_settings, Callable(self, "_save_settings"), Callable(self, "_refresh_dock"))
	_run_orchestrator.setup(_settings, _tool_catalog, _tool_router, _change_set_service, _execution_service, Callable(_session_manager, "ensure_session"), Callable(_session_manager, "sync_session"), Callable(self, "_save_settings"), Callable(self, "_push_log"), Callable(self, "_refresh_dock"))
	_create_dock()
	_refresh_dock("OrbitPilot initializing")
	call_deferred("_post_enter_setup")

func _init_services() -> bool:
	_openai_provider = OpenAIProvider.new()
	_anthropic_provider = AnthropicProvider.new()
	_remote_client = RemoteMcpClient.new()
	_local_tools = LocalTools.new()
	_tool_catalog = ToolCatalog.new()
	_tool_router = ToolRouter.new()
	_context_index_service = ContextIndexService.new()
	_regression_runner = OrbitRegressionRunner.new()
	_change_set_service = ChangeSetService.new()
	_execution_service = ExecutionService.new()
	_session_manager = SessionManager.new()
	_run_orchestrator = RunOrchestrator.new()
	return _openai_provider != null and _anthropic_provider != null and _remote_client != null and _local_tools != null and _tool_catalog != null and _tool_router != null and _context_index_service != null and _regression_runner != null and _change_set_service != null and _execution_service != null and _session_manager != null and _run_orchestrator != null

func _exit_tree() -> void:
	_save_settings()
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

func _create_dock() -> void:
	var scene := load(DOCK_SCENE_PATH)
	if scene == null:
		push_error("[OrbitPilot] Failed to load dock scene: %s" % DOCK_SCENE_PATH)
		return
	_dock = scene.instantiate()
	_dock.set_script(null)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_dock_controller = DockController.new()
	_dock_controller.setup(self, _dock)
	_dock_controller.save_settings_requested.connect(_on_save_settings_requested)
	_dock_controller.refresh_remote_tools_requested.connect(_on_refresh_remote_tools_requested)
	_dock_controller.send_prompt_requested.connect(Callable(_run_orchestrator, "on_send_prompt_requested"))
	_dock_controller.cancel_run_requested.connect(Callable(_run_orchestrator, "on_cancel_run_requested"))
	_dock_controller.run_tool_requested.connect(Callable(_run_orchestrator, "on_run_tool_requested"))
	_dock_controller.approve_change_set_requested.connect(Callable(_run_orchestrator, "on_approve_change_set_requested"))
	_dock_controller.session_selected_requested.connect(Callable(_session_manager, "on_session_selected_requested"))
	_dock_controller.session_create_requested.connect(Callable(_session_manager, "on_session_create_requested"))
	_dock_controller.session_archive_requested.connect(Callable(_session_manager, "on_session_archive_requested"))
	_dock_controller.session_delete_requested.connect(Callable(_session_manager, "on_session_delete_requested"))
	_dock_controller.session_rename_requested.connect(Callable(_session_manager, "on_session_rename_requested"))
	_dock_controller.provider_selected_requested.connect(_on_provider_selected_requested)
	_dock_controller_ready = true

func _post_enter_setup() -> void:
	await _refresh_remote_tools()
	await _run_startup_validation()
	_push_log("plugin_loaded")
	_refresh_dock("OrbitPilot loaded")

func _refresh_dock(status_text: String = "") -> void:
	if _dock == null:
		return
	if _dock_controller_ready and _dock_controller != null:
		var session: Dictionary = _session_manager.ensure_session()
		var pending: Dictionary = _change_set_service.list_pending()
		_dock_controller.apply_model({
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
		})
	else:
		push_warning("[OrbitPilot] Dock controller missing apply_model")

func _save_settings() -> void:
	if not (_settings is Dictionary):
		_settings = _settings_store.load_settings()
	var res := _settings_store.save_settings(_settings)
	if not bool(res.get("success", false)):
		_push_log("save_settings_failed")

func _push_log(line: String) -> void:
	if not (_logs is Array):
		_logs = []
	if not (_settings is Dictionary):
		_settings = _settings_store.load_settings()
	var ts := Time.get_datetime_string_from_system()
	_logs.append("[%s] %s" % [ts, line])
	var limit := int(_settings.get("log_limit", 300))
	while _logs.size() > limit:
		_logs.pop_front()

func _on_save_settings_requested(payload: Dictionary) -> void:
	var active_provider := str(payload.get("active_provider", ""))
	if not active_provider.is_empty():
		_settings["active_provider"] = active_provider
		var providers: Dictionary = _settings.get("providers", {})
		providers[active_provider] = _normalize_provider_config(active_provider, payload.get("provider_config", {}))
		_settings["providers"] = providers
	var remote_servers := payload.get("remote_servers", {})
	if remote_servers is Dictionary:
		_settings["remote_servers"] = remote_servers
	_tool_router.set_remote_servers(_settings.get("remote_servers", {}))
	_tool_router.set_route_strategy(_settings.get("route_strategy", {}))
	_save_settings()
	_push_log("settings_saved")
	await _refresh_remote_tools()
	await _run_startup_validation()
	_refresh_dock("Settings saved")

func _on_refresh_remote_tools_requested() -> void:
	await _refresh_remote_tools()
	await _run_startup_validation()
	_refresh_dock("Remote tools refreshed")

func _on_provider_selected_requested(provider_id: String) -> void:
	if provider_id.is_empty():
		return
	var providers: Dictionary = _settings.get("providers", {})
	if not providers.has(provider_id):
		_push_log("provider_unknown:%s" % provider_id)
		_refresh_dock("Unknown provider")
		return
	_settings["active_provider"] = provider_id
	_save_settings()
	_refresh_dock("Provider switched: %s" % provider_id)

func _refresh_remote_tools() -> void:
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
			_push_log("remote_tools_loaded:%s" % server_id)
		else:
			_tool_catalog.clear_remote_tools(server_id)
			_push_log("remote_tools_error:%s:%s" % [server_id, str(result.get("error", "unknown"))])

func _run_startup_validation() -> void:
	var providers: Dictionary = _settings.get("providers", {})
	var provider_checks: Array[Dictionary] = []
	for provider_id in providers.keys():
		var cfg: Dictionary = providers[provider_id]
		var has_direct := not str(cfg.get("api_key", "")).strip_edges().is_empty()
		var env_name := str(cfg.get("api_key_env", "")).strip_edges()
		var has_env := not env_name.is_empty() and not OS.get_environment(env_name).strip_edges().is_empty()
		provider_checks.append({"id": provider_id, "ready": has_direct or has_env, "mode": "direct" if has_direct else ("env" if has_env else "missing")})
	var suite_result: Dictionary = await _regression_runner.run_minimal_suite()
	_validation_summary = {"providers": provider_checks, "regression": suite_result, "remote_health": _remote_health.duplicate(true), "updated_at": Time.get_datetime_string_from_system()}
	if bool(suite_result.get("success", false)):
		_push_log("validation_suite:%s/%s" % [str(suite_result.get("passed", 0)), str(suite_result.get("total", 0))])
	else:
		_push_log("validation_suite_failed")


func _normalize_provider_config(provider_id: String, provider_config: Dictionary) -> Dictionary:
	var normalized := provider_config.duplicate(true)
	if provider_id == "deepseek":
		var base_url := str(normalized.get("base_url", "")).strip_edges().trim_suffix("/")
		if base_url == "https://api.deepseek.com":
			normalized["base_url"] = "https://api.deepseek.com/v1"
	return normalized
