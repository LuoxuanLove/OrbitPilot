@tool
class_name MarkdownConverter
extends RefCounted

## A simple Markdown to BBCode converter for Godot's RichTextLabel.

static func to_bbcode(markdown: String) -> String:
	var result := markdown

	var regex := RegEx.new()

	# Code blocks
	regex.compile("(?s)```(?:[a-zA-Z0-9]*)\\n(.*?)\\n```")
	result = regex.sub(result, "[code][bgcolor=#1e1e1e][color=#dcdcdc]$1[/color][/bgcolor][/code]", true)

	# Inline code
	regex.compile("`([^`\\n]+)`")
	result = regex.sub(result, "[code][color=#ce9178]$1[/color][/code]", true)

	# Bold
	regex.compile("\\*\\*([^\\*\\n]+)\\*\\*")
	result = regex.sub(result, "[b]$1[/b]", true)

	# Italic
	regex.compile("\\*([^\\*\\n]+)\\*")
	result = regex.sub(result, "[i]$1[/i]", true)

	# Headers
	regex.compile("(?m)^### (.*)$")
	result = regex.sub(result, "[font_size=18][b]$1[/b][/font_size]", true)
	regex.compile("(?m)^## (.*)$")
	result = regex.sub(result, "[font_size=20][b]$1[/b][/font_size]", true)
	regex.compile("(?m)^# (.*)$")
	result = regex.sub(result, "[font_size=24][b]$1[/b][/font_size]", true)

	# Lists
	regex.compile("(?m)^[\\-*] (.*)$")
	result = regex.sub(result, "  • $1", true)

	return result
