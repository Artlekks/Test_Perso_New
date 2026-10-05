extends Node
class_name DialogueService

## Pure dialogue state/flow owner.
##
## This service has no knowledge of fishing rewards, card progression, shops,
## crafting, mastery, cameras, or HUD layout. Gameplay systems decide *what*
## happens; DialogueService only owns the active conversation, line order and
## presentation-level choice selection.

signal dialogue_started(snapshot: Dictionary)
signal line_changed(snapshot: Dictionary)
signal dialogue_finished(dialogue_id: StringName, reason: StringName)
signal choice_selected(
	dialogue_id: StringName,
	choice_id: StringName,
	choice_metadata: Dictionary
)

var _catalog: DialogueCatalog = null
var _active: bool = false
var _dialogue_id: StringName = &""
var _lines: Array[Dictionary] = []
var _line_index: int = -1
var _choice_index: int = -1
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
	if not _get_current_choices().is_empty():
		return _failure("choice_required")
	if _line_index + 1 < _lines.size():
		_line_index += 1
		_sync_choice_index()
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


func move_choice(delta: int) -> Dictionary:
	if not _active:
		return _failure("no_active_dialogue")
	var choices := _get_current_choices()
	if choices.is_empty():
		return _failure("no_choices")
	var enabled_indices := _get_enabled_choice_indices(choices)
	if enabled_indices.is_empty():
		_choice_index = -1
		return _failure("no_enabled_choices")
	if delta == 0:
		return {
			"success": true,
			"snapshot": get_snapshot(),
		}
	var current_position := enabled_indices.find(_choice_index)
	if current_position < 0:
		current_position = 0
	else:
		current_position = posmod(current_position + (1 if delta > 0 else -1), enabled_indices.size())
	_choice_index = int(enabled_indices[current_position])
	var snapshot := get_snapshot()
	line_changed.emit(snapshot)
	return {
		"success": true,
		"snapshot": snapshot,
	}


func select_choice() -> Dictionary:
	if not _active:
		return _failure("no_active_dialogue")
	var choices := _get_current_choices()
	if choices.is_empty():
		return _failure("no_choices")
	if _choice_index < 0 or _choice_index >= choices.size():
		return _failure("no_enabled_choices")
	var choice: Dictionary = choices[_choice_index]
	if not bool(choice.get("enabled", true)):
		return _failure("choice_disabled")
	var selected_id := StringName(str(choice.get("choice_id", "")))
	if selected_id == &"":
		return _failure("invalid_choice")
	var selected_metadata: Dictionary = {}
	var raw_metadata = choice.get("metadata", {})
	if raw_metadata is Dictionary:
		selected_metadata = raw_metadata.duplicate(true)
	var completed_id := _dialogue_id
	_finish(&"choice_selected")
	# dialogue_finished is emitted by _finish first, so DialogueController releases
	# pause ownership before the gameplay caller reacts to the selected action.
	choice_selected.emit(completed_id, selected_id, selected_metadata)
	return {
		"success": true,
		"finished": true,
		"dialogue_id": completed_id,
		"reason": &"choice_selected",
		"choice_id": selected_id,
		"choice_metadata": selected_metadata,
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
			"choices": [],
			"has_choices": false,
			"selected_choice_index": -1,
			"metadata": {},
		}
	var line: Dictionary = _lines[_line_index]
	var portrait = line.get("portrait", null)
	if portrait == null:
		portrait = _metadata.get("portrait", null)
	var choices: Array = line.get("choices", [])
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
		"choices": choices.duplicate(true),
		"has_choices": not choices.is_empty(),
		"selected_choice_index": _choice_index,
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
		if not _runtime_choices_valid(line.get("choices", [])):
			return _failure("dialogue_has_invalid_choices")

	_active = true
	_dialogue_id = dialogue_id
	_lines = []
	for line in lines:
		_lines.append(line.duplicate(true))
	_line_index = 0
	_allow_cancel = allow_cancel
	_metadata = metadata.duplicate(true)
	_sync_choice_index()

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
	_choice_index = -1
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
			"choices": [],
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
	var runtime_choices: Array[Dictionary] = []
	if source.has("choices"):
		var raw_choices = source.get("choices", [])
		if not (raw_choices is Array):
			return {}
		var seen_ids: Dictionary = {}
		for raw_choice in raw_choices:
			var choice := _normalize_inline_choice(raw_choice, context)
			if choice.is_empty():
				return {}
			var key := str(choice.get("choice_id", ""))
			if seen_ids.has(key):
				return {}
			seen_ids[key] = true
			runtime_choices.append(choice)
	return {
		"speaker_id": StringName(str(source.get("speaker_id", ""))),
		"speaker_name": str(source.get("speaker_name", "")),
		"portrait": portrait,
		"text": resolved_text,
		"choices": runtime_choices,
	}


func _normalize_inline_choice(raw_choice, context: Dictionary) -> Dictionary:
	if not (raw_choice is Dictionary):
		return {}
	var source: Dictionary = raw_choice
	var choice_id := StringName(str(source.get("choice_id", "")).strip_edges())
	if choice_id == &"":
		return {}
	var resolved_text := DialogueLineDefinition.resolve_tokens(
		str(source.get("text", "")),
		context
	)
	if resolved_text.strip_edges().is_empty():
		return {}
	var metadata: Dictionary = {}
	var raw_metadata = source.get("metadata", {})
	if not (raw_metadata is Dictionary):
		return {}
	metadata = raw_metadata.duplicate(true)
	return {
		"choice_id": choice_id,
		"text": resolved_text,
		"enabled": bool(source.get("enabled", true)),
		"metadata": metadata,
	}


func _get_current_choices() -> Array:
	if not _active or _line_index < 0 or _line_index >= _lines.size():
		return []
	var raw_choices = _lines[_line_index].get("choices", [])
	if raw_choices is Array:
		return raw_choices
	return []


func _sync_choice_index() -> void:
	_choice_index = -1
	var choices := _get_current_choices()
	for index in range(choices.size()):
		var choice = choices[index]
		if choice is Dictionary and bool(choice.get("enabled", true)):
			_choice_index = index
			return


func _get_enabled_choice_indices(choices: Array) -> Array[int]:
	var result: Array[int] = []
	for index in range(choices.size()):
		var choice = choices[index]
		if choice is Dictionary and bool(choice.get("enabled", true)):
			result.append(index)
	return result


func _runtime_choices_valid(raw_choices) -> bool:
	if not (raw_choices is Array):
		return false
	var seen_ids: Dictionary = {}
	for raw_choice in raw_choices:
		if not (raw_choice is Dictionary):
			return false
		var choice: Dictionary = raw_choice
		var key := str(choice.get("choice_id", "")).strip_edges()
		if key.is_empty() or seen_ids.has(key):
			return false
		seen_ids[key] = true
		if str(choice.get("text", "")).strip_edges().is_empty():
			return false
		if not (choice.get("metadata", {}) is Dictionary):
			return false
	return true


func _failure(reason: String) -> Dictionary:
	return {
		"success": false,
		"reason": reason,
		"snapshot": get_snapshot(),
	}
