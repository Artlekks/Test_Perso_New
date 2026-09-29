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
const STATE_RESOLVING := 3
const STATE_ENTERING := 4
const STATE_FOCUS_HOLD := 5

const ROW_SCALE := Vector2(0.88, 0.88)
const ROW_STEP_X := 108.0
const TOP_ROW_ORIGIN := Vector2(42.0, 92.0)
const BOTTOM_ROW_ORIGIN := Vector2(42.0, 294.0)

# FFVIII-style result-screen entrance: opponent row comes in from the left,
# player row from the right, with a readable but tightening stagger.
const ROW_ENTRY_DISTANCE := 720.0
const ROW_ENTRY_SECONDS := 0.38
const ROW_ENTRY_STAGGER_START := 0.15
const ROW_ENTRY_STAGGER_END := 0.075

const OPPONENT_THINK_SECONDS := 0.55
const OPPONENT_PICK_HOLD_SECONDS := 0.45
const FOCUS_TRAVEL_SECONDS := 0.32
const EXIT_SECONDS := 0.34
const FOCUS_SCALE := Vector2(1.75, 1.75)

@onready var prompt_label: Label = $PromptPanel/PromptLabel
@onready var info_label: Label = $InfoPanel/InfoLabel
@onready var selection_arrow: Polygon2D = $SelectionArrow
@onready var confirm_overlay: ColorRect = $ConfirmOverlay
@onready var confirm_prompt: Label = $ConfirmOverlay/ConfirmPanel/ConfirmPrompt
@onready var choice_label: Label = $ConfirmOverlay/ConfirmPanel/ChoiceLabel
@onready var choice_arrow: Polygon2D = $ConfirmOverlay/ConfirmPanel/ChoiceArrow
@onready var help_label: Label = $HelpLabel
@onready var focus_dim: ColorRect = $FocusDim

var _state: int = STATE_CLOSED
var _winner: int = OWNER_PLAYER
var _opponent_cards: Array = []
var _player_cards: Array = []
var _opponent_views: Array = []
var _player_views: Array = []
var _selected_index: int = 0
var _yes_selected: bool = true
var _focus_card: Control = null
var _sequence_id: int = 0
var _entrance_started: bool = false
var _focus_exit_down: bool = true
var _focus_sequence_id: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_card_rows()


func open_reward(
	opponent_cards: Array,
	player_cards: Array,
	winner: int = OWNER_PLAYER,
	defer_entrance: bool = false
) -> void:
	_sequence_id += 1
	_winner = winner
	_opponent_cards = opponent_cards.duplicate()
	_player_cards = player_cards.duplicate()
	_selected_index = 0
	_yes_selected = true
	_entrance_started = false
	visible = true
	confirm_overlay.visible = false
	selection_arrow.visible = false
	focus_dim.visible = false
	focus_dim.modulate = Color(1, 1, 1, 0)
	_clear_focus_card()
	_refresh_rows()
	_prepare_row_entrance()
	_state = STATE_ENTERING
	prompt_label.text = ""
	info_label.text = ""
	help_label.text = ""
	focus_dim.visible = false
	focus_dim.modulate = Color(1, 1, 1, 0)
	_set_help_large(false)

	if not defer_entrance:
		start_entrance()


func start_entrance() -> void:
	if not visible or _state != STATE_ENTERING or _entrance_started:
		return
	_entrance_started = true
	_run_row_entrance(_sequence_id)


func close_reward() -> void:
	_sequence_id += 1
	_state = STATE_CLOSED
	_entrance_started = false
	_focus_exit_down = true
	_focus_sequence_id = -1
	visible = false
	confirm_overlay.visible = false
	selection_arrow.visible = false
	_clear_focus_card()


func is_active() -> bool:
	return _state != STATE_CLOSED


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _state == STATE_CLOSED or not _pressed(event):
		return

	match _state:
		STATE_ENTERING:
			_accept_input()

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
					_begin_player_reward_sequence()
				else:
					_return_to_selection()
				_accept_input()
				return
			if _is_back(event):
				_return_to_selection()
				_accept_input()
				return

		STATE_RESOLVING:
			# The transfer animation owns the screen until the chosen card reaches
			# the center. Input is intentionally swallowed during that movement.
			_accept_input()

		STATE_FOCUS_HOLD:
			# Keep the won/lost card on screen. The player explicitly dismisses it
			# with K instead of the result vanishing on a timer.
			if _is_confirm(event):
				_state = STATE_RESOLVING
				help_label.text = ""
				_run_focus_exit(_focus_exit_down, _focus_sequence_id)
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
		opponent_view.modulate = Color.WHITE
		opponent_view.position = TOP_ROW_ORIGIN + Vector2(float(index) * ROW_STEP_X, 0.0)
		if index < _opponent_cards.size():
			opponent_view.visible = true
			opponent_view.configure(_opponent_cards[index], OWNER_OPPONENT, false)
			opponent_view.scale = ROW_SCALE
			opponent_view.set_selected(false)
		else:
			opponent_view.visible = false

	for index in range(_player_views.size()):
		var player_view: Control = _player_views[index]
		player_view.modulate = Color.WHITE
		player_view.position = BOTTOM_ROW_ORIGIN + Vector2(float(index) * ROW_STEP_X, 0.0)
		if index < _player_cards.size():
			player_view.visible = true
			player_view.configure(_player_cards[index], OWNER_PLAYER, false)
			player_view.scale = ROW_SCALE
			player_view.set_selected(false)
		else:
			player_view.visible = false


