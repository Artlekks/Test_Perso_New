extends CanvasLayer
class_name PlayableCampaignQAGuide

signal preset_requested(preset_id: StringName)
signal refresh_requested

@onready var root: Control = $Root
@onready var stage_list_label: Label = $Root/Panel/StageListLabel
@onready var current_label: Label = $Root/Panel/CurrentLabel
@onready var objective_label: Label = $Root/Panel/ObjectiveLabel
@onready var guide_label: Label = $Root/Panel/GuideLabel
@onready var checklist_label: Label = $Root/Panel/ChecklistLabel
@onready var status_label: Label = $Root/Panel/StatusLabel

var _snapshot: Dictionary = {}
var _presets: Array = []
var _index: int = 0
var _confirming: bool = false
var _status: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.hide()


func open_menu(snapshot: Dictionary, presets: Array) -> void:
	_snapshot = snapshot.duplicate(true)
	_presets = presets.duplicate(true)
	_index = clampi(_index, 0, maxi(_presets.size() - 1, 0))
	_confirming = false
	_status = ""
	_refresh()
	root.show()


func update_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_confirming = false
	_status = "Live state refreshed."
	_refresh()


func close_menu() -> void:
	root.hide()
	_confirming = false


func is_open() -> bool:
	return root.visible


func set_status(text: String) -> void:
	_status = text
	_refresh()


func handle_input(event: InputEvent) -> bool:
	if not is_open() or not _pressed(event):
		return false
	if _is_shift_f10(event) or _is_key(event, KEY_I) or _is_key(event, KEY_ESCAPE):
		return true
	if _is_key(event, KEY_R):
		_confirming = false
		refresh_requested.emit()
		return false
	if _is_up(event):
		_move(-1)
		return false
	if _is_down(event):
		_move(1)
		return false
	if _is_confirm(event):
		_apply_selected()
		return false
	return false


func _move(step: int) -> void:
	if _presets.is_empty():
		return
	_index = posmod(_index + step, _presets.size())
	_confirming = false
	_status = ""
	_refresh()


func _apply_selected() -> void:
	if _presets.is_empty():
		return
	var row: Dictionary = _presets[_index]
	if not bool(row.get("applyable", false)):
		_status = "LIVE is read-only. Press R to refresh the current save."
		_refresh()
		return
	if not _confirming:
		_confirming = true
		_status = "DESTRUCTIVE QA PRESET — press K again to apply and reload."
		_refresh()
		return
	preset_requested.emit(StringName(str(row.get("id", ""))))


func _refresh() -> void:
	var stage_lines := PackedStringArray()
	for row_index in range(_presets.size()):
		var row: Dictionary = _presets[row_index]
		stage_lines.append(
			"%s %s" % [
				">" if row_index == _index else " ",
				str(row.get("name", "")),
			]
		)
	stage_list_label.text = "\n".join(stage_lines)

	var facts: Dictionary = _dict(_snapshot.get("facts", {}))
	var phase: String = str(_snapshot.get("phase_id", "unavailable"))
	var blockers: Array = _array(_snapshot.get("blockers", []))
	current_label.text = (
		"LIVE  PHASE: %s\n"
		+ "Zenny %d   Catches %d   Species %d   Cards %d   Rods %d   Lures %d   Duel Rank %d\n"
		+ "TT %s   Starter Case %s   Prepared Bait %d   Blockers %d"
	) % [
		phase.replace("_", " ").to_upper(),
		int(facts.get("zenny", 0)),
		int(facts.get("total_catches", 0)),
		int(facts.get("species_discovered", 0)),
		int(facts.get("cards_owned_unique", 0)),
		int(facts.get("rods_owned", 0)),
		int(facts.get("lures_owned", 0)),
		int(facts.get("duel_rank", 1)),
		"UNLOCKED" if bool(facts.get("card_game_unlocked", false)) else "LOCKED",
		"FOUND" if bool(facts.get("starter_case_discovered", false)) else "NOT FOUND",
		int(facts.get("prepared_bait_owned", 0)),
		blockers.size(),
	]

	var objective: Dictionary = _dict(_snapshot.get("next_objective", {}))
	objective_label.text = "NEXT OBJECTIVE\n%s\n%s" % [
		str(objective.get("title", "No objective available.")),
		str(objective.get("detail", "")),
	]

	var selected: Dictionary = (
		_presets[_index] if not _presets.is_empty() else {}
	)
	guide_label.text = "%s\n%s\n\n%s" % [
		str(selected.get("name", "")),
		str(selected.get("summary", "")),
		str(selected.get("tutorial", "")),
	]
	var checks := PackedStringArray()
	for raw_check in selected.get("checklist", []):
		checks.append("- %s" % str(raw_check))
	var target: Dictionary = _dict(_snapshot.get("target_milestone", {}))
	var pacing_lines: PackedStringArray = _activity_status_lines(target)
	if not pacing_lines.is_empty():
		checks.append("")
		checks.append("LIVE PACING EVIDENCE")
		for pacing_line in pacing_lines:
			checks.append(pacing_line)
	if not blockers.is_empty():
		checks.append("")
		checks.append("LIVE BLOCKERS")
		for raw_blocker in blockers:
			var blocker: Dictionary = _dict(raw_blocker)
			checks.append("! %s" % str(blocker.get("detail", blocker.get("code", "unknown"))))
	checklist_label.text = "\n".join(checks)

	status_label.text = (
		_status
		if not _status.is_empty()
		else "W/S select   K inspect/apply   R refresh   Shift+F10 / I close"
	)


func _activity_status_lines(target: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for raw_activity in _array(target.get("activity_requirements", [])):
		var activity: Dictionary = _dict(raw_activity)
		if activity.is_empty():
			continue
		lines.append("[%s] %s" % [
			"x" if bool(activity.get("complete", false)) else " ",
			str(activity.get("label", activity.get("activity_id", "Activity"))),
		])
	for raw_group in _array(target.get("activity_choice_groups", [])):
		var group: Dictionary = _dict(raw_group)
		if group.is_empty():
			continue
		lines.append("[%s] %s (%d/%d)" % [
			"x" if bool(group.get("complete", false)) else " ",
			str(group.get("label", group.get("group_id", "Activity choice"))),
			int(group.get("complete_count", 0)),
			int(group.get("minimum_complete", 1)),
		])
		for raw_option in _array(group.get("options", [])):
			var option: Dictionary = _dict(raw_option)
			if option.is_empty():
				continue
			lines.append("  [%s] %s" % [
				"x" if bool(option.get("complete", false)) else " ",
				str(option.get("label", option.get("activity_id", "Option"))),
			])
	return lines


func _dict(value) -> Dictionary:
	return value if value is Dictionary else {}


func _array(value) -> Array:
	return value if value is Array else []


func _pressed(event: InputEvent) -> bool:
	return event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo


func _is_confirm(event: InputEvent) -> bool:
	return _is_key(event, KEY_K) or _is_key(event, KEY_ENTER)


func _is_up(event: InputEvent) -> bool:
	return _is_key(event, KEY_W) or _is_key(event, KEY_UP)


func _is_down(event: InputEvent) -> bool:
	return _is_key(event, KEY_S) or _is_key(event, KEY_DOWN)


func _is_shift_f10(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.shift_pressed and (key_event.keycode == KEY_F10 or key_event.physical_keycode == KEY_F10)


func _is_key(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.keycode == key or key_event.physical_keycode == key
