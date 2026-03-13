@tool
class_name DockController
extends RefCounted

const ChromePainter = preload("res://addons/orbit_pilot/ui/chrome_painter.gd")
const OrbitPageCodex = preload("res://addons/orbit_pilot/ui/pages/page_codex.gd")
const OrbitPageSessions = preload("res://addons/orbit_pilot/ui/pages/page_sessions.gd")
const OrbitPageTools = preload("res://addons/orbit_pilot/ui/pages/page_tools.gd")
const OrbitPageReview = preload("res://addons/orbit_pilot/ui/pages/page_review.gd")
const OrbitPageSettings = preload("res://addons/orbit_pilot/ui/pages/page_settings.gd")

signal save_settings_requested(payload: Dictionary)
signal refresh_remote_tools_requested
signal send_prompt_requested(prompt: String, policy: String)
signal cancel_run_requested
signal run_tool_requested(tool_id: String, args_json: String)
signal approve_change_set_requested(change_set_id: String, approved: bool)
signal session_selected_requested(session_id: String)
signal session_create_requested
signal session_archive_requested(session_id: String)
signal session_delete_requested(session_id: String)
signal session_rename_requested(session_id: String, title: String)
signal provider_selected_requested(provider_id: String)

const PAGE_CODEX := 0
const PAGE_SESSIONS := 1
const PAGE_TOOLS := 2
const PAGE_REVIEW := 3
const PAGE_SETTINGS := 4

var _root: Control
var _current_page := PAGE_CODEX
var _chrome_painter: ChromePainter
var _tab_codex: Button
var _sessions_button: Button
var _tab_tools: Button
var _tab_review: Button
var _tab_settings: Button
var _page_stack: Control
var _status_pill: Label
var _status_label: Label
var _codex_page: OrbitPageCodex
var _sessions_page: OrbitPageSessions
var _tools_page: OrbitPageTools
var _review_page: OrbitPageReview
var _settings_page: OrbitPageSettings


func setup(editor_plugin: EditorPlugin, root: Control) -> void:
	_root = root
	_chrome_painter = ChromePainter.new()
	_chrome_painter.setup(editor_plugin, _root)
	_assign_nodes()
	_disable_auto_translate(_root)
	_setup_pages()
	_bind_navigation()
	_bind_page_signals()
	_apply_chrome()
	_set_page(PAGE_CODEX)


func apply_model(model: Dictionary) -> void:
	_codex_page.apply_model(model)
	_sessions_page.apply_model(model)
	_tools_page.apply_model(model)
	_review_page.apply_model(model)
	_settings_page.apply_model(model)
	var run_active := bool(model.get("is_run_active", false))
	_status_label.text = str(model.get("status_text", "OrbitPilot ready"))
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
	_status_label = _node("RootMargin/Root/Footer/FooterBox/StatusLabel")


func _setup_pages() -> void:
	_codex_page = OrbitPageCodex.new()
	_codex_page.setup(_root)
	_sessions_page = OrbitPageSessions.new()
	_sessions_page.setup(_root)
	_tools_page = OrbitPageTools.new()
	_tools_page.setup(_root)
	_review_page = OrbitPageReview.new()
	_review_page.setup(_root)
	_settings_page = OrbitPageSettings.new()
	_settings_page.setup(_root)


func _bind_navigation() -> void:
	_tab_codex.pressed.connect(_on_tab_codex_pressed)
	_sessions_button.pressed.connect(_on_tab_sessions_pressed)
	_tab_tools.pressed.connect(_on_tab_tools_pressed)
	_tab_review.pressed.connect(_on_tab_review_pressed)
	_tab_settings.pressed.connect(_on_tab_settings_pressed)


func _bind_page_signals() -> void:
	_codex_page.send_prompt_requested.connect(_on_send_prompt_requested)
	_codex_page.cancel_run_requested.connect(_on_cancel_run_requested)
	_codex_page.provider_selected_requested.connect(_on_provider_selected_requested)
	_codex_page.session_selected_requested.connect(_on_session_selected_requested)

	_sessions_page.session_create_requested.connect(_on_session_create_requested)
	_sessions_page.session_open_requested.connect(_on_session_open_requested)
	_sessions_page.session_archive_requested.connect(_on_session_archive_requested)
	_sessions_page.session_delete_requested.connect(_on_session_delete_requested)
	_sessions_page.session_rename_requested.connect(_on_session_rename_requested)

	_tools_page.run_tool_requested.connect(_on_run_tool_requested)
	_review_page.approve_change_set_requested.connect(_on_approve_change_set_requested)

	_settings_page.save_settings_requested.connect(_on_save_settings_requested)
	_settings_page.refresh_remote_tools_requested.connect(_on_refresh_remote_tools_requested)


