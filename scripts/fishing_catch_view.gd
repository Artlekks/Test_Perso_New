extends CanvasLayer

signal shown
signal dismissed

@export var slide_time: float = 0.35
@export var slide_padding_px: float = 30.0
@export var king_name_prefix: String = "KING "
@export_category("Record Result")
@export var record_text_position: Vector2 = Vector2(280.0, 310.0)
@export var record_text_size: Vector2 = Vector2(105.0, 24.0)
@export var record_text_scale: Vector2 = Vector2(1.6, 1.6)
@onready var root: Control = $Root
@onready var fish_portrait: TextureRect = $Root/FishPortrait
@onready var fish_name_label: Label = $Root/FishNameLabel
@onready var fish_size_label: Label = $Root/FishSizeLabel
@onready var fish_points_label: Label = $Root/FishPointsLabel
@onready var record_badge: TextureRect = $Root/NewRecordBadge
@onready var rank_badge: TextureRect = $Root/RankBadge

var _rest_position: Vector2 = Vector2.ZERO
var _move_tween: Tween = null
var _record_label: Label = null

const RANK_BADGE_DIRECTORY := "res://assets/ui/fishing_menu/ranks"
const DEFAULT_RANK_BADGE_PATH := "res://assets/ui/fishing_menu/ranks/Rank_Beginner.png"
# Rank art is authored at its final 640x480 HUD size. Keep it under Root so it
# never inherits CatchFrame's 2x transform. This is the requested final position.
const RANK_BADGE_ROOT_POSITION := Vector2(280.0, 274.0)

func _ready() -> void:
	_rest_position = root.position
	_create_record_label()
	_setup_rank_badge()
	root.visible = false

func show_catch(
	fish: FishInstance,
	record_result: Dictionary = {}
) -> void:
	_kill_move_tween()
	_center_composed_result()

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

func composed_result_rect() -> Rect2:
	var frame := root.get_node("CatchFrame") as TextureRect
	return Rect2(frame.position, frame.size * frame.scale)

func _center_composed_result() -> void:
	# The shell can publish its visible gameplay rectangle (never its controls
	# or chrome). Move the common Root once; retain every child's composition.
	var surface: Rect2 = get_meta("gameplay_presentation_rect", Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size))
	_rest_position = surface.get_center() - composed_result_rect().get_center()


func _create_record_label() -> void:
	if _record_label != null:
		return

	_record_label = Label.new()
	_record_label.name = "RecordResultLabel"
	_record_label.position = record_text_position
	_record_label.size = record_text_size
	_record_label.scale = record_text_scale
	_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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

	record_badge.visible = _should_show_record_badge(record_result)
	_update_rank_badge(record_result)

	# This label is the lifetime fishing-point total only. Keep it numeric so
	# the baked "pts." artwork in the catch frame remains the single unit label.
	_record_label.text = ""

	if record_result.has("fishing_points"):
		_record_label.text = "%d" % maxi(
			int(record_result.get("fishing_points", 0)),
			0
		)


func _should_show_record_badge(record_result: Dictionary) -> bool:
	if record_result.is_empty():
		return false

	return (
		bool(record_result.get("new_species", false))
		or bool(record_result.get("new_best_size", false))
		or bool(record_result.get("new_best_points", false))
	)


func _setup_rank_badge() -> void:
	if rank_badge == null:
		return

	# The badge is persistent catch-panel information. It is not tied to
	# New Record, rank-up, or any other one-shot result state.
	if rank_badge.get_parent() != root:
		rank_badge.reparent(root, false)

	rank_badge.position = RANK_BADGE_ROOT_POSITION
	rank_badge.scale = Vector2.ONE
	rank_badge.pivot_offset = Vector2.ZERO
	rank_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rank_badge.stretch_mode = TextureRect.STRETCH_KEEP

	if rank_badge.texture == null:
		rank_badge.texture = _load_default_rank_badge()

	if rank_badge.texture != null:
		rank_badge.size = rank_badge.texture.get_size()

	rank_badge.visible = rank_badge.texture != null


func _update_rank_badge(record_result: Dictionary) -> void:
	if rank_badge == null:
		return

	# Resolve the current rank art when it exists. Until the rest of the rank
	# sprites are authored, Beginner is the explicit visual fallback so the rank
	# area is never blank on a catch result.
	var rank_id := str(record_result.get("rank_id", "")).strip_edges()
	var rank_name := str(record_result.get("rank_name", "")).strip_edges()
	var badge_texture: Texture2D = null

	if not rank_id.is_empty() or not rank_name.is_empty():
		badge_texture = _load_rank_badge_texture(rank_id, rank_name)

	if badge_texture == null:
		badge_texture = _load_default_rank_badge()

	if badge_texture != null:
		rank_badge.texture = badge_texture
		rank_badge.size = badge_texture.get_size()

	rank_badge.position = RANK_BADGE_ROOT_POSITION
	rank_badge.scale = Vector2.ONE
	rank_badge.visible = rank_badge.texture != null


func _load_default_rank_badge() -> Texture2D:
	if ResourceLoader.exists(DEFAULT_RANK_BADGE_PATH):
		return load(DEFAULT_RANK_BADGE_PATH) as Texture2D

	# Compatibility with the earlier temporary filenames used during this pass.
	for fallback_name in ["beginner.png", "Beginner.png"]:
		var fallback_path := "%s/%s" % [RANK_BADGE_DIRECTORY, fallback_name]
		if ResourceLoader.exists(fallback_path):
			return load(fallback_path) as Texture2D

	return null


func _load_rank_badge_texture(rank_id: String, rank_name: String) -> Texture2D:
	var candidates: Array[String] = []

	# rank_id is the stable asset key. display_name may be renamed later without
	# breaking progression or forcing code changes.
	if not rank_id.is_empty():
		candidates.append(rank_id)
		candidates.append("Rank_" + rank_id)

	if not rank_name.is_empty():
		var underscored_name := rank_name.replace(" ", "_")
		candidates.append(rank_name)
		candidates.append(underscored_name)
		candidates.append("Rank_" + underscored_name)
		candidates.append(rank_name.to_lower())
		candidates.append(rank_name.to_lower().replace(" ", "_"))

	for candidate in candidates:
		var path := "%s/%s.png" % [RANK_BADGE_DIRECTORY, candidate]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D

	return null


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

	record_badge.visible = false
	if rank_badge != null:
		rank_badge.visible = false

	root.visible = false
	root.position = _rest_position
