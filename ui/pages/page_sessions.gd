@tool
class_name OrbitPageSessions
extends RefCounted

signal session_create_requested
signal session_open_requested(session_id: String)
signal session_archive_requested(session_id: String)
signal session_delete_requested(session_id: String)
signal session_rename_requested(session_id: String, title: String)

var _root: Control
var _new_session_button: Button
var _open_session_button: Button
var _archive_session_button: Button
var _delete_archived_button: Button
var _rename_session_edit: LineEdit
var _rename_session_button: Button
var _active_sessions_list: ItemList
var _archived_sessions_list: ItemList
var _session_manage_panel: Control
var _active_sessions_panel: Control
var _archived_sessions_panel: Control
var _active_session_ids := []
var _archived_session_ids := []


func setup(dock_root: Control) -> void:
	_root = dock_root
	_assign_nodes()
	_bind_events()


func apply_model(model: Dictionary) -> void:
	var sessions = model.get("sessions", [])
	var active_session_id := str(model.get("active_session_id", ""))
	_active_session_ids.clear()
	_archived_session_ids.clear()
	_active_sessions_list.clear()
	_archived_sessions_list.clear()
	_rename_session_edit.text = ""
	for session in sessions:
		if not (session is Dictionary):
			continue
		var session_id := str(session.get("id", ""))
		var title := str(session.get("title", "New Session"))
		if bool(session.get("archived", false)):
			_archived_sessions_list.add_item(title)
			_archived_session_ids.append(session_id)
		else:
			_active_sessions_list.add_item(title)
			_active_session_ids.append(session_id)
			if session_id == active_session_id:
				_active_sessions_list.select(_active_sessions_list.item_count - 1)
	if _active_sessions_list.get_selected_items().is_empty() and _active_sessions_list.item_count > 0:
		_active_sessions_list.select(0)
	if _active_sessions_list.get_selected_items().is_empty() and _archived_sessions_list.item_count > 0:
		_archived_sessions_list.select(0)
	var title := _get_selected_session_title()
	if not title.is_empty():
		_rename_session_edit.text = title
	_refresh_actions()


func get_chrome_panels() -> Dictionary:
	return {
		"sessions": _session_manage_panel,
		"sessions_active": _active_sessions_panel,
		"sessions_archived": _archived_sessions_panel,
	}


func _node(path: String):
	return _root.get_node(path)


func _assign_nodes() -> void:
	_new_session_button = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/NewSessionButtonPage")
	_open_session_button = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/OpenSessionButton")
	_archive_session_button = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/ArchiveSessionButtonPage")
	_delete_archived_button = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionActionRow/DeleteArchivedButton")
	_rename_session_edit = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionRenameRow/RenameSessionEdit")
	_rename_session_button = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionRenameRow/RenameSessionButton")
	_active_sessions_list = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ActiveSessionsPanel/ActiveSessionsBox/ActiveSessionsList")
	_archived_sessions_list = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ArchivedSessionsPanel/ArchivedSessionsBox/ArchivedSessionsList")
	_session_manage_panel = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel")
	_active_sessions_panel = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ActiveSessionsPanel")
	_archived_sessions_panel = _node("RootMargin/Root/PageStack/PageSessions/SessionManagePanel/SessionManage/SessionColumns/ArchivedSessionsPanel")


func _bind_events() -> void:
	_new_session_button.pressed.connect(_on_new_session_pressed)
	_open_session_button.pressed.connect(_on_open_selected_session_pressed)
	_archive_session_button.pressed.connect(_on_archive_selected_session_pressed)
	_delete_archived_button.pressed.connect(_on_delete_archived_session_pressed)
	_rename_session_button.pressed.connect(_on_rename_session_pressed)
	_rename_session_edit.text_changed.connect(_on_rename_text_changed)
	_active_sessions_list.item_selected.connect(_on_active_sessions_selected)
	_archived_sessions_list.item_selected.connect(_on_archived_sessions_selected)


func _on_new_session_pressed() -> void:
	emit_signal("session_create_requested")


func _on_rename_text_changed(_new_text: String) -> void:
	_refresh_actions()


func _refresh_actions() -> void:
	var active_id := _get_selected_active_session_id()
	var archived_id := _get_selected_archived_session_id()
	_open_session_button.disabled = active_id.is_empty()
	_archive_session_button.disabled = active_id.is_empty()
	_delete_archived_button.disabled = archived_id.is_empty()
	_rename_session_button.disabled = _get_selected_session_id().is_empty() or _rename_session_edit.text.strip_edges().is_empty()


func _on_open_selected_session_pressed() -> void:
	var session_id := _get_selected_active_session_id()
	if session_id.is_empty():
		return
	emit_signal("session_open_requested", session_id)


func _on_archive_selected_session_pressed() -> void:
	var session_id := _get_selected_active_session_id()
	if not session_id.is_empty():
		emit_signal("session_archive_requested", session_id)


func _on_delete_archived_session_pressed() -> void:
	var session_id := _get_selected_archived_session_id()
	if not session_id.is_empty():
		emit_signal("session_delete_requested", session_id)


func _on_rename_session_pressed() -> void:
	var session_id := _get_selected_session_id()
	var title: String = _rename_session_edit.text.strip_edges()
	if session_id.is_empty() or title.is_empty():
		return
	emit_signal("session_rename_requested", session_id, title)


func _on_active_sessions_selected(index: int) -> void:
	if index < 0 or index >= _active_session_ids.size():
		return
	_archived_sessions_list.deselect_all()
	_rename_session_edit.text = _active_sessions_list.get_item_text(index)
	_refresh_actions()


func _on_archived_sessions_selected(index: int) -> void:
	if index < 0 or index >= _archived_session_ids.size():
		return
	_active_sessions_list.deselect_all()
	_rename_session_edit.text = _archived_sessions_list.get_item_text(index)
	_refresh_actions()


func _get_selected_active_session_id() -> String:
	var selected: PackedInt32Array = _active_sessions_list.get_selected_items()
	if selected.is_empty():
		return ""
	var index := int(selected[0])
	if index < 0 or index >= _active_session_ids.size():
		return ""
	return str(_active_session_ids[index])


func _get_selected_archived_session_id() -> String:
	var selected: PackedInt32Array = _archived_sessions_list.get_selected_items()
	if selected.is_empty():
		return ""
	var index := int(selected[0])
	if index < 0 or index >= _archived_session_ids.size():
		return ""
	return str(_archived_session_ids[index])


func _get_selected_session_id() -> String:
	var active_id := _get_selected_active_session_id()
	if not active_id.is_empty():
		return active_id
	return _get_selected_archived_session_id()


func _get_selected_session_title() -> String:
	var selected: PackedInt32Array = _active_sessions_list.get_selected_items()
	if not selected.is_empty():
		return _active_sessions_list.get_item_text(int(selected[0]))
	selected = _archived_sessions_list.get_selected_items()
	if not selected.is_empty():
		return _archived_sessions_list.get_item_text(int(selected[0]))
	return ""
