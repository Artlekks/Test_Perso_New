extends Control
class_name TripleTriadMatchHUD

# EDIT LAYOUT IN: res://actors/TripleTriadMatchHUD.tscn
# Every visible HUD element is a real scene node now. Move it in Godot's 2D
# editor and the runtime will respect that placement. No hidden coordinate
# constants in this script should fight your scene edits.

const OWNER_PLAYER := 1

const COLOR_PATTERN_EMPTY := Color(0.10, 0.075, 0.05, 0.86)
const COLOR_PATTERN_BORDER := Color(0.92, 0.70, 0.16, 0.90)
const COLOR_PATTERN_CENTER := Color(0.85, 0.62, 0.14, 0.90)
const COLOR_PATTERN_PRESSURE := Color(0.78, 0.22, 0.12, 0.90)

@onready var _opponent_score_anchor: Control = $OpponentScoreAnchor
@onready var _opponent_score: Control = $OpponentScoreAnchor/Digits
@onready var _player_score_anchor: Control = $PlayerScoreAnchor
@onready var _player_score: Control = $PlayerScoreAnchor/Digits
@onready var _turn_label: Label = $TurnStatus
@onready var _top_info_label: Label = $TopInfo
@onready var _round_label: Label = $RoundStatus
@onready var _card_name_label: Label = $CardName
@onready var _card_description_label: Label = $CardDescription
@onready var _info_card: Control = $InfoCard

var _pattern_cells: Array[Panel] = []
var _help_roots: Array[Control] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pattern_cells = [
		$InfluencePattern/Cell00, $InfluencePattern/Cell10, $InfluencePattern/Cell20,
		$InfluencePattern/Cell01, $InfluencePattern/Cell11, $InfluencePattern/Cell21,
		$InfluencePattern/Cell02, $InfluencePattern/Cell12, $InfluencePattern/Cell22,
	]
	_help_roots = [
		$Hotkey1, $Hotkey2, $Hotkey3, $Hotkey4, $Hotkey5,
	]
	if _info_card.has_method("set_owner_outline_visible"):
		_info_card.call("set_owner_outline_visible", false)
	set_scores(5, 5)
	clear_help_entries()
	clear_card_info()


func set_scores(opponent_score: int, player_score: int) -> void:
	_set_score(_opponent_score, _opponent_score_anchor, opponent_score)
	_set_score(_player_score, _player_score_anchor, player_score)


func set_turn_text(value: String) -> void:
	_turn_label.text = value


func set_top_info_text(value: String) -> void:
	_top_info_label.text = value


func set_round_number(value: int) -> void:
	_round_label.text = "Round %d" % maxi(1, value)


func set_help_entries(entries: Array) -> void:
	for index in range(_help_roots.size()):
		var root: Control = _help_roots[index]
		var key_label: Label = root.get_node("Key")
		var action_label: Label = root.get_node("Action")
		if index < entries.size():
			var entry: Dictionary = entries[index]
			var key_text: String = str(entry.get("key", ""))
			var action_text: String = str(entry.get("action", ""))
			root.visible = not key_text.is_empty() or not action_text.is_empty()
			key_label.text = key_text
			action_label.text = action_text
			key_label.add_theme_font_size_override(
				"font_size",
				6 if key_text.length() >= 4 else 7
			)
		else:
			root.visible = false
			key_label.text = ""
			action_label.text = ""


func clear_help_entries() -> void:
	set_help_entries([])


func clear_card_info() -> void:
	_info_card.visible = false
	_card_name_label.text = ""
	_card_description_label.text = ""
	_set_pattern([])


func set_card_info(card, rotation_quarters: int) -> void:
	if card == null:
		clear_card_info()
		return

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


func _set_score(target: Control, anchor: Control, value: int) -> void:
	var score_text: String = str(maxi(value, 0))
	target.call("set_text", score_text)

	# Scale belongs to TripleTriadMatchHUD.tscn now. The runtime only updates
	# the number and keeps it centered, so manual editor tuning is never lost.
	var visual_scale: Vector2 = target.scale
	var scaled_size := Vector2(
		float(score_text.length() * 16) * visual_scale.x,
		16.0 * visual_scale.y
	)
	var anchor_center: Vector2 = Vector2.ZERO
	if anchor != null:
		anchor_center = anchor.size * 0.5
	target.position = anchor_center - scaled_size * 0.5


func _set_pattern(offsets: Array) -> void:
	for index in range(_pattern_cells.size()):
		var row: int = floori(float(index) / 3.0)
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
