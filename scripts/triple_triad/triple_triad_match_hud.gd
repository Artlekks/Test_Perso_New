extends Control
class_name TripleTriadMatchHUD

const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")
const BitmapTextScript = preload("res://scripts/bitmap_text.gd")
const NUMBER_TEXTURE = preload("res://assets/sprites/DistanceNumbers.png")
const BOF_FONT = preload("res://assets/fonts/BOF_Font_Refined.fnt")

const OWNER_PLAYER := 1

const ROUND_TEXT_RECT := Rect2(269.0, 2.0, 102.0, 16.0)
const TURN_MASK_RECT := Rect2(248.0, 25.0, 144.0, 34.0)
const TURN_TEXT_RECT := Rect2(238.0, 24.0, 164.0, 36.0)
const TOP_INFO_RECT := Rect2(139.0, 66.0, 362.0, 22.0)
const OPPONENT_NAME_RECT := Rect2(47.0, 7.0, 104.0, 18.0)
const PLAYER_NAME_RECT := Rect2(489.0, 7.0, 104.0, 18.0)
const OPPONENT_SCORE_CENTER := Vector2(47.0, 46.0)
const PLAYER_SCORE_CENTER := Vector2(593.0, 46.0)

const INFO_CARD_POSITION := Vector2(177.0, 384.0)
const INFO_CARD_SCALE := Vector2(0.45, 0.45)
const INFO_NAME_RECT := Rect2(235.0, 383.0, 146.0, 20.0)
const INFO_DESC_RECT := Rect2(235.0, 409.0, 146.0, 34.0)
const PATTERN_ORIGIN := Vector2(406.0, 391.0)
const PATTERN_CELL_SIZE := 13.0
const PATTERN_CELL_GAP := 2.0

const HELP_KEY_RECTS := [
	Rect2(132.0, 464.0, 22.0, 12.0),
	Rect2(264.0, 464.0, 22.0, 12.0),
	Rect2(357.0, 464.0, 22.0, 12.0),
	Rect2(453.0, 464.0, 22.0, 12.0),
	Rect2(545.0, 464.0, 22.0, 12.0),
]
const HELP_ACTION_RECTS := [
	Rect2(100.0, 447.0, 88.0, 14.0),
	Rect2(231.0, 447.0, 88.0, 14.0),
	Rect2(324.0, 447.0, 88.0, 14.0),
	Rect2(418.0, 447.0, 88.0, 14.0),
	Rect2(512.0, 447.0, 88.0, 14.0),
]

const COLOR_TEXT := Color(0.90, 0.85, 0.69, 1.0)
const COLOR_TURN_MASK := Color(0.016, 0.17, 0.38, 1.0)
const COLOR_PATTERN_EMPTY := Color(0.10, 0.075, 0.05, 0.86)
const COLOR_PATTERN_BORDER := Color(0.92, 0.70, 0.16, 0.90)
const COLOR_PATTERN_CENTER := Color(0.85, 0.62, 0.14, 0.90)
const COLOR_PATTERN_PRESSURE := Color(0.78, 0.22, 0.12, 0.90)

var _opponent_score = null
var _player_score = null
var _turn_mask: ColorRect = null
var _turn_label: Label = null
var _top_info_label: Label = null
var _round_label: Label = null
var _opponent_name_label: Label = null
var _player_name_label: Label = null
var _card_name_label: Label = null
var _card_description_label: Label = null
var _info_card: Control = null
var _pattern_cells: Array[Panel] = []
var _help_key_labels: Array[Label] = []
var _help_action_labels: Array[Label] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_scores()
	_build_round_status()
	_build_turn_status()
	_build_nameplates()
	_build_top_info()
	_build_card_info()
	_build_help_prompts()
	clear_help_entries()
	clear_card_info()


func set_scores(opponent_score: int, player_score: int) -> void:
	_set_score(_opponent_score, opponent_score, OPPONENT_SCORE_CENTER)
	_set_score(_player_score, player_score, PLAYER_SCORE_CENTER)


func set_turn_text(value: String) -> void:
	if _turn_label == null:
		return
	_turn_label.text = value


func set_top_info_text(value: String) -> void:
	if _top_info_label == null:
		return
	_top_info_label.text = value


