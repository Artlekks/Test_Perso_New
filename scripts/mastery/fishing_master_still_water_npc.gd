extends Node3D
class_name FishingMasterStillWaterNPC

const DialogueNPCBridgeScript = preload("res://scripts/dialogue/dialogue_npc_bridge.gd")
const MasterDialogueProfilesScript = preload(
	"res://scripts/mastery/fishing_master_dialogue_profiles.gd"
)

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_lesson_policy.gd"
)

const TECHNIQUE_ID: StringName = &"quiet_approach"
const TEACHER_ID: StringName = &"master_still_water"

enum LessonPhase {
	INACTIVE,
	SETTLING,
	WAITING_FOR_CATCH,
	COMPLETE,
}

@export var interaction_prompt: String = "K : Listen"
@export var idle_animation: StringName = &"Stand_Interest"
@export var talk_animation: StringName = &"Bag_Search"

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

var _player_in_range: bool = false
var _player: Node = null
var _mastery_service: FishingMasteryService = null
var _catch_repository: FishingCatchRepository = null
var _info_view: FishingInfoView = null
var _dialogue_bridge: Node = null
var _interaction_dialogue_mode: bool = false
var _interaction_dialogue_state: StringName = &""
var _completion_ack_pending: bool = false
var _process_was_enabled_before_dialogue: bool = false
var _phase: LessonPhase = LessonPhase.INACTIVE
var _stillness_progress: float = 0.0
var _was_disturbed_last_frame: bool = false


func _ready() -> void:
	add_to_group(&"world_interaction_targets")
	process_mode = Node.PROCESS_MODE_ALWAYS
	prompt_label.text = interaction_prompt
	prompt_label.visible = false
	_play_animation(idle_animation)
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	call_deferred("_bind_runtime")


func _process(delta: float) -> void:
	if _phase != LessonPhase.SETTLING:
		return
	if _mastery_service != null and _mastery_service.has_technique(TECHNIQUE_ID):
		_phase = LessonPhase.COMPLETE
		return
	if not is_instance_valid(_player):
		_player = _find_player()
	if _player == null or not _player.has_method("get_fishing_disturbance_strength"):
		return

	var disturbance: float = float(
		_player.call("get_fishing_disturbance_strength")
	)
	var previous_progress := _stillness_progress
	_stillness_progress = LessonPolicy.advance_stillness(
		_stillness_progress,
		disturbance,
		delta
	)

	var was_reset := previous_progress > 0.05 and _stillness_progress <= 0.0
	if was_reset and not _was_disturbed_last_frame:
		_show_message(
			"Still Water: Too much movement. Let the bank go quiet again.",
			2.2
		)
	_was_disturbed_last_frame = disturbance > LessonPolicy.STILLNESS_DISTURBANCE_THRESHOLD

	if LessonPolicy.is_stillness_complete(_stillness_progress):
		_phase = LessonPhase.WAITING_FOR_CATCH
		_play_animation(talk_animation)
		_show_message(
			"Still Water: Good. Now cast and land one fish. Don't rush the water.",
			3.8
		)


func is_world_interaction_available(event: InputEvent) -> bool:
	return _player_in_range and _is_confirm(event)


func interact_from_world(event: InputEvent) -> void:
	if not _player_in_range:
		return
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if not _is_confirm(event):
		return
	_interaction_dialogue_state = _get_dialogue_state()
	_interaction_dialogue_mode = true
	_handle_interaction()
	_interaction_dialogue_mode = false
	_interaction_dialogue_state = &""
	get_viewport().set_input_as_handled()


func _handle_interaction() -> void:
	if not _bind_runtime():
		_interaction_dialogue_state = MasterDialogueProfilesScript.STATE_UNAVAILABLE
		_show_message("Still Water: Come back when the water is ready.", 2.0)
		return

	if _mastery_service.has_technique(TECHNIQUE_ID):
		_phase = LessonPhase.COMPLETE
		_play_animation(talk_animation)
		_show_message(
			"Still Water: The water hears you before the fish sees you. Keep your steps soft.",
			3.6
		)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.SETTLING:
			_show_message(
				"Still Water: Stand still. Let the water forget you're here. %d%%"
				% int(round(LessonPolicy.get_stillness_ratio(_stillness_progress) * 100.0)),
				2.8
			)
		LessonPhase.WAITING_FOR_CATCH:
			_show_message(
				"Still Water: The bank is quiet. Make one cast and land a fish.",
				2.8
			)
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	_phase = LessonPhase.SETTLING
	_stillness_progress = 0.0
	_was_disturbed_last_frame = false
	_play_animation(talk_animation)
	_show_message(
		"Still Water: Don't cast yet. Stand still for a moment. Let the water settle around you.",
		4.2
	)


