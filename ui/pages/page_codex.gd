@tool
class_name OrbitPageCodex
extends RefCounted

signal send_prompt_requested(prompt: String, policy: String)
signal cancel_run_requested
signal provider_selected_requested(provider_id: String)
signal session_selected_requested(session_id: String)

const MarkdownConverter = preload("res://addons/orbit_pilot/core/utils/markdown_converter.gd")

var _root: Control
var _session_picker: OptionButton
var _conversation_log: RichTextLabel
var _provider_select: OptionButton
var _validation_badge: Label
var _prompt_edit: TextEdit
var _send_button: Button
var _cancel_button: Button
var _add_context_button: Button
var _language_select: OptionButton
var _context_toggle: Button
var _conversation_panel: Control
var _composer_panel: Control


func setup(dock_root: Control, editor_plugin: EditorPlugin) -> void:
	_root = dock_root
	_assign_nodes()
	_setup_icons(editor_plugin)
	_setup_language_select()
	_conversation_log.bbcode_enabled = true
	_bind_events()


func apply_model(model: Dictionary) -> void:
	_apply_provider_state(model)
	_apply_session_picker(model)
	_apply_session(model)
	_apply_validation(model)
	var run_active := bool(model.get("is_run_active", false))
	_send_button.disabled = run_active
	_cancel_button.disabled = not run_active


func get_chrome_panels() -> Dictionary:
	return {
		"conversation": _conversation_panel,
		"composer": _composer_panel,
	}


func get_chrome_refs() -> Dictionary:
	return {
		"validation_badge": _validation_badge,
		"session_picker": _session_picker,
		"send_button": _send_button,
		"cancel_button": _cancel_button,
	}


func _node(path: String):
	return _root.get_node(path)


func _assign_nodes() -> void:
	if _root == null:
		push_error("[OrbitPageCodex] _root is null in _assign_nodes")
		return
	_session_picker = _node("CodexTop/TitleBlock/SessionPicker")
	_conversation_panel = _node("ConversationPanel")
	_conversation_log = _node("ConversationPanel/ConversationLog")
	_composer_panel = _node("ComposerMargin/ComposerPanel")
	_prompt_edit = _node("ComposerMargin/ComposerPanel/Composer/PromptEdit")
	_add_context_button = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/AddContextButton")
	_provider_select = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/ProviderSelect")
	_language_select = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/LanguageSelect")
	_context_toggle = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/ContextToggle")
	_send_button = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/ComposerActions/SendPromptButton")
	_cancel_button = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/ComposerActions/CancelRunButton")
	_validation_badge = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/ValidationBadge")


func _bind_events() -> void:
	if _send_button:
		_send_button.pressed.connect(_on_send_prompt_pressed)
	if _cancel_button:
		_cancel_button.pressed.connect(func() -> void: emit_signal("cancel_run_requested"))
	if _provider_select:
		_provider_select.item_selected.connect(_on_provider_selected)
	if _session_picker:
		_session_picker.item_selected.connect(_on_session_picker_selected)


func _setup_icons(editor_plugin: EditorPlugin) -> void:
	var theme := editor_plugin.get_editor_interface().get_editor_theme()
	_add_context_button.icon = theme.get_icon("Add", "EditorIcons")
	_send_button.icon = theme.get_icon("Play", "EditorIcons")
	_send_button.text = ""
	_cancel_button.icon = theme.get_icon("Stop", "EditorIcons")


func _setup_language_select() -> void:
	_language_select.clear()
	_language_select.add_item("CN")
	_language_select.add_item("EN")
	_language_select.select(0)


func _apply_provider_state(model: Dictionary) -> void:

	var providers: Dictionary = model.get("provider_map", {})
	var active_provider := str(model.get("active_provider", "openai_compatible"))
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


func _apply_session_picker(model: Dictionary) -> void:
	var sessions = model.get("sessions", [])
	var active_session_id := str(model.get("active_session_id", ""))
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


func _apply_session(model: Dictionary) -> void:
	var session = model.get("session", {})
	var messages = session.get("messages", [])
	var bbcode := ""
	
	# Accent color from model or fallback
	var accent_color := "#6ea8fe" 
	
	for message in messages:
		if not (message is Dictionary):
			continue
		var role := str(message.get("role", "assistant"))
		var content := str(message.get("content", ""))
		if content.is_empty():
			continue
		
		var display_name := "[b]You[/b]" if role == "user" else "[b][color=%s]Orbit[/color][/b]" % accent_color
		var body := MarkdownConverter.to_bbcode(content)
		
		bbcode += display_name + "\n" + body + "\n\n"
		
	var stream_preview := str(model.get("stream_preview", ""))
	if not stream_preview.is_empty():
		bbcode += "[b][color=%s]Orbit[/color][/b]\n" % accent_color
		bbcode += MarkdownConverter.to_bbcode(stream_preview)
		
	_conversation_log.text = bbcode


func _apply_validation(model: Dictionary) -> void:
	var summary = model.get("validation_summary", {})
	var regression = summary.get("regression", {})
	if bool(regression.get("success", false)):
		var passed := int(regression.get("passed", 0))
		var total := int(regression.get("total", 0))
		_validation_badge.text = "Validation %d/%d" % [passed, total]
	else:
		_validation_badge.text = "Validation pending"


func _on_send_prompt_pressed() -> void:
	var prompt: String = _prompt_edit.text.strip_edges()
	if prompt.is_empty():
		return
	# Policy is hidden in new UI, defaulting to "propose" or last known
	emit_signal("send_prompt_requested", prompt, "propose")
	_prompt_edit.clear()


func _on_provider_selected(index: int) -> void:
	if index < 0 or index >= _provider_select.item_count:
		return
	emit_signal("provider_selected_requested", _provider_select.get_item_text(index))


func _on_session_picker_selected(index: int) -> void:
	if index < 0 or index >= _session_picker.item_count:
		return
	var session_id := str(_session_picker.get_item_metadata(index))
	if not session_id.is_empty():
		emit_signal("session_selected_requested", session_id)
