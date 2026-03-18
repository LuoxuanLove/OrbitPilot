@tool
extends RefCounted
class_name ToolDefinition

var name: String = ""
var description: String = ""
var source: String = ""
var server_id: String = ""


static func from_dict(data: Dictionary, default_source: String = "", default_server_id: String = "") -> ToolDefinition:
	var definition := ToolDefinition.new()
	definition.name = str(data.get("name", ""))
	definition.description = str(data.get("description", ""))
	definition.source = str(data.get("source", default_source))
	definition.server_id = str(data.get("server_id", default_server_id))
	return definition


func to_dict() -> Dictionary:
	var out := {
		"id": _build_id(),
		"name": name,
		"description": description,
		"source": source,
	}
	if source == "remote":
		out["server_id"] = server_id
	return out


func matches_id(tool_id: String) -> bool:
	return _build_id() == tool_id


func _build_id() -> String:
	if source == "remote":
		return "remote:%s:%s" % [server_id, name]
	return "local:%s" % name
