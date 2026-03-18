@tool
class_name MessageBubble
extends RefCounted

const MarkdownConverter = preload("res://addons/orbit_pilot/core/utils/markdown_converter.gd")
const Localizer = preload("res://addons/orbit_pilot/core/utils/localizer.gd")

const MUTED := Color("8b949e")


## 构建用户消息气泡节点
## raw_content: 原始文本（用于复制和编辑）
## accent: 强调色
## on_edit: 点击编辑按钮时的回调 Callable(text: String)
## editor_theme: EditorTheme（可选，用于图标，为 null 时退回文字）
static func build_user_bubble(
	raw_content: String,
	accent: Color,
	on_edit: Callable,
	editor_theme: Theme = null
) -> Control:
	# 外层行占满整行宽度，作为悬浮检测容器（PASS = 接收 mouse_entered/exited，不阻断子节点点击）
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(spacer)

	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_END
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(wrap)

	# 消息内容标签
	var content_label := RichTextLabel.new()
	content_label.name = "ContentLabel"
	content_label.bbcode_enabled = true
	content_label.fit_content = true
	content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_label.scroll_active = false
	content_label.mouse_filter = Control.MOUSE_FILTER_PASS
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_label.custom_minimum_size = Vector2(120, 0)
	content_label.text = MarkdownConverter.to_bbcode(raw_content)
	wrap.add_child(content_label)

	# 操作行：始终占位（modulate.a 控制透明度），避免显隐时改变消息行高度
	var actions := HBoxContainer.new()
	actions.name = "ActionsRow"
	actions.modulate.a = 0.0
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 4)
	actions.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(actions)

	# 编辑按钮（MOUSE_FILTER_PASS：不拦截鼠标，pressed 仍然正常触发）
	var edit_btn := Button.new()
	edit_btn.flat = true
	edit_btn.focus_mode = Control.FOCUS_NONE
	edit_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	edit_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	edit_btn.tooltip_text = "编辑"
	if editor_theme != null and editor_theme.has_icon("Edit", "EditorIcons"):
		edit_btn.icon = editor_theme.get_icon("Edit", "EditorIcons")
	else:
		edit_btn.text = "✎"
	edit_btn.add_theme_color_override("font_color", MUTED)
	edit_btn.pressed.connect(func(): on_edit.call(raw_content))
	actions.add_child(edit_btn)

	# 复制按钮（MOUSE_FILTER_PASS：不拦截鼠标，pressed 仍然正常触发）
	var copy_btn := Button.new()
	copy_btn.flat = true
	copy_btn.focus_mode = Control.FOCUS_NONE
	copy_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	copy_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	copy_btn.tooltip_text = "复制"
	if editor_theme != null and editor_theme.has_icon("ActionCopy", "EditorIcons"):
		copy_btn.icon = editor_theme.get_icon("ActionCopy", "EditorIcons")
	else:
		copy_btn.text = "⎘"
	copy_btn.add_theme_color_override("font_color", MUTED)
	copy_btn.pressed.connect(func(): DisplayServer.clipboard_set(raw_content))
	actions.add_child(copy_btn)

	# 悬浮：row 整行触发，modulate.a 控制按钮透明度（不改变高度）
	row.mouse_entered.connect(func(): actions.modulate.a = 1.0)
	row.mouse_exited.connect(func(): actions.modulate.a = 0.0)

	return row


## 构建助手消息节点（无气泡，带彩色 Sender 标签 + 悬浮复制按钮）
## editor_theme: EditorTheme（可选，用于图标，为 null 时退回文字）
static func build_assistant_bubble(
	raw_content: String,
	accent: Color,
	editor_theme: Theme = null
) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var wrap := VBoxContainer.new()
	wrap.name = "AssistantWrap"
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 4)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(wrap)

	# Sender 标签
	var sender := RichTextLabel.new()
	sender.bbcode_enabled = true
	sender.fit_content = true
	sender.scroll_active = false
	sender.mouse_filter = Control.MOUSE_FILTER_PASS
	sender.text = "[b][color=%s]%s[/color][/b]" % [accent.to_html(false), Localizer.t("ASSISTANT_LABEL")]
	wrap.add_child(sender)

	# 内容标签
	var content_label := RichTextLabel.new()
	content_label.name = "ContentLabel"
	content_label.bbcode_enabled = true
	content_label.fit_content = true
	content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_label.scroll_active = false
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if not raw_content.is_empty():
		content_label.text = MarkdownConverter.to_bbcode(raw_content)
	wrap.add_child(content_label)

	# 操作行：始终占位（modulate.a 控制透明度），避免显隐时改变消息行高度
	var actions := HBoxContainer.new()
	actions.name = "ActionsRow"
	actions.modulate.a = 0.0
	actions.alignment = BoxContainer.ALIGNMENT_BEGIN
	actions.add_theme_constant_override("separation", 4)
	actions.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(actions)

	# 复制按钮
	var copy_btn := Button.new()
	copy_btn.flat = true
	copy_btn.focus_mode = Control.FOCUS_NONE
	copy_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	copy_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	copy_btn.tooltip_text = "复制"
	if editor_theme != null and editor_theme.has_icon("ActionCopy", "EditorIcons"):
		copy_btn.icon = editor_theme.get_icon("ActionCopy", "EditorIcons")
	else:
		copy_btn.text = "⎘"
	copy_btn.add_theme_color_override("font_color", MUTED)
	copy_btn.pressed.connect(func(): DisplayServer.clipboard_set(raw_content))
	actions.add_child(copy_btn)

	# 悬浮：row 整行触发，modulate.a 控制按钮透明度（不改变高度）
	row.mouse_entered.connect(func(): actions.modulate.a = 1.0)
	row.mouse_exited.connect(func(): actions.modulate.a = 0.0)

	return row
