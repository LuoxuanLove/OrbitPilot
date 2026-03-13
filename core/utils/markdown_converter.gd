@tool
class_name MarkdownConverter
extends RefCounted

## A simple Markdown to BBCode converter for Godot's RichTextLabel.

static func to_bbcode(markdown: String) -> String:
	var result := markdown
	
	# 1. Code blocks (Triple backticks)
	# Matches: ```lang\ncontent\n```
	# We use a simple regex approach or sequential replacement.
	# For now, let's do a basic multiline replacement.
	var regex := RegEx.new()
	
	# Code blocks
	regex.compile("(?s)```(?:[a-zA-Z0-9]*)\\n(.*?)\\n```")
	result = regex.sub(result, "[code][bgcolor=#1e1e1e][color=#dcdcdc]\\1[/color][/bgcolor][/code]", true)
	
	# 2. Inline code
	regex.compile("`([^`\\n]+)`")
	result = regex.sub(result, "[code][color=#ce9178]\\1[/color][/code]", true)
	
	# 3. Bold
	regex.compile("\\*\\*([^\\*\\n]+)\\*\\*")
	result = regex.sub(result, "[b]\\1[/b]", true)
	
	# 4. Italic
	regex.compile("\\*([^\\*\\n]+)\\*")
	result = regex.sub(result, "[i]\\1[/i]", true)
	
	# 5. Headers
	regex.compile("(?m)^### (.*)$")
	result = regex.sub(result, "[font_size=18][b]\\1[/b][/font_size]", true)
	regex.compile("(?m)^## (.*)$")
	result = regex.sub(result, "[font_size=20][b]\\1[/b][/font_size]", true)
	regex.compile("(?m)^# (.*)$")
	result = regex.sub(result, "[font_size=24][b]\\1[/b][/font_size]", true)
	
	# 6. Lists (Basic)
	regex.compile("(?m)^[\\-*] (.*)$")
	result = regex.sub(result, "  • \\1", true)
	
	return result
