@tool
extends RefCounted
class_name SessionManager

const OrbitTypes = preload("res://addons/orbit_pilot/core/types.gd")

var _settings: Dictionary
var _save_settings: Callable
var _refresh_dock: Callable


func setup(settings: Dictionary, save_settings_callback: Callable, refresh_dock_callback: Callable) -> void:
	_settings = settings
	_save_settings = save_settings_callback
	_refresh_dock = refresh_dock_callback


func ensure_session() -> Dictionary:
	var sessions: Array = _settings.get("sessions", [])
	if sessions.is_empty():
		var created := OrbitTypes.default_session()
		sessions.append(created)
		_settings["sessions"] = sessions
		_settings["last_session_id"] = created["id"]
		return created
	var last_id := str(_settings.get("last_session_id", ""))
	for session in sessions:
		if session is Dictionary and str(session.get("id", "")) == last_id and not bool(session.get("archived", false)):
			return session
	for session in sessions:
		if session is Dictionary and not bool(session.get("archived", false)):
			return session
	var created := OrbitTypes.default_session()
	sessions.append(created)
	_settings["sessions"] = sessions
	_settings["last_session_id"] = created["id"]
	return created


func sync_session(updated: Dictionary) -> void:
	var sessions: Array = _settings.get("sessions", [])
	var found := false
	for i in range(sessions.size()):
		var item = sessions[i]
		if item is Dictionary and str(item.get("id", "")) == str(updated.get("id", "")):
			sessions[i] = updated
			found = true
			break
	if not found:
		sessions.append(updated)
	_settings["sessions"] = sessions
	_settings["last_session_id"] = str(updated.get("id", ""))


func on_session_selected_requested(session_id: String) -> void:
	if session_id.is_empty():
		return
	_settings["last_session_id"] = session_id
	_save_settings.call()
	_refresh_dock.call("Session switched")


func on_session_create_requested() -> void:
	var created := OrbitTypes.default_session()
	var sessions: Array = _settings.get("sessions", [])
	sessions.append(created)
	_settings["sessions"] = sessions
	_settings["last_session_id"] = str(created.get("id", ""))
	_save_settings.call()
	_refresh_dock.call("New session created")


func on_session_archive_requested(session_id: String) -> void:
	if session_id.is_empty():
		return
	var sessions: Array = _settings.get("sessions", [])
	var archived_title := ""
	for i in range(sessions.size()):
		var item: Variant = sessions[i]
		if item is Dictionary and str(item.get("id", "")) == session_id:
			var updated: Dictionary = (item as Dictionary).duplicate(true)
			updated["archived"] = true
			updated["archived_at"] = Time.get_datetime_string_from_system()
			sessions[i] = updated
			archived_title = str(updated.get("title", "Session"))
			break
	_settings["sessions"] = sessions
	if str(_settings.get("last_session_id", "")) == session_id:
		var created := OrbitTypes.default_session()
		sessions.append(created)
		_settings["sessions"] = sessions
		_settings["last_session_id"] = str(created.get("id", ""))
	_save_settings.call()
	_refresh_dock.call("Archived: %s" % archived_title)


func on_session_delete_requested(session_id: String) -> void:
	if session_id.is_empty():
		return
	var sessions: Array = _settings.get("sessions", [])
	var kept: Array = []
	var deleted := false
	for item in sessions:
		if item is Dictionary and str(item.get("id", "")) == session_id and bool(item.get("archived", false)):
			deleted = true
			continue
		kept.append(item)
	if not deleted:
		_refresh_dock.call("Only archived sessions can be deleted")
		return
	_settings["sessions"] = kept
	if str(_settings.get("last_session_id", "")) == session_id:
		_settings["last_session_id"] = ""
	ensure_session()
	_save_settings.call()
	_refresh_dock.call("Session deleted")


func on_session_rename_requested(session_id: String, title: String) -> void:
	var clean_title := title.strip_edges()
	if session_id.is_empty() or clean_title.is_empty():
		return
	var sessions: Array = _settings.get("sessions", [])
	for i in range(sessions.size()):
		var item: Variant = sessions[i]
		if item is Dictionary and str(item.get("id", "")) == session_id:
			var updated: Dictionary = (item as Dictionary).duplicate(true)
			updated["title"] = clean_title
			sessions[i] = updated
			break
	_settings["sessions"] = sessions
	_save_settings.call()
	_refresh_dock.call("Session renamed")
