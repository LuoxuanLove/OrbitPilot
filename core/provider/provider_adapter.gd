@tool
extends RefCounted

const CURL_EXECUTABLE := "curl.exe"
const CURL_STATUS_MARKER := "__ORBIT_HTTP_STATUS__:"

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
	return await _request_json_with_tls(url, method, headers, body, timeout_sec, false)


func _request_json_with_tls(
	url: String,
	method: int,
	headers: PackedStringArray,
	body: String,
	timeout_sec: float = 30.0,
	unsafe_tls: bool = false
) -> Dictionary:
	if _host_node == null:
		return {"success": false, "error": "host_node_missing"}

	var request := HTTPRequest.new()
	request.timeout = timeout_sec
	if unsafe_tls and url.begins_with("https://"):
		request.set_tls_options(TLSOptions.client_unsafe())
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
		if (
			not unsafe_tls
			and url.begins_with("https://")
			and result_code == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR
		):
			return await _request_json_with_tls(url, method, headers, body, timeout_sec, true)
		if (
			unsafe_tls
			and url.begins_with("https://")
			and result_code == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR
			and method == HTTPClient.METHOD_POST
		):
			return _request_json_via_curl(url, method, headers, body, timeout_sec)
		return {
			"success": false,
			"error": "http_request_failed",
			"phase": "request_completed",
			"url": url,
			"unsafe_tls": unsafe_tls,
			"result_code": result_code,
			"result_name": _request_result_name(result_code),
			"response_code": response_code,
			"body": parsed,
		}
	if response_code >= 400:
		return {
			"success": false,
			"error": "http_error_status",
			"phase": "request_completed",
			"url": url,
			"unsafe_tls": unsafe_tls,
			"response_code": response_code,
			"body": parsed,
		}
	var response := {"success": true, "response_code": response_code, "body": parsed}
	if unsafe_tls:
		response["tls_unsafe_fallback"] = true
		response["transport"] = "native_unsafe"
	else:
		response["transport"] = "native"
	return response


func _stream_sse_json(
	url: String,
	headers: PackedStringArray,
	body: String,
	event_callback: Callable,
	cancel_callback: Callable,
	timeout_sec: float = 60.0
) -> Dictionary:
	return await _stream_sse_json_with_tls(url, headers, body, event_callback, cancel_callback, timeout_sec, false)


