extends CanvasLayer


enum FeedbackType {
	HIT,
	HOOK_OFF,
	MISS,
	LINE_BREAK,
	CATCH
}


@onready var feedback_texture: TextureRect = $FeedbackTexture


@export var encounter: Node

@export_category("Feedback Textures")
@export var hit_texture: Texture2D
@export var hook_off_texture: Texture2D
@export var miss_texture: Texture2D
@export var line_break_texture: Texture2D
@export var catch_texture: Texture2D

@export_category("Timing")
@export var display_time: float = 0.8
@export var fade_time: float = 0.15
@export var slide_time: float = 0.18
@export var slide_padding_px: float = 30.0
@export var screen_transition: Node

@export_category("Responsive Feedback")
## Logical-pixel adjustment relative to the center of the active gameplay
## viewport. This is stable in floating/tall/docked windows.
@export var feedback_center_offset_pixels: Vector2 = Vector2.ZERO
## Extra size for the fishing prompt and catch, adjustable in Inspector.
## MISS / HOOK OFF / LINE BREAK keep their previously approved scale.
@export_range(1.0, 2.0, 0.05) var hit_catch_scale_multiplier: float = 1.30
var _authored_feedback_scale: Vector2 = Vector2.ONE

var _feedback_tween: Tween = null
var _rest_position: Vector2 = Vector2.ZERO
var _feedback_progress: float = 0.0
var _layout_viewport_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Scene-authoring offsets were for the fixed 640x480 surface. Use the
	# actual gameplay viewport for the center, and retain the original
	# texture/scale/nearest-filter assets unchanged.
	feedback_texture.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	_authored_feedback_scale = feedback_texture.scale
	_refresh_feedback_position()
	feedback_texture.visible = false
	screen_transition.covered.connect(clear)

	if encounter == null:
		push_warning("FishingFeedbackView: Encounter is not assigned.")
		return
	encounter.bite_triggered.connect(_on_bite_triggered)
	encounter.bite_missed.connect(_on_bite_missed)
	encounter.hook_off.connect(_on_hook_off)
	encounter.line_broken.connect(_on_line_broken)
	encounter.fish_caught.connect(_on_fish_caught)

func _process(_delta: float) -> void:
	# Keeps HIT / MISS centered even when resizing midway through its tween.
	var size: Vector2 = _feedback_viewport_size()
	if size != _layout_viewport_size:
		_refresh_feedback_position()

func _feedback_viewport_size() -> Vector2:
	var viewport: Viewport = custom_viewport if custom_viewport != null else get_viewport()
	return viewport.get_visible_rect().size

static func centered_feedback_position(viewport_size: Vector2, texture_size: Vector2, draw_scale: Vector2, offset: Vector2) -> Vector2:
	return (viewport_size - texture_size * draw_scale) * 0.5 + offset

func _refresh_feedback_position() -> void:
	_layout_viewport_size = _feedback_viewport_size()
	_rest_position = centered_feedback_position(_layout_viewport_size, feedback_texture.size, feedback_texture.scale, feedback_center_offset_pixels)
	_set_feedback_progress(_feedback_progress)

func _set_feedback_progress(value: float) -> void:
	_feedback_progress = value
	var travel: float = _layout_viewport_size.x + feedback_texture.size.x * feedback_texture.scale.x + slide_padding_px
	feedback_texture.position = _rest_position + Vector2(value * travel, 0.0)

func _on_bite_triggered() -> void:
	show_feedback(FeedbackType.HIT)

func _on_bite_missed() -> void:
	show_feedback(FeedbackType.MISS)

func _on_hook_off() -> void:
	show_feedback(FeedbackType.HOOK_OFF)

func _on_line_broken() -> void:
	show_feedback(FeedbackType.LINE_BREAK)

func _on_fish_caught(_fish: FishInstance) -> void:
	show_feedback(FeedbackType.CATCH)

func show_feedback(type: FeedbackType) -> void:
	var texture := _get_feedback_texture(type)
	if texture == null:
		return
	_kill_feedback_tween()
	feedback_texture.texture = texture
	var size_factor: float = hit_catch_scale_multiplier if type == FeedbackType.HIT or type == FeedbackType.CATCH else 1.0
	feedback_texture.scale = _authored_feedback_scale * size_factor
	feedback_texture.modulate.a = 1.0
	_refresh_feedback_position()
	_set_feedback_progress(1.0)
	feedback_texture.visible = true
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_feedback_progress, 1.0, 0.0, slide_time)
	if type == FeedbackType.HOOK_OFF or type == FeedbackType.LINE_BREAK:
		_feedback_tween = tween
		return
	tween.tween_interval(display_time)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_method(_set_feedback_progress, 0.0, -1.0, slide_time)
	tween.tween_callback(_hide_feedback)
	_feedback_tween = tween

func _get_feedback_texture(type: FeedbackType) -> Texture2D:
	match type:
		FeedbackType.HIT:
			return hit_texture

		FeedbackType.HOOK_OFF:
			return hook_off_texture

		FeedbackType.MISS:
			return miss_texture

		FeedbackType.LINE_BREAK:
			return line_break_texture

		FeedbackType.CATCH:
			return catch_texture

	return null

func _hide_feedback() -> void:
	feedback_texture.visible = false
	_set_feedback_progress(0.0)
	feedback_texture.modulate.a = 1.0
	_feedback_tween = null

func _kill_feedback_tween() -> void:
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = null

func clear() -> void:
	_kill_feedback_tween()
	feedback_texture.visible = false
	_set_feedback_progress(0.0)
	feedback_texture.modulate.a = 1.0
