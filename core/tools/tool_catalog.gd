@tool
extends RefCounted
class_name ToolCatalog

var _local_tools: Array = []
var _remote_tools_by_server: Dictionary = {}


func set_local_tools(definitions: Array) -> void:
	_local_tools = _sanitize_tool_definitions(definitions)


func set_remote_tools(server_id: String, definitions: Array) -> void:
	_remote_tools_by_server[server_id] = _sanitize_tool_definitions(definitions)


func clear_remote_tools(server_id: String) -> void:
	_remote_tools_by_server.erase(server_id)


func get_unified_tools() -> Array:
	var out: Array = []

	for tool_def in _local_tools:
		out.append({
			"id": "local:%s" % str(tool_def.get("name", "")),
			"name": str(tool_def.get("name", "")),
			"description": str(tool_def.get("description", "")),
			"source": "local",
		})

	for server_id in _remote_tools_by_server.keys():
		for tool_def in _remote_tools_by_server[server_id]:
			var name := str(tool_def.get("name", ""))
			out.append({
				"id": "remote:%s:%s" % [server_id, name],
				"name": name,
				"description": str(tool_def.get("description", "")),
				"source": "remote",
				"server_id": server_id,
			})
	return out


func find_by_id(tool_id: String) -> Dictionary:
	for item in get_unified_tools():
		if str(item.get("id", "")) == tool_id:
			return item
	return {}


func get_candidates_by_name(name: String) -> Array:
	var out: Array = []
	for item in get_unified_tools():
		if str(item.get("name", "")) == name:
			out.append(item)
	return out


func _sanitize_tool_definitions(definitions: Array) -> Array:
	var out: Array = []
	for item in definitions:
		if item is Dictionary:
			out.append((item as Dictionary).duplicate(true))
	return out
