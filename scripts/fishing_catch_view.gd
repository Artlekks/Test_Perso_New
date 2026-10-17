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
var _slide_phase: int = 0 # 1=appearing, -1=dismissing
var _record_label: Label = null
var _rank_text: Label = null

const RANK_BADGE_DIRECTORY := "res://assets/ui/fishing_menu/ranks"
const DEFAULT_RANK_BADGE_PATH := "res://assets/ui/fishing_menu/ranks/Rank_Beginner.png"
# Measured inner panel in CatchFrame.png's 159x141 source pixels. All rank
# content is laid out from this rect and the authored frame's transform.
const RANK_PANEL_IN_FRAME := Rect2(52.0, 94.0, 105.0, 45.0)
const CATCH_MARGIN := 12.0
@export_category("Tall Desktop Catch Readability")
## On a taller floating window, the world is expanded vertically while its
## authored width stays fixed. Enlarge the same catch art to match the
## full-width presentation; never change the accepted 480px-high layout.
@export_range(1.0, 2.0, 0.05) var tall_window_max_catch_scale: float = 1.55

func _ready() -> void:
	# The frame, portrait, and bitmap labels share the same pixel sampling path.
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for item in [fish_portrait, fish_name_label, fish_size_label,
		fish_points_label, record_badge]:
		item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rest_position = root.position
	_create_record_label()
	_setup_rank_badge()
	root.visible = false
	# The viewport can grow while this result is on-screen (float resize).
	# Recenter the WHOLE composition, not just the CatchFrame texture.
	get_viewport().size_changed.connect(_on_gameplay_viewport_resized)

func _on_gameplay_viewport_resized() -> void:
	if not is_instance_valid(root):
		return
	var showing: bool = root.visible
	var interrupted_phase: int = _slide_phase
	if showing:
		_kill_move_tween()
	_center_composed_result()
	if showing:
		root.position = _rest_position
		# Resizing during a slide must still deliver the lifecycle signal.
		# Otherwise Fishing can wait forever for `shown` / `dismissed`.
		if interrupted_phase == 1:
			_on_show_finished()
		elif interrupted_phase == -1:
			_on_dismiss_finished()


func show_catch(
	fish: FishInstance,
	record_result: Dictionary = {}
) -> void:
	_kill_move_tween()
	_slide_phase = 1
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
	# Include the rank and total-point caption below the main frame; otherwise
	# the frame is centered but the actual visual composition drifts down/right.
	var frame := root.get_node("CatchFrame") as TextureRect
	var result := Rect2(frame.position, frame.size * frame.scale)
	for item in [fish_portrait, fish_name_label, fish_size_label,
		fish_points_label, record_badge, rank_badge, _rank_text, _record_label]:
		if item == null:
			continue
		var rect := Rect2(item.position, item.size * item.scale)
		result = result.merge(rect)
	return result

func _center_composed_result() -> void:
	# This layer is rendered into the real game SubViewport. Layout must be in
	# that viewport's logical coordinates, not the OS window or toolbar rect.
	var surface := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var artwork := composed_result_rect()
	# Previously scale was hard-capped at 1, so a 960x800 tall viewport
	# displayed the catch ~30% smaller on screen than a 960x480 wide one.
	# Grow ONLY with added logical height; keep the original size at 480.
	var preferred_scale: float = clampf(
		surface.size.y / 480.0, 1.0, tall_window_max_catch_scale
	)
	var maximum_scale := minf(preferred_scale,
		minf((surface.size.x - 2.0 * CATCH_MARGIN) / maxf(1.0, artwork.size.x),
			(surface.size.y - 2.0 * CATCH_MARGIN) / maxf(1.0, artwork.size.y)))
	root.scale = Vector2.ONE * maxf(0.1, maximum_scale)
	_rest_position = surface.get_center() - (artwork.position + artwork.size * 0.5) * root.scale


func _create_record_label() -> void:
	if _record_label != null:
		return

	_record_label = Label.new()
	_record_label.name = "RecordResultLabel"
	_record_label.position = record_text_position
	_record_label.size = record_text_size
	_record_label.scale = Vector2.ONE
	_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_record_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_record_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_record_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_record_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_record_label.add_theme_color_override("font_color", Color(0.18, 0.27, 0.13))

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
	_layout_rank_panel()


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
	_rank_text = Label.new()
	_rank_text.name = "RankTextFallback"
	_rank_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_rank_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_rank_text.clip_text = true
	_rank_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_text.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rank_text.add_theme_font_override("font", fish_name_label.get_theme_font("font"))
	_rank_text.add_theme_color_override("font_color", Color(0.18, 0.27, 0.13))
	root.add_child(_rank_text)
	_layout_rank_panel()


