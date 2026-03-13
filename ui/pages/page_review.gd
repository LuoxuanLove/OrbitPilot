@tool
class_name OrbitPageReview
extends RefCounted

signal approve_change_set_requested(change_set_id: String, approved: bool)

var _root: Control
var _change_set_select: OptionButton
var _change_set_preview: RichTextLabel
var _approve_button: Button
var _reject_button: Button
var _change_set_preview_panel: Control
var _model := {}


func setup(dock_root: Control) -> void:
	_root = dock_root
	_assign_nodes()
	_bind_events()


func apply_model(model: Dictionary) -> void:
	_model = model
	var items = model.get("pending_change_sets", [])
	_change_set_select.clear()
	for item in items:
		if not (item is Dictionary):
			continue
		var change_id := str(item.get("id", ""))
		var label := "%s | %s" % [change_id, str(item.get("file_path", ""))]
		_change_set_select.add_item(label)
		_change_set_select.set_item_metadata(_change_set_select.item_count - 1, change_id)
	if _change_set_select.item_count > 0:
		_change_set_select.select(0)
		_on_change_set_selected(0)
	else:
		_change_set_preview.text = "No pending change sets."


func get_chrome_panels() -> Dictionary:
	return {"review": _change_set_preview_panel}


func _node(path: String):
	return _root.get_node(path)


func _assign_nodes() -> void:
	if _root == null:
		push_error("[OrbitPageReview] _root is null in _assign_nodes")
		return
	_change_set_select = _node("ChangeSetSelect")
	_change_set_preview_panel = _node("ChangeSetPreviewPanel")
	_change_set_preview = _node("ChangeSetPreviewPanel/ChangeSetPreview")
	_approve_button = _node("ReviewButtons/ApproveButton")
	_reject_button = _node("ReviewButtons/RejectButton")


func _bind_events() -> void:
	if _change_set_select == null:
		push_error("[OrbitPageReview] _change_set_select is null in _bind_events")
		return
	_change_set_select.item_selected.connect(_on_change_set_selected)
	if _approve_button:
		_approve_button.pressed.connect(func() -> void: _on_approve_changed(true))
	if _reject_button:
		_reject_button.pressed.connect(func() -> void: _on_approve_changed(false))


func _on_change_set_selected(index: int) -> void:
	if index < 0 or index >= _change_set_select.item_count:
		return
	var selected_id := str(_change_set_select.get_item_metadata(index))
	for item in _model.get("pending_change_sets", []):
		if item is Dictionary and str(item.get("id", "")) == selected_id:
			_change_set_preview.text = "File: %s\nStatus: %s\n\n%s" % [
				str(item.get("file_path", "")),
				str(item.get("status", "")),
				str(item.get("preview", "")),
			]
			return


func _on_approve_changed(approved: bool) -> void:
	if _change_set_select.item_count == 0:
		return
	emit_signal("approve_change_set_requested", str(_change_set_select.get_item_metadata(_change_set_select.selected)), approved)
