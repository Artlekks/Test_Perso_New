extends Node3D
class_name FishingCardMakerNPC

const DialogueNPCBridgeScript = preload("res://scripts/dialogue/dialogue_npc_bridge.gd")
const PORTRAIT: Texture2D = preload("res://data/dialogue/portraits/card_maker.tres")
const DIALOGUE_ID: StringName = &"card_maker_greeting"
const ACTION_OPEN_CARD_MAKER: StringName = &"open_card_maker"

@export var interaction_prompt: String = "K : Card Maker"
@export var greeting_text: String = "Bring me a worthy fish, and I can turn its story into a card."

@export_category("Beach Patrol")
@export var patrol_enabled: bool = true
@export_range(0.05, 1.0, 0.01) var patrol_speed: float = 0.18
@export_range(0.25, 20.0, 0.25) var idle_pause_min: float = 1.75
@export_range(0.25, 20.0, 0.25) var idle_pause_max: float = 4.25
@export_range(1.0, 60.0, 0.5) var smoke_interval_min: float = 7.0
@export_range(1.0, 60.0, 0.5) var smoke_interval_max: float = 14.0

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var card_maker_menu: FishingCardMakerMenu = $FishingCardMakerMenu

var _player_in_range: bool = false
var _service: FishingCardMakerService = null
var _player_body: Node3D = null
var _rng := RandomNumberGenerator.new()

var _home_position := Vector3.ZERO
var _patrol_index: int = 0
var _target_position := Vector3.ZERO
var _moving: bool = false
var _pause_remaining: float = 0.0
var _smoke_remaining: float = 0.0
var _smoke_pending: bool = false
var _special_playing: bool = false
var _facing: StringName = &"se"
var _dialogue_bridge: DialogueNPCBridge = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_home_position = position
	_target_position = position
	_pause_remaining = _random_idle_pause()
	_smoke_remaining = _random_smoke_interval()
	_play_idle(_facing)
	prompt_label.visible = false
	prompt_label.text = interaction_prompt
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	card_maker_menu.closed.connect(_on_menu_closed)
	if animated_sprite != null:
		animated_sprite.animation_finished.connect(_on_animation_finished)
	_create_dialogue_bridge()
	call_deferred("_bind_card_maker")
	call_deferred("_cache_player_body")


func _process(delta: float) -> void:
	_update_depth_sort()
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if _player_in_range or (card_maker_menu != null and card_maker_menu.is_open()):
		return
	if _special_playing:
		return

	_smoke_remaining -= delta
	if _smoke_remaining <= 0.0:
		if _moving:
			_smoke_pending = true
		else:
			_play_smoke()
			_smoke_remaining = _random_smoke_interval()
		return

	if not patrol_enabled:
		return

	if _moving:
		_process_patrol_leg(delta)
		return

	_pause_remaining -= delta
	if _pause_remaining <= 0.0:
		_begin_next_patrol_leg()


func _input(event: InputEvent) -> void:
	if card_maker_menu != null and card_maker_menu.is_open():
		return
	if not _player_in_range:
		return
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if not _is_confirm(event):
		return

	if _start_interaction():
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _patrol_offsets() -> Array[Vector2]:
	# Small loop around the Card Maker's authored beach position.
	# Every leg is diagonal so it uses the real walk animations that exist
	# in the source sheet rather than faking missing cardinal walk cycles.
	return [
		Vector2(0.0, 0.0),
		Vector2(0.30, -0.17),
		Vector2(0.62, 0.05),
		Vector2(0.35, 0.28),
		Vector2(-0.10, 0.10),
	]


func _begin_next_patrol_leg() -> void:
	var points := _patrol_offsets()
	if points.size() < 2:
		_pause_remaining = _random_idle_pause()
		return

	_patrol_index = (_patrol_index + 1) % points.size()
	var offset := points[_patrol_index]
	_target_position = _home_position + Vector3(offset.x, 0.0, offset.y)
	var travel := Vector2(
		_target_position.x - position.x,
		_target_position.z - position.z
	)
	if travel.length_squared() <= 0.0001:
		_finish_patrol_leg()
		return

	_moving = true
	_facing = _direction_name(travel)
	_play_walk(_facing)


func _process_patrol_leg(delta: float) -> void:
	var flat_position := Vector2(position.x, position.z)
	var flat_target := Vector2(_target_position.x, _target_position.z)
	var delta_to_target := flat_target - flat_position
	var distance := delta_to_target.length()
	if distance <= 0.005:
		position.x = _target_position.x
		position.z = _target_position.z
		_finish_patrol_leg()
		return

	var direction := delta_to_target / distance
	_facing = _direction_name(direction)
	_play_walk(_facing)
	var step := minf(patrol_speed * delta, distance)
	position.x += direction.x * step
	position.z += direction.y * step


func _finish_patrol_leg() -> void:
	_moving = false
	_pause_remaining = _random_idle_pause()
	# Keep a single relaxed idle pose. Directional frames are reserved for
	# locomotion/turning so the captain does not snap through cardinal idles.
	_play_idle(&"se")

	if _smoke_pending:
		_smoke_pending = false
		_play_smoke()
		_smoke_remaining = _random_smoke_interval()
		return


func _stop_patrol() -> void:
	_moving = false
	_pause_remaining = _random_idle_pause()


func _direction_name(direction: Vector2) -> StringName:
	var x := direction.x
	var z := direction.y
	var ax := absf(x)
	var az := absf(z)

	if ax > az * 2.25:
		return &"e" if x >= 0.0 else &"w"
	if az > ax * 2.25:
		return &"s" if z >= 0.0 else &"n"
	if z < 0.0:
		return &"ne" if x >= 0.0 else &"nw"
	return &"se" if x >= 0.0 else &"sw"


