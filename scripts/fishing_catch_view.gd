extends CanvasLayer

signal shown
signal dismissed

@export var slide_time: float = 0.35
@export var slide_padding_px: float = 30.0
@export var king_name_prefix: String = "KING "
@export_category("Record Result")
@export var record_text_position: Vector2 = Vector2(205.0, 235.0)
@export var record_text_size: Vector2 = Vector2(230.0, 88.0)
@export var record_text_scale: Vector2 = Vector2(1.0, 1.0)


@onready var root: Control = $Root
@onready var fish_portrait: TextureRect = $Root/FishPortrait
@onready var fish_name_label: Label = $Root/FishNameLabel
@onready var fish_size_label: Label = $Root/FishSizeLabel
@onready var fish_points_label: Label = $Root/FishPointsLabel

var _rest_position: Vector2 = Vector2.ZERO
var _move_tween: Tween = null
var _record_label: Label = null

func _ready() -> void:
	_rest_position = root.position
	_create_record_label()
	root.visible = false

func show_catch(
	fish: FishInstance,
	record_result: Dictionary = {}
) -> void:
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

	_set_record_text(record_result)

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


func _create_record_label() -> void:
	if _record_label != null:
		return

	_record_label = Label.new()
	_record_label.name = "RecordResultLabel"
	_record_label.position = record_text_position
	_record_label.size = record_text_size
	_record_label.scale = record_text_scale
	_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_record_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_record_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_record_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Reuse the exact same font family as the catch frame instead of
	# introducing a new visual dependency.
	var catch_font := fish_name_label.get_theme_font("font")

	if catch_font != null:
		_record_label.add_theme_font_override(
			"font",
			catch_font
		)

	root.add_child(_record_label)


func _set_record_text(record_result: Dictionary) -> void:
	if _record_label == null:
		return

	_record_label.text = ""

	if record_result.is_empty():
		return

	var lines: Array[String] = []
	var is_new_species := bool(
		record_result.get(
			"new_species",
			false
		)
	)

	if is_new_species:
		lines.append("NEW SPECIES!")
	else:
		if bool(
			record_result.get(
				"new_best_size",
				false
			)
		):
			lines.append("NEW SIZE RECORD!")

		if bool(
			record_result.get(
				"new_best_points",
				false
			)
		):
			lines.append("NEW POINT RECORD!")

	if bool(
		record_result.get(
			"first_king",
			false
		)
	):
		lines.append("FIRST KING!")

	_record_label.text = "\n".join(lines)


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

	if _record_label != null:
		_record_label.text = ""

	root.visible = false
	root.position = _rest_position
