@tool
extends RefCounted
class_name ProviderBase

var _host_node: Node


func setup(host_node: Node) -> void:
	_host_node = host_node


func get_id() -> String:
	return ""


func send_chat(_provider_config: Dictionary, _messages: Array, _tools: Array) -> Dictionary:
	return {"success": false, "error": "not_implemented"}


func send_chat_stream(
	provider_config: Dictionary,
	messages: Array,
	tools: Array,
	event_callback: Callable,
	cancel_callback: Callable
) -> Dictionary:
	var result := await send_chat(provider_config, messages, tools)
	if not bool(result.get("success", false)):
		return result
	var assistant_message: Dictionary = result.get("assistant_message", {})
	var content := str(assistant_message.get("content", ""))
	if event_callback.is_valid() and not content.is_empty():
		event_callback.call({"kind": "message_delta", "delta": content})
	result["streamed"] = false
	return result


func _request_json(url: String, method: int, headers: PackedStringArray, body: String, timeout_sec: float = 30.0) -> Dictionary:
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
	var parser := JSON.new()
	var parsed: Variant = text
	if not text.strip_edges().is_empty() and parser.parse(text) == OK:
		parsed = parser.get_data()
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"success": false, "error": "http_request_failed", "result_code": result_code, "response_code": response_code, "body": parsed}
	if response_code >= 400:
		return {"success": false, "error": "http_error_status", "response_code": response_code, "body": parsed}
	return {"success": true, "response_code": response_code, "body": parsed}


func _stream_sse_json(
	url: String,
	headers: PackedStringArray,
	body: String,
	event_callback: Callable,
	cancel_callback: Callable,
	timeout_sec: float = 60.0
) -> Dictionary:
	var parsed_url := _parse_http_url(url)
	if parsed_url.is_empty():
		return {"success": false, "error": "invalid_url"}
	var client := HTTPClient.new()
	var tls := bool(parsed_url.get("tls", false))
	var host := str(parsed_url.get("host", ""))
	var port := int(parsed_url.get("port", 0))
	var path := str(parsed_url.get("path", "/"))
	var tls_options: TLSOptions = null
	if tls:
		tls_options = TLSOptions.client()
	var err := client.connect_to_host(host, port, tls_options)
	if err != OK:
		return {"success": false, "error": "connect_failed", "code": err}
	var start_ms := Time.get_ticks_msec()
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		if _should_cancel(cancel_callback):
			client.close()
			return {"success": false, "error": "cancelled"}
		if _timeout_exceeded(start_ms, timeout_sec):
			client.close()
			return {"success": false, "error": "connect_timeout"}
		client.poll()
		var tree := _host_node.get_tree()
		if tree == null:
			client.close()
			return {"success": false, "error": "host_node_tree_missing"}
		await tree.process_frame
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		client.close()
		return {"success": false, "error": "not_connected", "status": client.get_status()}
	var final_headers: PackedStringArray = PackedStringArray(headers)
	final_headers.append("Accept: text/event-stream")
	err = client.request(HTTPClient.METHOD_POST, path, final_headers, body)
	if err != OK:
		client.close()
		return {"success": false, "error": "request_failed", "code": err}
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		if _should_cancel(cancel_callback):
			client.close()
			return {"success": false, "error": "cancelled"}
		if _timeout_exceeded(start_ms, timeout_sec):
			client.close()
			return {"success": false, "error": "stream_timeout"}
		client.poll()
		var tree := _host_node.get_tree()
		if tree == null:
			client.close()
			return {"success": false, "error": "host_node_tree_missing"}
		await tree.process_frame
	var response_code := client.get_response_code()
	if response_code >= 400:
		client.close()
		return {"success": false, "error": "http_error_status", "response_code": response_code}
	var buffer := ""
	while true:
		if _should_cancel(cancel_callback):
			client.close()
			return {"success": false, "error": "cancelled"}
		if _timeout_exceeded(start_ms, timeout_sec):
			client.close()
			return {"success": false, "error": "stream_timeout"}
		client.poll()
		var status := client.get_status()
		if status == HTTPClient.STATUS_BODY:
			var chunk := client.read_response_body_chunk()
			if not chunk.is_empty():
				buffer += chunk.get_string_from_utf8()
				var drain := _drain_sse_buffer(buffer, event_callback)
				buffer = str(drain.get("remaining", ""))
				if bool(drain.get("done", false)):
					client.close()
					return {"success": true}
		elif status == HTTPClient.STATUS_CONNECTED or status == HTTPClient.STATUS_DISCONNECTED:
			var drain := _drain_sse_buffer(buffer, event_callback)
			buffer = str(drain.get("remaining", ""))
			client.close()
			return {"success": true}
		var tree := _host_node.get_tree()
		if tree == null:
			client.close()
			return {"success": false, "error": "host_node_tree_missing"}
		await tree.process_frame


func _drain_sse_buffer(buffer: String, event_callback: Callable) -> Dictionary:
	var normalized := buffer.replace("\r\n", "\n")
	var remaining := normalized
	while true:
		var boundary := remaining.find("\n\n")
		if boundary < 0:
			break
		var raw_event := remaining.substr(0, boundary)
		remaining = remaining.substr(boundary + 2)
		var data_lines := PackedStringArray()
		for line in raw_event.split("\n"):
			var trimmed := str(line).strip_edges()
			if trimmed.begins_with("data:"):
				data_lines.append(trimmed.trim_prefix("data:").strip_edges())
		if data_lines.is_empty():
			continue
		var data_str := "\n".join(data_lines)
		if data_str == "[DONE]":
			return {"remaining": remaining, "done": true}
		var parsed: Variant = data_str
		var parser := JSON.new()
		if parser.parse(data_str) == OK:
			parsed = parser.get_data()
		if event_callback.is_valid():
			event_callback.call({"raw": data_str, "json": parsed})
	return {"remaining": remaining, "done": false}


func _parse_http_url(url: String) -> Dictionary:
	var value := url.strip_edges()
	var tls := false
	if value.begins_with("https://"):
		tls = true
		value = value.trim_prefix("https://")
	elif value.begins_with("http://"):
		value = value.trim_prefix("http://")
	else:
		return {}
	var slash_index := value.find("/")
	var host_port := value if slash_index < 0 else value.substr(0, slash_index)
	var path := "/" if slash_index < 0 else value.substr(slash_index)
	if host_port.is_empty():
		return {}
	var host := host_port
	var port := 443 if tls else 80
	var colon_index := host_port.rfind(":")
	if colon_index > 0:
		host = host_port.substr(0, colon_index)
		var port_text := host_port.substr(colon_index + 1)
		if port_text.is_valid_int():
			port = int(port_text)
	return {"tls": tls, "host": host, "port": port, "path": path}


func _resolve_api_key(config: Dictionary) -> String:
	var direct := str(config.get("api_key", "")).strip_edges()
	if not direct.is_empty():
		return direct
	var env_key := str(config.get("api_key_env", "")).strip_edges()
	if env_key.is_empty():
		return ""
	return OS.get_environment(env_key).strip_edges()


func _should_cancel(cancel_callback: Callable) -> bool:
	if not cancel_callback.is_valid():
		return false
	return bool(cancel_callback.call())


func _timeout_exceeded(start_ms: int, timeout_sec: float) -> bool:
	if timeout_sec <= 0.0:
		return false
	return (Time.get_ticks_msec() - start_ms) > int(timeout_sec * 1000.0)