func _play_idle(_direction: StringName = &"se") -> void:
	_special_playing = false
	_play_animation_if_available(&"idle_se")


func _play_walk(direction: StringName) -> void:
	_special_playing = false
	var walk_direction := direction
	# The original sprite sheet contains real walking cycles for NE and SE.
	# West versions are exact mirrors. Cardinal movement is intentionally
	# resolved to the nearest diagonal instead of replaying an idle cycle.
	match direction:
		&"n", &"e":
			walk_direction = &"ne"
		&"s":
			walk_direction = &"se"
		&"w":
			walk_direction = &"sw"
	_play_animation_if_available(StringName("walk_%s" % String(walk_direction)))


func _play_smoke() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(&"smoke"):
		_play_idle(_facing)
		return
	_special_playing = true
	animated_sprite.play(&"smoke")


func _play_animation_if_available(animation_name: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return
	if animated_sprite.animation == animation_name and animated_sprite.is_playing():
		return
	animated_sprite.play(animation_name)


func _random_idle_pause() -> float:
	return _rng.randf_range(
		minf(idle_pause_min, idle_pause_max),
		maxf(idle_pause_min, idle_pause_max)
	)


func _random_smoke_interval() -> float:
	return _rng.randf_range(
		minf(smoke_interval_min, smoke_interval_max),
		maxf(smoke_interval_min, smoke_interval_max)
	)


func _start_interaction() -> bool:
	if not _bind_card_maker():
		return false
	_stop_patrol()
	_play_idle(_facing)
	if (
		_dialogue_bridge != null
		and _dialogue_bridge.start_single_line(
			DIALOGUE_ID,
			ACTION_OPEN_CARD_MAKER,
			&"card_maker",
			"Card Maker",
			greeting_text,
			PORTRAIT
		)
	):
		return true
	return _open_card_maker_menu()


func _open_card_maker_menu() -> bool:
	if not _bind_card_maker():
		return false
	return card_maker_menu.open_menu()


func _create_dialogue_bridge() -> void:
	if _dialogue_bridge != null:
		return
	_dialogue_bridge = DialogueNPCBridgeScript.new() as DialogueNPCBridge
	_dialogue_bridge.name = "DialogueNPCBridge"
	add_child(_dialogue_bridge)
	_dialogue_bridge.interaction_finished.connect(_on_dialogue_interaction_finished)


func _on_dialogue_interaction_finished(action_id: StringName, reason: StringName) -> void:
	if action_id != ACTION_OPEN_CARD_MAKER:
		return
	if reason != &"completed":
		_play_idle(_facing)
		return
	call_deferred("_open_card_maker_menu")


func _bind_card_maker() -> bool:
	var services := _find_session_services()
	if services == null:
		return false

	var raw_service = services.get("card_maker_service")
	if raw_service is FishingCardMakerService:
		_service = raw_service
	elif services.has_method("get_card_maker_service"):
		var resolved = services.call("get_card_maker_service")
		if resolved is FishingCardMakerService:
			_service = resolved

	if _service == null:
		return false
	card_maker_menu.configure(_service)
	return true


func _find_session_services() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null

	var services := tree.root.get_node_or_null("FishingSessionServices")
	if services != null:
		return services

	var scene := tree.current_scene
	if scene == null:
		return null
	var fishing := scene.find_child("Fishing", true, false)
	if fishing != null:
		var candidate = fishing.get("session_services")
		if candidate is Node:
			return candidate
	return null


func _on_animation_finished() -> void:
	if animated_sprite == null or animated_sprite.animation != &"smoke":
		return
	_special_playing = false
	_play_idle(_facing)


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_body = body as Node3D
	_player_in_range = true
	_stop_patrol()
	_play_idle(_facing)
	prompt_label.visible = false


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	prompt_label.visible = false
	if card_maker_menu == null or not card_maker_menu.is_open():
		_pause_remaining = _random_idle_pause()
		_play_idle(_facing)


func _on_menu_closed() -> void:
	_pause_remaining = _random_idle_pause()
	_smoke_remaining = _random_smoke_interval()
	_play_idle(_facing)



func _cache_player_body() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var candidate := tree.current_scene.get_node_or_null("Player/CharacterBody3D")
	if candidate is Node3D:
		_player_body = candidate as Node3D
		return
	var found := tree.current_scene.find_child("CharacterBody3D", true, false)
	if found is Node3D:
		_player_body = found as Node3D


func _update_depth_sort() -> void:
	if animated_sprite == null or not is_inside_tree():
		return
	if not is_instance_valid(_player_body):
		_cache_player_body()
	if not is_instance_valid(_player_body):
		animated_sprite.sorting_offset = 0.0
		return

	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return

	# 2.5D overlap rule: whichever character appears lower on screen is in
	# front. sorting_offset is only used as a small tie-breaker between the
	# two billboard sprites; normal world depth still handles everything else.
	var npc_screen := camera.unproject_position(global_position)
	var player_screen := camera.unproject_position(_player_body.global_position)
	var delta_y := npc_screen.y - player_screen.y
	if absf(delta_y) < 1.0:
		animated_sprite.sorting_offset = 0.0
	elif delta_y > 0.0:
		animated_sprite.sorting_offset = 0.65
	else:
		animated_sprite.sorting_offset = -0.65


func _is_player_body(body: Node) -> bool:
	return (
		body != null
		and body is CharacterBody3D
		and body.name == "CharacterBody3D"
	)


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
