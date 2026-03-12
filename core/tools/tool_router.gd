@tool
extends RefCounted

var _local_tools
var _remote_client
var _tool_catalog
var _remote_servers: Dictionary = {}
var _route_strategy: Dictionary = {
	"prefer_local_reads": true,
	"prefer_remote_writes": true,
}


func setup(local_tools, remote_client, tool_catalog) -> void:
	_local_tools = local_tools
	_remote_client = remote_client
	_tool_catalog = tool_catalog


func set_remote_servers(remote_servers: Dictionary) -> void:
	_remote_servers = remote_servers.duplicate(true)


func set_route_strategy(route_strategy: Dictionary) -> void:
	for key in route_strategy.keys():
		_route_strategy[key] = route_strategy[key]


func execute(tool_id: String, args: Dictionary) -> Dictionary:
	var resolved_id := _resolve_tool_id(tool_id)
	if resolved_id.begins_with("local:"):
		var local_name := resolved_id.trim_prefix("local:")
		return await _local_tools.execute(local_name, args)

	if resolved_id.begins_with("remote:"):
		var parts := resolved_id.split(":")
		if parts.size() < 3:
			return {"success": false, "error": "invalid_remote_tool_id"}

		var server_id := parts[1]
		var remote_name := ":".join(parts.slice(2, parts.size()))
		if not _remote_servers.has(server_id):
			return {"success": false, "error": "remote_server_not_found"}

		var server_cfg: Dictionary = _remote_servers[server_id]
		if not bool(server_cfg.get("enabled", false)):
			return {"success": false, "error": "remote_server_disabled"}

		var endpoint := str(server_cfg.get("endpoint", ""))
		if endpoint.is_empty():
			return {"success": false, "error": "remote_endpoint_empty"}

		if _remote_client == null or not _remote_client.has_method("call_tool"):
			return {"success": false, "error": "remote_client_unavailable"}
		return await _remote_client.call_tool(endpoint, remote_name, args, float(server_cfg.get("timeout_sec", 30.0)))

	return {"success": false, "error": "unknown_tool_source", "tool_id": tool_id}


func _resolve_tool_id(tool_name: String) -> String:
	if tool_name.begins_with("local:") or tool_name.begins_with("remote:"):
		return tool_name
	if _tool_catalog == null:
		return tool_name

	var candidates: Array = _tool_catalog.get_candidates_by_name(tool_name)
	if candidates.is_empty():
		return tool_name
	if candidates.size() == 1:
		return str(candidates[0].get("id", tool_name))

	var read_names := {
		"search_files": true,
		"search_text": true,
		"read_file": true,
		"get_editor_context": true,
		"get_script_symbols": true,
		"get_scene_dependencies": true,
		"get_context_bundle": true,
	}
	if bool(_route_strategy.get("prefer_local_reads", true)) and read_names.has(tool_name):
		for item in candidates:
			if str(item.get("source", "")) == "local":
				return str(item.get("id", tool_name))

	if bool(_route_strategy.get("prefer_remote_writes", true)) and _looks_mutating(tool_name):
		for item in candidates:
			if str(item.get("source", "")) == "remote":
				return str(item.get("id", tool_name))

	return str(candidates[0].get("id", tool_name))


func _looks_mutating(tool_name: String) -> bool:
	if tool_name.find("set_") >= 0:
		return true
	if tool_name.find("write") >= 0:
		return true
	if tool_name.find("create_") >= 0:
		return true
	if tool_name.find("delete") >= 0:
		return true
	if tool_name.find("apply") >= 0:
		return true
	return false
