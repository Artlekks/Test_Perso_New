extends CanvasLayer
## The bite-window signal belongs above Ryu's HEAD (not at the splash).
## When Ryu is offscreen the same cue follows the sliding CharacterView head.
## No new animation data or replacement artwork is generated.

const EXCLAMATION_SHEET: Texture2D = preload("res://assets/ui/Exclamation.png")
const FRAME_COUNT: int = 6
const FRAME_WIDTH: int = 32
const FRAME_HEIGHT: int = 33

@export var alert_fps: float = 11.0
@export var alert_scale: float = 2.0
@export var screen_offset: Vector2 = Vector2(0.0, -8.0)

var _player: Node3D = null
var _inset: Control = null
var _player_billboard: AnimatedSprite3D = null
var _camera: Camera3D = null
var _alert_sprite: AnimatedSprite2D = null
var _active: bool = false

func set_follow_targets(player_actor: Node3D, camera: Camera3D, inset: Control = null) -> void:
	_player = player_actor
	_camera = camera
	_inset = inset
	if is_instance_valid(_player):
		_player_billboard = _player.get_node_or_null("GroundPresentation/VisualAnchor/AnimatedSprite3D") as AnimatedSprite3D

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
	if not is_instance_valid(_alert_sprite) or not is_instance_valid(_player): return
	if not is_instance_valid(_camera) or not _camera.is_current():
		_camera = _player.get_viewport().get_camera_3d()
	if not is_instance_valid(_camera):
		_alert_sprite.visible = false
		return
	var point := Vector2.ZERO
	if is_instance_valid(_inset) and _inset.visible:
		# Inset Grid shows the whole body but the cue belongs over the sprite's
		# HEAD, which travels when the inset slides in or out of the left edge.
		var inset_actor := _inset.get_node_or_null("Character") as AnimatedSprite2D
		if inset_actor == null:
			_alert_sprite.visible = false
			return
		# AnimatedSprite2D is not Sprite2D: it does NOT implement get_rect().
		# Sample the current animation-frame texture, including sprite offset
		# and its centered flag, to anchor the cue to the visible head.
		var frames: SpriteFrames = inset_actor.sprite_frames
		if frames == null or not frames.has_animation(inset_actor.animation):
			_alert_sprite.visible = false
			return
		var frame_art: Texture2D = frames.get_frame_texture(inset_actor.animation, inset_actor.frame)
		if frame_art == null:
			_alert_sprite.visible = false
			return
		var top_y: float = inset_actor.offset.y
		if inset_actor.centered:
			top_y -= frame_art.get_height() * 0.5
		point = inset_actor.get_global_transform_with_canvas() * Vector2(inset_actor.offset.x, top_y)
	else:
		if not is_instance_valid(_player_billboard):
			_alert_sprite.visible = false
			return
		var head_world := _player_billboard.global_position
		var frames := _player_billboard.sprite_frames
		if frames != null and frames.has_animation(_player_billboard.animation):
			var texture := frames.get_frame_texture(_player_billboard.animation, _player_billboard.frame)
			if texture != null:
				var half_height: float = texture.get_height() * _player_billboard.pixel_size * 0.46
				head_world += _camera.global_basis.y * half_height * _player_billboard.global_basis.get_scale().y
		if _camera.is_position_behind(head_world):
			_alert_sprite.visible = false
			return
		point = _camera.unproject_position(head_world)
	_alert_sprite.position = point.round() + screen_offset
	_alert_sprite.visible = _active