func _prepare_row_entrance() -> void:
	for index in range(_opponent_views.size()):
		var view: Control = _opponent_views[index]
		if not view.visible:
			continue
		view.position = _row_final_position(TOP_ROW_ORIGIN, index) + Vector2(-ROW_ENTRY_DISTANCE, 0.0)
		view.modulate = Color(1, 1, 1, 0)

	for index in range(_player_views.size()):
		var view: Control = _player_views[index]
		if not view.visible:
			continue
		view.position = _row_final_position(BOTTOM_ROW_ORIGIN, index) + Vector2(ROW_ENTRY_DISTANCE, 0.0)
		view.modulate = Color(1, 1, 1, 0)


func _run_row_entrance(sequence_id: int) -> void:
	var count: int = maxi(_opponent_cards.size(), _player_cards.size())
	for index in range(count):
		if not _entry_sequence_is_current(sequence_id):
			return
		if index < _opponent_views.size() and index < _opponent_cards.size():
			_start_row_card_entry(_opponent_views[index], _row_final_position(TOP_ROW_ORIGIN, index))
		if index < _player_views.size() and index < _player_cards.size():
			_start_row_card_entry(_player_views[index], _row_final_position(BOTTOM_ROW_ORIGIN, index))
		if index < count - 1:
			var progress: float = 0.0 if count <= 2 else float(index) / float(count - 2)
			var stagger: float = lerpf(ROW_ENTRY_STAGGER_START, ROW_ENTRY_STAGGER_END, progress)
			await get_tree().create_timer(stagger, true).timeout

	await get_tree().create_timer(ROW_ENTRY_SECONDS + 0.04, true).timeout
	if not _entry_sequence_is_current(sequence_id):
		return

	if _winner == OWNER_PLAYER:
		_state = STATE_SELECT
		_refresh_selection()
	else:
		_state = STATE_RESOLVING
		selection_arrow.visible = false
		prompt_label.text = "Opponent selects one of your cards"
		info_label.text = ""
		_set_help_large(false)
		help_label.text = ""
		_run_opponent_take_sequence(sequence_id)


func _start_row_card_entry(view: Control, final_position: Vector2) -> void:
	var tween: Tween = view.create_tween()
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "position", final_position, ROW_ENTRY_SECONDS)
	tween.parallel().tween_property(view, "modulate", Color.WHITE, ROW_ENTRY_SECONDS * 0.72)


func _row_final_position(row_origin: Vector2, index: int) -> Vector2:
	return row_origin + Vector2(float(index) * ROW_STEP_X, 0.0)


func _refresh_selection() -> void:
	if _opponent_cards.is_empty():
		selection_arrow.visible = false
		info_label.text = ""
		return
	selection_arrow.visible = true
	selection_arrow.position = _arrow_position(TOP_ROW_ORIGIN, _selected_index)
	var card = _opponent_cards[_selected_index]
	info_label.text = str(card.display_name)
	prompt_label.text = "Select 1 card you want"
	_set_help_large(false)
	help_label.text = "A/D: Choose   K: Select   I: Leave"


func _enter_confirm() -> void:
	_state = STATE_CONFIRM
	_yes_selected = true
	confirm_overlay.visible = true
	confirm_prompt.text = "Are you sure?"
	_refresh_confirm_choices()


func _return_to_selection() -> void:
	_state = STATE_SELECT
	confirm_overlay.visible = false
	_refresh_selection()


func _begin_player_reward_sequence() -> void:
	if _selected_index < 0 or _selected_index >= _opponent_cards.size():
		return
	_state = STATE_RESOLVING
	confirm_overlay.visible = false
	selection_arrow.visible = false
	help_label.text = ""
	var sequence_id := _sequence_id
	var card = _opponent_cards[_selected_index]
	var source_view = _opponent_views[_selected_index]
	reward_selected.emit(card)
	prompt_label.text = "%s acquired!" % str(card.display_name)
	info_label.text = str(card.display_name)
	_animate_card_transfer(card, source_view, OWNER_PLAYER, true, sequence_id)


func _run_opponent_take_sequence(sequence_id: int) -> void:
	if _player_cards.is_empty():
		completed.emit()
		return
	await get_tree().create_timer(OPPONENT_THINK_SECONDS, true).timeout
	if not _sequence_is_current(sequence_id):
		return

	_selected_index = _choose_opponent_take_index()
	selection_arrow.visible = true
	selection_arrow.position = _arrow_position(BOTTOM_ROW_ORIGIN, _selected_index)
	var card = _player_cards[_selected_index]
	info_label.text = str(card.display_name)
	await get_tree().create_timer(OPPONENT_PICK_HOLD_SECONDS, true).timeout
	if not _sequence_is_current(sequence_id):
		return

	selection_arrow.visible = false
	prompt_label.text = "Opponent takes %s" % str(card.display_name)
	var source_view = _player_views[_selected_index]
	_animate_card_transfer(card, source_view, OWNER_OPPONENT, false, sequence_id)


