@tool
extends EditorPlugin

const OrbitTypes = preload("res://addons/orbit_pilot/core/types.gd")
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
const DOCK_SCENE_PATH := "res://addons/orbit_pilot/ui/orbit_dock.tscn"


class DockController extends RefCounted:
	const PAGE_CODEX := 0
	const PAGE_SESSIONS := 1
	const PAGE_TOOLS := 2
	const PAGE_REVIEW := 3
	const PAGE_SETTINGS := 4

	var _host
	var _root
	var _model := {}
	var _current_page := PAGE_CODEX
	var _active_session_ids := []
	var _archived_session_ids := []

	var _tab_codex
	var _sessions_button
	var _tab_tools
	var _tab_review
	var _tab_settings
	var _page_stack
	var _status_pill
	var _session_picker
	var _conversation_log
	var _provider_select
	var _policy_select
	var _validation_badge
	var _prompt_edit
	var _send_button
	var _cancel_button
	var _new_session_button_page
	var _open_session_button
	var _archive_session_button_page
	var _delete_archived_button
	var _rename_session_edit
	var _rename_session_button
	var _active_sessions_list
	var _archived_sessions_list
	var _tool_select
	var _tool_args_edit
	var _run_tool_button
	var _tool_result
	var _change_set_select
	var _change_set_preview
	var _approve_button
	var _reject_button
	var _overview_status
	var _model_edit
	var _base_url_edit
	var _api_key_edit
	var _remote_id_edit
	var _remote_url_edit
	var _save_button
	var _refresh_remote_button
	var _runtime_log
	var _status_label

	func setup(host, root: Control) -> void:
		_host = host
		_root = root
		_assign_nodes()
		_disable_auto_translate(_root)
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

	func _node(path: String):
		return _root.get_node(path)

	func _assign_nodes() -> void:
		_tab_codex = _node("RootMargin/Root/Header/HeaderBox/Nav/TabCodex")
		_sessions_button = _node("RootMargin/Root/Header/HeaderBox/Nav/SessionsButton")
		_tab_tools = _node("RootMargin/Root/Header/HeaderBox/Nav/TabTools")
		_tab_review = _node("RootMargin/Root/Header/HeaderBox/Nav/TabReview")
		_tab_settings = _node("RootMargin/Root/Header/HeaderBox/Nav/TabSettings")
		_page_stack = _node("RootMargin/Root/PageStack")
		_status_pill = _node("RootMargin/Root/Header/HeaderBox/StatusPill")
		_session_picker = _node("RootMargin/Root/PageStack/PageCodex/CodexTop/TitleBlock/SessionPicker")
		_conversation_log = _node("RootMargin/Root/PageStack/PageCodex/ConversationPanel/ConversationLog")
		_provider_select = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerMeta/ProviderSelect")
		_policy_select = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerMeta/PolicySelect")
		_validation_badge = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerMeta/ValidationBadge")
		_prompt_edit = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/PromptEdit")
		_send_button = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerActions/SendPromptButton")
		_cancel_button = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerActions/CancelRunButton")
		_new_session_button_page = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/NewSessionButtonPage")
		_open_session_button = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/OpenSessionButton")
		_archive_session_button_page = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/ArchiveSessionButtonPage")
		_delete_archived_button = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/DeleteArchivedButton")
		_rename_session_edit = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionRenameRow/RenameSessionEdit")
		_rename_session_button = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionRenameRow/RenameSessionButton")
		_active_sessions_list = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ActiveSessionsPanel/ActiveSessionsBox/ActiveSessionsList")
		_archived_sessions_list = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ArchivedSessionsPanel/ArchivedSessionsBox/ArchivedSessionsList")
		_tool_select = _node("RootMargin/Root/PageStack/PageTools/ToolSelect")
		_tool_args_edit = _node("RootMargin/Root/PageStack/PageTools/ToolArgsEdit")
		_run_tool_button = _node("RootMargin/Root/PageStack/PageTools/RunToolButton")
		_tool_result = _node("RootMargin/Root/PageStack/PageTools/ToolResultPanel/ToolResult")
		_change_set_select = _node("RootMargin/Root/PageStack/PageReview/ChangeSetSelect")
		_change_set_preview = _node("RootMargin/Root/PageStack/PageReview/ChangeSetPreviewPanel/ChangeSetPreview")
		_approve_button = _node("RootMargin/Root/PageStack/PageReview/ReviewButtons/ApproveButton")
		_reject_button = _node("RootMargin/Root/PageStack/PageReview/ReviewButtons/RejectButton")
		_overview_status = _node("RootMargin/Root/PageStack/PageSettings/OverviewStatusPanel/OverviewStatus")
		_model_edit = _node("RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/ModelEdit")
		_base_url_edit = _node("RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/BaseUrlEdit")
		_api_key_edit = _node("RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/ApiKeyEdit")
		_remote_id_edit = _node("RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/RemoteIdEdit")
		_remote_url_edit = _node("RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/RemoteUrlEdit")
		_save_button = _node("RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/SettingsButtons/SaveSettingsButton")
		_refresh_remote_button = _node("RootMargin/Root/PageStack/PageSettings/SettingsPanel/Settings/SettingsButtons/RefreshRemoteButton")
		_runtime_log = _node("RootMargin/Root/PageStack/PageSettings/RuntimeLogPanel/RuntimeLog")
		_status_label = _node("RootMargin/Root/Footer/FooterBox/StatusLabel")

	func _bind_events() -> void:
		_tab_codex.pressed.connect(func() -> void: _set_page(PAGE_CODEX))
		_sessions_button.pressed.connect(func() -> void: _set_page(PAGE_SESSIONS))
		_tab_tools.pressed.connect(func() -> void: _set_page(PAGE_TOOLS))
		_tab_review.pressed.connect(func() -> void: _set_page(PAGE_REVIEW))
		_tab_settings.pressed.connect(func() -> void: _set_page(PAGE_SETTINGS))
		_save_button.pressed.connect(_on_save_settings_pressed)
		_refresh_remote_button.pressed.connect(_host._on_refresh_remote_tools_requested)
		_send_button.pressed.connect(_on_send_prompt_pressed)
		_cancel_button.pressed.connect(_host._on_cancel_run_requested)
		_run_tool_button.pressed.connect(_on_run_tool_pressed)
		_approve_button.pressed.connect(func() -> void: _on_approve_changed(true))
		_reject_button.pressed.connect(func() -> void: _on_approve_changed(false))
		_new_session_button_page.pressed.connect(_host._on_session_create_requested)
		_open_session_button.pressed.connect(_on_open_selected_session_pressed)
		_archive_session_button_page.pressed.connect(_on_archive_selected_session_pressed)
		_delete_archived_button.pressed.connect(_on_delete_archived_session_pressed)
		_rename_session_button.pressed.connect(_on_rename_session_pressed)
		_rename_session_edit.text_changed.connect(func(_new_text: String) -> void: _refresh_session_actions())
		_active_sessions_list.item_selected.connect(_on_active_sessions_selected)
		_archived_sessions_list.item_selected.connect(_on_archived_sessions_selected)
		_provider_select.item_selected.connect(_on_provider_selected)
		_policy_select.item_selected.connect(func(_index: int) -> void: pass)
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
		var accent := _get_editor_accent()
		var composer_bg := _mix_with(accent, Color("141b26"), 0.14)
		var chrome_bg := composer_bg
		var panel_bg := _mix_with(accent, Color("151922"), 0.08)
		_status_pill.add_theme_color_override("font_color", accent)
		_validation_badge.add_theme_color_override("font_color", muted)
		_runtime_log.add_theme_color_override("default_color", muted)
		_session_picker.add_theme_color_override("font_color", muted)
		_send_button.add_theme_color_override("font_color", Color("eef4ff"))
		_cancel_button.add_theme_color_override("font_color", muted)
		_apply_panel_style(_node("RootMargin/Root/Header"), chrome_bg, 12, 12)
		_apply_panel_style(_node("RootMargin/Root/PageStack/PageCodex/ConversationPanel"), Color("151922"), 12, 12)
		_apply_panel_style(_node("RootMargin/Root/PageStack/PageCodex/ComposerPanel"), composer_bg, 22, 18)
		_apply_panel_style(_node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel"), panel_bg, 12, 12)
		_apply_panel_style(_node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ActiveSessionsPanel"), Color("151922"), 10, 10)
		_apply_panel_style(_node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ArchivedSessionsPanel"), Color("151922"), 10, 10)
		_apply_panel_style(_node("RootMargin/Root/PageStack/PageTools/ToolResultPanel"), panel_bg, 12, 12)
		_apply_panel_style(_node("RootMargin/Root/PageStack/PageReview/ChangeSetPreviewPanel"), panel_bg, 12, 12)
		_apply_panel_style(_node("RootMargin/Root/PageStack/PageSettings/OverviewStatusPanel"), panel_bg, 12, 12)
		_apply_panel_style(_node("RootMargin/Root/PageStack/PageSettings/SettingsPanel"), panel_bg, 12, 12)
		_apply_panel_style(_node("RootMargin/Root/PageStack/PageSettings/RuntimeLogPanel"), panel_bg, 12, 12)
		_apply_panel_style(_node("RootMargin/Root/Footer"), chrome_bg, 12, 10)
		_session_picker.add_theme_stylebox_override("normal", _build_subtle_stylebox(chrome_bg))
		_session_picker.add_theme_stylebox_override("hover", _build_subtle_stylebox(_mix_with(accent, chrome_bg, 0.10)))
		_session_picker.add_theme_stylebox_override("pressed", _build_subtle_stylebox(_mix_with(accent, chrome_bg, 0.14)))
		_session_picker.add_theme_stylebox_override("focus", _build_subtle_stylebox(_mix_with(accent, chrome_bg, 0.14)))
		for button in [_tab_codex, _sessions_button, _tab_tools, _tab_review, _tab_settings]:
			button.flat = true
			button.focus_mode = Control.FOCUS_NONE
		_cancel_button.flat = true
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

	func _build_subtle_stylebox(bg_color: Color) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = bg_color
		style.border_color = _mix_with(_get_editor_accent(), bg_color, 0.35)
		style.set_border_width_all(1)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		return style

	func _apply_nav_state() -> void:
		var active_text := Color("eef3fb")
		var inactive_text := Color("a4adba")
		var accent := _get_editor_accent()
		var active_style := StyleBoxFlat.new()
		active_style.bg_color = Color(0, 0, 0, 0)
		active_style.border_color = accent
		active_style.set_border_width_all(0)
		active_style.border_width_bottom = 2
		var inactive_style := StyleBoxFlat.new()
		inactive_style.bg_color = Color(0, 0, 0, 0)
		inactive_style.set_border_width_all(0)
		for pair in [
			[_tab_codex, _current_page == PAGE_CODEX],
			[_sessions_button, _current_page == PAGE_SESSIONS],
			[_tab_tools, _current_page == PAGE_TOOLS],
			[_tab_review, _current_page == PAGE_REVIEW],
			[_tab_settings, _current_page == PAGE_SETTINGS],
		]:
			var button: Button = pair[0]
			var is_active := bool(pair[1])
			button.button_pressed = is_active
			button.add_theme_color_override("font_color", active_text if is_active else inactive_text)
			button.add_theme_stylebox_override("normal", active_style if is_active else inactive_style)
			button.add_theme_stylebox_override("hover", active_style if is_active else inactive_style)
			button.add_theme_stylebox_override("pressed", active_style if is_active else inactive_style)

	func _get_editor_accent() -> Color:
		var base: Control = _host.get_editor_interface().get_base_control()
		if base != null:
			var accent: Color = base.get_theme_color("accent_color", "Editor")
			if accent != Color():
				return accent
		return Color("6ea8fe")

	func _mix_with(tint: Color, base: Color, weight: float) -> Color:
		return base.lerp(tint, clampf(weight, 0.0, 1.0))

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
		if bool(regression.get("success", false)):
			var passed := int(regression.get("passed", 0))
			var total := int(regression.get("total", 0))
			_validation_badge.text = "Validation %d/%d" % [passed, total]
		else:
			_validation_badge.text = "Validation pending"
		var remote_health = _model.get("remote_health", {})
		var lines := PackedStringArray()
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
		_tool_result.text = "Tool: %s\nAt: %s\n\n%s" % [
			str(last_tool_result.get("tool_id", "")),
			str(last_tool_result.get("at", "")),
			JSON.stringify(last_tool_result.get("result", {}), "\t"),
		]

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
		var provider_id: String = _provider_select.get_item_text(_provider_select.selected)
		var providers: Dictionary = _model.get("provider_map", {})
		var provider_cfg: Dictionary = providers.get(provider_id, {}).duplicate(true)
		provider_cfg["model"] = _model_edit.text
		provider_cfg["base_url"] = _base_url_edit.text
		provider_cfg["api_key"] = _api_key_edit.text
		var remote_id: String = _remote_id_edit.text.strip_edges()
		if remote_id.is_empty():
			remote_id = "main"
		_host._on_save_settings_requested({
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

	func _on_send_prompt_pressed() -> void:
		var prompt: String = _prompt_edit.text.strip_edges()
		if prompt.is_empty():
			return
		_host._on_send_prompt_requested(prompt, _policy_select.get_item_text(_policy_select.selected))
		_prompt_edit.clear()

	func _on_run_tool_pressed() -> void:
		if _tool_select.item_count == 0:
			return
		_host._on_run_tool_requested(str(_tool_select.get_item_metadata(_tool_select.selected)), _tool_args_edit.text)

	func _on_approve_changed(approved: bool) -> void:
		if _change_set_select.item_count == 0:
			return
		_host._on_approve_change_set_requested(str(_change_set_select.get_item_metadata(_change_set_select.selected)), approved)

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
		_host._on_provider_selected_requested(_provider_select.get_item_text(index))

	func _on_session_picker_selected(index: int) -> void:
		if index < 0 or index >= _session_picker.item_count:
			return
		var session_id := str(_session_picker.get_item_metadata(index))
		if not session_id.is_empty():
			_host._on_session_selected_requested(session_id)

	func _on_open_selected_session_pressed() -> void:
		var session_id := _get_selected_active_session_id()
		if session_id.is_empty():
			return
		_host._on_session_selected_requested(session_id)
		_set_page(PAGE_CODEX)

	func _on_archive_selected_session_pressed() -> void:
		var session_id := _get_selected_active_session_id()
		if not session_id.is_empty():
			_host._on_session_archive_requested(session_id)

	func _on_delete_archived_session_pressed() -> void:
		var session_id := _get_selected_archived_session_id()
		if not session_id.is_empty():
			_host._on_session_delete_requested(session_id)

	func _on_rename_session_pressed() -> void:
		var session_id := _get_selected_session_id()
		var title: String = _rename_session_edit.text.strip_edges()
		if session_id.is_empty() or title.is_empty():
			return
		_host._on_session_rename_requested(session_id, title)

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
		var selected: PackedInt32Array = _active_sessions_list.get_selected_items()
		if selected.is_empty():
			return ""
		var index := int(selected[0])
		if index < 0 or index >= _active_session_ids.size():
			return ""
		return str(_active_session_ids[index])

	func _get_selected_archived_session_id() -> String:
		var selected: PackedInt32Array = _archived_sessions_list.get_selected_items()
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
		var selected: PackedInt32Array = _active_sessions_list.get_selected_items()
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

var _dock
var _dock_controller
var _dock_controller_ready := false
var _settings_store := OrbitSettingsStore.new()
var _settings: Dictionary = {}
var _logs: Array[String] = []
var _active_run_id := ""
var _is_run_active := false
var _stream_preview := ""
var _validation_summary: Dictionary = {}
var _remote_health: Dictionary = {}
var _last_tool_result: Dictionary = {}

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
	_execution_service.setup(
		{
			_openai_provider.get_id(): _openai_provider,
			"deepseek": _openai_provider,
			_anthropic_provider.get_id(): _anthropic_provider,
		},
		_tool_router
	)

	_create_dock()
	_refresh_dock("OrbitPilot initializing")
	call_deferred("_post_enter_setup")


func _init_services() -> bool:
	_openai_provider = _safe_new(OpenAIProvider, "OpenAIProvider")
	_anthropic_provider = _safe_new(AnthropicProvider, "AnthropicProvider")
	_remote_client = _safe_new(RemoteMcpClient, "RemoteMcpClient")
	_local_tools = _safe_new(LocalTools, "LocalTools")
	_tool_catalog = _safe_new(ToolCatalog, "ToolCatalog")
	_tool_router = _safe_new(ToolRouter, "ToolRouter")
	_context_index_service = _safe_new(ContextIndexService, "ContextIndexService")
	_regression_runner = _safe_new(OrbitRegressionRunner, "OrbitRegressionRunner")
	_change_set_service = _safe_new(ChangeSetService, "ChangeSetService")
	_execution_service = _safe_new(ExecutionService, "ExecutionService")
	return (
		_openai_provider != null
		and _anthropic_provider != null
		and _remote_client != null
		and _local_tools != null
		and _tool_catalog != null
		and _tool_router != null
		and _context_index_service != null
		and _regression_runner != null
		and _change_set_service != null
		and _execution_service != null
	)


func _safe_new(script_ref: Variant, label: String) -> Variant:
	if script_ref == null:
		push_error("[OrbitPilot] %s script ref is null" % label)
		return null
	if script_ref is Script:
		var script_obj: Script = script_ref
		if not script_obj.can_instantiate():
			push_error("[OrbitPilot] %s cannot instantiate: %s" % [label, str(script_obj.resource_path)])
			return null
		return script_obj.new()
	push_error("[OrbitPilot] %s is not a Script; may have parse/load errors" % label)
	return null


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
	_dock_controller_ready = true


func _connect_dock_signal(signal_name: String, callback: Callable) -> void:
	if _dock == null:
		return
	if _dock.has_signal(signal_name):
		_dock.connect(signal_name, callback)
	else:
		push_warning("[OrbitPilot] Dock missing signal: %s" % signal_name)


func _post_enter_setup() -> void:
	await _refresh_remote_tools()
	await _run_startup_validation()
	_push_log("plugin_loaded")
	_refresh_dock("OrbitPilot loaded")


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
		var health: Dictionary = await _remote_client.health_check(endpoint, float(cfg.get("timeout_sec", 8.0)))
		_remote_health[server_id] = health
		var result: Dictionary = await _remote_client.fetch_tools(endpoint, float(cfg.get("timeout_sec", 10.0)))
		if bool(result.get("success", false)):
			_tool_catalog.set_remote_tools(server_id, result.get("tools", []))
			_push_log("remote_tools_loaded:%s" % server_id)
		else:
			_tool_catalog.clear_remote_tools(server_id)
			_push_log("remote_tools_error:%s:%s" % [server_id, str(result.get("error", "unknown"))])


func _refresh_dock(status_text: String = "") -> void:
	if _dock == null:
		return
	var pending: Dictionary = _change_set_service.list_pending()
	var session: Dictionary = _ensure_session()
	var model := {
		"status_text": status_text if not status_text.is_empty() else "OrbitPilot ready",
		"active_provider": str(_settings.get("active_provider", "openai_compatible")),
		"active_session_id": str(session.get("id", "")),
		"provider_map": _settings.get("providers", {}),
		"remote_servers": _settings.get("remote_servers", {}),
		"remote_health": _remote_health,
		"tools": _tool_catalog.get_unified_tools(),
		"pending_change_sets": pending.get("items", []),
		"logs": _logs,
		"active_run_id": _active_run_id,
		"is_run_active": _is_run_active,
		"stream_preview": _stream_preview,
		"validation_summary": _validation_summary,
		"last_tool_result": _last_tool_result,
		"sessions": _settings.get("sessions", []),
		"session": session,
	}
	if _dock_controller_ready and _dock_controller != null:
		_dock_controller.apply_model(model)
	else:
		push_warning("[OrbitPilot] Dock controller missing apply_model")


func _save_settings() -> void:
	var res := _settings_store.save_settings(_settings)
	if not bool(res.get("success", false)):
		_push_log("save_settings_failed")


func _push_log(line: String) -> void:
	var ts := Time.get_datetime_string_from_system()
	_logs.append("[%s] %s" % [ts, line])
	var limit := int(_settings.get("log_limit", 300))
	while _logs.size() > limit:
		_logs.pop_front()


func _ensure_session() -> Dictionary:
	var sessions: Array = _settings.get("sessions", [])
	if sessions.is_empty():
		var created := OrbitTypes.default_session()
		sessions.append(created)
		_settings["sessions"] = sessions
		_settings["last_session_id"] = created["id"]
		return created

	var last_id := str(_settings.get("last_session_id", ""))
	for s in sessions:
		if s is Dictionary and str(s.get("id", "")) == last_id and not bool(s.get("archived", false)):
			return s
	for s in sessions:
		if s is Dictionary and not bool(s.get("archived", false)):
			return s
	var created := OrbitTypes.default_session()
	sessions.append(created)
	_settings["sessions"] = sessions
	_settings["last_session_id"] = created["id"]
	return created


func _sync_session(updated: Dictionary) -> void:
	var sessions: Array = _settings.get("sessions", [])
	var found := false
	for i in range(sessions.size()):
		var item = sessions[i]
		if item is Dictionary and str(item.get("id", "")) == str(updated.get("id", "")):
			sessions[i] = updated
			found = true
			break
	if not found:
		sessions.append(updated)
	_settings["sessions"] = sessions
	_settings["last_session_id"] = str(updated.get("id", ""))


func _build_agent_tools() -> Array:
	var tools: Array = []
	for item in _tool_catalog.get_unified_tools():
		var tool_name := str(item.get("name", ""))
		if tool_name.is_empty():
			tool_name = str(item.get("id", ""))
		tools.append({
			"name": tool_name,
			"description": "[%s] %s" % [str(item.get("id", "")), str(item.get("description", ""))],
			"input_schema": {
				"type": "object",
				"properties": {},
				"additionalProperties": true,
			}
		})
	return tools


func _on_save_settings_requested(payload: Dictionary) -> void:
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

	_save_settings()
	_push_log("settings_saved")
	await _refresh_remote_tools()
	await _run_startup_validation()
	_refresh_dock("Settings saved")


func _on_refresh_remote_tools_requested() -> void:
	await _refresh_remote_tools()
	await _run_startup_validation()
	_refresh_dock("Remote tools refreshed")


func _on_send_prompt_requested(prompt: String, policy: String) -> void:
	if _is_run_active:
		_push_log("run_rejected:another_run_active")
		_refresh_dock("Run already active")
		return

	_active_run_id = _new_run_id()
	_is_run_active = true
	_stream_preview = ""
	_refresh_dock("Run started: %s" % _active_run_id)

	var session: Dictionary = _ensure_session().duplicate(true)
	var messages: Array = session.get("messages", [])
	messages.append({"role": "user", "content": prompt})
	session["messages"] = messages
	_sync_session(session)
	_save_settings()
	_refresh_dock("Run started: %s" % _active_run_id)

	var provider_id := str(_settings.get("active_provider", "openai_compatible"))
	var provider_map: Dictionary = _settings.get("providers", {})
	var provider_cfg: Dictionary = provider_map.get(provider_id, {})
	var available_tools := _build_agent_tools()
	var turn_result: Dictionary = await _execution_service.execute_turn(
		policy,
		provider_id,
		provider_cfg,
		messages,
		available_tools,
		_active_run_id,
		Callable(self, "_on_execution_event")
	)
	if not bool(turn_result.get("success", false)):
		var run_error := _format_run_error(turn_result)
		var error_session: Dictionary = _ensure_session().duplicate(true)
		var error_messages: Array = error_session.get("messages", [])
		error_messages.append({"role": "assistant", "content": "Request failed: %s" % run_error})
		error_session["messages"] = error_messages
		_sync_session(error_session)
		_save_settings()
		_push_log("agent_error:%s" % run_error)
		_is_run_active = false
		_active_run_id = ""
		_stream_preview = ""
		if run_error == "run_cancelled":
			_refresh_dock("Run cancelled")
		else:
			_refresh_dock("Agent call failed")
		return

	var assistant_message: Dictionary = turn_result.get("assistant_message", {"role": "assistant", "content": ""})
	messages.append(assistant_message)
	session["messages"] = messages
	_sync_session(session)
	_save_settings()

	_push_log("assistant:%s" % str(assistant_message.get("content", "")))
	for tool_result in turn_result.get("tool_results", []):
		_push_log("tool_result:%s" % JSON.stringify(tool_result))

	_is_run_active = false
	_active_run_id = ""
	_stream_preview = ""
	_refresh_dock("Prompt executed")


func _on_run_tool_requested(tool_id: String, args_json: String) -> void:
	var args: Dictionary = {}
	if not args_json.strip_edges().is_empty():
		var parser := JSON.new()
		if parser.parse(args_json) == OK and parser.get_data() is Dictionary:
			args = parser.get_data()
		else:
			_push_log("tool_args_parse_error")
			_refresh_dock("Invalid tool args JSON")
			return

	var run_result: Dictionary = await _tool_router.execute(tool_id, args)
	_last_tool_result = {
		"tool_id": tool_id,
		"args": args,
		"result": run_result,
		"at": Time.get_datetime_string_from_system(),
	}
	_push_log("manual_tool:%s:%s" % [tool_id, JSON.stringify(run_result)])
	_refresh_dock("Tool executed")


func _on_approve_change_set_requested(change_set_id: String, approved: bool) -> void:
	var res: Dictionary = _change_set_service.apply_change_set(change_set_id, approved)
	_push_log("change_set:%s:%s" % [change_set_id, JSON.stringify(res)])
	_refresh_dock("Change set updated")


func _on_cancel_run_requested() -> void:
	if _active_run_id.is_empty():
		_refresh_dock("No active run")
		return
	_execution_service.cancel_run(_active_run_id)
	_push_log("run_cancel_requested:%s" % _active_run_id)
	_refresh_dock("Cancel requested: %s" % _active_run_id)


func _on_execution_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	var payload := event.get("payload", {})
	match kind:
		"status":
			_push_log("run_status:%s" % str(payload.get("message", "")))
		"message_delta":
			_stream_preview += str(payload.get("delta", ""))
		"tool_call":
			_push_log("tool_call:%s" % JSON.stringify(payload))
		"tool_call_delta":
			_push_log("tool_call_delta:%s" % JSON.stringify(payload))
		"tool_result":
			_push_log("tool_event_result:%s" % JSON.stringify(payload))
	_refresh_dock("Run active: %s" % _active_run_id if _is_run_active else "OrbitPilot ready")


func _on_session_selected_requested(session_id: String) -> void:
	if session_id.is_empty():
		return
	_settings["last_session_id"] = session_id
	_save_settings()
	_refresh_dock("Session switched")


func _on_session_create_requested() -> void:
	var created := OrbitTypes.default_session()
	var sessions: Array = _settings.get("sessions", [])
	sessions.append(created)
	_settings["sessions"] = sessions
	_settings["last_session_id"] = str(created.get("id", ""))
	_save_settings()
	_refresh_dock("New session created")


func _on_session_archive_requested(session_id: String) -> void:
	if session_id.is_empty():
		return
	var sessions: Array = _settings.get("sessions", [])
	var archived_title := ""
	for i in range(sessions.size()):
		var item: Variant = sessions[i]
		if item is Dictionary and str(item.get("id", "")) == session_id:
			var updated: Dictionary = (item as Dictionary).duplicate(true)
			updated["archived"] = true
			updated["archived_at"] = Time.get_datetime_string_from_system()
			sessions[i] = updated
			archived_title = str(updated.get("title", "Session"))
			break
	_settings["sessions"] = sessions
	if str(_settings.get("last_session_id", "")) == session_id:
		var created := OrbitTypes.default_session()
		sessions.append(created)
		_settings["sessions"] = sessions
		_settings["last_session_id"] = str(created.get("id", ""))
	_save_settings()
	_refresh_dock("Archived: %s" % archived_title)


func _on_session_delete_requested(session_id: String) -> void:
	if session_id.is_empty():
		return
	var sessions: Array = _settings.get("sessions", [])
	var kept: Array = []
	var deleted := false
	for item in sessions:
		if item is Dictionary and str(item.get("id", "")) == session_id:
			if bool(item.get("archived", false)):
				deleted = true
				continue
		kept.append(item)
	if not deleted:
		_refresh_dock("Only archived sessions can be deleted")
		return
	_settings["sessions"] = kept
	if str(_settings.get("last_session_id", "")) == session_id:
		_settings["last_session_id"] = ""
	_ensure_session()
	_save_settings()
	_refresh_dock("Session deleted")


func _on_session_rename_requested(session_id: String, title: String) -> void:
	var clean_title := title.strip_edges()
	if session_id.is_empty() or clean_title.is_empty():
		return
	var sessions: Array = _settings.get("sessions", [])
	for i in range(sessions.size()):
		var item: Variant = sessions[i]
		if item is Dictionary and str(item.get("id", "")) == session_id:
			var updated: Dictionary = (item as Dictionary).duplicate(true)
			updated["title"] = clean_title
			sessions[i] = updated
			break
	_settings["sessions"] = sessions
	_save_settings()
	_refresh_dock("Session renamed")


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


func _new_run_id() -> String:
	return "run_%s_%s" % [str(Time.get_unix_time_from_system()), str(randi())]


func _format_run_error(result: Dictionary) -> String:
	var error_code := str(result.get("error", "unknown"))
	var response_code := int(result.get("response_code", 0))
	var body: Variant = result.get("body", {})
	var detail := ""
	if body is Dictionary:
		var body_dict: Dictionary = body
		if body_dict.has("error"):
			var error_item: Variant = body_dict.get("error")
			if error_item is Dictionary:
				detail = str((error_item as Dictionary).get("message", ""))
			else:
				detail = str(error_item)
		elif body_dict.has("message"):
			detail = str(body_dict.get("message", ""))
		elif body_dict.has("detail"):
			detail = str(body_dict.get("detail", ""))
	elif body is String:
		detail = str(body)
	if response_code > 0 and not detail.is_empty():
		return "%s (%d: %s)" % [error_code, response_code, detail]
	if response_code > 0:
		return "%s (%d)" % [error_code, response_code]
	if not detail.is_empty():
		return "%s (%s)" % [error_code, detail]
	return error_code


func _run_startup_validation() -> void:
	var providers: Dictionary = _settings.get("providers", {})
	var provider_checks: Array[Dictionary] = []
	for provider_id in providers.keys():
		var cfg: Dictionary = providers[provider_id]
		var has_direct := not str(cfg.get("api_key", "")).strip_edges().is_empty()
		var env_name := str(cfg.get("api_key_env", "")).strip_edges()
		var has_env := false
		if not env_name.is_empty():
			has_env = not OS.get_environment(env_name).strip_edges().is_empty()
		provider_checks.append({
			"id": provider_id,
			"ready": has_direct or has_env,
			"mode": "direct" if has_direct else ("env" if has_env else "missing"),
		})

	var suite_result: Dictionary = await _regression_runner.run_minimal_suite()
	_validation_summary = {
		"providers": provider_checks,
		"regression": suite_result,
		"remote_health": _remote_health.duplicate(true),
		"updated_at": Time.get_datetime_string_from_system(),
	}
	if bool(suite_result.get("success", false)):
		_push_log("validation_suite:%s/%s" % [str(suite_result.get("passed", 0)), str(suite_result.get("total", 0))])
	else:
		_push_log("validation_suite_failed")
