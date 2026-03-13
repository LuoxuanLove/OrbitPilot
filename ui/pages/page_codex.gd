@tool
class_name OrbitPageCodex
extends RefCounted

signal send_prompt_requested(prompt: String, policy: String)
signal cancel_run_requested
signal provider_selected_requested(provider_id: String)
signal session_selected_requested(session_id: String)

var _root: Control
var _session_picker: OptionButton
var _conversation_log: RichTextLabel
var _provider_select: OptionButton
var _policy_select: OptionButton
var _validation_badge: Label
var _prompt_edit: TextEdit
var _send_button: Button
var _cancel_button: Button
var _conversation_panel: Control
var _composer_panel: Control


func setup(dock_root: Control) -> void:
	_root = dock_root
	_assign_nodes()
	_setup_policy_select()
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
	_session_picker = _node("RootMargin/Root/PageStack/PageCodex/CodexTop/TitleBlock/SessionPicker")
	_conversation_panel = _node("RootMargin/Root/PageStack/PageCodex/ConversationPanel")
	_conversation_log = _node("RootMargin/Root/PageStack/PageCodex/ConversationPanel/ConversationLog")
	_provider_select = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerMeta/ProviderSelect")
	_policy_select = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerMeta/PolicySelect")
	_validation_badge = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerMeta/ValidationBadge")
	_prompt_edit = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/PromptEdit")
	_send_button = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerActions/SendPromptButton")
	_cancel_button = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel/Composer/ComposerFooter/ComposerActions/CancelRunButton")
	_composer_panel = _node("RootMargin/Root/PageStack/PageCodex/ComposerPanel")


func _bind_events() -> void:
	_send_button.pressed.connect(_on_send_prompt_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_provider_select.item_selected.connect(_on_provider_selected)
	_session_picker.item_selected.connect(_on_session_picker_selected)


func _on_cancel_pressed() -> void:
	emit_signal("cancel_run_requested")


func _setup_policy_select() -> void:
	_policy_select.clear()
	_policy_select.add_item("analyze")
	_policy_select.add_item("propose")
	_policy_select.add_item("apply_with_approval")
	_policy_select.select(1)


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
	var stream_preview := str(model.get("stream_preview", ""))
	if not stream_preview.is_empty():
		lines.append("Orbit\n" + stream_preview)
	_conversation_log.text = "\n".join(lines)


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
	emit_signal("send_prompt_requested", prompt, _policy_select.get_item_text(_policy_select.selected))
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
