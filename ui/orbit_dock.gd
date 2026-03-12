@tool
extends Control

signal save_settings_requested(settings: Dictionary)
signal refresh_remote_tools_requested()
signal send_prompt_requested(prompt: String, policy: String)
signal cancel_run_requested()
signal run_tool_requested(tool_id: String, args_json: String)
signal approve_change_set_requested(change_set_id: String, approved: bool)
signal session_selected_requested(session_id: String)
signal session_create_requested()
signal session_archive_requested(session_id: String)
signal session_delete_requested(session_id: String)
signal session_rename_requested(session_id: String, title: String)
signal provider_selected_requested(provider_id: String)

const PAGE_CODEX := 0
const PAGE_SESSIONS := 1
const PAGE_TOOLS := 2
const PAGE_REVIEW := 3
const PAGE_SETTINGS := 4

@onready var _tab_codex = $RootMargin/Root/Header/HeaderBox/Nav/TabCodex
@onready var _sessions_button = $RootMargin/Root/Header/HeaderBox/Nav/SessionsButton
@onready var _tab_tools = $RootMargin/Root/Header/HeaderBox/Nav/TabTools
@onready var _tab_review = $RootMargin/Root/Header/HeaderBox/Nav/TabReview
@onready var _tab_settings = $RootMargin/Root/Header/HeaderBox/Nav/TabSettings
@onready var _page_stack = $RootMargin/Root/PageStack
@onready var _status_pill = $RootMargin/Root/Header/HeaderBox/StatusPill

@onready var _session_picker = $RootMargin/Root/PageStack/PageCodex/CodexTop/TitleBlock/SessionPicker
@onready var _conversation_log = $RootMargin/Root/PageStack/PageCodex/ConversationPanel/ConversationLog
@onready var _provider_select = $RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerMeta/ProviderSelect
@onready var _policy_select = $RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerMeta/PolicySelect
@onready var _validation_badge = $RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerMeta/ValidationBadge
@onready var _prompt_edit = $RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/PromptEdit
@onready var _send_button = $RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerActions/SendPromptButton
@onready var _cancel_button = $RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerActions/CancelRunButton

@onready var _new_session_button_page = $RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/NewSessionButtonPage
@onready var _open_session_button = $RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/OpenSessionButton
@onready var _archive_session_button_page = $RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/ArchiveSessionButtonPage
@onready var _delete_archived_button = $RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/DeleteArchivedButton
@onready var _rename_session_edit = $RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionRenameRow/RenameSessionEdit
@onready var _rename_session_button = $RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionRenameRow/RenameSessionButton
@onready var _active_sessions_list = $RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ActiveSessionsPanel/ActiveSessionsBox/ActiveSessionsList
@onready var _archived_sessions_list = $RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ArchivedSessionsPanel/ArchivedSessionsBox/ArchivedSessionsList

@onready var _tool_select = $RootMargin/Root/PageStack/PageTools/ToolSelect
@onready var _tool_args_edit = $RootMargin/Root/PageStack/PageTools/ToolArgsEdit
@onready var _run_tool_button = $RootMargin/Root/PageStack/PageTools/RunToolButton
@onready var _tool_result = $RootMargin/Root/PageStack/PageTools/ToolResultPanel/ToolResult

@onready var _change_set_select = $RootMargin/Root/PageStack/PageReview/ChangeSetSelect
@onready var _change_set_preview = $RootMargin/Root/PageStack/PageReview/ChangeSetPreviewPanel/ChangeSetPreview
@onready var _approve_button = $RootMargin/Root/PageStack/PageReview/ReviewButtons/ApproveButton
@onready var _reject_button = $RootMargin/Root/PageStack/PageReview/ReviewButtons/RejectButton

@onready var _overview_status = $RootMargin/Root/PageStack/PageSettings/OverviewStatusPanel/OverviewStatus
@onready var _model_edit = $RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/ModelEdit
@onready var _base_url_edit = $RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/BaseUrlEdit
@onready var _api_key_edit = $RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/ApiKeyEdit
@onready var _remote_id_edit = $RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/RemoteIdEdit
@onready var _remote_url_edit = $RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/RemoteUrlEdit
@onready var _save_button = $RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/SettingsButtons/SaveSettingsButton
@onready var _refresh_remote_button = $RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/SettingsButtons/RefreshRemoteButton
@onready var _runtime_log = $RootMargin/Root/PageStack/PageSettings/RuntimeLogPanel/RuntimeLog
@onready var _status_label = $RootMargin/Root/Footer/FooterBox/StatusLabel

