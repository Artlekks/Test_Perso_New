extends CanvasLayer
## Original Exclamation.png bite-window animation, projected above Ryu's actual
## AnimatedSprite3D into the *same gameplay viewport* as the fishing HUD.
## A separate world-space sprite was not reliable during fishing camera/docking.
## No new animation data or replacement artwork is generated.

const EXCLAMATION_SHEET: Texture2D = preload("res://assets/ui/Exclamation.png")
const FRAME_COUNT: int = 6
const FRAME_WIDTH: int = 32
const FRAME_HEIGHT: int = 33

@export var alert_fps: float = 11.0
@export var alert_scale: float = 2.0
@export var screen_offset: Vector2 = Vector2(-10.0, 10.0)
@export var head_height_cap_px: float = 68.0
@export var facing_shift_pixels: float = 7.0

var _player: Node3D = null
var _camera: Camera3D = null
var _player_sprite: AnimatedSprite3D = null
var _alert_sprite: AnimatedSprite2D = null
var _active: bool = false

func set_follow_targets(player: Node3D, camera: Camera3D) -> void:
	_player = player
	_camera = camera
	_player_sprite = null
	if is_instance_valid(_player):
		_player_sprite = _player.get_node_or_null(
			"GroundPresentation/VisualAnchor/AnimatedSprite3D"
		) as AnimatedSprite3D

func _ready() -> void:
	layer = 40
	process_priority = 120
	_alert_sprite = AnimatedSprite2D.new()
	_alert_sprite.name = "OriginalExclamationFrames"
	_alert_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_alert_sprite.centered = true
	_alert_sprite.scale = Vector2.ONE * alert_scale
	_alert_sprite.visible = false
	add_child(_alert_sprite)

	var animation_frames: SpriteFrames = SpriteFrames.new()
	animation_frames.add_animation(&"Alert")
	animation_frames.set_animation_speed(&"Alert", alert_fps)
	animation_frames.set_animation_loop(&"Alert", false)
	for index in range(FRAME_COUNT):
		var atlas_frame: AtlasTexture = AtlasTexture.new()
		atlas_frame.atlas = EXCLAMATION_SHEET
		atlas_frame.region = Rect2(index * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)
		animation_frames.add_frame(&"Alert", atlas_frame)
	_alert_sprite.sprite_frames = animation_frames
	_alert_sprite.animation = &"Alert"
	_alert_sprite.stop()
	set_process(false)

func show_bite_window() -> void:
	if not is_instance_valid(_alert_sprite):
		push_error("Bite exclamation: animation node was not initialized")
		return
	_active = true
	set_process(true)
	_update_screen_position()
	_alert_sprite.stop()
	_alert_sprite.frame = 0
	_alert_sprite.play(&"Alert")

func hide_bite_window() -> void:
	_active = false
	set_process(false)
	if is_instance_valid(_alert_sprite):
		_alert_sprite.visible = false
		_alert_sprite.stop()
		_alert_sprite.frame = 0

func is_bite_window_visible() -> bool:
	return _active and is_instance_valid(_alert_sprite) and _alert_sprite.visible

func get_alert_screen_position() -> Vector2:
	if is_instance_valid(_alert_sprite):
		return _alert_sprite.position
	return Vector2.ZERO

func _process(_delta: float) -> void:
	if _active:
		_update_screen_position()

func _update_screen_position() -> void:
	if not is_instance_valid(_player):
		if is_instance_valid(_alert_sprite):
			_alert_sprite.visible = false
		return
	if not is_instance_valid(_camera) or not _camera.is_current():
		_camera = _player.get_viewport().get_camera_3d()
	if not is_instance_valid(_camera) or not is_instance_valid(_alert_sprite):
		return

	if not is_instance_valid(_player_sprite):
		_player_sprite = _player.get_node_or_null(
			"GroundPresentation/VisualAnchor/AnimatedSprite3D"
		) as AnimatedSprite3D

	var head_position: Vector3 = _player.global_position + Vector3.UP * 0.85
	if is_instance_valid(_player_sprite) and _player_sprite.sprite_frames != null:
		var frames: SpriteFrames = _player_sprite.sprite_frames
		var pose: StringName = _player_sprite.animation
		if frames.has_animation(pose):
			var index: int = clampi(_player_sprite.frame, 0, frames.get_frame_count(pose) - 1)
			var texture: Texture2D = frames.get_frame_texture(pose, index)
			if texture != null:
				# GroundPresentation puts the sprite's feet at the player's
				# ground anchor by updating sprite.offset on frame changes.
				# The upper edge is (half height + authored offset) pixels up.
				# Cap height to Ryu's head: the fishing frame also contains
				# a raised ROD extending above his head.
				var pixels_to_top: float = minf(
					texture.get_height() * 0.5 + _player_sprite.offset.y,
					head_height_cap_px
				)
				var world_up: float = (
					pixels_to_top * _player_sprite.pixel_size
					* _player_sprite.global_basis.get_scale().y
				)
				head_position = (
					_player_sprite.global_position + _camera.global_basis.y * world_up
				)

	if _camera.is_position_behind(head_position):
		_alert_sprite.visible = false
		return

	# A modest shift toward the player's current facing. The camera projection
	# is updated each frame, so changes of heading, camera yaw/pitch, docking,
	# and resolution cannot leave this cue behind.
	var side: float = clampf(
		_player.global_basis.z.dot(_camera.global_basis.x), -1.0, 1.0
	)
	_alert_sprite.position = (
		_camera.unproject_position(head_position)
		+ screen_offset
		+ Vector2(side * facing_shift_pixels, 0.0)
	)
	_alert_sprite.visible = _active
