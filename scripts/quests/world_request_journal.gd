extends CanvasLayer
class_name WorldRequestJournal

## Read-only request journal presentation.
##
## The journal receives resolved request snapshots from WorldObjectiveTracker.
## It never changes acceptance, objective completion, rewards, inventory, or save
## data. For v1 it is opened from a request source (the Harbor Request Board),
## which avoids adding another global hotkey before the eventual general-menu
## integration is designed.

@onready var root: Control = $Root
@onready var request_list: ItemList = $Root/Panel/RequestList
@onready var title_label: Label = $Root/Panel/Details/TitleLabel
@onready var status_label: Label = $Root/Panel/Details/StatusLabel
@onready var objective_label: Label = $Root/Panel/Details/ObjectiveLabel
@onready var empty_label: Label = $Root/Panel/EmptyLabel

var _snapshots: Array = []
var _selected_index: int = 0
var _pause_was_active: bool = false
var _is_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	request_list.item_selected.connect(_on_item_selected)


func is_open() -> bool:
	return _is_open


func open_with_requests(snapshots: Array) -> void:
	_snapshots = normalize_snapshots(snapshots)
	_selected_index = 0
	_rebuild_list()
	_refresh_details()

	if not _is_open:
		_pause_was_active = get_tree().paused
	_is_open = true
	root.visible = true
	get_tree().paused = true


func close_journal() -> void:
	if not _is_open:
		return
	_is_open = false
	root.visible = false
	ModalInputOwnership.release_modal(self)
	get_tree().paused = _pause_was_active


func _exit_tree() -> void:
	if _is_open and get_tree() != null:
		ModalInputOwnership.release_modal(self)
		get_tree().paused = _pause_was_active


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if _is_cancel(event):
		close_journal()
		get_viewport().set_input_as_handled()
		return

	var step := _vertical_step(event)
	if step != 0 and not _snapshots.is_empty():
		_selected_index = posmod(_selected_index + step, _snapshots.size())
		request_list.select(_selected_index)
		request_list.ensure_current_is_visible()
		_refresh_details()
		get_viewport().set_input_as_handled()
		return

	# K/Enter is intentionally inert in the read-only v1 journal. Consume it so
	# the paused world never receives an interaction while the log is open.
	if _is_confirm(event):
		get_viewport().set_input_as_handled()


func _rebuild_list() -> void:
	request_list.clear()
	empty_label.visible = _snapshots.is_empty()
	request_list.visible = not _snapshots.is_empty()
	$Root/Panel/Details.visible = not _snapshots.is_empty()

	for raw_snapshot in _snapshots:
		if not (raw_snapshot is Dictionary):
			continue
		var snapshot: Dictionary = raw_snapshot
		var state_id := StringName(str(snapshot.get("state_id", "")))
		var title := str(snapshot.get("title", "Request"))
		var state := state_label(state_id)
		request_list.add_item("%s  [%s]" % [title, state])

	if not _snapshots.is_empty():
		request_list.select(0)


func _refresh_details() -> void:
	if _snapshots.is_empty():
		return
	_selected_index = clampi(_selected_index, 0, _snapshots.size() - 1)
	var raw_snapshot = _snapshots[_selected_index]
	if not (raw_snapshot is Dictionary):
		return
	var snapshot: Dictionary = raw_snapshot
	var state_id := StringName(str(snapshot.get("state_id", "")))
	title_label.text = str(snapshot.get("title", "Request"))
	status_label.text = state_label(state_id)
	objective_label.text = str(snapshot.get("objective", ""))


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _snapshots.size():
		return
	_selected_index = index
	_refresh_details()


func _is_confirm(event: InputEvent) -> bool:
	if event.is_action_pressed("enter_fishing"):
		return true
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return (
			key_event.pressed
			and not key_event.echo
			and (
				key_event.keycode == KEY_ENTER
				or key_event.physical_keycode == KEY_ENTER
			)
		)
	return false


func _is_cancel(event: InputEvent) -> bool:
	return event.is_action_pressed("cancel_fishing") or event.is_action_pressed("ui_cancel")


func _vertical_step(event: InputEvent) -> int:
	if event.is_action_pressed("move_forward") or event.is_action_pressed("ui_up"):
		return -1
	if event.is_action_pressed("move_back") or event.is_action_pressed("ui_down"):
		return 1
	return 0


static func normalize_snapshots(snapshots: Array) -> Array:
	var normalized: Array = []
	for raw_snapshot in snapshots:
		if not (raw_snapshot is Dictionary):
			continue
		var snapshot: Dictionary = (raw_snapshot as Dictionary).duplicate(true)
		var state_id := StringName(str(snapshot.get("state_id", "")))
		if not (
			state_id == &"accepted"
			or state_id == &"ready_to_turn_in"
			or state_id == &"completed"
		):
			continue
		normalized.append(snapshot)
	return normalized


static func state_label(state_id: StringName) -> String:
	match state_id:
		&"accepted":
			return "ACTIVE"
		&"ready_to_turn_in":
			return "READY"
		&"completed":
			return "COMPLETE"
	return ""
