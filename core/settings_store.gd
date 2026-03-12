@tool
extends RefCounted
class_name OrbitSettingsStore

const OrbitTypes = preload("res://addons/orbit_pilot/core/types.gd")


func load_settings() -> Dictionary:
	var defaults := OrbitTypes.default_settings()
	if not FileAccess.file_exists(OrbitTypes.SETTINGS_PATH):
		return defaults.duplicate(true)

	var file := FileAccess.open(OrbitTypes.SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return defaults.duplicate(true)

	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return defaults.duplicate(true)

	var parser := JSON.new()
	if parser.parse(text) != OK:
		return defaults.duplicate(true)

	var loaded := parser.get_data()
	if not (loaded is Dictionary):
		return defaults.duplicate(true)

	return _deep_merge(defaults, loaded)


func save_settings(settings: Dictionary) -> Dictionary:
	var merged := _deep_merge(OrbitTypes.default_settings(), settings)
	var file := FileAccess.open(OrbitTypes.SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return {"success": false, "error": "write_failed"}

	file.store_string(JSON.stringify(merged, "\t"))
	file.close()
	return {"success": true}


func _deep_merge(base: Dictionary, override: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in override.keys():
		var base_value: Variant = result.get(key)
		var override_value: Variant = override.get(key)
		if base_value is Dictionary and override_value is Dictionary:
			result[key] = _deep_merge(base_value, override_value)
		else:
			result[key] = override_value
	return result