func _animate_card_transfer(
	card,
	source_view,
	new_owner: int,
	exit_down: bool,
	sequence_id: int
) -> void:
	if source_view == null or not is_instance_valid(source_view):
		completed.emit()
		return

	# Full reward flip: front -> real menu-background back -> front, then the
	# chosen card comes forward and leaves the screen.
	await source_view.play_reward_flip(new_owner)
	if not _sequence_is_current(sequence_id):
		return

	_focus_card = CardViewScene.instantiate() as Control
	add_child(_focus_card)
	_focus_card.configure(card, new_owner, false)
	_focus_card.set_selected(false)
	_focus_card.pivot_offset = _focus_card.size * 0.5
	_focus_card.scale = ROW_SCALE
	_focus_card.z_index = 800
	_focus_card.global_position = source_view.global_position
	source_view.visible = false

	# The card scales around its center pivot, so center the pivot itself.
	# This keeps the enlarged reward card visually centered on screen.
	var center_global := global_position + Vector2(
		(size.x - _focus_card.size.x) * 0.5,
		(size.y - _focus_card.size.y) * 0.5
	)
	focus_dim.visible = true
	focus_dim.modulate = Color(1, 1, 1, 0)
	var focus_tween: Tween = _focus_card.create_tween()
	focus_tween.set_trans(Tween.TRANS_QUINT)
	focus_tween.set_ease(Tween.EASE_OUT)
	focus_tween.tween_property(_focus_card, "global_position", center_global, FOCUS_TRAVEL_SECONDS)
	focus_tween.parallel().tween_property(_focus_card, "scale", FOCUS_SCALE, FOCUS_TRAVEL_SECONDS)
	focus_tween.parallel().tween_property(focus_dim, "modulate", Color.WHITE, FOCUS_TRAVEL_SECONDS)
	await focus_tween.finished
	if not _sequence_is_current(sequence_id):
		return

	_focus_exit_down = exit_down
	_focus_sequence_id = sequence_id
	_state = STATE_FOCUS_HOLD
	_set_help_large(true)
	help_label.text = "K: Continue"


func _run_focus_exit(exit_down: bool, sequence_id: int) -> void:
	if not _sequence_is_current(sequence_id):
		return
	if _focus_card == null or not is_instance_valid(_focus_card):
		completed.emit()
		return

	var exit_global := _focus_card.global_position
	if exit_down:
		exit_global.y = global_position.y + size.y + _focus_card.size.y * 1.7
	else:
		exit_global.y = global_position.y - _focus_card.size.y * 2.0

	var exit_tween: Tween = _focus_card.create_tween()
	exit_tween.set_trans(Tween.TRANS_QUAD)
	exit_tween.set_ease(Tween.EASE_IN)
	exit_tween.tween_property(_focus_card, "global_position", exit_global, EXIT_SECONDS)
	exit_tween.parallel().tween_property(focus_dim, "modulate", Color(1, 1, 1, 0), EXIT_SECONDS)
	await exit_tween.finished
	if not _sequence_is_current(sequence_id):
		return

	focus_dim.visible = false
	_clear_focus_card()
	completed.emit()


func _choose_opponent_take_index() -> int:
	var best_index: int = 0
	var best_total: int = -1
	for index in range(_player_cards.size()):
		var card = _player_cards[index]
		var total: int = int(card.top_rank) + int(card.right_rank) + int(card.bottom_rank) + int(card.left_rank)
		if total > best_total:
			best_total = total
			best_index = index
	return best_index


func _arrow_position(row_origin: Vector2, index: int) -> Vector2:
	return row_origin + Vector2(float(index) * ROW_STEP_X - 15.0, 42.0)


func _refresh_confirm_choices() -> void:
	choice_label.text = "YES          NO"
	choice_arrow.position = Vector2(52.0, 86.0) if _yes_selected else Vector2(158.0, 86.0)
	_set_help_large(false)
	help_label.text = "A/D: Choice   K: Confirm   I: Back"


func _entry_sequence_is_current(sequence_id: int) -> bool:
	return visible and _state == STATE_ENTERING and sequence_id == _sequence_id


func _sequence_is_current(sequence_id: int) -> bool:
	return visible and _state in [STATE_RESOLVING, STATE_FOCUS_HOLD] and sequence_id == _sequence_id


func _clear_focus_card() -> void:
	if is_instance_valid(_focus_card):
		_focus_card.queue_free()
	_focus_card = null


func _set_help_large(value: bool) -> void:
	help_label.add_theme_font_size_override("font_size", 15 if value else 10)


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
