@tool
class_name OrbitPageCodex
extends RefCounted

signal send_prompt_requested(prompt: String, policy: String)
signal cancel_run_requested
signal provider_selected_requested(provider_id: String)
signal session_selected_requested(session_id: String)

const MarkdownConverter = preload("res://addons/orbit_pilot/core/utils/markdown_converter.gd")
const Localizer = preload("res://addons/orbit_pilot/core/utils/localizer.gd")
const MessageBubble = preload("res://addons/orbit_pilot/ui/message_bubble.gd")

var _root: Control
var _session_picker: OptionButton
var _conversation_scroll: ScrollContainer
var _conversation_list: VBoxContainer
var _provider_select: OptionButton
var _validation_badge: Label
var _prompt_edit: TextEdit
var _send_button: Button
var _is_run_active := false
var _add_context_button: Button
var _context_toggle: Button
var _conversation_panel: Control
var _composer_panel: Control
var _editor_theme: Theme

var _current_session_id := ""
var _rendered_message_count := 0
var _stream_node: Control = null

# Context popup
var _context_popup: PopupPanel = null
var _ide_context_enabled := true
var _plan_mode_enabled := false
var _ide_popup_toggle: CheckButton = null
var _plan_popup_toggle: CheckButton = null
var _ide_context_chip: Control = null
var _plan_mode_chip: Control = null


func setup(dock_root: Control, editor_plugin: EditorPlugin) -> void:
	_root = dock_root
	_assign_nodes()
	_setup_icons(editor_plugin)
	_setup_context_popup()
	_bind_events()
	refresh_translations()


func apply_model(model: Dictionary) -> void:
	_apply_provider_state(model)
	_apply_session_picker(model)
	_apply_session(model)
	_apply_validation(model)
	var run_active := bool(model.get("is_run_active", false))
	if run_active != _is_run_active:
		_is_run_active = run_active
		_update_send_button_state()


func get_chrome_panels() -> Dictionary:
	return {
		"conversation": _conversation_panel,
		"conversation_scroll": _conversation_scroll,
		"composer": _composer_panel,
	}


func get_chrome_refs() -> Dictionary:
	return {
		"validation_badge": _validation_badge,
		"session_picker": _session_picker,
		"send_button": _send_button,
		"prompt_edit": _prompt_edit,
	}


func _node(path: String):
	return _root.get_node(path)


func _assign_nodes() -> void:
	if _root == null:
		push_error("[OrbitPageCodex] _root is null in _assign_nodes")
		return
	_session_picker = _node("CodexTop/TitleBlock/SessionPicker")
	_conversation_panel = _node("ConversationPanel")
	_conversation_scroll = _node("ConversationPanel/ConversationScroll")
	_conversation_list = _node("ConversationPanel/ConversationScroll/ConversationList")
	_composer_panel = _node("ComposerMargin/ComposerPanel")
	_prompt_edit = _node("ComposerMargin/ComposerPanel/Composer/PromptEdit")
	_add_context_button = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/AddContextButton")
	_provider_select = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/ProviderSelect")
	_context_toggle = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/ContextToggle")
	_send_button = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/ComposerActions/SendPromptButton")
	_validation_badge = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter/ValidationBadge")


func _bind_events() -> void:
	if _add_context_button:
		_add_context_button.pressed.connect(_on_add_context_pressed)
	if _send_button:
		_send_button.pressed.connect(_on_action_button_pressed)
	if _provider_select:
		_provider_select.item_selected.connect(_on_provider_selected)
	if _session_picker:
		_session_picker.item_selected.connect(_on_session_picker_selected)


func _setup_icons(editor_plugin: EditorPlugin) -> void:
	_editor_theme = editor_plugin.get_editor_interface().get_editor_theme()
	_add_context_button.icon = _editor_theme.get_icon("Add", "EditorIcons")
	_update_send_button_state()


func _update_send_button_state() -> void:
	if _send_button == null or _editor_theme == null:
		return
	if _is_run_active:
		_send_button.icon = _editor_theme.get_icon("Stop", "EditorIcons")
		_send_button.tooltip_text = Localizer.t("ACTION_CANCEL")
	else:
		_send_button.icon = _editor_theme.get_icon("Play", "EditorIcons")
		_send_button.tooltip_text = Localizer.t("ACTION_SEND")
	_send_button.text = ""


func _on_action_button_pressed() -> void:
	if _is_run_active:
		emit_signal("cancel_run_requested")
	else:
		_on_send_prompt_pressed()


func refresh_translations() -> void:
	_prompt_edit.placeholder_text = Localizer.t("PROMPT_PLACEHOLDER")
	_update_send_button_state()


