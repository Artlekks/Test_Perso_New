extends PanelContainer

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const COLOR_PLAYER := Color(0.32, 0.70, 1.0, 1.0)
const COLOR_OPPONENT := Color(1.0, 0.42, 0.66, 1.0)
const COLOR_SELECTED := Color(1.0, 0.88, 0.30, 1.0)
const COLOR_EMPTY := Color(0.43, 0.43, 0.47, 0.92)

# Board captures keep the quick flip that already feels right.
const CAPTURE_HALF_DURATION := 0.14
# Reward-card transfer uses a complete front -> back -> front rotation so the
# actual card back is readable before ownership changes.
const REWARD_FLIP_HALF_DURATION := 0.12
const REWARD_BACK_HOLD_SECONDS := 0.07

@onready var portrait_background: ColorRect = $Root/PortraitBackground
@onready var portrait: TextureRect = $Root/Portrait
@onready var hidden_fill: ColorRect = $Root/HiddenFill
@onready var top_label: Label = $Root/Top
@onready var right_label: Label = $Root/Right
@onready var bottom_label: Label = $Root/Bottom
@onready var left_label: Label = $Root/Left
@onready var hidden_label: Label = $Root/Hidden
@onready var card_back: TextureRect = $Root/CardBack
@onready var border_overlay: Panel = $BorderOverlay

var card = null
var card_owner: int = OWNER_NONE
var selected: bool = false
var is_hidden: bool = false
var _showing_back: bool = false
var _capture_tween: Tween = null
var _capture_base_scale := Vector2.ONE


func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
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
	_showing_back = false

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
	_showing_back = false
	selected = false
	_refresh()


func set_selected(value: bool) -> void:
	selected = value
	_refresh_style()


# Full 2D Y-axis-style card rotation for the post-match card transfer. In a
# Control node, squeezing scale.x to almost zero gives the same visual read as
# a 3D card rotating edge-on. The real menu background is shown on the reverse.
func play_reward_flip(new_owner: int) -> void:
	if card == null:
		return
	_stop_capture_tween(true)
	pivot_offset = size * 0.5
	_capture_base_scale = scale
	var squeezed_scale := Vector2(
		maxf(_capture_base_scale.x * 0.035, 0.001),
		_capture_base_scale.y
	)

	_capture_tween = create_tween()
	_capture_tween.set_trans(Tween.TRANS_QUAD)
	_capture_tween.set_ease(Tween.EASE_IN_OUT)
	_capture_tween.tween_property(self, "scale", squeezed_scale, REWARD_FLIP_HALF_DURATION)
	_capture_tween.tween_callback(func() -> void:
		_showing_back = true
		_refresh_content()
	)
	_capture_tween.tween_property(self, "scale", _capture_base_scale, REWARD_FLIP_HALF_DURATION)
	_capture_tween.tween_interval(REWARD_BACK_HOLD_SECONDS)
	_capture_tween.tween_property(self, "scale", squeezed_scale, REWARD_FLIP_HALF_DURATION)
	_capture_tween.tween_callback(func() -> void:
		_showing_back = false
		card_owner = new_owner
		_refresh_content()
		_refresh_style()
	)
	_capture_tween.tween_property(self, "scale", _capture_base_scale, REWARD_FLIP_HALF_DURATION)
	await _capture_tween.finished
	_capture_tween = null


func _refresh() -> void:
	if not is_node_ready():
		return
	_refresh_content()
	_refresh_style()


func _refresh_content() -> void:
	var has_card: bool = card != null
	var show_face: bool = has_card and not is_hidden and not _showing_back
	var show_back: bool = has_card and (is_hidden or _showing_back)

	portrait_background.visible = show_face
	portrait.visible = show_face
	hidden_fill.visible = false
	top_label.visible = show_face
	right_label.visible = show_face
	bottom_label.visible = show_face
	left_label.visible = show_face
	hidden_label.visible = false
	card_back.visible = show_back

	if show_face:
		portrait.texture = card.portrait
		portrait_background.color = Color(0.16, 0.15, 0.17, 1.0)
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
	_capture_base_scale = scale
	var squeezed_scale := Vector2(
		maxf(_capture_base_scale.x * 0.04, 0.001),
		_capture_base_scale.y
	)
	_capture_tween = create_tween()
	_capture_tween.set_trans(Tween.TRANS_QUAD)
	_capture_tween.set_ease(Tween.EASE_IN_OUT)
	_capture_tween.tween_property(self, "scale", squeezed_scale, CAPTURE_HALF_DURATION)
	_capture_tween.tween_callback(func() -> void:
		card_owner = new_owner
		_refresh_style()
	)
	_capture_tween.tween_property(self, "scale", _capture_base_scale, CAPTURE_HALF_DURATION)
	_capture_tween.tween_callback(func() -> void:
		_capture_tween = null
	)


func _stop_capture_tween(reset_scale: bool) -> void:
	if _capture_tween != null:
		_capture_tween.kill()
		if reset_scale:
			scale = _capture_base_scale
	_capture_tween = null
	_showing_back = false


func _owner_color(card_owner_value: int) -> Color:
	match card_owner_value:
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
