extends PanelContainer

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const COLOR_PLAYER := Color(0.32, 0.70, 1.0, 1.0)
const COLOR_OPPONENT := Color(1.0, 0.42, 0.66, 1.0)
const COLOR_SELECTED := Color(1.0, 0.88, 0.30, 1.0)
const COLOR_EMPTY := Color(0.43, 0.43, 0.47, 0.92)
const CAPTURE_HALF_DURATION := 0.20

@onready var portrait_background: ColorRect = $Root/PortraitBackground
@onready var portrait: TextureRect = $Root/Portrait
@onready var hidden_fill: ColorRect = $Root/HiddenFill
@onready var top_label: Label = $Root/Top
@onready var right_label: Label = $Root/Right
@onready var bottom_label: Label = $Root/Bottom
@onready var left_label: Label = $Root/Left
@onready var hidden_label: Label = $Root/Hidden
@onready var border_overlay: Panel = $BorderOverlay

var card = null
var card_owner: int = OWNER_NONE
var selected: bool = false
var is_hidden: bool = false
var _capture_tween: Tween = null


func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	_refresh()


func configure(card_definition, new_owner: int, hide_card: bool = false, animate_owner_change: bool = false) -> void:
	var previous_card = card
	var previous_owner: int = card_owner
	var can_animate_capture: bool = (
		animate_owner_change
		and previous_card != null
		and previous_card == card_definition
		and previous_owner in [OWNER_PLAYER, OWNER_OPPONENT]
		and new_owner in [OWNER_PLAYER, OWNER_OPPONENT]
		and previous_owner != new_owner
	)

	card = card_definition
	is_hidden = hide_card

	if can_animate_capture:
		_stop_capture_tween(false)
		card_owner = previous_owner
		_refresh_content()
		_refresh_style()
		_play_capture_flip(new_owner)
		return

	_stop_capture_tween(true)
	card_owner = new_owner
	_refresh()


func clear_card() -> void:
	_stop_capture_tween(true)
	card = null
	card_owner = OWNER_NONE
	is_hidden = false
	selected = false
	_refresh()


func set_selected(value: bool) -> void:
	selected = value
	_refresh_style()


func _refresh() -> void:
	if not is_node_ready():
		return
	_refresh_content()
	_refresh_style()


func _refresh_content() -> void:
	var has_card: bool = card != null
	portrait_background.visible = has_card and not is_hidden
	portrait.visible = has_card and not is_hidden
	hidden_fill.visible = has_card and is_hidden
	top_label.visible = has_card and not is_hidden
	right_label.visible = has_card and not is_hidden
	bottom_label.visible = has_card and not is_hidden
	left_label.visible = has_card and not is_hidden
	hidden_label.visible = has_card and is_hidden

	if has_card and not is_hidden:
		portrait.texture = card.portrait
		var is_fish_card: bool = card.source_kind == &"fish"
		portrait.stretch_mode = 5 if is_fish_card else 6
		portrait_background.color = (
			Color(0.42, 0.48, 0.41, 1.0)
			if is_fish_card
			else Color(0.16, 0.15, 0.17, 1.0)
		)
		top_label.text = _rank_text(card.top_rank)
		right_label.text = _rank_text(card.right_rank)
		bottom_label.text = _rank_text(card.bottom_rank)
		left_label.text = _rank_text(card.left_rank)
	else:
		portrait.texture = null
		top_label.text = ""
		right_label.text = ""
		bottom_label.text = ""
		left_label.text = ""
	if has_card and is_hidden:
		hidden_label.text = "?"


func _refresh_style() -> void:
	if not is_node_ready():
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.set_corner_radius_all(3)
	style.border_color = _owner_color(card_owner)
	if selected:
		style.border_color = COLOR_SELECTED
	border_overlay.add_theme_stylebox_override("panel", style)


func _play_capture_flip(new_owner: int) -> void:
	pivot_offset = size * 0.5
	_capture_tween = create_tween()
	_capture_tween.set_trans(Tween.TRANS_QUAD)
	_capture_tween.set_ease(Tween.EASE_IN_OUT)
	_capture_tween.tween_property(self, "scale", Vector2(0.04, 1.0), CAPTURE_HALF_DURATION)
	_capture_tween.tween_callback(func() -> void:
		card_owner = new_owner
		_refresh_style()
	)
	_capture_tween.tween_property(self, "scale", Vector2.ONE, CAPTURE_HALF_DURATION)
	_capture_tween.tween_callback(func() -> void:
		_capture_tween = null
	)


func _stop_capture_tween(reset_scale: bool) -> void:
	if _capture_tween != null:
		_capture_tween.kill()
	_capture_tween = null
	if reset_scale:
		scale = Vector2.ONE


func _owner_color(owner: int) -> Color:
	match owner:
		OWNER_PLAYER:
			return COLOR_PLAYER
		OWNER_OPPONENT:
			return COLOR_OPPONENT
		_:
			return COLOR_EMPTY


func _rank_text(value: int) -> String:
	return "A" if value >= 10 else str(value)


func _on_resized() -> void:
	pivot_offset = size * 0.5
