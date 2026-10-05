extends Node
class_name DialogueService

## Pure dialogue state/flow owner.
##
## This service has no knowledge of fishing rewards, card progression, shops,
## crafting, mastery, cameras, or HUD layout. Gameplay systems decide *what*
## happens; DialogueService only owns the active conversation and line order.

signal dialogue_started(snapshot: Dictionary)
signal line_changed(snapshot: Dictionary)
signal dialogue_finished(dialogue_id: StringName, reason: StringName)

var _catalog: DialogueCatalog = null
var _active: bool = false
var _dialogue_id: StringName = &""
var _lines: Array[Dictionary] = []
var _line_index: int = -1
var _allow_cancel: bool = true
var _metadata: Dictionary = {}


func configure(catalog: DialogueCatalog) -> void:
	_catalog = catalog


func is_configured() -> bool:
	return _catalog != null


func is_active() -> bool:
	return _active


func start_dialogue(
	dialogue_id: StringName,
	context: Dictionary = {},
	metadata: Dictionary = {}
) -> Dictionary:
	if _active:
		return _failure("dialogue_busy")
	if _catalog == null:
		return _failure("catalog_unavailable")
	var definition := _catalog.get_dialogue(dialogue_id)
	if definition == null:
		return _failure("dialogue_not_found")
	var runtime_lines := definition.to_runtime_lines(context)
	return _begin_dialogue(
		dialogue_id,
		runtime_lines,
		definition.allow_cancel,
		metadata
	)


func start_inline_dialogue(
	dialogue_id: StringName,
	lines: Array,
	allow_cancel: bool = true,
	context: Dictionary = {},
	metadata: Dictionary = {}
) -> Dictionary:
	if _active:
		return _failure("dialogue_busy")
	if dialogue_id == &"":
		return _failure("empty_dialogue_id")
	var runtime_lines: Array[Dictionary] = []
	for raw_line in lines:
		var normalized := _normalize_inline_line(raw_line, context)
		if normalized.is_empty():
			return _failure("invalid_inline_line")
		runtime_lines.append(normalized)
	return _begin_dialogue(
		dialogue_id,
		runtime_lines,
		allow_cancel,
		metadata
	)


func advance() -> Dictionary:
	if not _active:
		return _failure("no_active_dialogue")
	if _line_index + 1 < _lines.size():
		_line_index += 1
		var snapshot := get_snapshot()
		line_changed.emit(snapshot)
		return {
			"success": true,
			"finished": false,
			"snapshot": snapshot,
		}
	var completed_id := _dialogue_id
	_finish(&"completed")
	return {
		"success": true,
		"finished": true,
		"dialogue_id": completed_id,
		"reason": &"completed",
	}


func cancel(reason: StringName = &"cancelled") -> Dictionary:
	if not _active:
		return _failure("no_active_dialogue")
	if not _allow_cancel:
		return _failure("cancel_disabled")
	var cancelled_id := _dialogue_id
	_finish(reason)
	return {
		"success": true,
		"finished": true,
		"dialogue_id": cancelled_id,
		"reason": reason,
	}


func force_close(reason: StringName = &"forced") -> Dictionary:
	if not _active:
		return _failure("no_active_dialogue")
	var closed_id := _dialogue_id
	_finish(reason)
	return {
		"success": true,
		"finished": true,
		"dialogue_id": closed_id,
		"reason": reason,
	}


func get_snapshot() -> Dictionary:
	if not _active or _line_index < 0 or _line_index >= _lines.size():
		return {
			"active": false,
			"dialogue_id": &"",
			"line_index": -1,
			"line_count": 0,
			"is_last_line": false,
			"allow_cancel": false,
			"speaker_id": &"",
			"speaker_name": "",
			"portrait": null,
			"text": "",
			"metadata": {},
		}
	var line: Dictionary = _lines[_line_index]
	var portrait = line.get("portrait", null)
	if portrait == null:
		portrait = _metadata.get("portrait", null)
	return {
		"active": true,
		"dialogue_id": _dialogue_id,
		"line_index": _line_index,
		"line_count": _lines.size(),
		"is_last_line": _line_index == _lines.size() - 1,
		"allow_cancel": _allow_cancel,
		"speaker_id": line.get("speaker_id", &""),
		"speaker_name": str(line.get("speaker_name", "")),
		"portrait": portrait,
		"text": str(line.get("text", "")),
		"metadata": _metadata.duplicate(true),
	}


func _begin_dialogue(
	dialogue_id: StringName,
	lines: Array[Dictionary],
	allow_cancel: bool,
	metadata: Dictionary
) -> Dictionary:
	if lines.is_empty():
		return _failure("dialogue_has_no_lines")
	for line in lines:
		if str(line.get("text", "")).strip_edges().is_empty():
			return _failure("dialogue_has_empty_line")

	_active = true
	_dialogue_id = dialogue_id
	_lines = []
	for line in lines:
		_lines.append(line.duplicate(true))
	_line_index = 0
	_allow_cancel = allow_cancel
	_metadata = metadata.duplicate(true)

	var snapshot := get_snapshot()
	dialogue_started.emit(snapshot)
	return {
		"success": true,
		"snapshot": snapshot,
	}


func _finish(reason: StringName) -> void:
	var finished_id := _dialogue_id
	_active = false
	_dialogue_id = &""
	_lines.clear()
	_line_index = -1
	_allow_cancel = true
	_metadata.clear()
	dialogue_finished.emit(finished_id, reason)


func _normalize_inline_line(raw_line, context: Dictionary) -> Dictionary:
	if raw_line is String:
		var resolved_string := DialogueLineDefinition.resolve_tokens(
			str(raw_line),
			context
		)
		if resolved_string.strip_edges().is_empty():
			return {}
		return {
			"speaker_id": &"",
			"speaker_name": "",
			"portrait": null,
			"text": resolved_string,
		}
	if not (raw_line is Dictionary):
		return {}
	var source: Dictionary = raw_line
	var resolved_text := DialogueLineDefinition.resolve_tokens(
		str(source.get("text", "")),
		context
	)
	if resolved_text.strip_edges().is_empty():
		return {}
	var portrait = source.get("portrait", null)
	if portrait != null and not (portrait is Texture2D):
		return {}
	return {
		"speaker_id": StringName(str(source.get("speaker_id", ""))),
		"speaker_name": str(source.get("speaker_name", "")),
		"portrait": portrait,
		"text": resolved_text,
	}


func _failure(reason: String) -> Dictionary:
	return {
		"success": false,
		"reason": reason,
		"snapshot": get_snapshot(),
	}
