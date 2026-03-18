@tool
class_name OrbitLocalizer
extends RefCounted

const LANG_EN = "EN"
const LANG_CN = "CN"

static var _current_lang = LANG_CN

static var _translations = {
	LANG_EN: {
		"TAB_CHAT": "CHAT",
		"TAB_TOOLS": "TOOLS",
		"TAB_REVIEW": "REVIEW",
		"TIP_NEW_SESSION": "New Session",
		"TIP_SESSIONS": "History / Sessions",
		"TIP_SETTINGS": "Settings",
		"STATUS_READY": "OrbitPilot ready",
		"STATUS_RUNNING": "Running",
		"PROMPT_PLACEHOLDER": "Ask Orbit to inspect, propose, or prepare a change...",
		"CONTEXT_IDE": "IDE Context",
		"ACTION_SEND": "Send",
		"ACTION_CANCEL": "Cancel",
		"STATUS_READY_PILL": "Ready",
		"VALIDATION_PENDING": "Validation pending",
		"VALIDATION_COUNT": "Validation %d/%d",
		"USER_LABEL": "You",
		"ASSISTANT_LABEL": "Orbit",
		"SET_LANGUAGE": "Language",
		"SET_HIDE_KEY": "Hide Key",
		"SET_SHOW_KEY": "Show Key",
		"SET_COPY_LOGS": "Copy Logs",
		"SET_COPIED": "Copied",
		"SET_PROVIDER": "Provider",
		"SET_PROVIDER_CONFIG": "Configure Provider: %s",
		"SET_KEY_SOURCE": "Key source",
		"SET_MCP_STATUS": "MCP %s: %s",
	},
	LANG_CN: {
		"TAB_CHAT": "聊天",
		"TAB_TOOLS": "工具",
		"TAB_REVIEW": "审查",
		"TIP_NEW_SESSION": "新建会话",
		"TIP_SESSIONS": "历史 / 会话",
		"TIP_SETTINGS": "设置",
		"STATUS_READY": "OrbitPilot 已就绪",
		"STATUS_RUNNING": "运行中",
		"PROMPT_PLACEHOLDER": "让 Orbit 检查、建议或准备变更...",
		"CONTEXT_IDE": "IDE 上下文",
		"ACTION_SEND": "发送",
		"ACTION_CANCEL": "取消",
		"STATUS_READY_PILL": "就绪",
		"VALIDATION_PENDING": "等待校验",
		"VALIDATION_COUNT": "校验 %d/%d",
		"USER_LABEL": "你",
		"ASSISTANT_LABEL": "Orbit",
		"SET_LANGUAGE": "语言",
		"SET_HIDE_KEY": "隐藏 Key",
		"SET_SHOW_KEY": "显示 Key",
		"SET_COPY_LOGS": "复制日志",
		"SET_COPIED": "已复制",
		"SET_PROVIDER": "供应商",
		"SET_PROVIDER_CONFIG": "配置供应商: %s",
		"SET_KEY_SOURCE": "Key 来源",
		"SET_MCP_STATUS": "MCP %s: %s",
	}
}

static func set_language(lang: String) -> void:
	if lang == LANG_EN or lang == LANG_CN:
		_current_lang = lang

static func get_language() -> String:
	return _current_lang

static func translate(key: String) -> String:
	var lang_map = _translations.get(_current_lang, _translations[LANG_EN])
	if not lang_map.has(key):
		# Fallback to English if key missing in current language
		lang_map = _translations[LANG_EN]
	
	var result = lang_map.get(key, key)
	return result

static func t(key: String) -> String:
	return translate(key)
