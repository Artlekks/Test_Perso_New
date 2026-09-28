extends PanelContainer

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const COLOR_PLAYER := Color(0.32, 0.70, 1.0, 1.0)
const COLOR_OPPONENT := Color(1.0, 0.42, 0.66, 1.0)
const COLOR_SELECTED := Color(1.0, 0.88, 0.30, 1.0)
const COLOR_EMPTY := Color(0.43, 0.43, 0.47, 0.92)

# Board captures keep the quick flip that already feels right.
const CAPTURE_HALF_DURATION := 0.08
# Reward-card transfer uses a complete front -> back -> front rotation so the
# actual card back is readable before ownership changes.
const REWARD_FLIP_HALF_DURATION := 0.12
const REWARD_BACK_HOLD_SECONDS := 0.07

@onready var empty_slot_fill: ColorRect = $Root/EmptySlotFill
@onready var portrait_background: ColorRect = $Root/PortraitBackground
@onready var portrait: TextureRect = $Root/Portrait
@onready var hidden_fill: ColorRect = $Root/HiddenFill
@onready var top_label: Control = $Root/Top
@onready var right_label: Control = $Root/Right
@onready var bottom_label: Control = $Root/Bottom
@onready var left_label: Control = $Root/Left
@onready var hidden_label: Label = $Root/Hidden
@onready var card_back: TextureRect = $Root/CardBack
@onready var border_overlay: Panel = $BorderOverlay

var card = null
var card_owner: int = OWNER_NONE
var selected: bool = false
var is_hidden: bool = false
var rotation_quarters: int = 0
var rank_bonus: int = 0
var _showing_back: bool = false
var _capture_tween: Tween = null
var _capture_base_scale := Vector2.ONE


func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_refresh()


func configure(
	card_definition,
	new_owner: int,
	hide_card: bool = false,
	animate_owner_change: bool = false,
	new_rotation_quarters: int = 0,
	new_rank_bonus: int = 0
) -> void:
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
	rotation_quarters = posmod(new_rotation_quarters, 4)
	rank_bonus = new_rank_bonus
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
	rotation_quarters = 0
	rank_bonus = 0
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
	var show_empty_slot: bool = not has_card

	empty_slot_fill.visible = show_empty_slot
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
		_set_rank_text(top_label, _display_rank(0))
		_set_rank_text(right_label, _display_rank(1))
		_set_rank_text(bottom_label, _display_rank(2))
		_set_rank_text(left_label, _display_rank(3))
	else:
		portrait.texture = null
		_set_rank_text(top_label, 0)
		_set_rank_text(right_label, 0)
		_set_rank_text(bottom_label, 0)
		_set_rank_text(left_label, 0)


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


func _display_rank(side: int) -> int:
	if card == null:
		return 0
	var value: int
	if card.has_method("rank_for_side_rotated"):
		value = int(card.rank_for_side_rotated(side, rotation_quarters))
	else:
		value = int(card.rank_for_side(side))
	return clampi(value + rank_bonus, 1, 10)


func _set_rank_text(target: Control, value: int) -> void:
	if target == null or not target.has_method("set_text"):
		return
	# DistanceNumbers.png contains the 0-9 bitmap strip used by the fishing HUD.
	# Prototype Triple Triad values currently stay below 10; if a future authored
	# card reaches 10, the bitmap renderer can still display it as two digits.
	target.call("set_text", "" if value <= 0 else str(value))


func _on_resized() -> void:
	pivot_offset = size * 0.5
