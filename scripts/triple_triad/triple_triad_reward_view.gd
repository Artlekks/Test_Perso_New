extends Control

signal reward_selected(card_definition)
signal completed
signal leave_requested

const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")

const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2
const STATE_CLOSED := 0
const STATE_SELECT := 1
const STATE_CONFIRM := 2
const STATE_ACQUIRED := 3

const ROW_SCALE := Vector2(0.78, 0.78)
const ROW_STEP_X := 100.0
const TOP_ROW_ORIGIN := Vector2(70.0, 92.0)
const BOTTOM_ROW_ORIGIN := Vector2(70.0, 258.0)

@onready var prompt_label: Label = $PromptLabel
@onready var info_label: Label = $InfoPanel/InfoLabel
@onready var selection_arrow: Polygon2D = $SelectionArrow
@onready var confirm_dim: ColorRect = $ConfirmDim
@onready var confirm_prompt: Label = $ConfirmDim/ConfirmPrompt
@onready var choice_label: Label = $ConfirmDim/ChoiceLabel
@onready var acquired_label: Label = $ConfirmDim/AcquiredLabel
@onready var help_label: Label = $HelpLabel

var _state: int = STATE_CLOSED
var _opponent_cards: Array = []
var _player_cards: Array = []
var _opponent_views: Array = []
var _player_views: Array = []
var _selected_index: int = 0
var _yes_selected: bool = true
var _confirm_card: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_card_rows()


func open_reward(opponent_cards: Array, player_cards: Array) -> void:
	_opponent_cards = opponent_cards.duplicate()
	_player_cards = player_cards.duplicate()
	_selected_index = 0
	_yes_selected = true
	_state = STATE_SELECT
	visible = true
	confirm_dim.visible = false
	_clear_confirm_card()
	_refresh_rows()
	_refresh_selection()


func close_reward() -> void:
	_state = STATE_CLOSED
	visible = false
	_clear_confirm_card()


func is_active() -> bool:
	return _state != STATE_CLOSED


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _state == STATE_CLOSED or not _pressed(event):
		return

	match _state:
		STATE_SELECT:
			if _is_left(event):
				_selected_index = wrapi(_selected_index - 1, 0, maxi(_opponent_cards.size(), 1))
				_refresh_selection()
				_accept_input()
				return
			if _is_right(event):
				_selected_index = wrapi(_selected_index + 1, 0, maxi(_opponent_cards.size(), 1))
				_refresh_selection()
				_accept_input()
				return
			if _is_confirm(event) and not _opponent_cards.is_empty():
				_enter_confirm()
				_accept_input()
				return
			if _is_back(event):
				leave_requested.emit()
				_accept_input()
				return

		STATE_CONFIRM:
			if _is_left(event) or _is_right(event) or _is_up(event) or _is_down(event):
				_yes_selected = not _yes_selected
				_refresh_confirm_choices()
				_accept_input()
				return
			if _is_confirm(event):
				if _yes_selected:
					_confirm_reward()
				else:
					_return_to_selection()
				_accept_input()
				return
			if _is_back(event):
				_return_to_selection()
				_accept_input()
				return

		STATE_ACQUIRED:
			if _is_confirm(event):
				completed.emit()
				_accept_input()
				return
			if _is_back(event):
				leave_requested.emit()
				_accept_input()


func _build_card_rows() -> void:
	for index in range(5):
		var opponent_view: Control = CardViewScene.instantiate() as Control
		add_child(opponent_view)
		opponent_view.scale = ROW_SCALE
		opponent_view.position = TOP_ROW_ORIGIN + Vector2(float(index) * ROW_STEP_X, 0.0)
		opponent_view.z_index = 10 + index
		_opponent_views.append(opponent_view)

	for index in range(5):
		var player_view: Control = CardViewScene.instantiate() as Control
		add_child(player_view)
		player_view.scale = ROW_SCALE
		player_view.position = BOTTOM_ROW_ORIGIN + Vector2(float(index) * ROW_STEP_X, 0.0)
		player_view.z_index = 10 + index
		_player_views.append(player_view)


