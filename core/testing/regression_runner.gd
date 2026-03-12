@tool
extends RefCounted
class_name OrbitRegressionRunner

const OrbitTypes = preload("res://addons/orbit_pilot/core/types.gd")
const ChangeSetService = preload("res://addons/orbit_pilot/core/changes/change_set_service.gd")
const LocalTools = preload("res://addons/orbit_pilot/core/tools/local_tools.gd")
const ToolCatalog = preload("res://addons/orbit_pilot/core/tools/tool_catalog.gd")
const ToolRouter = preload("res://addons/orbit_pilot/core/tools/tool_router.gd")
const ExecutionService = preload("res://addons/orbit_pilot/core/execution/execution_service.gd")
const ContextIndexService = preload("res://addons/orbit_pilot/core/context/context_index_service.gd")

var _host_node: Node
var _editor_interface: EditorInterface


func setup(host_node: Node, editor_interface: EditorInterface) -> void:
	_host_node = host_node
	_editor_interface = editor_interface


func run_minimal_suite() -> Dictionary:
	var started_unix := Time.get_unix_time_from_system()
	var cases: Array[Dictionary] = []
	cases.append(await _run_case("change_set_lifecycle", Callable(self, "_test_change_set_lifecycle")))
	cases.append(await _run_case("propose_blocks_mutating", Callable(self, "_test_propose_blocks_mutating")))
	cases.append(await _run_case("cancel_run_semantics", Callable(self, "_test_cancel_run_semantics")))
	cases.append(await _run_case("tool_catalog_prefix", Callable(self, "_test_tool_catalog_prefix")))

	var passed := 0
	for item in cases:
		if bool(item.get("passed", false)):
			passed += 1

	return {
		"success": true,
		"suite": "orbitpilot_minimal",
		"started_unix": started_unix,
		"finished_unix": Time.get_unix_time_from_system(),
		"total": cases.size(),
		"passed": passed,
		"failed": cases.size() - passed,
		"cases": cases,
	}


func _run_case(name: String, fn: Callable) -> Dictionary:
	var started := Time.get_ticks_msec()
	var result: Dictionary = {}
	if fn.is_valid():
		var raw = await fn.call()
		if raw is Dictionary:
			result = raw
	var passed := bool(result.get("passed", false))
	return {
		"name": name,
		"passed": passed,
		"elapsed_ms": Time.get_ticks_msec() - started,
		"detail": result.get("detail", ""),
		"data": result.get("data", {}),
	}


func _test_change_set_lifecycle() -> Dictionary:
	await _yield_frame()
	var change_set_service := ChangeSetService.new()
	var test_path := "user://orbit_pilot_regression_tmp.txt"
	var abs := ProjectSettings.globalize_path(test_path)

	var seed_file := FileAccess.open(abs, FileAccess.WRITE)
	if seed_file == null:
		return {"passed": false, "detail": "failed_to_create_seed_file"}
	seed_file.store_string("old")
	seed_file.close()

	var create_res := change_set_service.create_change_set(test_path, "new")
	if not bool(create_res.get("success", false)):
		return {"passed": false, "detail": "create_change_set_failed", "data": create_res}

	var change_set: Dictionary = create_res.get("change_set", {})
	var apply_res := change_set_service.apply_change_set(str(change_set.get("id", "")), true)
	if not bool(apply_res.get("success", false)):
		return {"passed": false, "detail": "apply_change_set_failed", "data": apply_res}

	var read_file := FileAccess.open(abs, FileAccess.READ)
	if read_file == null:
		return {"passed": false, "detail": "failed_to_read_after_apply"}
	var after_apply := read_file.get_as_text()
	read_file.close()
	if after_apply != "new":
		return {"passed": false, "detail": "apply_content_mismatch", "data": {"after_apply": after_apply}}

	var rollback_res := change_set_service.rollback_last()
	if not bool(rollback_res.get("success", false)):
		return {"passed": false, "detail": "rollback_failed", "data": rollback_res}

	read_file = FileAccess.open(abs, FileAccess.READ)
	if read_file == null:
		return {"passed": false, "detail": "failed_to_read_after_rollback"}
	var after_rollback := read_file.get_as_text()
	read_file.close()
	if after_rollback != "old":
		return {"passed": false, "detail": "rollback_content_mismatch", "data": {"after_rollback": after_rollback}}

	DirAccess.remove_absolute(abs)
	return {"passed": true, "detail": "ok"}