func _update_rank_badge(record_result: Dictionary) -> void:
	if rank_badge == null:
		return

	# Use authored art where available, otherwise the same bitmap font. Never
	# substitute a Beginner badge for an earned higher rank.
	var rank_id := str(record_result.get("rank_id", "")).strip_edges()
	var rank_name := str(record_result.get("rank_name", "")).strip_edges()
	var badge_texture: Texture2D = null

	if not rank_id.is_empty() or not rank_name.is_empty():
		badge_texture = _load_rank_badge_texture(rank_id, rank_name)

	if badge_texture == null and rank_id.is_empty() and rank_name.is_empty():
		badge_texture = _load_default_rank_badge()

	if badge_texture != null:
		rank_badge.texture = badge_texture
		rank_badge.size = badge_texture.get_size()

	rank_badge.visible = badge_texture != null
	_rank_text.text = rank_name if not rank_name.is_empty() else rank_id.replace("_", " ").capitalize()
	_rank_text.visible = badge_texture == null
	_layout_rank_panel()


func _rank_panel_rect() -> Rect2:
	var frame := root.get_node("CatchFrame") as TextureRect
	return Rect2(frame.position + RANK_PANEL_IN_FRAME.position * frame.scale,
		RANK_PANEL_IN_FRAME.size * frame.scale)


func _layout_rank_panel() -> void:
	if rank_badge == null or _record_label == null or _rank_text == null:
		return
	var panel := _rank_panel_rect()
	var rank_band := Rect2(panel.position + Vector2(8, 6), Vector2(panel.size.x - 16, 26))
	var points_band := Rect2(panel.position + Vector2(8, 49), Vector2(panel.size.x - 74, 27))
	if rank_badge.texture != null:
		var art_size := rank_badge.texture.get_size()
		var art_scale := minf(1.0, minf(rank_band.size.x / art_size.x, rank_band.size.y / art_size.y))
		rank_badge.size = art_size
		rank_badge.scale = Vector2.ONE * art_scale
		# Authored rank badges and fallback text share the same left edge.
		rank_badge.position = Vector2(rank_band.position.x, rank_band.get_center().y - art_size.y * art_scale * 0.5).round()
	# Only the rank name has its own visual scale; it never changes the score size.
	_rank_text.scale = Vector2.ONE * 1.20
	_rank_text.position = rank_band.position.round()
	_rank_text.size = rank_band.size / _rank_text.scale
	var rank_font: Font = _rank_text.get_theme_font("font")
	var rank_font_size := 14
	if rank_font != null:
		while rank_font_size > 8 and rank_font.get_string_size(_rank_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, rank_font_size).x > _rank_text.size.x:
			rank_font_size -= 1
	_rank_text.add_theme_font_size_override("font_size", rank_font_size)

	# The upper Data frame's fish points are the numeric alignment reference.
	# In particular the ones digit of 4069 must land on the same X as the
	# six in 176; never center the lower total or shrink its bitmap glyphs.
	_record_label.scale = fish_points_label.scale
	# Match the actual upper Data number, including its text INK, not just
	# its bitmap family/size. The earlier green-black ink made the cumulative
	# result look much heavier than the pale upper number.
	_record_label.add_theme_font_override("font", fish_points_label.get_theme_font("font"))
	_record_label.add_theme_font_size_override("font_size", fish_points_label.get_theme_font_size("font_size"))
	_record_label.add_theme_color_override("font_color", fish_points_label.get_theme_color("font_color"))
	_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var number_right: float = fish_points_label.position.x + fish_points_label.size.x * fish_points_label.scale.x
	var number_left: float = panel.position.x + 8.0
	var number_width: float = maxf(1.0, (number_right - number_left) / _record_label.scale.x)
	_record_label.position = Vector2(number_left, points_band.position.y).round()
	_record_label.size = Vector2(number_width, points_band.size.y / _record_label.scale.y)
	_record_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


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
	_slide_phase = -1

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
	_slide_phase = 0
	_move_tween = null
	shown.emit()


func _on_dismiss_finished() -> void:
	_slide_phase = 0
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
	_slide_phase = 0

	if _record_label != null:
		_record_label.text = ""

	record_badge.visible = false
	if rank_badge != null:
		rank_badge.visible = false
	if _rank_text != null:
		_rank_text.visible = false

	root.visible = false
	root.position = _rest_position