func _bind_runtime() -> bool:
	if _mastery_service != null and _catch_repository != null:
		return true
	var tree := get_tree()
	if tree == null:
		return false
	var services := tree.root.get_node_or_null("FishingSessionServices")
	if services == null:
		var scene := tree.current_scene
		if scene != null:
			var fishing := scene.find_child("Fishing", true, false)
			if fishing != null:
				var candidate = fishing.get("session_services")
				if candidate is Node:
					services = candidate
	if services == null:
		return false

	if services.has_method("get_fishing_mastery_service"):
		var raw_mastery = services.call("get_fishing_mastery_service")
		if raw_mastery is FishingMasteryService:
			_mastery_service = raw_mastery
	if _mastery_service == null:
		var raw_mastery_property = services.get("mastery_service")
		if raw_mastery_property is FishingMasteryService:
			_mastery_service = raw_mastery_property

	var raw_repository = services.get("catch_repository")
	if raw_repository is FishingCatchRepository:
		_catch_repository = raw_repository
		if not _catch_repository.catch_committed.is_connected(_on_catch_committed):
			_catch_repository.catch_committed.connect(_on_catch_committed)

	_player = _find_player()
	_info_view = _find_info_view()
	if _mastery_service != null and _mastery_service.has_technique(TECHNIQUE_ID):
		_phase = LessonPhase.COMPLETE
	return _mastery_service != null and _catch_repository != null


func _on_catch_committed(result: Dictionary) -> void:
	if _phase != LessonPhase.WAITING_FOR_CATCH:
		return
	if not bool(result.get("committed", false)):
		return
	if _mastery_service == null:
		return

	var learned := _mastery_service.learn_technique(
		TECHNIQUE_ID,
		TEACHER_ID,
		true
	)
	if bool(learned.get("success", false)):
		_phase = LessonPhase.COMPLETE
		_completion_ack_pending = true
		_play_animation(talk_animation)
		_show_message(
			"Technique learned — Quiet Approach. Your movement now disturbs wary fish far less.",
			4.5
		)
	else:
		_show_message(
			"Still Water: You did it. But the lesson could not be saved yet.",
			3.0
		)


func _get_dialogue_state() -> StringName:
	_bind_runtime()
	var technique_known := (
		_mastery_service != null
		and _mastery_service.has_technique(TECHNIQUE_ID)
	)
	return MasterDialogueProfilesScript.classify_state(
		technique_known,
		int(_phase),
		_completion_ack_pending
	)


func _find_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var candidates := tree.get_nodes_in_group("fishing_player")
	if not candidates.is_empty():
		return candidates[0] as Node
	var scene := tree.current_scene
	if scene == null:
		return null
	return scene.find_child("CharacterBody3D", true, false)


func _find_info_view() -> FishingInfoView:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	var candidate := tree.current_scene.find_child("FishingInfoView", true, false)
	return candidate as FishingInfoView


func _show_message(text: String, duration: float) -> void:
	if _interaction_dialogue_mode and _show_npc_dialogue(text):
		return
	if not is_instance_valid(_info_view):
		_info_view = _find_info_view()
	if _info_view != null:
		_info_view.show_message(text, duration, FishingInfoView.Priority.IMPORTANT)


func _show_npc_dialogue(text: String) -> bool:
	var bridge := _ensure_dialogue_bridge()
	if bridge == null or not bridge.has_method("start_lines"):
		return false
	var state := _interaction_dialogue_state
	if state == &"":
		state = _get_dialogue_state()
	var lines: Array = MasterDialogueProfilesScript.build_runtime_lines(
		TEACHER_ID,
		state,
		text,
		animated_sprite
	)
	if lines.is_empty():
		return false
	var started := bool(bridge.call(
		"start_lines",
		StringName("master_talk_still_water_%s" % str(state)),
		&"",
		lines,
		true,
		{
			"source": "fishing_master",
			"teacher_id": TEACHER_ID,
			"master_dialogue_state": state,
		}
	))
	if not started:
		return false
	_suspend_lesson_process_for_dialogue()
	if state == MasterDialogueProfilesScript.STATE_LEARNED:
		_completion_ack_pending = false
	return true


func _ensure_dialogue_bridge() -> Node:
	if not is_instance_valid(_dialogue_bridge):
		_dialogue_bridge = DialogueNPCBridgeScript.new()
		_dialogue_bridge.name = "DialogueNPCBridge"
		add_child(_dialogue_bridge)
	_connect_dialogue_bridge_signals()
	return _dialogue_bridge


func _connect_dialogue_bridge_signals() -> void:
	if not is_instance_valid(_dialogue_bridge):
		return
	if not _dialogue_bridge.has_signal("interaction_finished"):
		return
	var callback := Callable(self, "_on_dialogue_interaction_finished")
	if not _dialogue_bridge.is_connected("interaction_finished", callback):
		_dialogue_bridge.connect("interaction_finished", callback)


func _suspend_lesson_process_for_dialogue() -> void:
	_process_was_enabled_before_dialogue = is_processing()
	if _process_was_enabled_before_dialogue:
		set_process(false)


func _on_dialogue_interaction_finished(
	_action_id: StringName,
	_reason: StringName
) -> void:
	if _process_was_enabled_before_dialogue:
		set_process(true)
	_process_was_enabled_before_dialogue = false


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	_player = body
	prompt_label.visible = false


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		_play_animation(idle_animation)


func _play_animation(animation_name: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)


func _is_player_body(body: Node) -> bool:
	return body != null and body is CharacterBody3D and body.name == "CharacterBody3D"


func _is_confirm(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		key_event.pressed
		and not key_event.echo
		and (
			key_event.keycode == KEY_K
			or key_event.physical_keycode == KEY_K
			or key_event.keycode == KEY_ENTER
			or key_event.physical_keycode == KEY_ENTER
		)
	)
