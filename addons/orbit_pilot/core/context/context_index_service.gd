@tool
extends RefCounted
class_name ContextIndexService

var _script_symbol_cache: Dictionary = {}
var _scene_dependency_cache: Dictionary = {}


func clear_cache() -> void:
	_script_symbol_cache.clear()
	_scene_dependency_cache.clear()


func get_script_symbols(path: String, refresh: bool = false) -> Dictionary:
	var normalized := _normalize_res_path(path)
	if normalized.is_empty():
		return {"success": false, "error": "invalid_path"}
	if not refresh and _script_symbol_cache.has(normalized):
		return {"success": true, "path": normalized, "symbols": _script_symbol_cache[normalized], "cached": true}

	var abs := ProjectSettings.globalize_path(normalized)
	if not FileAccess.file_exists(abs):
		return {"success": false, "error": "not_found"}
	var file := FileAccess.open(abs, FileAccess.READ)
	if file == null:
		return {"success": false, "error": "open_failed"}
	var text := file.get_as_text()
	file.close()

	var symbols := _parse_symbols(normalized, text)
	_script_symbol_cache[normalized] = symbols
	return {"success": true, "path": normalized, "symbols": symbols, "cached": false}


func get_scene_dependencies(path: String, refresh: bool = false) -> Dictionary:
	var normalized := _normalize_res_path(path)
	if normalized.is_empty():
		return {"success": false, "error": "invalid_path"}
	if not refresh and _scene_dependency_cache.has(normalized):
		return {"success": true, "path": normalized, "dependencies": _scene_dependency_cache[normalized], "cached": true}

	var abs := ProjectSettings.globalize_path(normalized)
	if not FileAccess.file_exists(abs):
		return {"success": false, "error": "not_found"}
	var file := FileAccess.open(abs, FileAccess.READ)
	if file == null:
		return {"success": false, "error": "open_failed"}
	var text := file.get_as_text()
	file.close()

	var deps := _parse_scene_dependencies(text)
	_scene_dependency_cache[normalized] = deps
	return {"success": true, "path": normalized, "dependencies": deps, "cached": false}


func _normalize_res_path(path: String) -> String:
	var value := path.strip_edges()
	if value.is_empty():
		return ""
	if value.begins_with("res://"):
		return value
	return "res://%s" % value


func _parse_symbols(path: String, text: String) -> Array[Dictionary]:
	if path.ends_with(".gd"):
		return _parse_gd_symbols(text)
	if path.ends_with(".cs"):
		return _parse_cs_symbols(text)
	return []


func _parse_gd_symbols(text: String) -> Array[Dictionary]:
	var symbols: Array[Dictionary] = []
	var lines := text.split("\n")
	for i in range(lines.size()):
		var line := String(lines[i]).strip_edges()
		if line.begins_with("class_name "):
			symbols.append({"kind": "class", "name": line.trim_prefix("class_name ").strip_edges(), "line": i + 1})
		elif line.begins_with("func "):
			var name := line.trim_prefix("func ").split("(")[0].strip_edges()
			symbols.append({"kind": "method", "name": name, "line": i + 1})
		elif line.begins_with("@export "):
			symbols.append({"kind": "export", "name": _extract_tail_name(line), "line": i + 1})
		elif line.begins_with("var "):
			var var_name := line.trim_prefix("var ").split(":")[0].split("=")[0].strip_edges()
			symbols.append({"kind": "var", "name": var_name, "line": i + 1})
	return symbols


func _parse_cs_symbols(text: String) -> Array[Dictionary]:
	var symbols: Array[Dictionary] = []
	var lines := text.split("\n")
	for i in range(lines.size()):
		var line := String(lines[i]).strip_edges()
		if line.begins_with("namespace "):
			symbols.append({"kind": "namespace", "name": line.trim_prefix("namespace ").strip_edges().trim_suffix("{").strip_edges(), "line": i + 1})
		elif line.find(" class ") >= 0:
			var parts := line.replace("{", "").split(" ")
			var class_index := parts.find("class")
			if class_index >= 0 and class_index + 1 < parts.size():
				symbols.append({"kind": "class", "name": String(parts[class_index + 1]).strip_edges(), "line": i + 1})
		elif line.find("(") > 0 and line.find(")") > line.find("(") and line.ends_with("{"):
			var before := line.split("(")[0].strip_edges()
			var tokens := before.split(" ")
			if not tokens.is_empty():
				var method_name := String(tokens[tokens.size() - 1]).strip_edges()
				if method_name != "if" and method_name != "for" and method_name != "while" and method_name != "switch":
					symbols.append({"kind": "method", "name": method_name, "line": i + 1})
		elif line.begins_with("[Export"):
			symbols.append({"kind": "export", "name": "", "line": i + 1})
	return symbols


func _parse_scene_dependencies(text: String) -> Array[Dictionary]:
	var deps: Array[Dictionary] = []
	var lines := text.split("\n")
	for i in range(lines.size()):
		var line := String(lines[i]).strip_edges()
		if line.find("path=\"res://") >= 0:
			var start := line.find("path=\"")
			if start >= 0:
				start += 6
				var end := line.find("\"", start)
				if end > start:
					var path := line.substr(start, end - start)
					deps.append({"path": path, "line": i + 1, "kind": "resource_path"})
	return deps


func _extract_tail_name(line: String) -> String:
	var tokens := line.split(" ")
	if tokens.is_empty():
		return ""
	var raw := String(tokens[tokens.size() - 1])
	return raw.split(":")[0].split("=")[0].strip_edges()