func set_round_number(value: int) -> void:
	if _round_label == null:
		return
	_round_label.text = "Round %d" % maxi(1, value)


func set_help_entries(entries: Array) -> void:
	for index in range(_help_key_labels.size()):
		var key_label: Label = _help_key_labels[index]
		var action_label: Label = _help_action_labels[index]
		if index < entries.size():
			var entry: Dictionary = entries[index]
			var key_text: String = str(entry.get("key", ""))
			var action_text: String = str(entry.get("action", ""))
			key_label.visible = not key_text.is_empty()
			action_label.visible = not action_text.is_empty()
			key_label.text = key_text
			action_label.text = action_text
			key_label.add_theme_font_size_override(
				"font_size",
				6 if key_text.length() >= 4 else 7
			)
		else:
			key_label.visible = false
			action_label.visible = false
			key_label.text = ""
			action_label.text = ""


func clear_help_entries() -> void:
	set_help_entries([])


func clear_card_info() -> void:
	if is_instance_valid(_info_card):
		_info_card.visible = false
	if _card_name_label != null:
		_card_name_label.text = ""
	if _card_description_label != null:
		_card_description_label.text = ""
	_set_pattern([])


func set_card_info(card, rotation_quarters: int) -> void:
	if card == null:
		clear_card_info()
		return

	if is_instance_valid(_info_card):
		_info_card.visible = true
		_info_card.configure(
			card,
			OWNER_PLAYER,
			false,
			false,
			rotation_quarters,
			0
		)
		_info_card.set_selected(false)
		if _info_card.has_method("set_owner_outline_visible"):
			_info_card.call("set_owner_outline_visible", false)

	_card_name_label.text = str(card.get("display_name"))
	_card_description_label.text = _card_description(card)

	var offsets: Array = []
	if card.has_method("get_influence_offsets_rotated"):
		for raw_offset in card.call(
			"get_influence_offsets_rotated",
			rotation_quarters
		):
			offsets.append(raw_offset)
	_set_pattern(offsets)


func _build_scores() -> void:
	_opponent_score = BitmapTextScript.new()
	_opponent_score.name = "OpponentScore"
	_opponent_score.font_texture = NUMBER_TEXTURE
	_opponent_score.font_color = Color(0.90, 0.90, 0.86, 1.0)
	_opponent_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_opponent_score)

	_player_score = BitmapTextScript.new()
	_player_score.name = "PlayerScore"
	_player_score.font_texture = NUMBER_TEXTURE
	_player_score.font_color = Color(0.90, 0.90, 0.86, 1.0)
	_player_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player_score)

	set_scores(5, 5)


func _build_round_status() -> void:
	_round_label = _make_label("RoundStatus", 7, COLOR_TEXT)
	_round_label.position = ROUND_TEXT_RECT.position
	_round_label.size = ROUND_TEXT_RECT.size
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_round_label.text = "Round 1"
	add_child(_round_label)


func _build_turn_status() -> void:
	_turn_mask = ColorRect.new()
	_turn_mask.name = "TurnTextMask"
	_turn_mask.position = TURN_MASK_RECT.position
	_turn_mask.size = TURN_MASK_RECT.size
	_turn_mask.color = COLOR_TURN_MASK
	_turn_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_turn_mask)

	_turn_label = _make_label("TurnStatus", 15, COLOR_TEXT)
	_turn_label.position = TURN_TEXT_RECT.position
	_turn_label.size = TURN_TEXT_RECT.size
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_turn_label)


func _build_nameplates() -> void:
	_opponent_name_label = _make_label("OpponentName", 8, COLOR_TEXT)
	_opponent_name_label.position = OPPONENT_NAME_RECT.position
	_opponent_name_label.size = OPPONENT_NAME_RECT.size
	_opponent_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_opponent_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_opponent_name_label.text = "Opponent"
	add_child(_opponent_name_label)

	_player_name_label = _make_label("PlayerName", 8, COLOR_TEXT)
	_player_name_label.position = PLAYER_NAME_RECT.position
	_player_name_label.size = PLAYER_NAME_RECT.size
	_player_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_name_label.text = "Player"
	add_child(_player_name_label)