func _stream_sse_json_with_tls(
	url: String,
	headers: PackedStringArray,
	body: String,
	event_callback: Callable,
	cancel_callback: Callable,
	timeout_sec: float = 60.0,
	unsafe_tls: bool = false
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
		tls_options = TLSOptions.client_unsafe() if unsafe_tls else TLSOptions.client()

	var err := client.connect_to_host(host, port, tls_options)
	if err != OK:
		if tls and not unsafe_tls:
			client.close()
			return await _stream_sse_json_with_tls(url, headers, body, event_callback, cancel_callback, timeout_sec, true)
		return {
			"success": false,
			"error": "connect_failed",
			"phase": "connect_to_host",
			"url": url,
			"unsafe_tls": unsafe_tls,
			"code": err,
		}

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

	var connect_status := client.get_status()
	if connect_status != HTTPClient.STATUS_CONNECTED:
		client.close()
		if tls and not unsafe_tls and _is_tls_like_client_status(connect_status):
			return await _stream_sse_json_with_tls(url, headers, body, event_callback, cancel_callback, timeout_sec, true)
		return {
			"success": false,
			"error": "not_connected",
			"phase": "await_connect",
			"url": url,
			"unsafe_tls": unsafe_tls,
			"status": connect_status,
			"status_name": _client_status_name(connect_status),
		}

	var final_headers: PackedStringArray = PackedStringArray(headers)
	final_headers.append("Accept: text/event-stream")
	err = client.request(HTTPClient.METHOD_POST, path, final_headers, body)
	if err != OK:
		client.close()
		return {
			"success": false,
			"error": "request_failed",
			"phase": "client_request",
			"url": url,
			"unsafe_tls": unsafe_tls,
			"code": err,
		}

	# Wait for response headers so we can check the HTTP status code.
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

	var header_status := client.get_status()
	if _is_client_error_status(header_status):
		client.close()
		if tls and not unsafe_tls and _is_tls_like_client_status(header_status):
			return await _stream_sse_json_with_tls(url, headers, body, event_callback, cancel_callback, timeout_sec, true)
		return {
			"success": false,
			"error": "http_request_failed",
			"phase": "await_headers",
			"url": url,
			"unsafe_tls": unsafe_tls,
			"status": header_status,
			"status_name": _client_status_name(header_status),
		}

	var response_code := client.get_response_code()
	if response_code >= 400:
		client.close()
		return {
			"success": false,
			"error": "http_error_status",
			"phase": "response_headers",
			"url": url,
			"unsafe_tls": unsafe_tls,
			"response_code": response_code,
		}

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
					var done_result := {"success": true}
					if unsafe_tls:
						done_result["tls_unsafe_fallback"] = true
					return done_result
		elif status == HTTPClient.STATUS_CONNECTED:
			# Request completed and socket still connected.
			var drain := _drain_sse_buffer(buffer, event_callback)
			buffer = str(drain.get("remaining", ""))
			client.close()
			var connected_result := {"success": true}
			if unsafe_tls:
				connected_result["tls_unsafe_fallback"] = true
			return connected_result
		elif status == HTTPClient.STATUS_DISCONNECTED:
			var drain := _drain_sse_buffer(buffer, event_callback)
			buffer = str(drain.get("remaining", ""))
			client.close()
			var disconnected_result := {"success": true}
			if unsafe_tls:
				disconnected_result["tls_unsafe_fallback"] = true
			return disconnected_result
		elif _is_client_error_status(status):
			client.close()
			if tls and not unsafe_tls and _is_tls_like_client_status(status):
				return await _stream_sse_json_with_tls(url, headers, body, event_callback, cancel_callback, timeout_sec, true)
			return {
				"success": false,
				"error": "http_request_failed",
				"phase": "stream_body",
				"url": url,
				"unsafe_tls": unsafe_tls,
				"status": status,
				"status_name": _client_status_name(status),
			}
		var tree := _host_node.get_tree()
		if tree == null:
			client.close()
			return {"success": false, "error": "host_node_tree_missing"}
		await tree.process_frame
	client.close()
	return {"success": false, "error": "stream_ended_unexpectedly"}


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


func _is_client_error_status(status: int) -> bool:
	return (
		status == HTTPClient.STATUS_CANT_RESOLVE
		or status == HTTPClient.STATUS_CANT_CONNECT
		or status == HTTPClient.STATUS_CONNECTION_ERROR
		or status == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR
	)


func _is_tls_like_client_status(status: int) -> bool:
	return (
		status == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR
		or status == HTTPClient.STATUS_CONNECTION_ERROR
		or status == HTTPClient.STATUS_DISCONNECTED
	)


func _request_json_via_curl(
	url: String,
	method: int,
	headers: PackedStringArray,
	body: String,
	timeout_sec: float
) -> Dictionary:
	var payload_path := _write_temp_payload(body)
	if payload_path.is_empty():
		return {
			"success": false,
			"error": "curl_payload_write_failed",
			"phase": "curl_prepare",
			"url": url,
			"transport": "curl",
		}

	var output_lines: Array = []
	var args: Array[String] = [
		"--silent",
		"--show-error",
		"--location",
		"--request",
		_http_method_name(method),
		"--max-time",
		str(maxf(timeout_sec, 1.0)),
		"--output",
		"-",
		"--write-out",
		"\n%s%%{http_code}" % CURL_STATUS_MARKER,
	]
	for header in headers:
		args.append("--header")
		args.append(str(header))
	args.append("--data-binary")
	args.append("@%s" % payload_path)
	args.append(url)

	var executable := CURL_EXECUTABLE
	if OS.get_name() != "Windows":
		executable = "curl"

	var exit_code := OS.execute(executable, args, output_lines, true, true)
	_delete_temp_file(payload_path)

	var stdout_text := "\n".join(_stringify_array(output_lines))
	var stderr_text := stdout_text
	if exit_code != OK:
		return {
			"success": false,
			"error": "curl_execute_failed",
			"phase": "curl_execute",
			"url": url,
			"transport": "curl",
			"code": exit_code,
			"body": stderr_text,
		}

	var marker_index := stdout_text.rfind(CURL_STATUS_MARKER)
	if marker_index < 0:
		return {
			"success": false,
			"error": "curl_status_missing",
			"phase": "curl_parse",
			"url": url,
			"transport": "curl",
			"body": stdout_text if not stdout_text.is_empty() else stderr_text,
		}

	var response_text := stdout_text.substr(0, marker_index).rstrip("\r\n")
	var status_text := stdout_text.substr(marker_index + CURL_STATUS_MARKER.length()).strip_edges()
	var response_code := int(status_text) if status_text.is_valid_int() else 0
	var parsed_body := _parse_json_maybe(response_text)

	if response_code >= 400:
		return {
			"success": false,
			"error": "http_error_status",
			"phase": "curl_response",
			"url": url,
			"transport": "curl",
			"response_code": response_code,
			"body": parsed_body,
		}
	if response_code <= 0:
		return {
			"success": false,
			"error": "curl_invalid_status",
			"phase": "curl_response",
			"url": url,
			"transport": "curl",
			"body": parsed_body if response_text.length() > 0 else stderr_text,
		}
	return {
		"success": true,
		"response_code": response_code,
		"body": parsed_body,
		"transport": "curl",
	}


func _write_temp_payload(body: String) -> String:
	var temp_path := "user://orbit_pilot_http_bridge_%s.json" % str(Time.get_ticks_usec())
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(body)
	file.close()
	return ProjectSettings.globalize_path(temp_path)


func _delete_temp_file(path: String) -> void:
	if path.strip_edges().is_empty():
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _parse_json_maybe(text: String) -> Variant:
	var stripped := text.strip_edges()
	if stripped.is_empty():
		return ""
	var parser := JSON.new()
	if parser.parse(text) == OK:
		return parser.get_data()
	return text


func _stringify_array(values: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for value in values:
		out.append(str(value))
	return out


func _http_method_name(method: int) -> String:
	match method:
		HTTPClient.METHOD_GET:
			return "GET"
		HTTPClient.METHOD_POST:
			return "POST"
		HTTPClient.METHOD_PUT:
			return "PUT"
		HTTPClient.METHOD_DELETE:
			return "DELETE"
		HTTPClient.METHOD_PATCH:
			return "PATCH"
		_:
			return "POST"


func _client_status_name(status: int) -> String:
	match status:
		HTTPClient.STATUS_DISCONNECTED:
			return "disconnected"
		HTTPClient.STATUS_RESOLVING:
			return "resolving"
		HTTPClient.STATUS_CANT_RESOLVE:
			return "cant_resolve"
		HTTPClient.STATUS_CONNECTING:
			return "connecting"
		HTTPClient.STATUS_CANT_CONNECT:
			return "cant_connect"
		HTTPClient.STATUS_CONNECTED:
			return "connected"
		HTTPClient.STATUS_REQUESTING:
			return "requesting"
		HTTPClient.STATUS_BODY:
			return "body"
		HTTPClient.STATUS_CONNECTION_ERROR:
			return "connection_error"
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			return "tls_handshake_error"
		_:
			return "unknown_status_%d" % status


func _request_result_name(result_code: int) -> String:
	match result_code:
		HTTPRequest.RESULT_SUCCESS:
			return "success"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "chunked_body_size_mismatch"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "cant_connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "cant_resolve"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection_error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "tls_handshake_error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "no_response"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "body_size_limit_exceeded"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "body_decompress_failed"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "request_failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "download_file_cant_open"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "download_file_write_error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "redirect_limit_reached"
		HTTPRequest.RESULT_TIMEOUT:
			return "timeout"
		_:
			return "unknown_result_%d" % result_code
