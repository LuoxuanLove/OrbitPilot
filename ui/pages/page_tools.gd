@tool
class_name OrbitPageTools
extends RefCounted

signal run_tool_requested(tool_id: String, args_json: String)

var _root: Control
var _tool_select: OptionButton
var _tool_args_edit: TextEdit
var _run_tool_button: Button
var _tool_result: RichTextLabel
var _tool_result_panel: Control


func setup(dock_root: Control) -> void:
	_root = dock_root
	_assign_nodes()
	_bind_events()


func apply_model(model: Dictionary) -> void:
	var tools = model.get("tools", [])
	_tool_select.clear()
	for tool in tools:
		if not (tool is Dictionary):
			continue
		var tool_id := str(tool.get("id", ""))
		var label := "%s  %s" % [str(tool.get("source", "local")).to_upper(), tool_id]
		_tool_select.add_item(label)
		_tool_select.set_item_metadata(_tool_select.item_count - 1, tool_id)
	if _tool_select.item_count > 0:
		_tool_select.select(0)
		_on_tool_selected(0)
	_apply_tool_result(model)


func get_chrome_panels() -> Dictionary:
	return {"tool_result": _tool_result_panel}


func _node(path: String):
	return _root.get_node(path)


func _assign_nodes() -> void:
	_tool_select = _node("RootMargin/Root/PageStack/PageTools/ToolSelect")
	_tool_args_edit = _node("RootMargin/Root/PageStack/PageTools/ToolArgsEdit")
	_run_tool_button = _node("RootMargin/Root/PageStack/PageTools/RunToolButton")
	_tool_result_panel = _node("RootMargin/Root/PageStack/PageTools/ToolResultPanel")
	_tool_result = _node("RootMargin/Root/PageStack/PageTools/ToolResultPanel/ToolResult")


func _bind_events() -> void:
	_run_tool_button.pressed.connect(_on_run_tool_pressed)
	_tool_select.item_selected.connect(_on_tool_selected)


func _apply_tool_result(model: Dictionary) -> void:
	var last_tool_result = model.get("last_tool_result", {})
	if last_tool_result.is_empty():
		_tool_result.text = "No tool result yet."
		return
	_tool_result.text = "Tool: %s\nAt: %s\n\n%s" % [
		str(last_tool_result.get("tool_id", "")),
		str(last_tool_result.get("at", "")),
		JSON.stringify(last_tool_result.get("result", {}), "\t"),
	]


func _on_run_tool_pressed() -> void:
	if _tool_select.item_count == 0:
		return
	emit_signal("run_tool_requested", str(_tool_select.get_item_metadata(_tool_select.selected)), _tool_args_edit.text)


func _on_tool_selected(index: int) -> void:
	if index < 0 or index >= _tool_select.item_count:
		return
	var tool_id := str(_tool_select.get_item_metadata(index))
	if tool_id.find("read_file") >= 0:
		_tool_args_edit.text = "{\"path\":\"res://README.md\"}"
	elif tool_id.find("search_files") >= 0:
		_tool_args_edit.text = "{\"pattern\":\"*.gd\",\"path\":\"res://addons/orbit_pilot\"}"
	elif tool_id.find("run_regression_suite") >= 0:
		_tool_args_edit.text = "{}"
	elif tool_id.find("apply_change_set") >= 0:
		_tool_args_edit.text = "{\"change_set_id\":\"\",\"approved\":true}"
	else:
		_tool_args_edit.text = "{}"
