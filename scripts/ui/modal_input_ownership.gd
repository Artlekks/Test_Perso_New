extends Node
class_name ModalInputOwnership
## Shared transition boundary. Modal controllers retain their own navigation;
## world consumers require release and a new press after ownership is returned.
const ACTIONS := [&"enter_fishing", &"cancel_fishing", &"world_card_challenge", &"lure_menu", &"ui_accept", &"ui_cancel"]
var _held: Array[StringName] = []
var _closed_frame := -1
var _await_release := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

static func release_modal(owner: Node) -> void:
	var gate := owner.get_node_or_null("/root/ModalInputGate")
	if gate != null: gate.arm()
	# Consume before unpausing: the closing event must not resume traversal in
	# exploration in this same dispatch, including SubViewport forwarding.
	owner.get_viewport().set_input_as_handled()

func arm() -> void:
	_closed_frame = Engine.get_process_frames()
	# Input.parse_input_event()/touch forwarding can still have a press queued
	# before Input's pressed-action snapshot is updated. A snapshot alone cannot
	# prove freshness: wait for an actual release at the input boundary.
	_await_release = true
	for action in ACTIONS:
		if Input.is_action_pressed(action) and not _held.has(action): _held.append(action)

func _input(event: InputEvent) -> void:
	observe_release(event)

func observe_release(event: InputEvent) -> void:
	if event.is_pressed(): return
	var relevant := event is InputEventMouseButton or event is InputEventScreenTouch
	if event is InputEventKey and (event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE):
		relevant = true # Manual-pause owner closes on Space, without an InputMap action.
	for action in ACTIONS:
		if event.is_action_released(action): relevant = true
	for action in _held.duplicate():
		if event.is_action_released(action): _held.erase(action)
	if relevant and not ACTIONS.any(func(action): return Input.is_action_pressed(action)):
		_await_release = false
		_held.clear()

static func gameplay_accepts(owner: Node, event: InputEvent) -> bool:
	var gate := owner.get_node_or_null("/root/ModalInputGate")
	if gate == null: return not owner.get_tree().paused
	gate.observe_release(event)
	return not owner.get_tree().paused and not gate._await_release \
		and gate._closed_frame != Engine.get_process_frames()