func _test_propose_blocks_mutating() -> Dictionary:
	await _yield_frame()
	var change_set_service := ChangeSetService.new()
	var context_service := ContextIndexService.new()
	var local_tools := LocalTools.new()
	local_tools.setup(_editor_interface, change_set_service, context_service)

	var tool_catalog := ToolCatalog.new()
	tool_catalog.set_local_tools(local_tools.get_definitions())

	var tool_router := ToolRouter.new()
	tool_router.setup(local_tools, _MockRemoteClient.new(), tool_catalog)

	var execution_service := ExecutionService.new()
	var provider := _MockProviderMutating.new()
	provider.setup(_host_node)
	execution_service.setup({provider.get_id(): provider}, tool_router)

	var res := await execution_service.execute_turn(
		OrbitTypes.RUN_POLICY_PROPOSE,
		provider.get_id(),
		{},
		[{"role": "user", "content": "test"}],
		[{"name": "local:create_change_set", "description": "x", "input_schema": {"type": "object"}}],
		"run_prop",
		Callable()
	)
	if not bool(res.get("success", false)):
		return {"passed": false, "detail": "execute_turn_failed", "data": res}

	var tool_results: Array = res.get("tool_results", [])
	if tool_results.is_empty():
		return {"passed": false, "detail": "missing_tool_results"}
	var first: Dictionary = tool_results[0]
	if not bool(first.get("skipped", false)):
		return {"passed": false, "detail": "mutating_call_not_blocked", "data": first}
	return {"passed": true, "detail": "ok"}


func _test_cancel_run_semantics() -> Dictionary:
	await _yield_frame()
	var change_set_service := ChangeSetService.new()
	var context_service := ContextIndexService.new()
	var local_tools := LocalTools.new()
	local_tools.setup(_editor_interface, change_set_service, context_service)
	var tool_catalog := ToolCatalog.new()
	tool_catalog.set_local_tools(local_tools.get_definitions())
	var tool_router := ToolRouter.new()
	tool_router.setup(local_tools, _MockRemoteClient.new(), tool_catalog)

	var execution_service := ExecutionService.new()
	var provider := _MockProviderStreamCancelable.new()
	provider.setup(_host_node)
	execution_service.setup({provider.get_id(): provider}, tool_router)

	var run_id := "run_cancel_test"
	execution_service.cancel_run(run_id)
	var res := await execution_service.execute_turn(
		OrbitTypes.RUN_POLICY_ANALYZE,
		provider.get_id(),
		{},
		[{"role": "user", "content": "test"}],
		[],
		run_id,
		Callable()
	)
	if bool(res.get("success", false)):
		return {"passed": false, "detail": "cancel_not_effective", "data": res}
	if str(res.get("error", "")) != "run_cancelled":
		return {"passed": false, "detail": "unexpected_cancel_error", "data": res}
	return {"passed": true, "detail": "ok"}


func _test_tool_catalog_prefix() -> Dictionary:
	await _yield_frame()
	var catalog := ToolCatalog.new()
	catalog.set_local_tools([{"name": "read_file", "description": "x"}])
	catalog.set_remote_tools("main", [{"name": "scene_management", "description": "y"}])
	var tools := catalog.get_unified_tools()
	var has_local := false
	var has_remote := false
	for item in tools:
		var id := str(item.get("id", ""))
		if id == "local:read_file":
			has_local = true
		if id == "remote:main:scene_management":
			has_remote = true
	if has_local and has_remote:
		return {"passed": true, "detail": "ok"}
	return {"passed": false, "detail": "prefix_missing", "data": {"tools": tools}}


func _yield_frame() -> void:
	if _host_node != null and _host_node.get_tree() != null:
		await _host_node.get_tree().process_frame


class _MockRemoteClient:
	extends RefCounted

	func call_tool(_endpoint: String, _tool_name: String, _args: Dictionary, _timeout_sec: float = 30.0) -> Dictionary:
		return {"success": true, "result": {"mock": true}}


class _MockProviderMutating:
	extends RefCounted

	var _host_node: Node

	func setup(host_node: Node) -> void:
		_host_node = host_node

	func get_id() -> String:
		return "mock_mutating"

	func send_chat(_provider_config: Dictionary, _messages: Array, _tools: Array) -> Dictionary:
		return {
			"success": true,
			"assistant_message": {"role": "assistant", "content": "call tool"},
			"tool_calls": [{
				"type": "function",
				"function": {"name": "local:create_change_set", "arguments": "{\"path\":\"user://x.txt\",\"new_text\":\"abc\"}"}
			}],
			"raw": {},
			"streamed": false,
		}

	func send_chat_stream(
		provider_config: Dictionary,
		messages: Array,
		tools: Array,
		_event_callback: Callable,
		_cancel_callback: Callable
	) -> Dictionary:
		return send_chat(provider_config, messages, tools)


class _MockProviderStreamCancelable:
	extends RefCounted

	var _host_node: Node

	func setup(host_node: Node) -> void:
		_host_node = host_node

	func get_id() -> String:
		return "mock_stream"

	func send_chat_stream(
		_provider_config: Dictionary,
		_messages: Array,
		_tools: Array,
		event_callback: Callable,
		cancel_callback: Callable
	) -> Dictionary:
		for i in range(5):
			if cancel_callback.is_valid() and bool(cancel_callback.call()):
				return {"success": false, "error": "cancelled"}
			if event_callback.is_valid():
				event_callback.call({"kind": "message_delta", "delta": "chunk_%d" % i})
		return {
			"success": true,
			"assistant_message": {"role": "assistant", "content": "done"},
			"tool_calls": [],
			"streamed": true,
		}
