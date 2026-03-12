@tool
extends RefCounted
class_name OrbitTypes

const RUN_POLICY_ANALYZE := "analyze"
const RUN_POLICY_PROPOSE := "propose"
const RUN_POLICY_APPLY := "apply_with_approval"

const SETTINGS_PATH := "user://orbit_pilot_settings.json"


static func default_settings() -> Dictionary:
	return {
		"active_provider": "openai_compatible",
		"providers": {
			"openai_compatible": {
				"id": "openai_compatible",
				"base_url": "https://api.openai.com/v1",
				"model": "gpt-4.1-mini",
				"api_key": "",
				"api_key_env": "OPENAI_API_KEY",
			},
			"deepseek": {
				"id": "deepseek",
				"base_url": "https://api.deepseek.com",
				"model": "deepseek-chat",
				"api_key": "",
				"api_key_env": "DEEPSEEK_API_KEY",
			},
			"anthropic": {
				"id": "anthropic",
				"base_url": "https://api.anthropic.com",
				"model": "claude-3-5-sonnet-latest",
				"api_key": "",
				"api_key_env": "ANTHROPIC_API_KEY",
				"anthropic_version": "2023-06-01",
			},
		},
		"remote_servers": {
			"main": {
				"id": "main",
				"name": "Main MCP Server",
				"endpoint": "http://127.0.0.1:3000",
				"enabled": false,
				"timeout_sec": 15.0,
			},
		},
		"default_policy": RUN_POLICY_PROPOSE,
		"route_strategy": {
			"prefer_local_reads": true,
			"prefer_remote_writes": true,
		},
		"sessions": [],
		"last_session_id": "",
		"log_limit": 300,
	}


static func default_session() -> Dictionary:
	return {
		"id": "%s_%s" % [str(Time.get_unix_time_from_system()), str(randi())],
		"title": "New Session",
		"messages": [],
		"run_records": [],
	}
