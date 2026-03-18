@tool
class_name OrbitPageSettings
extends RefCounted

signal save_settings_requested(payload: Dictionary)
signal refresh_remote_tools_requested
signal language_selected_requested(lang: String)

const Localizer = preload("res://addons/orbit_pilot/core/utils/localizer.gd")

var _root: Control
var _overview_status: RichTextLabel
var _model_edit: LineEdit
var _base_url_edit: LineEdit
var _api_key_edit: LineEdit
var _toggle_api_key_button: Button
var _remote_id_edit: LineEdit
var _remote_url_edit: LineEdit
var _save_button: Button
var _refresh_remote_button: Button
var _copy_runtime_log_button: Button
var _runtime_log: RichTextLabel
var _language_select: OptionButton
var _language_label: Label
var _provider_edit_select: OptionButton
var _provider_select_label: Label
var _overview_status_panel: Control
var _settings_panel: Control
var _runtime_log_panel: Control
var _model := {}
var _api_key_visible := false


func setup(dock_root: Control) -> void:
	_root = dock_root
	_assign_nodes()
	_setup_language_select()
	_bind_events()
	refresh_translations()


func apply_model(model: Dictionary) -> void:
	_model = model
	_apply_settings(model)
	_apply_overview(model)
	_apply_logs(model)


func get_chrome_panels() -> Dictionary:
	return {
		"settings_overview": _overview_status_panel,
		"settings": _settings_panel,
		"runtime_log": _runtime_log_panel,
	}


func get_chrome_refs() -> Dictionary:
	return {"runtime_log": _runtime_log}


func _node(path: String):
	return _root.get_node(path)


func _assign_nodes() -> void:
	if _root == null:
		push_error("[OrbitPageSettings] _root is null in _assign_nodes")
		return
	_overview_status_panel = _node("OverviewStatusPanel")
	_overview_status = _node("OverviewStatusPanel/OverviewStatus")
	_settings_panel = _node("SettingsPanel")
	_model_edit = _node("SettingsPanel/Settings/ModelEdit")
	_base_url_edit = _node("SettingsPanel/Settings/BaseUrlEdit")
	_api_key_edit = _node("SettingsPanel/Settings/ApiKeyRow/ApiKeyEdit")
	_toggle_api_key_button = _node("SettingsPanel/Settings/ApiKeyRow/ToggleApiKeyButton")
	_remote_id_edit = _node("SettingsPanel/Settings/RemoteIdEdit")
	_remote_url_edit = _node("SettingsPanel/Settings/RemoteUrlEdit")
	_save_button = _node("SettingsPanel/Settings/SettingsButtons/SaveSettingsButton")
	_refresh_remote_button = _node("SettingsPanel/Settings/SettingsButtons/RefreshRemoteButton")
	_runtime_log_panel = _node("RuntimeLogPanel")
	_copy_runtime_log_button = _node("RuntimeLogPanel/RuntimeLogContainer/RuntimeLogButtons/CopyRuntimeLogButton")
	_runtime_log = _node("RuntimeLogPanel/RuntimeLogContainer/RuntimeLog")
	_language_select = _node("SettingsPanel/Settings/LanguageRow/LanguageSelect")
	_language_label = _node("SettingsPanel/Settings/LanguageRow/LanguageLabel")
	_provider_edit_select = _node("SettingsPanel/Settings/ProviderSelectRow/ProviderEditSelect")
	_provider_select_label = _node("SettingsPanel/Settings/ProviderSelectRow/ProviderSelectLabel")


func _bind_events() -> void:
	if _save_button:
		_save_button.pressed.connect(_on_save_settings_pressed)
	if _refresh_remote_button:
		_refresh_remote_button.pressed.connect(_on_refresh_remote_pressed)
	if _copy_runtime_log_button:
		_copy_runtime_log_button.pressed.connect(_on_copy_runtime_log_pressed)
	if _toggle_api_key_button:
		_toggle_api_key_button.pressed.connect(_on_toggle_api_key_visibility_pressed)
	if _language_select:
		_language_select.item_selected.connect(_on_language_selected)
	if _provider_edit_select:
		_provider_edit_select.item_selected.connect(_on_provider_edit_selected)


func refresh_translations() -> void:
	_language_label.text = Localizer.t("SET_LANGUAGE")
	_provider_select_label.text = Localizer.t("SET_PROVIDER")
	_apply_settings(_model)
	_apply_overview(_model)
	_apply_logs(_model)


func _setup_language_select() -> void:
	_language_select.clear()
	_language_select.add_item(Localizer.LANG_CN)
	_language_select.add_item(Localizer.LANG_EN)
	_language_select.select(0 if Localizer.get_language() == Localizer.LANG_CN else 1)


func _on_language_selected(index: int) -> void:
	if index < 0 or index >= _language_select.item_count:
		return
	emit_signal("language_selected_requested", _language_select.get_item_text(index))


func _on_provider_edit_selected(index: int) -> void:
	if index < 0 or index >= _provider_edit_select.item_count:
		return
	var providers: Dictionary = _model.get("provider_map", {})
	var provider_id := _provider_edit_select.get_item_text(index)
	var provider_cfg: Dictionary = providers.get(provider_id, {})
	_model_edit.text = str(provider_cfg.get("model", ""))
	_base_url_edit.text = str(provider_cfg.get("base_url", ""))
	_api_key_edit.text = str(provider_cfg.get("api_key", ""))


