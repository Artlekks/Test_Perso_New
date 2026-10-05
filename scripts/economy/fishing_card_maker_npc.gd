extends Node3D
class_name FishingCardMakerNPC

@export var idle_animation: StringName = &"idle_s"
@export var side_idle_animation: StringName = &"idle_se"
@export var talk_animation: StringName = &"smoke"
@export var walk_left_animation: StringName = &"walk_sw"
@export var walk_right_animation: StringName = &"walk_se"
@export var interaction_prompt: String = "K : Card Maker"

@export_category("Ambient Roaming")
@export var roaming_enabled: bool = true
@export_range(0.05, 1.0, 0.01) var roam_half_width: float = 0.34
@export_range(0.05, 1.0, 0.01) var roam_speed: float = 0.16
@export_range(0.25, 20.0, 0.25) var idle_pause_min: float = 2.0
@export_range(0.25, 20.0, 0.25) var idle_pause_max: float = 5.0
@export_range(1.0, 60.0, 0.5) var smoke_interval_min: float = 8.0
@export_range(1.0, 60.0, 0.5) var smoke_interval_max: float = 16.0

@export_category("Smoke Alignment")
@export_range(0.0, 20.0, 0.5) var smoke_horizontal_correction_pixels: float = 8.0

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var card_maker_menu: FishingCardMakerMenu = $FishingCardMakerMenu

var _player_in_range: bool = false
var _service: FishingCardMakerService = null
var _rng := RandomNumberGenerator.new()
var _home_x: float = 0.0
var _target_x: float = 0.0
var _pause_remaining: float = 0.0
var _smoke_remaining: float = 0.0
var _roaming: bool = false
var _special_playing: bool = false
var _facing_right: bool = true
var _base_sprite_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_home_x = position.x
	if animated_sprite != null:
		_base_sprite_offset = animated_sprite.offset
	_target_x = _home_x
	_pause_remaining = _random_idle_pause()
	_smoke_remaining = _random_smoke_interval()
	_play_idle()
	prompt_label.visible = false
	prompt_label.text = interaction_prompt
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	card_maker_menu.closed.connect(_on_menu_closed)
	if animated_sprite != null:
		animated_sprite.animation_finished.connect(_on_animation_finished)
	call_deferred("_bind_card_maker")


func _process(delta: float) -> void:
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if not roaming_enabled:
		return
	if _player_in_range or (card_maker_menu != null and card_maker_menu.is_open()):
		return
	if _special_playing:
		return

	_smoke_remaining -= delta
	if _smoke_remaining <= 0.0:
		_play_smoke()
		_smoke_remaining = _random_smoke_interval()
		return

	if _roaming:
		_process_roaming(delta)
		return

	_pause_remaining -= delta
	if _pause_remaining <= 0.0:
		_begin_roaming_leg()


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


func _start_interaction() -> bool:
	if not _bind_card_maker():
		return false
	_stop_roaming()
	_play_smoke()
	return card_maker_menu.open_menu()


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


func _process_roaming(delta: float) -> void:
	var direction := signf(_target_x - position.x)
	if is_zero_approx(direction):
		_finish_roaming_leg()
		return

	_facing_right = direction > 0.0
	_play_walk_for_direction()
	position.x = move_toward(position.x, _target_x, roam_speed * delta)
	if is_equal_approx(position.x, _target_x):
		_finish_roaming_leg()


func _begin_roaming_leg() -> void:
	if roam_half_width <= 0.0:
		_pause_remaining = _random_idle_pause()
		return

	var left_x := _home_x - roam_half_width
	var right_x := _home_x + roam_half_width
	if absf(position.x - left_x) < absf(position.x - right_x):
		_target_x = right_x
	else:
		_target_x = left_x
	_roaming = true
	_facing_right = _target_x > position.x
	_play_walk_for_direction()


func _finish_roaming_leg() -> void:
	_roaming = false
	_pause_remaining = _random_idle_pause()
	_play_side_idle()


func _stop_roaming() -> void:
	_roaming = false
	_pause_remaining = _random_idle_pause()


func _play_idle() -> void:
	_special_playing = false
	if animated_sprite != null:
		animated_sprite.flip_h = false
	_play_animation_if_available(idle_animation)


func _play_side_idle() -> void:
	_special_playing = false
	if animated_sprite != null:
		animated_sprite.flip_h = not _facing_right
	_play_animation_if_available(side_idle_animation)


func _play_walk_for_direction() -> void:
	_special_playing = false
	if animated_sprite == null:
		return
	animated_sprite.flip_h = false
	if _facing_right:
		_play_animation_if_available(walk_right_animation)
	else:
		_play_animation_if_available(walk_left_animation)


func _play_smoke() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(talk_animation):
		_play_side_idle()
		return
	_special_playing = true
	animated_sprite.flip_h = not _facing_right
	var smoke_shift: float = smoke_horizontal_correction_pixels
	if animated_sprite.flip_h:
		smoke_shift = -smoke_shift
	animated_sprite.offset = _base_sprite_offset + Vector2(smoke_shift, 0.0)
	animated_sprite.play(talk_animation)


func _play_animation_if_available(animation_name: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return
	animated_sprite.offset = _base_sprite_offset
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


func _on_animation_finished() -> void:
	if animated_sprite == null:
		return
	if animated_sprite.animation != talk_animation:
		return
	_special_playing = false
	if _player_in_range or (card_maker_menu != null and card_maker_menu.is_open()):
		_play_idle()
	else:
		_play_side_idle()


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	_stop_roaming()
	_play_idle()
	prompt_label.visible = false


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	prompt_label.visible = false
	if card_maker_menu == null or not card_maker_menu.is_open():
		_play_side_idle()


func _on_menu_closed() -> void:
	_pause_remaining = _random_idle_pause()
	_smoke_remaining = _random_smoke_interval()
	_play_idle()


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
