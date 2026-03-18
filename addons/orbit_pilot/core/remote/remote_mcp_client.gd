@tool
extends RefCounted
class_name RemoteMcpClient

var _host_node: Node


func setup(host_node: Node) -> void:
	_host_node = host_node


func health_check(endpoint: String, timeout_sec: float = 8.0) -> Dictionary:
	return await _request_json("%s/health" % endpoint.trim_suffix("/"), HTTPClient.METHOD_GET, "", PackedStringArray(), timeout_sec)


func fetch_tools(endpoint: String, timeout_sec: float = 10.0) -> Dictionary:
	var response := await _request_json("%s/api/tools" % endpoint.trim_suffix("/"), HTTPClient.METHOD_GET, "", PackedStringArray(), timeout_sec)
	if not bool(response.get("success", false)):
		return response

	var body := response.get("body")
	if body is Array:
		return {"success": true, "tools": body}
	if body is Dictionary:
		if body.has("tools") and body["tools"] is Array:
			return {"success": true, "tools": body["tools"]}
		if body.has("result") and body["result"] is Array:
			return {"success": true, "tools": body["result"]}
	return {"success": false, "error": "unexpected_tools_payload", "raw": body}


func call_tool(endpoint: String, tool_name: String, args: Dictionary, timeout_sec: float = 30.0) -> Dictionary:
	var payload := {
		"jsonrpc": "2.0",
		"id": str(Time.get_unix_time_from_system()),
		"method": "tools/call",
		"params": {
			"name": tool_name,
			"arguments": args,
		}
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	var response := await _request_json(
		"%s/mcp" % endpoint.trim_suffix("/"),
		HTTPClient.METHOD_POST,
		JSON.stringify(payload),
		headers,
		timeout_sec
	)
	if not bool(response.get("success", false)):
		return response

	var body := response.get("body")
	if body is Dictionary and body.has("result"):
		return {"success": true, "result": body["result"], "raw": body}
	return {"success": true, "result": body, "raw": body}


func _request_json(url: String, method: int, body: String, headers: PackedStringArray, timeout_sec: float) -> Dictionary:
	if _host_node == null:
		return {"success": false, "error": "host_node_missing"}

	var request := HTTPRequest.new()
	request.timeout = timeout_sec
	_host_node.add_child(request)

	var err := request.request(url, headers, method, body)
	if err != OK:
		request.queue_free()
		return {"success": false, "error": "request_start_failed", "code": err}

	var completed = await request.request_completed
	request.queue_free()
	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var response_body: PackedByteArray = completed[3]

	var text := response_body.get_string_from_utf8()
	var parsed: Variant = text
	var parser := JSON.new()
	if not text.strip_edges().is_empty() and parser.parse(text) == OK:
		parsed = parser.get_data()

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {
			"success": false,
			"error": "http_request_failed",
			"result_code": result_code,
			"response_code": response_code,
			"body": parsed,
		}

	if response_code >= 400:
		return {
			"success": false,
			"error": "http_error_status",
			"response_code": response_code,
			"body": parsed,
		}

	return {"success": true, "response_code": response_code, "body": parsed}
