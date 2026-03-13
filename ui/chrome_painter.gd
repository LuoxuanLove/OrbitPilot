@tool
class_name ChromePainter
extends RefCounted

var _editor_plugin: EditorPlugin
var _root: Control


func setup(editor_plugin: EditorPlugin, root: Control) -> void:
	_editor_plugin = editor_plugin
	_root = root


func paint_chrome(nav_refs: Dictionary, page_panels: Dictionary) -> void:
	var muted := Color("9aa3b2")
	var accent := _get_editor_accent()
	var composer_bg := _mix_with(accent, Color("141b26"), 0.14)
	var chrome_bg := composer_bg
	var panel_bg := _mix_with(accent, Color("151922"), 0.08)
	var status_pill: Label = nav_refs.get("status_pill")
	var validation_badge: Label = nav_refs.get("validation_badge")
	var runtime_log: RichTextLabel = nav_refs.get("runtime_log")
	var session_picker: OptionButton = nav_refs.get("session_picker")
	var send_button: Button = nav_refs.get("send_button")
	var cancel_button: Button = nav_refs.get("cancel_button")
	if status_pill != null:
		status_pill.add_theme_color_override("font_color", accent)
	if validation_badge != null:
		validation_badge.add_theme_color_override("font_color", muted)
	if runtime_log != null:
		runtime_log.add_theme_color_override("default_color", muted)
	if session_picker != null:
		session_picker.add_theme_color_override("font_color", muted)
		session_picker.add_theme_stylebox_override("normal", _build_subtle_stylebox(chrome_bg))
		session_picker.add_theme_stylebox_override("hover", _build_subtle_stylebox(_mix_with(accent, chrome_bg, 0.10)))
		session_picker.add_theme_stylebox_override("pressed", _build_subtle_stylebox(_mix_with(accent, chrome_bg, 0.14)))
		session_picker.add_theme_stylebox_override("focus", _build_subtle_stylebox(_mix_with(accent, chrome_bg, 0.14)))
	if send_button != null:
		send_button.add_theme_color_override("font_color", Color("eef4ff"))
	if cancel_button != null:
		cancel_button.add_theme_color_override("font_color", muted)
		cancel_button.flat = true
	_apply_panel_style(page_panels.get("header"), chrome_bg, 12, 12)
	_apply_panel_style(page_panels.get("conversation"), Color("151922"), 12, 12)
	_apply_panel_style(page_panels.get("composer"), composer_bg, 22, 18)
	_apply_panel_style(page_panels.get("sessions"), panel_bg, 12, 12)
	_apply_panel_style(page_panels.get("sessions_active"), Color("151922"), 10, 10)
	_apply_panel_style(page_panels.get("sessions_archived"), Color("151922"), 10, 10)
	_apply_panel_style(page_panels.get("tool_result"), panel_bg, 12, 12)
	_apply_panel_style(page_panels.get("review"), panel_bg, 12, 12)
	_apply_panel_style(page_panels.get("settings_overview"), panel_bg, 12, 12)
	_apply_panel_style(page_panels.get("settings"), panel_bg, 12, 12)
	_apply_panel_style(page_panels.get("runtime_log"), panel_bg, 12, 12)
	_apply_panel_style(page_panels.get("footer"), chrome_bg, 12, 10)
	for button in nav_refs.get("buttons", []):
		if button is Button:
			button.flat = true
			button.focus_mode = Control.FOCUS_NONE


func update_nav_state(nav_refs: Dictionary, current_page: int) -> void:
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
	for item in nav_refs.get("button_states", []):
		if not (item is Dictionary):
			continue
		var button: Button = item.get("button")
		if button == null:
			continue
		var is_active := int(item.get("page", -1)) == current_page
		button.button_pressed = is_active
		button.add_theme_color_override("font_color", active_text if is_active else inactive_text)
		button.add_theme_stylebox_override("normal", active_style if is_active else inactive_style)
		button.add_theme_stylebox_override("hover", active_style if is_active else inactive_style)
		button.add_theme_stylebox_override("pressed", active_style if is_active else inactive_style)


func _apply_panel_style(node: Control, bg_color: Color, radius: int, margin: int) -> void:
	if node == null:
		return
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


func _get_editor_accent() -> Color:
	if _editor_plugin != null:
		var base: Control = _editor_plugin.get_editor_interface().get_base_control()
		if base != null:
			var accent: Color = base.get_theme_color("accent_color", "Editor")
			if accent != Color():
				return accent
	return Color("6ea8fe")


func _mix_with(tint: Color, base: Color, weight: float) -> Color:
	return base.lerp(tint, clampf(weight, 0.0, 1.0))
