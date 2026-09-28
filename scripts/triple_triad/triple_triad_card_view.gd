extends PanelContainer

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

@onready var portrait: TextureRect = $Margin/Root/Portrait
@onready var top_label: Label = $Margin/Root/Top
@onready var right_label: Label = $Margin/Root/Right
@onready var bottom_label: Label = $Margin/Root/Bottom
@onready var left_label: Label = $Margin/Root/Left
@onready var hidden_label: Label = $Margin/Root/Hidden

var card = null
var card_owner: int = OWNER_NONE
var selected: bool = false
var is_hidden: bool = false


func configure(card_definition, card_owner: int, hide_card: bool = false) -> void:
	card = card_definition
	self.card_owner = card_owner
	is_hidden = hide_card
	_refresh()


func clear_card() -> void:
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
	var has_card: bool = card != null
	portrait.visible = has_card and not is_hidden
	top_label.visible = has_card and not is_hidden
	right_label.visible = has_card and not is_hidden
	bottom_label.visible = has_card and not is_hidden
	left_label.visible = has_card and not is_hidden
	hidden_label.visible = has_card and is_hidden

	if has_card and not is_hidden:
		portrait.texture = card.portrait
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
	_refresh_style()


func _refresh_style() -> void:
	if not is_node_ready():
		return
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	match card_owner:
		OWNER_PLAYER:
			style.bg_color = Color(0.12, 0.23, 0.42, 0.96)
			style.border_color = Color(0.38, 0.72, 1.0, 1.0)
		OWNER_OPPONENT:
			style.bg_color = Color(0.42, 0.13, 0.25, 0.96)
			style.border_color = Color(1.0, 0.47, 0.68, 1.0)
		_:
			style.bg_color = Color(0.08, 0.08, 0.1, 0.80)
			style.border_color = Color(0.44, 0.44, 0.48, 0.9)
	if selected:
		style.border_width_left = 4
		style.border_width_top = 4
		style.border_width_right = 4
		style.border_width_bottom = 4
		style.border_color = Color(1.0, 0.9, 0.35, 1.0)
	add_theme_stylebox_override("panel", style)


func _rank_text(value: int) -> String:
	return "A" if value >= 10 else str(value)
