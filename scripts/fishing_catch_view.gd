extends CanvasLayer

signal shown
signal dismissed

@export var slide_time: float = 0.35
@export var slide_padding_px: float = 30.0
@export var king_name_prefix: String = "KING "

@onready var root: Control = $Root
@onready var fish_portrait: TextureRect = $Root/FishPortrait
@onready var fish_name_label: Label = $Root/FishNameLabel
@onready var fish_size_label: Label = $Root/FishSizeLabel
@onready var fish_points_label: Label = $Root/FishPointsLabel

var _rest_position: Vector2 = Vector2.ZERO
var _move_tween: Tween = null

func _ready() -> void:
	_rest_position = root.position
	root.visible = false

func show_catch(fish: FishInstance) -> void:
	_kill_move_tween()

	# Prepare the frame offscreen to the right.
	root.position = _get_offscreen_right_position()
	root.visible = true

	# Default to baked placeholder artwork.
	fish_portrait.visible = false
	fish_portrait.texture = null

	fish_name_label.text = ""
	fish_size_label.text = ""
	fish_points_label.text = ""

	if fish == null:
		push_warning("FishingCatchView: Received a null FishInstance.")
	else:
		if fish.species == null:
			push_warning("FishingCatchView: Caught fish has no species.")
		else:
			if fish.species.portrait != null:
				fish_portrait.texture = fish.species.portrait
				fish_portrait.visible = true

			if fish.is_king:
				fish_name_label.text = (
					king_name_prefix
					+ fish.species.fish_name
				)
			else:
				fish_name_label.text = fish.species.fish_name
			fish_size_label.text = "%d" % roundi(fish.size)
			fish_points_label.text = "%d" % fish.points

	# Right → center/resting position.
	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_SINE)
	_move_tween.set_ease(Tween.EASE_OUT)

	_move_tween.tween_property(
		root,
		"position",
		_rest_position,
		slide_time
	)

	_move_tween.tween_callback(_on_show_finished)

func dismiss_catch() -> void:
	_kill_move_tween()

	# Center → right, using exactly the same speed.
	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_SINE)
	_move_tween.set_ease(Tween.EASE_IN)

	_move_tween.tween_property(
		root,
		"position",
		_get_offscreen_right_position(),
		slide_time
	)

	_move_tween.tween_callback(_on_dismiss_finished)


func _on_show_finished() -> void:
	_move_tween = null
	shown.emit()


func _on_dismiss_finished() -> void:
	_move_tween = null

	root.visible = false
	root.position = _rest_position

	dismissed.emit()


func _get_offscreen_right_position() -> Vector2:
	var viewport_width := get_viewport().get_visible_rect().size.x

	return _rest_position + Vector2(
		viewport_width + slide_padding_px,
		0.0
	)


func _kill_move_tween() -> void:
	if _move_tween != null:
		_move_tween.kill()
		_move_tween = null
		
func hide_catch() -> void:
	_kill_move_tween()
	root.visible = false
	root.position = _rest_position
