@tool
extends RefCounted
class_name ToolCatalog

const ToolDefinition = preload("res://addons/orbit_pilot/core/tools/tool_definition.gd")

var _local_tools: Array[ToolDefinition] = []
var _remote_tools_by_server: Dictionary = {}


func set_local_tools(definitions: Array) -> void:
	_local_tools = _sanitize_tool_definitions(definitions, "local")


func set_remote_tools(server_id: String, definitions: Array) -> void:
	_remote_tools_by_server[server_id] = _sanitize_tool_definitions(definitions, "remote", server_id)


func clear_remote_tools(server_id: String) -> void:
	_remote_tools_by_server.erase(server_id)


func get_unified_tools() -> Array:
	var out: Array = []

	for tool_def in _local_tools:
		out.append(tool_def.to_dict())

	for server_id in _remote_tools_by_server.keys():
		for tool_def in _remote_tools_by_server[server_id]:
			out.append(tool_def.to_dict())
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


func _sanitize_tool_definitions(definitions: Array, default_source: String = "", default_server_id: String = "") -> Array:
	var out: Array[ToolDefinition] = []
	for item in definitions:
		if item is Dictionary:
			out.append(ToolDefinition.from_dict(item as Dictionary, default_source, default_server_id))
		elif item is ToolDefinition:
			out.append(ToolDefinition.from_dict((item as ToolDefinition).to_dict()))
	return out