func _on_refresh_remote_pressed() -> void:
	emit_signal("refresh_remote_tools_requested")


func _apply_settings(model: Dictionary) -> void:
	var providers: Dictionary = model.get("provider_map", {})
	var active_provider := str(model.get("active_provider", "openai_compatible"))
	
	_provider_edit_select.clear()
	for p_id in providers.keys():
		_provider_edit_select.add_item(str(p_id))
	
	# Default selection to active provider if not interacting
	var current_idx = -1
	for i in range(_provider_edit_select.item_count):
		if _provider_edit_select.get_item_text(i) == active_provider:
			current_idx = i
			break
	if current_idx >= 0:
		_provider_edit_select.select(current_idx)
		_on_provider_edit_selected(current_idx)

	_api_key_edit.secret = not _api_key_visible
	_toggle_api_key_button.text = Localizer.t("SET_HIDE_KEY") if _api_key_visible else Localizer.t("SET_SHOW_KEY")
	var remote_servers = model.get("remote_servers", {})
	if remote_servers.has("main"):
		var main = remote_servers["main"]
		_remote_id_edit.text = str(main.get("id", "main"))
		_remote_url_edit.text = str(main.get("endpoint", "http://127.0.0.1:3000"))
	else:
		_remote_id_edit.text = "main"
		_remote_url_edit.text = "http://127.0.0.1:3000"


func _apply_overview(model: Dictionary) -> void:
	var remote_health = model.get("remote_health", {})
	var lines := PackedStringArray()
	var providers: Dictionary = model.get("provider_map", {})
	var active_provider := str(model.get("active_provider", "openai_compatible"))
	var provider_cfg: Dictionary = providers.get(active_provider, {})
	lines.append("%s: %s" % [Localizer.t("SET_PROVIDER"), active_provider])
	lines.append("%s: %s" % [Localizer.t("SET_KEY_SOURCE"), _describe_api_key_source(provider_cfg)])
	lines.append("")
	for server_id in remote_health.keys():
		var item = remote_health[server_id]
		lines.append(Localizer.t("SET_MCP_STATUS") % [str(server_id), "ok" if bool(item.get("success", false)) else str(item.get("error", "error"))])
	_overview_status.text = "\n".join(lines)


func _apply_logs(model: Dictionary) -> void:
	var logs = model.get("logs", [])
	var lines := PackedStringArray()
	var start_index := maxi(logs.size() - 10, 0)
	for i in range(start_index, logs.size()):
		lines.append(str(logs[i]))
	_runtime_log.text = "\n".join(lines)
	_copy_runtime_log_button.text = Localizer.t("SET_COPY_LOGS")


func _on_copy_runtime_log_pressed() -> void:
	var logs = _model.get("logs", [])
	var lines := PackedStringArray()
	for entry in logs:
		lines.append(str(entry))
	var text := "\n".join(lines)
	if text.is_empty():
		text = _runtime_log.text
	DisplayServer.clipboard_set(text)
	_copy_runtime_log_button.text = Localizer.t("SET_COPIED")


func _on_toggle_api_key_visibility_pressed() -> void:
	_api_key_visible = not _api_key_visible
	_api_key_edit.secret = not _api_key_visible
	_toggle_api_key_button.text = Localizer.t("SET_HIDE_KEY") if _api_key_visible else Localizer.t("SET_SHOW_KEY")


func _on_save_settings_pressed() -> void:
	var edit_provider_id := _provider_edit_select.get_item_text(_provider_edit_select.selected)
	var provider_cfg: Dictionary = {
		"id": edit_provider_id,
		"model": _model_edit.text,
		"base_url": _base_url_edit.text,
		"api_key": _api_key_edit.text,
	}
	var remote_id := _remote_id_edit.text.strip_edges()
	if remote_id.is_empty():
		remote_id = "main"
	emit_signal("save_settings_requested", {
		"active_provider": edit_provider_id,
		"provider_config": provider_cfg,
		"remote_servers": {
			remote_id: {
				"id": remote_id,
				"name": remote_id,
				"endpoint": _remote_url_edit.text.strip_edges(),
				"enabled": true,
				"timeout_sec": 15.0,
			}
		},
	})


func _describe_api_key_source(provider_cfg: Dictionary) -> String:
	var direct := str(provider_cfg.get("api_key", "")).strip_edges()
	if not direct.is_empty():
		return "direct (%s)" % _mask_api_key(direct)
	var env_name := str(provider_cfg.get("api_key_env", "")).strip_edges()
	if env_name.is_empty():
		return "missing"
	var env_value := OS.get_environment(env_name).strip_edges()
	if env_value.is_empty():
		return "env:%s (empty)" % env_name
	return "env:%s (%s)" % [env_name, _mask_api_key(env_value)]


func _mask_api_key(value: String) -> String:
	var clean := value.strip_edges()
	if clean.is_empty():
		return "empty"
	if clean.length() <= 4:
		return clean
	return "****%s" % clean.right(4)