func _build_top_info() -> void:
	_top_info_label = _make_label("TopInfo", 8, COLOR_TEXT)
	_top_info_label.position = TOP_INFO_RECT.position
	_top_info_label.size = TOP_INFO_RECT.size
	_top_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_top_info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_top_info_label)


func _build_card_info() -> void:
	_info_card = CardViewScene.instantiate() as Control
	_info_card.name = "InfoCard"
	add_child(_info_card)
	_info_card.position = INFO_CARD_POSITION
	_info_card.scale = INFO_CARD_SCALE
	_info_card.pivot_offset = Vector2.ZERO
	_info_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_card.z_index = 2
	if _info_card.has_method("set_owner_outline_visible"):
		_info_card.call("set_owner_outline_visible", false)

	_card_name_label = _make_label("CardName", 9, COLOR_TEXT)
	_card_name_label.position = INFO_NAME_RECT.position
	_card_name_label.size = INFO_NAME_RECT.size
	_card_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_card_name_label)

	_card_description_label = _make_label("CardDescription", 7, COLOR_TEXT)
	_card_description_label.position = INFO_DESC_RECT.position
	_card_description_label.size = INFO_DESC_RECT.size
	_card_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_card_description_label)

	_pattern_cells.clear()
	for row in range(3):
		for column in range(3):
			var cell := Panel.new()
			cell.name = "InfluenceCell_%d_%d" % [column, row]
			cell.position = PATTERN_ORIGIN + Vector2(
				float(column) * (PATTERN_CELL_SIZE + PATTERN_CELL_GAP),
				float(row) * (PATTERN_CELL_SIZE + PATTERN_CELL_GAP)
			)
			cell.size = Vector2(PATTERN_CELL_SIZE, PATTERN_CELL_SIZE)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(cell)
			_pattern_cells.append(cell)
	_set_pattern([])


func _build_help_prompts() -> void:
	_help_key_labels.clear()
	_help_action_labels.clear()
	for index in range(HELP_KEY_RECTS.size()):
		var key_label := _make_label("HelpKey%d" % index, 7, COLOR_TEXT)
		key_label.position = HELP_KEY_RECTS[index].position
		key_label.size = HELP_KEY_RECTS[index].size
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(key_label)
		_help_key_labels.append(key_label)

		var action_label := _make_label("HelpAction%d" % index, 7, COLOR_TEXT)
		action_label.position = HELP_ACTION_RECTS[index].position
		action_label.size = HELP_ACTION_RECTS[index].size
		action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(action_label)
		_help_action_labels.append(action_label)


func _set_score(target, value: int, center: Vector2) -> void:
	if target == null:
		return
	var score_text := str(maxi(value, 0))
	var scale_value: float = 2.40 if score_text.length() <= 1 else 1.95
	target.scale = Vector2(scale_value, scale_value)
	target.call("set_text", score_text)
	var scaled_size := Vector2(
		float(score_text.length() * 16) * scale_value,
		16.0 * scale_value
	)
	target.position = center - scaled_size * 0.5


func _set_pattern(offsets: Array) -> void:
	for index in range(_pattern_cells.size()):
		var row: int = index / 3
		var column: int = index % 3
		var relative := Vector2i(column - 1, row - 1)
		var fill: Color = COLOR_PATTERN_EMPTY
		if relative == Vector2i.ZERO:
			fill = COLOR_PATTERN_CENTER
		else:
			for raw_offset in offsets:
				if raw_offset is Vector2i and raw_offset == relative:
					fill = COLOR_PATTERN_PRESSURE
					break
		_pattern_cells[index].add_theme_stylebox_override(
			"panel",
			_pattern_style(fill)
		)


func _pattern_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = COLOR_PATTERN_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(1)
	return style


func _card_description(card) -> String:
	var mode: String = str(card.get("influence_mode")).strip_edges().to_lower()
	var strength: int = int(card.get("influence_strength"))
	if mode == "pressure" and strength > 0:
		return "Pressure -%d on enemy cards in highlighted cells. Can create Same setups." % strength
	return "No Influence. Captures rely on directional values."


func _make_label(label_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", BOF_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.015, 1.0))
	label.add_theme_constant_override("outline_size", 2)
	return label