# ── Context popup ──────────────────────────────────────────────────────────────

func _setup_context_popup() -> void:
	_context_toggle.visible = false

	# 弹出面板
	_context_popup = PopupPanel.new()
	_context_popup.min_size = Vector2(270, 0)
	_root.add_child(_context_popup)

	var style := StyleBoxFlat.new()
	style.bg_color = Color("1c2128")
	style.border_color = Color(0.4, 0.5, 0.6, 0.25)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	_context_popup.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	_context_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# 行1：包含编辑器背景信息
	var row1 := _build_popup_row("包含编辑器背景信息", "Signals", _ide_context_enabled,
		func(v: bool): _on_ide_context_toggled(v))
	_ide_popup_toggle = row1.get_child(row1.get_child_count() - 1) as CheckButton
	vbox.add_child(row1)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# 行2：计划模式
	var row2 := _build_popup_row("计划模式", "Edit", _plan_mode_enabled,
		func(v: bool): _on_plan_mode_toggled(v))
	_plan_popup_toggle = row2.get_child(row2.get_child_count() - 1) as CheckButton
	vbox.add_child(row2)

	# 在 ProviderSelect 右侧插入状态芯片（index 2, 3）
	var footer: HBoxContainer = _node("ComposerMargin/ComposerPanel/Composer/ComposerFooter")

	_ide_context_chip = _build_status_chip(
		"IDE 背景信息", "Signals",
		"包含来自 IDE 的上下文信息，例如当前选中代码和打开的文件。",
		func(): _on_ide_context_toggled(false)
	)
	_ide_context_chip.visible = _ide_context_enabled
	footer.add_child(_ide_context_chip)
	footer.move_child(_ide_context_chip, 2)

	_plan_mode_chip = _build_status_chip(
		"计划", "Edit",
		"切换计划模式，AI 将先制定计划再执行变更。",
		func(): _on_plan_mode_toggled(false)
	)
	_plan_mode_chip.visible = _plan_mode_enabled
	footer.add_child(_plan_mode_chip)
	footer.move_child(_plan_mode_chip, 3)


func _build_popup_row(label_text: String, icon_name: String, initial: bool, on_toggle: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	if _editor_theme != null and _editor_theme.has_icon(icon_name, "EditorIcons"):
		var icon_rect := TextureRect.new()
		icon_rect.texture = _editor_theme.get_icon(icon_name, "EditorIcons")
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon_rect.custom_minimum_size = Vector2(16, 16)
		row.add_child(icon_rect)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var toggle := CheckButton.new()
	toggle.button_pressed = initial
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(on_toggle)
	row.add_child(toggle)

	return row


func _build_status_chip(text: String, icon_name: String, tip: String, on_deactivate: Callable) -> PanelContainer:
	var accent := _get_accent_color()

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0, 0, 0, 0)
	style_normal.set_border_width_all(0)
	style_normal.corner_radius_top_left = 12
	style_normal.corner_radius_top_right = 12
	style_normal.corner_radius_bottom_left = 12
	style_normal.corner_radius_bottom_right = 12
	style_normal.content_margin_left = 6
	style_normal.content_margin_right = 6
	style_normal.content_margin_top = 2
	style_normal.content_margin_bottom = 2

	var style_hover := style_normal.duplicate() as StyleBoxFlat
	style_hover.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style_hover.set_border_width_all(1)

	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.tooltip_text = tip
	chip.add_theme_stylebox_override("panel", style_normal)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.add_child(hbox)

	var icon_rect := TextureRect.new()
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_rect.custom_minimum_size = Vector2(14, 14)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	var normal_tex: Texture2D = null
	var close_tex: Texture2D = null
	if _editor_theme != null:
		if _editor_theme.has_icon(icon_name, "EditorIcons"):
			normal_tex = _editor_theme.get_icon(icon_name, "EditorIcons")
		if _editor_theme.has_icon("GuiClose", "EditorIcons"):
			close_tex = _editor_theme.get_icon("GuiClose", "EditorIcons")
		elif _editor_theme.has_icon("Remove", "EditorIcons"):
			close_tex = _editor_theme.get_icon("Remove", "EditorIcons")
	icon_rect.texture = normal_tex
	hbox.add_child(icon_rect)

	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(lbl)

	# 悬浮：切换样式 + 图标换为 X
	chip.mouse_entered.connect(func():
		chip.add_theme_stylebox_override("panel", style_hover)
		if close_tex != null:
			icon_rect.texture = close_tex
	)
	chip.mouse_exited.connect(func():
		chip.add_theme_stylebox_override("panel", style_normal)
		icon_rect.texture = normal_tex
	)
	# 点击：取消该选项
	chip.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			on_deactivate.call()
	)

	return chip


