@tool
extends RefCounted
class_name LocalTools

var _editor_interface: EditorInterface
var _change_set_service: ChangeSetService
var _context_index_service: ContextIndexService
var _regression_runner: RefCounted


func setup(
	editor_interface: EditorInterface,
	change_set_service: ChangeSetService,
	context_index_service: ContextIndexService,
	regression_runner: RefCounted = null
) -> void:
	_editor_interface = editor_interface
	_change_set_service = change_set_service
	_context_index_service = context_index_service
	_regression_runner = regression_runner


func get_definitions() -> Array[Dictionary]:
	return [
		{"name": "search_files", "description": "Find files by wildcard under a path", "source": "local"},
		{"name": "search_text", "description": "Find text in project files", "source": "local"},
		{"name": "read_file", "description": "Read a text file", "source": "local"},
		{"name": "get_editor_context", "description": "Read current editor scene and selection context", "source": "local"},
		{"name": "get_script_symbols", "description": "Get script symbol index for .gd/.cs", "source": "local"},
		{"name": "get_scene_dependencies", "description": "Get scene resource dependencies for .tscn", "source": "local"},
		{"name": "get_context_bundle", "description": "Get an aggregated context bundle", "source": "local"},
		{"name": "run_regression_suite", "description": "Run minimal OrbitPilot regression suite", "source": "local"},
		{"name": "create_change_set", "description": "Create a pending file change set", "source": "local"},
		{"name": "get_change_set", "description": "Get a pending change set preview", "source": "local"},
		{"name": "apply_change_set", "description": "Apply or reject a pending change set", "source": "local"},
	]


func execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"search_files":
			return _search_files(
				str(args.get("pattern", "*")),
				str(args.get("path", "res://")),
				bool(args.get("recursive", true))
			)
		"search_text":
			return _search_text(
				str(args.get("query", "")),
				str(args.get("path", "res://")),
				str(args.get("filter", "*")),
				bool(args.get("recursive", true))
			)
		"read_file":
			return _read_file(str(args.get("path", "")))
		"get_editor_context":
			return _get_editor_context()
		"get_script_symbols":
			return _context_index_service.get_script_symbols(
				str(args.get("path", "")),
				bool(args.get("refresh", false))
			)
		"get_scene_dependencies":
			return _context_index_service.get_scene_dependencies(
				str(args.get("path", "")),
				bool(args.get("refresh", false))
			)
		"get_context_bundle":
			return _get_context_bundle(args)
		"run_regression_suite":
			return await _run_regression_suite()
		"create_change_set":
			return _change_set_service.create_change_set(str(args.get("path", "")), str(args.get("new_text", "")))
		"get_change_set":
			return _change_set_service.get_change_set(str(args.get("change_set_id", "")))
		"apply_change_set":
			return _change_set_service.apply_change_set(str(args.get("change_set_id", "")), bool(args.get("approved", false)))
		_:
			return {"success": false, "error": "unknown_local_tool"}


func _search_files(pattern: String, base_path: String, recursive: bool) -> Dictionary:
	var root := _normalize_to_res_path(base_path)
	if root.is_empty():
		return {"success": false, "error": "invalid_path"}

	var results: Array[String] = []
	_walk_dir_collect(root, pattern, recursive, results)
	return {"success": true, "items": results}


func _search_text(query: String, base_path: String, filter: String, recursive: bool) -> Dictionary:
	if query.is_empty():
		return {"success": false, "error": "empty_query"}
	var files_result := _search_files(filter, base_path, recursive)
	if not bool(files_result.get("success", false)):
		return files_result

	var hits: Array[Dictionary] = []
	for file_path in files_result["items"]:
		var abs := ProjectSettings.globalize_path(file_path)
		var file := FileAccess.open(abs, FileAccess.READ)
		if file == null:
			continue
		var line_number := 0
		while not file.eof_reached():
			line_number += 1
			var line := file.get_line()
			if line.find(query) >= 0:
				hits.append({"path": file_path, "line": line_number, "text": line})
		file.close()
	return {"success": true, "items": hits}


func _read_file(path: String) -> Dictionary:
	var normalized := _normalize_to_res_path(path)
	if normalized.is_empty():
		return {"success": false, "error": "invalid_path"}
	var abs := ProjectSettings.globalize_path(normalized)
	if not FileAccess.file_exists(abs):
		return {"success": false, "error": "not_found"}
	var file := FileAccess.open(abs, FileAccess.READ)
	if file == null:
		return {"success": false, "error": "open_failed"}
	var content := file.get_as_text()
	file.close()
	return {"success": true, "path": normalized, "content": content}


func _get_editor_context() -> Dictionary:
	var context := {
		"edited_scene_root": "",
		"selected_nodes": [],
		"open_scripts": [],
	}

	if _editor_interface != null:
		var root := _editor_interface.get_edited_scene_root()
		if root != null:
			context["edited_scene_root"] = str(root.get_path())

		var selection := _editor_interface.get_selection()
		if selection != null:
			for node in selection.get_selected_nodes():
				context["selected_nodes"].append(str(node.get_path()))

		var script_editor := _editor_interface.get_script_editor()
		if script_editor != null and script_editor.has_method("get_open_scripts"):
			for script_res in script_editor.call("get_open_scripts"):
				if script_res != null:
					context["open_scripts"].append(str(script_res.resource_path))

	return {"success": true, "context": context}


func _get_context_bundle(args: Dictionary) -> Dictionary:
	var bundle := {
		"editor_context": _get_editor_context().get("context", {}),
		"script_symbols": {},
		"scene_dependencies": {},
	}
	var script_path := str(args.get("script_path", "")).strip_edges()
	if not script_path.is_empty():
		var script_symbols := _context_index_service.get_script_symbols(script_path, bool(args.get("refresh", false)))
		bundle["script_symbols"] = script_symbols.get("symbols", [])

	var scene_path := str(args.get("scene_path", "")).strip_edges()
	if not scene_path.is_empty():
		var scene_deps := _context_index_service.get_scene_dependencies(scene_path, bool(args.get("refresh", false)))
		bundle["scene_dependencies"] = scene_deps.get("dependencies", [])

	return {"success": true, "context_bundle": bundle}


func _run_regression_suite() -> Dictionary:
	if _regression_runner == null or not _regression_runner.has_method("run_minimal_suite"):
		return {"success": false, "error": "regression_runner_missing"}
	return await _regression_runner.run_minimal_suite()


func _walk_dir_collect(path: String, pattern: String, recursive: bool, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue

		var full := "%s/%s" % [path.trim_suffix("/"), entry]
		if dir.current_is_dir():
			if recursive:
				_walk_dir_collect(full, pattern, recursive, out)
		else:
			if entry.match(pattern):
				out.append(full)
	dir.list_dir_end()


func _normalize_to_res_path(path: String) -> String:
	var cleaned := path.strip_edges()
	if cleaned.is_empty():
		return ""
	if cleaned.begins_with("res://"):
		return cleaned
	if cleaned.begins_with("user://"):
		return cleaned
	return "res://%s" % cleaned