var _model := {}
var _current_page := PAGE_CODEX
var _active_session_ids := []
var _archived_session_ids := []


func _ready() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_disable_auto_translate(self)
	_setup_policy_select()
	_bind_events()
	_apply_chrome()
	_set_page(PAGE_CODEX)


func apply_model(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_apply_settings()
	_apply_session_picker()
	_apply_sessions_page()
	_apply_session()
	_apply_validation()
	_apply_tools()
	_apply_change_sets()
	_apply_logs()
	var run_active := bool(_model.get("is_run_active", false))
	_send_button.disabled = run_active
	_cancel_button.disabled = not run_active
	_status_label.text = str(_model.get("status_text", "OrbitPilot ready"))
	_status_pill.text = "Running" if run_active else "Ready"


func _bind_events() -> void:
	_tab_codex.pressed.connect(_on_tab_codex_pressed)
	_sessions_button.pressed.connect(_on_sessions_button_pressed)
	_tab_tools.pressed.connect(_on_tab_tools_pressed)
	_tab_review.pressed.connect(_on_tab_review_pressed)
	_tab_settings.pressed.connect(_on_tab_settings_pressed)
	_save_button.pressed.connect(_on_save_settings_pressed)
	_refresh_remote_button.pressed.connect(_on_refresh_remote_pressed)
	_send_button.pressed.connect(_on_send_prompt_pressed)
	_cancel_button.pressed.connect(_on_cancel_run_pressed)
	_run_tool_button.pressed.connect(_on_run_tool_pressed)
	_approve_button.pressed.connect(_on_approve_pressed)
	_reject_button.pressed.connect(_on_reject_pressed)
	_new_session_button_page.pressed.connect(_on_new_session_pressed)
	_open_session_button.pressed.connect(_on_open_selected_session_pressed)
	_archive_session_button_page.pressed.connect(_on_archive_selected_session_pressed)
	_delete_archived_button.pressed.connect(_on_delete_archived_session_pressed)
	_rename_session_button.pressed.connect(_on_rename_session_pressed)
	_rename_session_edit.text_changed.connect(_on_rename_session_text_changed)
	_active_sessions_list.item_selected.connect(_on_active_sessions_selected)
	_archived_sessions_list.item_selected.connect(_on_archived_sessions_selected)
	_provider_select.item_selected.connect(_on_provider_selected)
	_policy_select.item_selected.connect(_on_policy_selected)
	_tool_select.item_selected.connect(_on_tool_selected)
	_change_set_select.item_selected.connect(_on_change_set_selected)
	_session_picker.item_selected.connect(_on_session_picker_selected)


func _setup_policy_select() -> void:
	_policy_select.clear()
	_policy_select.add_item("analyze")
	_policy_select.add_item("propose")
	_policy_select.add_item("apply_with_approval")
	_policy_select.select(1)


func _set_page(page_index: int) -> void:
	_current_page = page_index
	for i in range(_page_stack.get_child_count()):
		var child = _page_stack.get_child(i)
		if child is CanvasItem:
			child.visible = i == page_index
	_apply_nav_state()


func _apply_chrome() -> void:
	var muted := Color("9aa3b2")
	var accent := Color("6ea8fe")
	_status_pill.add_theme_color_override("font_color", accent)
	_validation_badge.add_theme_color_override("font_color", muted)
	_runtime_log.add_theme_color_override("default_color", muted)

	_apply_panel_style($RootMargin/Root/Header, Color("11161f"), 12, 12)
	_apply_panel_style($RootMargin/Root/PageStack/PageCodex/ConversationPanel, Color("151922"), 12, 12)
	_apply_panel_style($RootMargin/Root/PageStack/PageCodex/ComposerPanel, Color("1a1f2a"), 24, 18)
	_apply_panel_style($RootMargin/Root/PageStack/PageSessions/SessionManagePanel, Color("171a20"), 12, 12)
	_apply_panel_style($RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ActiveSessionsPanel, Color("151922"), 10, 10)
	_apply_panel_style($RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ArchivedSessionsPanel, Color("151922"), 10, 10)
	_apply_panel_style($RootMargin/Root/PageStack/PageTools/ToolResultPanel, Color("171a20"), 12, 12)
	_apply_panel_style($RootMargin/Root/PageStack/PageReview/ChangeSetPreviewPanel, Color("171a20"), 12, 12)
	_apply_panel_style($RootMargin/Root/PageStack/PageSettings/OverviewStatusPanel, Color("171a20"), 12, 12)
	_apply_panel_style($RootMargin/Root/PageStack/PageSettings/SettingsPanel, Color("171a20"), 12, 12)
	_apply_panel_style($RootMargin/Root/PageStack/PageSettings/RuntimeLogPanel, Color("171a20"), 12, 12)

	for button in [_tab_codex, _sessions_button, _tab_tools, _tab_review, _tab_settings]:
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE

	_session_picker.focus_mode = Control.FOCUS_NONE
	_session_picker.add_theme_color_override("font_color", muted)
	_session_picker.add_theme_stylebox_override("normal", _build_subtle_stylebox())
	_session_picker.add_theme_stylebox_override("hover", _build_subtle_stylebox(Color("212632")))
	_session_picker.add_theme_stylebox_override("pressed", _build_subtle_stylebox(Color("252b38")))
	_session_picker.add_theme_stylebox_override("focus", _build_subtle_stylebox(Color("212632")))
	_cancel_button.flat = true
	_cancel_button.add_theme_color_override("font_color", muted)
	_apply_nav_state()


func _apply_panel_style(node: Control, bg_color: Color, radius: int, margin: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = margin
	style.content_margin_top = margin
	style.content_margin_right = margin
	style.content_margin_bottom = margin
	node.add_theme_stylebox_override("panel", style)


func _build_subtle_stylebox(bg_color = null) -> StyleBoxFlat:
	var resolved_bg := Color("141922")
	if bg_color is Color:
		resolved_bg = bg_color
	var style := StyleBoxFlat.new()
	style.bg_color = resolved_bg
	style.border_color = Color("2a3140")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _apply_nav_state() -> void:
	var active_text := Color("eef3fb")
	var inactive_text := Color("a4adba")
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = Color(0, 0, 0, 0)
	active_style.border_color = Color("6ea8fe")
	active_style.set_border_width_all(0)
	active_style.border_width_bottom = 2

	var inactive_style := StyleBoxFlat.new()
	inactive_style.bg_color = Color(0, 0, 0, 0)
	inactive_style.set_border_width_all(0)

	_apply_nav_button(_tab_codex, _current_page == PAGE_CODEX, active_text, inactive_text, active_style, inactive_style)
	_apply_nav_button(_sessions_button, _current_page == PAGE_SESSIONS, active_text, inactive_text, active_style, inactive_style)
	_apply_nav_button(_tab_tools, _current_page == PAGE_TOOLS, active_text, inactive_text, active_style, inactive_style)
	_apply_nav_button(_tab_review, _current_page == PAGE_REVIEW, active_text, inactive_text, active_style, inactive_style)
	_apply_nav_button(_tab_settings, _current_page == PAGE_SETTINGS, active_text, inactive_text, active_style, inactive_style)


func _apply_nav_button(button: Button, is_active: bool, active_text: Color, inactive_text: Color, active_style: StyleBoxFlat, inactive_style: StyleBoxFlat) -> void:
	button.button_pressed = is_active
	button.add_theme_color_override("font_color", active_text if is_active else inactive_text)
	button.add_theme_stylebox_override("normal", active_style if is_active else inactive_style)
	button.add_theme_stylebox_override("hover", active_style if is_active else inactive_style)
	button.add_theme_stylebox_override("pressed", active_style if is_active else inactive_style)


func _apply_settings() -> void:
	var providers = _model.get("provider_map", {})
	var active_provider := str(_model.get("active_provider", "openai_compatible"))
	_provider_select.clear()
	var active_index := 0
	var idx := 0
	for provider_id in providers.keys():
		_provider_select.add_item(str(provider_id))
		if str(provider_id) == active_provider:
			active_index = idx
		idx += 1
	if _provider_select.item_count > 0:
		_provider_select.select(active_index)

	var provider_cfg = providers.get(active_provider, {})
	_model_edit.text = str(provider_cfg.get("model", ""))
	_base_url_edit.text = str(provider_cfg.get("base_url", ""))
	_api_key_edit.text = str(provider_cfg.get("api_key", ""))

	var remote_servers = _model.get("remote_servers", {})
	if remote_servers.has("main"):
		var main = remote_servers["main"]
		_remote_id_edit.text = str(main.get("id", "main"))
		_remote_url_edit.text = str(main.get("endpoint", "http://127.0.0.1:3000"))
	else:
		_remote_id_edit.text = "main"
		_remote_url_edit.text = "http://127.0.0.1:3000"


func _apply_session_picker() -> void:
	var sessions = _model.get("sessions", [])
	var active_session_id := str(_model.get("active_session_id", ""))
	_session_picker.clear()
	var selected_index := -1
	for session in sessions:
		if not (session is Dictionary):
			continue
		if bool(session.get("archived", false)):
			continue
		var session_id := str(session.get("id", ""))
		_session_picker.add_item(str(session.get("title", "New Session")))
		_session_picker.set_item_metadata(_session_picker.item_count - 1, session_id)
		if session_id == active_session_id:
			selected_index = _session_picker.item_count - 1
	if _session_picker.item_count > 0:
		_session_picker.select(maxi(selected_index, 0))


func _apply_sessions_page() -> void:
	var sessions = _model.get("sessions", [])
	var active_session_id := str(_model.get("active_session_id", ""))
	_active_session_ids.clear()
	_archived_session_ids.clear()
	_active_sessions_list.clear()
	_archived_sessions_list.clear()
	_rename_session_edit.text = ""

	for session in sessions:
		if not (session is Dictionary):
			continue
		var session_id := str(session.get("id", ""))
		var title := str(session.get("title", "New Session"))
		if bool(session.get("archived", false)):
			_archived_sessions_list.add_item(title)
			_archived_session_ids.append(session_id)
		else:
			_active_sessions_list.add_item(title)
			_active_session_ids.append(session_id)
			if session_id == active_session_id:
				_active_sessions_list.select(_active_sessions_list.item_count - 1)

	if _active_sessions_list.get_selected_items().is_empty() and _active_sessions_list.item_count > 0:
		_active_sessions_list.select(0)
	if _active_sessions_list.get_selected_items().is_empty() and _archived_sessions_list.item_count > 0:
		_archived_sessions_list.select(0)

	var title := _get_selected_session_title()
	if not title.is_empty():
		_rename_session_edit.text = title
	_refresh_session_actions()


func _refresh_session_actions() -> void:
	var active_id := _get_selected_active_session_id()
	var archived_id := _get_selected_archived_session_id()
	_open_session_button.disabled = active_id.is_empty()
	_archive_session_button_page.disabled = active_id.is_empty()
	_delete_archived_button.disabled = archived_id.is_empty()
	_rename_session_button.disabled = _get_selected_session_id().is_empty() or _rename_session_edit.text.strip_edges().is_empty()


func _apply_session() -> void:
	var session = _model.get("session", {})
	var messages = session.get("messages", [])
	var lines := PackedStringArray()
	for message in messages:
		if not (message is Dictionary):
			continue
		var role := str(message.get("role", "assistant"))
		var content := str(message.get("content", ""))
		if content.is_empty():
			continue
		lines.append(("You" if role == "user" else "Orbit") + "\n" + content)
		lines.append("")
	var stream_preview := str(_model.get("stream_preview", ""))
	if not stream_preview.is_empty():
		lines.append("Orbit\n" + stream_preview)
	_conversation_log.text = "\n".join(lines)


func _apply_validation() -> void:
	var summary = _model.get("validation_summary", {})
	var regression = summary.get("regression", {})
	var lines := PackedStringArray()
	if bool(regression.get("success", false)):
		var passed := int(regression.get("passed", 0))
		var total := int(regression.get("total", 0))
		_validation_badge.text = "Validation %d/%d" % [passed, total]
		lines.append("Regression: %d/%d passed" % [passed, total])
	else:
		_validation_badge.text = "Validation pending"
		lines.append("Regression: pending")
	for provider in summary.get("providers", []):
		if provider is Dictionary:
			lines.append("Provider %s: %s" % [str(provider.get("id", "")), str(provider.get("mode", "missing"))])
	var remote_health = _model.get("remote_health", {})
	for server_id in remote_health.keys():
		var item = remote_health[server_id]
		lines.append("MCP %s: %s" % [str(server_id), "ok" if bool(item.get("success", false)) else str(item.get("error", "error"))])
	_overview_status.text = "\n".join(lines)


func _apply_tools() -> void:
	var tools = _model.get("tools", [])
	_tool_select.clear()
	for tool in tools:
		if not (tool is Dictionary):
			continue
		var tool_id := str(tool.get("id", ""))
		var label := "%s  %s" % [str(tool.get("source", "local")).to_upper(), tool_id]
		_tool_select.add_item(label)
		_tool_select.set_item_metadata(_tool_select.item_count - 1, tool_id)
	if _tool_select.item_count > 0:
		_tool_select.select(0)
		_on_tool_selected(0)
	_apply_tool_result()


func _apply_tool_result() -> void:
	var last_tool_result = _model.get("last_tool_result", {})
	if last_tool_result.is_empty():
		_tool_result.text = "No tool result yet."
		return
	var lines := PackedStringArray()
	lines.append("Tool: %s" % str(last_tool_result.get("tool_id", "")))
	lines.append("At: %s" % str(last_tool_result.get("at", "")))
	lines.append("")
	lines.append(JSON.stringify(last_tool_result.get("result", {}), "\t"))
	_tool_result.text = "\n".join(lines)


func _apply_change_sets() -> void:
	var items = _model.get("pending_change_sets", [])
	_change_set_select.clear()
	for item in items:
		if not (item is Dictionary):
			continue
		var change_id := str(item.get("id", ""))
		var label := "%s | %s" % [change_id, str(item.get("file_path", ""))]
		_change_set_select.add_item(label)
		_change_set_select.set_item_metadata(_change_set_select.item_count - 1, change_id)
	if _change_set_select.item_count > 0:
		_change_set_select.select(0)
		_on_change_set_selected(0)
	else:
		_change_set_preview.text = "No pending change sets."


func _apply_logs() -> void:
	var logs = _model.get("logs", [])
	var lines := PackedStringArray()
	var start_index := maxi(logs.size() - 10, 0)
	for i in range(start_index, logs.size()):
		lines.append(str(logs[i]))
	_runtime_log.text = "\n".join(lines)


func _on_save_settings_pressed() -> void:
	if _provider_select.item_count == 0:
		return
	var provider_id := _provider_select.get_item_text(_provider_select.selected)
	var providers = _model.get("provider_map", {})
	var provider_cfg = providers.get(provider_id, {}).duplicate(true)
	provider_cfg["model"] = _model_edit.text
	provider_cfg["base_url"] = _base_url_edit.text
	provider_cfg["api_key"] = _api_key_edit.text
	var remote_id := _remote_id_edit.text.strip_edges()
	if remote_id.is_empty():
		remote_id = "main"
	save_settings_requested.emit({
		"active_provider": provider_id,
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


func _on_tab_codex_pressed() -> void:
	_set_page(PAGE_CODEX)


func _on_sessions_button_pressed() -> void:
	_set_page(PAGE_SESSIONS)


func _on_tab_tools_pressed() -> void:
	_set_page(PAGE_TOOLS)


func _on_tab_review_pressed() -> void:
	_set_page(PAGE_REVIEW)


func _on_tab_settings_pressed() -> void:
	_set_page(PAGE_SETTINGS)


func _on_approve_pressed() -> void:
	_on_approve_changed(true)


func _on_reject_pressed() -> void:
	_on_approve_changed(false)


func _on_rename_session_text_changed(_new_text: String) -> void:
	_refresh_session_actions()


func _on_refresh_remote_pressed() -> void:
	refresh_remote_tools_requested.emit()


func _on_send_prompt_pressed() -> void:
	var prompt := _prompt_edit.text.strip_edges()
	if prompt.is_empty():
		return
	send_prompt_requested.emit(prompt, _policy_select.get_item_text(_policy_select.selected))
	_prompt_edit.clear()


func _on_cancel_run_pressed() -> void:
	cancel_run_requested.emit()


func _on_run_tool_pressed() -> void:
	if _tool_select.item_count == 0:
		return
	run_tool_requested.emit(str(_tool_select.get_item_metadata(_tool_select.selected)), _tool_args_edit.text)


func _on_approve_changed(approved: bool) -> void:
	if _change_set_select.item_count == 0:
		return
	approve_change_set_requested.emit(str(_change_set_select.get_item_metadata(_change_set_select.selected)), approved)


func _on_tool_selected(index: int) -> void:
	if index < 0 or index >= _tool_select.item_count:
		return
	var tool_id := str(_tool_select.get_item_metadata(index))
	if tool_id.find("read_file") >= 0:
		_tool_args_edit.text = "{\"path\":\"res://README.md\"}"
	elif tool_id.find("search_files") >= 0:
		_tool_args_edit.text = "{\"pattern\":\"*.gd\",\"path\":\"res://addons/orbit_pilot\"}"
	elif tool_id.find("run_regression_suite") >= 0:
		_tool_args_edit.text = "{}"
	elif tool_id.find("apply_change_set") >= 0:
		_tool_args_edit.text = "{\"change_set_id\":\"\",\"approved\":true}"
	else:
		_tool_args_edit.text = "{}"


func _on_change_set_selected(index: int) -> void:
	if index < 0 or index >= _change_set_select.item_count:
		return
	var selected_id := str(_change_set_select.get_item_metadata(index))
	for item in _model.get("pending_change_sets", []):
		if item is Dictionary and str(item.get("id", "")) == selected_id:
			_change_set_preview.text = "File: %s\nStatus: %s\n\n%s" % [
				str(item.get("file_path", "")),
				str(item.get("status", "")),
				str(item.get("preview", "")),
			]
			return


func _on_provider_selected(index: int) -> void:
	if index < 0 or index >= _provider_select.item_count:
		return
	provider_selected_requested.emit(_provider_select.get_item_text(index))


func _on_policy_selected(_index: int) -> void:
	pass


func _on_session_picker_selected(index: int) -> void:
	if index < 0 or index >= _session_picker.item_count:
		return
	var session_id := str(_session_picker.get_item_metadata(index))
	if not session_id.is_empty():
		session_selected_requested.emit(session_id)


func _on_new_session_pressed() -> void:
	session_create_requested.emit()


func _on_open_selected_session_pressed() -> void:
	var session_id := _get_selected_active_session_id()
	if session_id.is_empty():
		return
	session_selected_requested.emit(session_id)
	_set_page(PAGE_CODEX)


func _on_archive_selected_session_pressed() -> void:
	var session_id := _get_selected_active_session_id()
	if not session_id.is_empty():
		session_archive_requested.emit(session_id)


func _on_delete_archived_session_pressed() -> void:
	var session_id := _get_selected_archived_session_id()
	if not session_id.is_empty():
		session_delete_requested.emit(session_id)


func _on_rename_session_pressed() -> void:
	var session_id := _get_selected_session_id()
	var title := _rename_session_edit.text.strip_edges()
	if session_id.is_empty() or title.is_empty():
		return
	session_rename_requested.emit(session_id, title)


func _on_active_sessions_selected(index: int) -> void:
	if index < 0 or index >= _active_session_ids.size():
		return
	_archived_sessions_list.deselect_all()
	_rename_session_edit.text = _active_sessions_list.get_item_text(index)
	_refresh_session_actions()


func _on_archived_sessions_selected(index: int) -> void:
	if index < 0 or index >= _archived_session_ids.size():
		return
	_active_sessions_list.deselect_all()
	_rename_session_edit.text = _archived_sessions_list.get_item_text(index)
	_refresh_session_actions()


func _get_selected_active_session_id() -> String:
	var selected := _active_sessions_list.get_selected_items()
	if selected.is_empty():
		return ""
	var index := int(selected[0])
	if index < 0 or index >= _active_session_ids.size():
		return ""
	return str(_active_session_ids[index])


func _get_selected_archived_session_id() -> String:
	var selected := _archived_sessions_list.get_selected_items()
	if selected.is_empty():
		return ""
	var index := int(selected[0])
	if index < 0 or index >= _archived_session_ids.size():
		return ""
	return str(_archived_session_ids[index])


func _get_selected_session_id() -> String:
	var active_id := _get_selected_active_session_id()
	if not active_id.is_empty():
		return active_id
	return _get_selected_archived_session_id()


func _get_selected_session_title() -> String:
	var selected := _active_sessions_list.get_selected_items()
	if not selected.is_empty():
		return _active_sessions_list.get_item_text(int(selected[0]))
	selected = _archived_sessions_list.get_selected_items()
	if not selected.is_empty():
		return _archived_sessions_list.get_item_text(int(selected[0]))
	return ""


func _disable_auto_translate(node: Node) -> void:
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for child in node.get_children():
		if child is Node:
			_disable_auto_translate(child)
