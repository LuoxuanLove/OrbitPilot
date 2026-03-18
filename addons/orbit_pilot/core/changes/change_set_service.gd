@tool
extends RefCounted
class_name ChangeSetService

var _pending: Dictionary = {}
var _history: Array[Dictionary] = []


func create_change_set(file_path: String, new_text: String) -> Dictionary:
	var resolved := _resolve_res_path(file_path)
	if resolved.is_empty():
		return _error("invalid_path")

	var old_text := ""
	if FileAccess.file_exists(resolved):
		var read_file := FileAccess.open(resolved, FileAccess.READ)
		if read_file:
			old_text = read_file.get_as_text()
			read_file.close()

	var id := "%s_%s" % [str(Time.get_unix_time_from_system()), str(randi())]
	var record := {
		"id": id,
		"file_path": file_path,
		"resolved_path": resolved,
		"created_at_unix": Time.get_unix_time_from_system(),
		"old_text": old_text,
		"new_text": new_text,
		"preview": _build_preview(old_text, new_text),
		"status": "pending",
	}
	_pending[id] = record
	return {"success": true, "change_set": _sanitize_change_set(record)}


func get_change_set(change_set_id: String) -> Dictionary:
	if not _pending.has(change_set_id):
		return _error("change_set_not_found")
	return {"success": true, "change_set": _sanitize_change_set(_pending[change_set_id])}


func list_pending() -> Dictionary:
	var out: Array[Dictionary] = []
	for id in _pending.keys():
		out.append(_sanitize_change_set(_pending[id]))
	return {"success": true, "items": out}


func list_history(limit: int = 50) -> Dictionary:
	var size := _history.size()
	var begin := maxi(size - limit, 0)
	var out: Array[Dictionary] = []
	for i in range(begin, size):
		out.append(_sanitize_change_set(_history[i]))
	return {"success": true, "items": out}


func apply_change_set(change_set_id: String, approved: bool) -> Dictionary:
	if not _pending.has(change_set_id):
		return _error("change_set_not_found")
	if not approved:
		_pending[change_set_id]["status"] = "rejected"
		_history.append(_pending[change_set_id].duplicate(true))
		_pending.erase(change_set_id)
		return {"success": true, "status": "rejected"}

	var record: Dictionary = _pending[change_set_id]
	var file := FileAccess.open(record["resolved_path"], FileAccess.WRITE)
	if file == null:
		return _error("apply_failed")

	file.store_string(str(record["new_text"]))
	file.close()

	record["status"] = "applied"
	record["applied_at_unix"] = Time.get_unix_time_from_system()
	_history.append(record.duplicate(true))
	_pending.erase(change_set_id)
	return {"success": true, "status": "applied", "change_set": _sanitize_change_set(record)}


func rollback_last() -> Dictionary:
	if _history.is_empty():
		return _error("no_history")
	var last: Dictionary = _history[_history.size() - 1]
	if str(last.get("status", "")) != "applied":
		return _error("last_not_applied")

	var file := FileAccess.open(str(last["resolved_path"]), FileAccess.WRITE)
	if file == null:
		return _error("rollback_failed")
	file.store_string(str(last["old_text"]))
	file.close()

	last["status"] = "rolled_back"
	last["rolled_back_at_unix"] = Time.get_unix_time_from_system()
	_history[_history.size() - 1] = last
	return {"success": true, "status": "rolled_back", "change_set": _sanitize_change_set(last)}


func _resolve_res_path(path: String) -> String:
	var normalized := path.strip_edges()
	if normalized.is_empty():
		return ""
	if normalized.begins_with("res://"):
		return ProjectSettings.globalize_path(normalized)
	if normalized.begins_with("user://"):
		return ProjectSettings.globalize_path(normalized)
	if normalized.contains(":/") or normalized.begins_with("/"):
		return normalized
	return ProjectSettings.globalize_path("res://%s" % normalized)


func _build_preview(old_text: String, new_text: String) -> String:
	var old_lines := old_text.split("\n")
	var new_lines := new_text.split("\n")
	var preview := PackedStringArray()
	preview.append("--- old")
	preview.append("+++ new")
	var max_lines := mini(maxi(old_lines.size(), new_lines.size()), 120)
	for i in range(max_lines):
		var old_line := old_lines[i] if i < old_lines.size() else ""
		var new_line := new_lines[i] if i < new_lines.size() else ""
		if old_line == new_line:
			preview.append(" %s" % old_line)
		else:
			preview.append("-%s" % old_line)
			preview.append("+%s" % new_line)
	if maxi(old_lines.size(), new_lines.size()) > max_lines:
		preview.append("... truncated ...")
	return "\n".join(preview)


func _sanitize_change_set(record: Dictionary) -> Dictionary:
	return {
		"id": str(record.get("id", "")),
		"file_path": str(record.get("file_path", "")),
		"created_at_unix": int(record.get("created_at_unix", 0)),
		"status": str(record.get("status", "")),
		"preview": str(record.get("preview", "")),
	}


func _error(code: String) -> Dictionary:
	return {"success": false, "error": code}
