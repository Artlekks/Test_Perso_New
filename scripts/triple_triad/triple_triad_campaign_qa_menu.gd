extends CanvasLayer
class_name TripleTriadCampaignQAMenu

signal scenario_requested(scenario_id: StringName)
signal action_requested(action_id: StringName)

const TAB_SCENARIOS := 0
const TAB_ACTIONS := 1

@onready var root: Control = $Root
@onready var tab_label: Label = $Root/Panel/TabLabel
@onready var list_label: Label = $Root/Panel/ListLabel
@onready var description_label: Label = $Root/Panel/DescriptionLabel
@onready var status_label: Label = $Root/Panel/StatusLabel
@onready var snapshot_label: Label = $Root/Panel/SnapshotLabel

var _harness = null
var _tab: int = TAB_SCENARIOS
var _index: int = 0
var _scenario_rows: Array = []
var _snapshot: Dictionary = {}
var _status: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.hide()


func configure(harness) -> void:
	_harness = harness
	_scenario_rows = (
		harness.get_scenarios()
		if harness != null
		else []
	)


func open_menu(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_status = ""
	_index = 0
	_refresh()
	root.show()


func close_menu() -> void:
	root.hide()


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

	if _is_left(event) or _is_right(event):
		_tab = TAB_ACTIONS if _tab == TAB_SCENARIOS else TAB_SCENARIOS
		_index = 0
		_status = ""
		_refresh()
		return false

	if _is_up(event):
		_move(-1)
		return false
	if _is_down(event):
		_move(1)
		return false

	if _is_confirm(event):
		if _tab == TAB_SCENARIOS:
			if not _scenario_rows.is_empty():
				scenario_requested.emit(
					StringName(
						str(
							_scenario_rows[_index].get(
								"id",
								""
							)
						)
					)
				)
		else:
			action_requested.emit(_action_id(_index))
		return false

	return false


func _move(step: int) -> void:
	var count: int = (
		_scenario_rows.size()
		if _tab == TAB_SCENARIOS
		else _action_count()
	)
	if count <= 0:
		return
	_index = posmod(_index + step, count)
	_status = ""
	_refresh()


func _refresh() -> void:
	tab_label.text = (
		"< SCENARIOS >     ACTIONS"
		if _tab == TAB_SCENARIOS
		else "SCENARIOS     < ACTIONS >"
	)

	var lines := PackedStringArray()
	if _tab == TAB_SCENARIOS:
		for row_index in range(_scenario_rows.size()):
			var marker: String = ">" if row_index == _index else " "
			lines.append(
				"%s %s"
				% [
					marker,
					str(_scenario_rows[row_index].get("name", "")),
				]
			)
		if not _scenario_rows.is_empty():
			description_label.text = str(
				_scenario_rows[_index].get("summary", "")
			)
	else:
		for row_index in range(_action_count()):
			var marker: String = ">" if row_index == _index else " "
			lines.append(
				"%s %s" % [marker, _action_name(row_index)]
			)
		description_label.text = _action_description(_index)

	list_label.text = "\n".join(lines)

	var completion: Dictionary = {}
	var raw_completion = _snapshot.get("completion", {})
	if raw_completion is Dictionary:
		completion = raw_completion
	var progression: Dictionary = {}
	var raw_player = _snapshot.get("player", {})
	if raw_player is Dictionary:
		progression = raw_player
	var acquisition: Dictionary = {}
	var raw_acquisition = _snapshot.get("acquisition", {})
	if raw_acquisition is Dictionary:
		acquisition = raw_acquisition

	var qa_snapshot: Dictionary = {}
	var raw_qa_snapshot = _snapshot.get("qa_snapshot", {})
	if raw_qa_snapshot is Dictionary:
		qa_snapshot = raw_qa_snapshot
	snapshot_label.text = (
		"CURRENT   Rank %d   Cards %d / 179   Unlocked %s   QA-A %s"
		% [
			int(progression.get("duel_rank", progression.get("rank", 1))),
			int(completion.get("owned_unique", 0)),
			"YES" if bool(acquisition.get("card_game_unlocked", false)) else "NO",
			"SAVED" if bool(qa_snapshot.get("exists", false)) else "EMPTY",
		]
	)

	status_label.text = (
		_status
		if not _status.is_empty()
		else "W/S select   A/D tab   K apply   Shift+F10 / I close"
	)


func _action_count() -> int:
	return 10


func _action_id(index: int) -> StringName:
	match index:
		0:
			return &"arm_next_coast_salvage"
		1:
			return &"resume_active_tournament"
		2:
			return &"save_qa_snapshot"
		3:
			return &"restore_qa_snapshot"
		4:
			return &"delete_qa_snapshot"
		5:
			return &"reset_decks"
		6:
			return &"reconcile"
		7:
			return &"capture_qa_report"
		8:
			return &"clear_playtest_log"
		9:
			return &"run_backend_qa"
		_:
			return &""


func _action_name(index: int) -> String:
	match index:
		0:
			return "Next Ocean 2 Catch = Coast Salvage Card"
		1:
			return "Open / Resume Active Tournament"
		2:
			return "Save QA Snapshot A"
		3:
			return "Restore QA Snapshot A"
		4:
			return "Delete QA Snapshot A"
		5:
			return "Reset Deck Profiles Only"
		6:
			return "Reconcile Runtime / Save State"
		7:
			return "Capture Diagnostic Report"
		8:
			return "Clear Playtest Log"
		9:
			return "Run Backend QA"
		_:
			return ""


func _action_description(index: int) -> String:
	match index:
		0:
			return "Keeps your collection/progression. Arms the normal 4-catch coast-salvage counter so the next eligible Ocean 2 catch grants a mapped salvage card."
		1:
			return "If a tournament attempt is active, opens its expected next opponent immediately using the locked tournament deck."
		2:
			return "Copies every Triple Triad save/journal plus backups into QA Snapshot A. Fishing state is never included."
		3:
			return "Restores QA Snapshot A exactly, replacing the current Triple Triad campaign state, then reloads the scene."
		4:
			return "Deletes only the stored QA Snapshot A. Your live campaign is unchanged."
		5:
			return "Deletes only Triple Triad deck profiles. Collection and progression stay intact; Deck #1 rebuilds from owned cards after reload."
		6:
			return "Runs the production recovery/reconciliation pass against the current card-game save."
		7:
			return "Writes user://triple_triad_qa_report.json with backend, progression, collection, tournament, recovery and pending-event diagnostics."
		8:
			return "Clears the debug JSON-lines playtest log. New gameplay events will start a fresh log automatically."
		9:
			return "Runs the backend regression suite without modifying campaign state."
		_:
			return ""


func _pressed(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
	)


func _is_confirm(event: InputEvent) -> bool:
	return _is_key(event, KEY_K) or _is_key(event, KEY_ENTER)


func _is_left(event: InputEvent) -> bool:
	return _is_key(event, KEY_A) or _is_key(event, KEY_LEFT)


func _is_right(event: InputEvent) -> bool:
	return _is_key(event, KEY_D) or _is_key(event, KEY_RIGHT)


func _is_up(event: InputEvent) -> bool:
	return _is_key(event, KEY_W) or _is_key(event, KEY_UP)


func _is_down(event: InputEvent) -> bool:
	return _is_key(event, KEY_S) or _is_key(event, KEY_DOWN)


func _is_shift_f10(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		key_event.shift_pressed
		and (
			key_event.keycode == KEY_F10
			or key_event.physical_keycode == KEY_F10
		)
	)


func _is_key(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		key_event.keycode == key
		or key_event.physical_keycode == key
	)
