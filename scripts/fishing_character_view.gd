extends Control

const FishingRodHandoff = preload("res://scripts/fishing_rod_handoff.gd")
signal inset_visibility_changed(is_present: bool)

@export var source_sprite: AnimatedSprite3D
@export var caster: Node
@export var player_screen_notifier: VisibleOnScreenNotifier3D

@export_category("Transition")
@export var slide_in_time: float = 0.30
@export var slide_out_time: float = 0.12
@export var slide_distance: float = 220.0

@onready var character: AnimatedSprite2D = $Character

var rest_position: Vector2
var slide_tween: Tween
var bait_in_water: bool = false
var _slide_fraction: float = 1.0
var _rod_handoff_latched: bool = false


func _ready() -> void:
	# Sample after CameraRig and GroundPresentation update, before the frame
	# is painted. A notifier signal can be one or more frames late.
	process_priority = 1000
	rest_position = position
	visible = false

	if source_sprite != null:
		character.sprite_frames = source_sprite.sprite_frames

	if caster != null:
		caster.bait_landed.connect(_on_bait_landed)
		caster.bait_returned.connect(_on_bait_returned)

	if player_screen_notifier != null:
		player_screen_notifier.screen_entered.connect(
			_on_player_screen_entered
		)
		player_screen_notifier.screen_exited.connect(
			_on_player_screen_exited
		)


func _process(_delta: float) -> void:
	if source_sprite == null:
		return

	if character.animation != source_sprite.animation:
		character.animation = source_sprite.animation

	character.set_frame_and_progress(
		source_sprite.frame,
		source_sprite.frame_progress
	)

	character.flip_h = source_sprite.flip_h
	# Also guard slide-out/cancel frames AFTER bait return. A real sprite may
	# enter during the HUD tween, so checking only while bait_in_water is unsafe.
	if bait_in_water:
		_refresh_character_visibility()
	elif visible and _real_character_is_visible():
		_retire_inset_immediately()


func _on_bait_landed(_point: Vector3) -> void:
	bait_in_water = true
	_rod_handoff_latched = false
	_refresh_character_visibility()


func _on_bait_returned() -> void:
	bait_in_water = false
	_rod_handoff_latched = false
	hide_character()


func _on_player_screen_entered() -> void:
	# The collider/notifier may enter before the painted rod. Wait for
	# the actual rod visibility test (also used by CameraRig).
	_refresh_character_visibility()


func _on_player_screen_exited() -> void:
	# If the bait is already in the water, this is the moment
	# the HUD copy is allowed to appear.
	_refresh_character_visibility()


func _refresh_character_visibility() -> void:
	if not bait_in_water:
		return

	if player_screen_notifier == null:
		return

	# The real actor may disappear again while a cast is still in water.
	# Do not permanently suppress the inset after one visibility event.
	_rod_handoff_latched = _real_character_is_visible()
	if _rod_handoff_latched:
		_retire_inset_immediately()
	else:
		show_character()


func _real_character_is_visible() -> bool:
	if not is_instance_valid(source_sprite):
		return false
	var world_camera: Camera3D = source_sprite.get_viewport().get_camera_3d()
	if world_camera == null:
		return false
	var rig: Node = world_camera.get_parent()
	if rig != null and rig.has_method("is_inset_presentation_active"):
		return not bool(rig.is_inset_presentation_active())
	return FishingRodHandoff.is_player_view_ready(player_screen_notifier,world_camera)


func _retire_inset_immediately() -> void:
	_kill_tween()
	if visible:
		visible = false
		inset_visibility_changed.emit(false)
	_set_slide_fraction(1.0)


func set_layout_rest(value: Vector2) -> void:
	# The inset is the only part of the bottom HUD allowed to slide in/out.
	# A changing wide-window composition must not invalidate tween end points.
	rest_position = value
	_set_slide_fraction(_slide_fraction)

func _set_slide_fraction(value: float) -> void:
	_slide_fraction = clampf(value, 0.0, 1.0)
	position = rest_position + Vector2(-slide_distance * _slide_fraction, 0.0)

func show_character() -> void:
	if visible:
		return
	_kill_tween()
	# G17: During the 0.2-second travel from -220 px the real player had
	# already left the screen, leaving neither representation visible.
	# At water contact the inset takes over at its settled HUD anchor.
	_set_slide_fraction(0.0)
	visible = true
	inset_visibility_changed.emit(true)

func hide_character() -> void:
	if not visible:
		return
	_kill_tween()
	inset_visibility_changed.emit(false)
	slide_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	slide_tween.tween_method(_set_slide_fraction, _slide_fraction, 1.0, slide_out_time)
	slide_tween.tween_callback(_finish_hide)

func _finish_hide() -> void:
	visible = false
	_set_slide_fraction(0.0)
	slide_tween = null


func _kill_tween() -> void:
	if slide_tween != null and slide_tween.is_valid():
		slide_tween.kill()

	slide_tween = null