func _on_add_context_pressed() -> void:
	if _context_popup == null:
		return
	if _context_popup.visible:
		_context_popup.hide()
		return
	var btn_rect := _add_context_button.get_global_rect()
	var popup_w := int(maxf(float(_context_popup.min_size.x), 270.0))
	var popup_h := 110
	_context_popup.popup(Rect2i(
		Vector2i(int(btn_rect.position.x), int(btn_rect.position.y) - popup_h - 4),
		Vector2i(popup_w, popup_h)
	))


func _on_ide_context_toggled(enabled: bool) -> void:
	_ide_context_enabled = enabled
	if _ide_context_chip != null:
		_ide_context_chip.visible = enabled
	if _ide_popup_toggle != null and _ide_popup_toggle.button_pressed != enabled:
		_ide_popup_toggle.button_pressed = enabled


func _on_plan_mode_toggled(enabled: bool) -> void:
	_plan_mode_enabled = enabled
	if _plan_mode_chip != null:
		_plan_mode_chip.visible = enabled
	if _plan_popup_toggle != null and _plan_popup_toggle.button_pressed != enabled:
		_plan_popup_toggle.button_pressed = enabled


# ── Model / session state ──────────────────────────────────────────────────────

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


# ── Session / conversation rendering ──────────────────────────────────────────

func _apply_session(model: Dictionary) -> void:
	var session = model.get("session", {})
	var session_id := str(session.get("id", ""))
	var messages = session.get("messages", [])

	if session_id != _current_session_id:
		_current_session_id = session_id
		_clear_conversation()

	for i in range(_rendered_message_count, messages.size()):
		var msg = messages[i]
		if msg is Dictionary:
			_append_message(msg)
	_rendered_message_count = messages.size()

	var stream_preview := str(model.get("stream_preview", ""))
	_update_stream_node(stream_preview)
	_scroll_to_bottom()


func _clear_conversation() -> void:
	for child in _conversation_list.get_children():
		child.queue_free()
	_rendered_message_count = 0
	_stream_node = null


func _append_message(msg: Dictionary) -> void:
	var role := str(msg.get("role", "assistant"))
	var content := str(msg.get("content", ""))
	if content.is_empty():
		return
	var node: Control
	if role == "user":
		node = MessageBubble.build_user_bubble(
			content, _get_accent_color(),
			func(text: String): _prompt_edit.text = text,
			_editor_theme
		)
	else:
		node = MessageBubble.build_assistant_bubble(content, _get_accent_color(), _editor_theme)
	_conversation_list.add_child(node)


func _update_stream_node(preview: String) -> void:
	if preview.is_empty():
		if _stream_node != null:
			_stream_node.queue_free()
			_stream_node = null
		return
	if _stream_node == null:
		_stream_node = MessageBubble.build_assistant_bubble("", _get_accent_color(), _editor_theme)
		_conversation_list.add_child(_stream_node)
	var label: RichTextLabel = _stream_node.find_child("ContentLabel", true, false)
	if label != null:
		label.text = MarkdownConverter.to_bbcode(preview)
	_scroll_to_bottom()


func _scroll_to_bottom() -> void:
	if _conversation_scroll == null:
		return
	if _root != null and _root.get_tree() != null:
		_root.get_tree().process_frame.connect(
			func():
				if is_instance_valid(_conversation_scroll):
					_conversation_scroll.scroll_vertical = \
						_conversation_scroll.get_v_scroll_bar().max_value,
			CONNECT_ONE_SHOT
		)


func _get_accent_color() -> Color:
	return Color("6ea8fe")


func _apply_validation(model: Dictionary) -> void:
	var summary = model.get("validation_summary", {})
	var regression = summary.get("regression", {})
	var template := Localizer.t("VALIDATION_COUNT")
	if bool(regression.get("success", false)) and "%d" in template:
		var passed := int(regression.get("passed", 0))
		var total := int(regression.get("total", 0))
		_validation_badge.text = template % [passed, total]
	else:
		_validation_badge.text = Localizer.t("VALIDATION_PENDING")


# ── User actions ───────────────────────────────────────────────────────────────

func _on_send_prompt_pressed() -> void:
	var prompt: String = _prompt_edit.text.strip_edges()
	if prompt.is_empty():
		return
	var policy := "plan" if _plan_mode_enabled else "propose"
	emit_signal("send_prompt_requested", prompt, policy)
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