func _refresh_rows() -> void:
	for index in range(_opponent_views.size()):
		var opponent_view: Control = _opponent_views[index]
		if index < _opponent_cards.size():
			opponent_view.visible = true
			opponent_view.configure(_opponent_cards[index], OWNER_OPPONENT, false)
			opponent_view.set_selected(false)
		else:
			opponent_view.visible = false

	for index in range(_player_views.size()):
		var player_view: Control = _player_views[index]
		if index < _player_cards.size():
			player_view.visible = true
			player_view.configure(_player_cards[index], OWNER_PLAYER, false)
			player_view.set_selected(false)
		else:
			player_view.visible = false


func _refresh_selection() -> void:
	if _opponent_cards.is_empty():
		selection_arrow.visible = false
		info_label.text = ""
		return
	selection_arrow.visible = true
	selection_arrow.position = TOP_ROW_ORIGIN + Vector2(
		float(_selected_index) * ROW_STEP_X - 15.0,
		42.0
	)
	var card = _opponent_cards[_selected_index]
	info_label.text = str(card.display_name)
	prompt_label.text = "Select one card you want"
	help_label.text = "A/D: Choose   K: Select   I: Leave"


func _enter_confirm() -> void:
	_state = STATE_CONFIRM
	_yes_selected = true
	selection_arrow.visible = false
	confirm_dim.visible = true
	prompt_label.text = ""
	confirm_prompt.text = "Are you sure?"
	acquired_label.text = ""
	_refresh_confirm_choices()
	_clear_confirm_card()

	var card = _opponent_cards[_selected_index]
	_confirm_card = CardViewScene.instantiate() as Control
	confirm_dim.add_child(_confirm_card)
	_confirm_card.configure(card, OWNER_OPPONENT, false)
	_confirm_card.set_selected(false)
	_confirm_card.position = Vector2(262.0, 126.0)
	_confirm_card.pivot_offset = _confirm_card.size * 0.5
	_confirm_card.scale = Vector2(0.05, 1.55)
	_confirm_card.z_index = 50

	var tween: Tween = _confirm_card.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_confirm_card, "scale", Vector2(1.55, 1.55), 0.34)


func _return_to_selection() -> void:
	_state = STATE_SELECT
	confirm_dim.visible = false
	_clear_confirm_card()
	_refresh_selection()


func _confirm_reward() -> void:
	_state = STATE_ACQUIRED
	var card = _opponent_cards[_selected_index]
	reward_selected.emit(card)
	confirm_prompt.text = ""
	choice_label.text = ""
	acquired_label.text = "%s acquired!" % str(card.display_name)
	help_label.text = "K: Continue   I: Leave"

	if _confirm_card != null:
		var tween: Tween = _confirm_card.create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(_confirm_card, "scale", Vector2(0.05, 1.75), 0.18)
		tween.tween_property(_confirm_card, "scale", Vector2(1.75, 1.75), 0.24)


func _refresh_confirm_choices() -> void:
	choice_label.text = "> YES     NO" if _yes_selected else "  YES   > NO"
	help_label.text = "A/D: Choice   K: Confirm   I: Back"


func _clear_confirm_card() -> void:
	if is_instance_valid(_confirm_card):
		_confirm_card.queue_free()
	_confirm_card = null


func _accept_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent) -> bool:
	return event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo


func _is_confirm(event: InputEvent) -> bool:
	return _key_matches(event, KEY_K) or _key_matches(event, KEY_ENTER)


func _is_back(event: InputEvent) -> bool:
	return _key_matches(event, KEY_I) or _key_matches(event, KEY_ESCAPE)


func _is_left(event: InputEvent) -> bool:
	return _key_matches(event, KEY_A) or _key_matches(event, KEY_LEFT)


func _is_right(event: InputEvent) -> bool:
	return _key_matches(event, KEY_D) or _key_matches(event, KEY_RIGHT)


func _is_up(event: InputEvent) -> bool:
	return _key_matches(event, KEY_W) or _key_matches(event, KEY_UP)


func _is_down(event: InputEvent) -> bool:
	return _key_matches(event, KEY_S) or _key_matches(event, KEY_DOWN)


func _key_matches(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.keycode == key or key_event.physical_keycode == key