func _on_tab_codex_pressed() -> void:
	_set_page(PAGE_CODEX)


func _on_tab_sessions_pressed() -> void:
	_set_page(PAGE_SESSIONS)


func _on_tab_tools_pressed() -> void:
	_set_page(PAGE_TOOLS)


func _on_tab_review_pressed() -> void:
	_set_page(PAGE_REVIEW)


func _on_tab_settings_pressed() -> void:
	_set_page(PAGE_SETTINGS)


func _on_send_prompt_requested(prompt: String, policy: String) -> void:
	emit_signal("send_prompt_requested", prompt, policy)


func _on_cancel_run_requested() -> void:
	emit_signal("cancel_run_requested")


func _on_provider_selected_requested(provider_id: String) -> void:
	emit_signal("provider_selected_requested", provider_id)


func _on_session_selected_requested(session_id: String) -> void:
	emit_signal("session_selected_requested", session_id)


func _on_session_create_requested() -> void:
	emit_signal("session_create_requested")


func _on_session_archive_requested(session_id: String) -> void:
	emit_signal("session_archive_requested", session_id)


func _on_session_delete_requested(session_id: String) -> void:
	emit_signal("session_delete_requested", session_id)


func _on_session_rename_requested(session_id: String, title: String) -> void:
	emit_signal("session_rename_requested", session_id, title)


func _on_run_tool_requested(tool_id: String, args_json: String) -> void:
	emit_signal("run_tool_requested", tool_id, args_json)


func _on_approve_change_set_requested(change_set_id: String, approved: bool) -> void:
	emit_signal("approve_change_set_requested", change_set_id, approved)


func _on_save_settings_requested(payload: Dictionary) -> void:
	emit_signal("save_settings_requested", payload)


func _on_refresh_remote_tools_requested() -> void:
	emit_signal("refresh_remote_tools_requested")


func _on_session_open_requested(session_id: String) -> void:
	emit_signal("session_selected_requested", session_id)
	_set_page(PAGE_CODEX)


func _set_page(page_index: int) -> void:
	_current_page = page_index
	for i in range(_page_stack.get_child_count()):
		var child = _page_stack.get_child(i)
		if child is CanvasItem:
			child.visible = i == page_index
	_apply_nav_state()


func _apply_chrome() -> void:
	_chrome_painter.paint_chrome(_build_nav_refs(), _build_page_panels())
	_apply_nav_state()


func _apply_nav_state() -> void:
	_chrome_painter.update_nav_state(_build_nav_refs(), _current_page)


func _build_nav_refs() -> Dictionary:
	var codex_refs := _codex_page.get_chrome_refs()
	var settings_refs := _settings_page.get_chrome_refs()
	return {
		"buttons": [_tab_codex, _sessions_button, _tab_tools, _tab_review, _tab_settings],
		"button_states": [
			{"button": _tab_codex, "page": PAGE_CODEX},
			{"button": _sessions_button, "page": PAGE_SESSIONS},
			{"button": _tab_tools, "page": PAGE_TOOLS},
			{"button": _tab_review, "page": PAGE_REVIEW},
			{"button": _tab_settings, "page": PAGE_SETTINGS},
		],
		"status_pill": _status_pill,
		"validation_badge": codex_refs.get("validation_badge"),
		"runtime_log": settings_refs.get("runtime_log"),
		"session_picker": codex_refs.get("session_picker"),
		"send_button": codex_refs.get("send_button"),
		"cancel_button": codex_refs.get("cancel_button"),
	}


func _build_page_panels() -> Dictionary:
	var panels := {"header": _node("RootMargin/Root/Header"), "footer": _node("RootMargin/Root/Footer")}
	panels.merge(_codex_page.get_chrome_panels())
	panels.merge(_sessions_page.get_chrome_panels())
	panels.merge(_tools_page.get_chrome_panels())
	panels.merge(_review_page.get_chrome_panels())
	panels.merge(_settings_page.get_chrome_panels())
	return panels


func _disable_auto_translate(node: Node) -> void:
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for child in node.get_children():
		if child is Node:
			_disable_auto_translate(child)
