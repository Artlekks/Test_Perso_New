extends CanvasLayer

signal opened
signal closed
signal match_finished(result: Dictionary)
signal card_reward_selected(card_definition)

const MatchScript = preload("res://scripts/triple_triad/triple_triad_match.gd")
const AIScript = preload("res://scripts/triple_triad/triple_triad_ai.gd")
const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")
const CollectionScript = preload("res://scripts/triple_triad/triple_triad_collection.gd")
const OpponentCollectionScript = preload("res://scripts/triple_triad/triple_triad_opponent_collection.gd")

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const PHASE_CLOSED := 0
const PHASE_DEALING := 1
const PHASE_SELECT_CARD := 2
const PHASE_SELECT_CELL := 3
const PHASE_ANIMATING := 4
const PHASE_AI := 5
const PHASE_RESULT := 6
const PHASE_REWARD := 7
const PHASE_DECK_SETUP := 8

const HAND_STEP_Y := 72.0
const HAND_SELECTED_X_OFFSET := -10.0
const CAPTURE_SETTLE_SECONDS := 0.24
const RESULT_FADE_IN_SECONDS := 0.24
const RESULT_FADE_OUT_SECONDS := 0.30

@export var card_catalog: Resource
@export var rule_set: Resource
@export var region_profile: Resource
@export var ai_profile: Resource
@export_range(5, 50, 1) var deck_budget: int = 30
@export_range(5, 50, 1) var player_deck_budget: int = 30
@export_range(1, 6, 1) var player_card_rank: int = 6
@export_range(1, 10, 1) var prototype_min_level: int = 1
@export_range(1, 10, 1) var prototype_max_level: int = 3
@export_range(0.0, 2.0, 0.05) var ai_delay_seconds: float = 0.75

@onready var root: Control = $Root
@onready var opponent_hand_container: Control = $Root/OpponentHand
@onready var board_container: GridContainer = $Root/Board
@onready var player_hand_container: Control = $Root/PlayerHand
@onready var opponent_score_label: Control = $Root/OpponentScoreLabel/Digits
@onready var player_score_label: Control = $Root/PlayerScoreLabel/Digits
@onready var turn_label: Label = $Root/InfoPanel/TurnLabel
@onready var message_label: Label = $Root/MessageLabel
@onready var help_label: Label = $Root/HelpLabel
@onready var info_panel: Control = $Root/InfoPanel
@onready var info_label: Label = $Root/InfoPanel/InfoLabel
@onready var selection_arrow: Polygon2D = $Root/SelectionArrow
@onready var turn_arrow: Polygon2D = $Root/TurnArrow
@onready var result_label: Label = $Root/ResultLabel
@onready var reward_view = $Root/TripleTriadRewardView
@onready var transition_fade: ColorRect = $Root/TransitionFade
@onready var animation_director = $AnimationDirector
@onready var ai_timer: Timer = $AITimer
@onready var debug_menu = $TripleTriadDebugMenu
@onready var deck_setup = $Root/TripleTriadDeckSetup

var _match = null
var _ai = null
var _rng := RandomNumberGenerator.new()
var _phase: int = PHASE_CLOSED
var _selected_hand_index: int = 0
var _selected_cell_index: int = 4
var _previous_pause: bool = false
var _player_views: Array = []
var _opponent_views: Array = []
var _board_views: Array = []
var _starting_player_cards: Array = []
var _starting_opponent_cards: Array = []
var _last_info_name: String = ""
var _result_winner: int = OWNER_NONE
var _active_opponent_profile: Resource = null
var _active_region_profile: Resource = null
var _active_ai_profile: Resource = null
var _active_rule_set: Resource = null
var _active_deck_budget: int = 30
var _active_min_level: int = 1
var _active_max_level: int = 3
var _qa_profile_override: Resource = null
var _qa_forced_starting_owner: int = OWNER_NONE
var _qa_hand_seed: int = 0
var _qa_base_summary: Dictionary = {}
var _active_player_deck: Array = []
var _collection_backend = null
var _opponent_collection_backend = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	transition_fade.visible = false
	transition_fade.modulate = Color(1, 1, 1, 0)
	_match = MatchScript.new()
	_ai = AIScript.new()
	_collection_backend = CollectionScript.new()
	_collection_backend.initialize(card_catalog)
	_rng.randomize()
	_build_views()
	ai_timer.timeout.connect(_on_ai_timer_timeout)
	reward_view.reward_selected.connect(_on_reward_selected)
	reward_view.completed.connect(_on_reward_completed)
	reward_view.leave_requested.connect(_on_reward_leave_requested)
	debug_menu.apply_requested.connect(_on_qa_profile_apply_requested)
	deck_setup.deck_confirmed.connect(_on_deck_confirmed)
	deck_setup.cancelled.connect(_on_deck_cancelled)
	if card_catalog != null and card_catalog.has_method("validate_catalog"):
		var audit: Dictionary = card_catalog.validate_catalog()
		if not bool(audit.get("valid", false)):
			push_error("TripleTriadGame: invalid card catalog: %s" % str(audit.get("errors", [])))


func is_open() -> bool:
	return _phase != PHASE_CLOSED


func open_game(opponent_profile_override: Resource = null) -> void:
	if is_open() or card_catalog == null:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	_previous_pause = tree.paused
	_resolve_active_configuration(opponent_profile_override)
	_opponent_collection_backend = OpponentCollectionScript.new()
	_opponent_collection_backend.initialize(
		card_catalog,
		_active_opponent_id(),
		_active_min_level,
		_active_max_level,
		_active_deck_budget
	)
	root.visible = true
	_phase = PHASE_DECK_SETUP
	deck_setup.open_setup(card_catalog, player_deck_budget, player_card_rank, _collection_backend)
	tree.paused = true
	opened.emit()


func close_game() -> void:
	if not is_open():
		return
	ai_timer.stop()
	reward_view.close_reward()
	debug_menu.close_menu()
	deck_setup.close_setup()
	transition_fade.visible = false
	transition_fade.modulate = Color(1, 1, 1, 0)
	_phase = PHASE_CLOSED
	root.visible = false
	_opponent_collection_backend = null
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = _previous_pause
	closed.emit()


func _input(event: InputEvent) -> void:
	if not is_open() or not _pressed(event):
		return

	if _phase == PHASE_DECK_SETUP:
		return

	# F10 belongs to the card-game QA overlay while Triple Triad is open. The
	# overlay is intentionally available only in stable phases so applying a
	# profile cannot collide with an in-flight placement/deal coroutine.
	if debug_menu.is_open():
		var close_requested: bool = bool(debug_menu.handle_input(event))
		if close_requested:
			debug_menu.close_menu()
		_accept_input()
		return

	if _is_debug_toggle(event) and _phase in [PHASE_SELECT_CARD, PHASE_SELECT_CELL, PHASE_RESULT]:
		debug_menu.open_menu(_qa_base_summary, _qa_profile_override)
		_accept_input()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not _pressed(event):
		return

	if _phase == PHASE_DECK_SETUP:
		return

	# The reward view owns input while it is active.
	if _phase == PHASE_REWARD:
		return

	if _phase == PHASE_RESULT:
		if _is_confirm(event):
			_begin_result_transition()
			_accept_input()
			return
		if _is_back(event):
			close_game()
			_accept_input()
		return

	if _phase in [PHASE_DEALING, PHASE_ANIMATING, PHASE_AI]:
		if _is_back(event):
			close_game()
			_accept_input()
		return

	if _phase == PHASE_SELECT_CARD:
		var hand_step: int = _hand_step(event)
		if hand_step != 0:
			_selected_hand_index = clampi(
				_selected_hand_index + hand_step,
				0,
				maxi(_match.player_hand.size() - 1, 0)
			)
			_refresh_views()
			_accept_input()
			return
		if _is_rotate(event):
			_try_rotate_selected_card()
			_accept_input()
			return
		if _is_confirm(event) and not _match.player_hand.is_empty():
			_phase = PHASE_SELECT_CELL
			_selected_cell_index = _find_nearest_empty_cell(_selected_cell_index)
			_refresh_views()
			_accept_input()
			return
		if _is_back(event):
			close_game()
			_accept_input()
			return

	if _phase == PHASE_SELECT_CELL:
		var moved: bool = false
		if _is_left(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, -1, 0)
			moved = true
		elif _is_right(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, 1, 0)
			moved = true
		elif _is_up(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, 0, -1)
			moved = true
		elif _is_down(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, 0, 1)
			moved = true
		if moved:
			_refresh_views()
			_accept_input()
			return
		if _is_rotate(event):
			_try_rotate_selected_card()
			_accept_input()
			return
		if _is_confirm(event):
			_try_player_move()
			_accept_input()
			return
		if _is_back(event):
			_phase = PHASE_SELECT_CARD
			_refresh_views()
			_accept_input()


func _start_new_match(player_cards_override: Array = []) -> void:
	ai_timer.stop()
	reward_view.close_reward()
	result_label.visible = false
	transition_fade.visible = false
	transition_fade.modulate = Color(1, 1, 1, 0)
	_result_winner = OWNER_NONE
	message_label.text = ""
	_last_info_name = ""

	if _qa_hand_seed > 0:
		_rng.seed = _qa_hand_seed

	var player_cards: Array = []
	if player_cards_override.size() == 5:
		player_cards = player_cards_override.duplicate()
	elif _active_player_deck.size() == 5:
		player_cards = _active_player_deck.duplicate()
	else:
		player_cards = _build_budgeted_hand(_active_min_level, _active_max_level)
	var opponent_cards: Array = []
	if _opponent_collection_backend != null:
		opponent_cards = _opponent_collection_backend.build_match_deck(5, _active_deck_budget)
	if opponent_cards.size() != 5:
		opponent_cards = _build_budgeted_hand(_active_min_level, _active_max_level)
	_starting_player_cards = player_cards.duplicate()
	_starting_opponent_cards = opponent_cards.duplicate()
	var starting_owner: int
	match _qa_forced_starting_owner:
		OWNER_PLAYER:
			starting_owner = OWNER_PLAYER
		OWNER_OPPONENT:
			starting_owner = OWNER_OPPONENT
		_:
			starting_owner = OWNER_PLAYER if _rng.randi_range(0, 1) == 0 else OWNER_OPPONENT
	_match.reset_match(player_cards, opponent_cards, starting_owner, _active_rule_set, _active_region_profile)
	_selected_hand_index = 0
	_selected_cell_index = 4
	_phase = PHASE_DEALING
	_refresh_views()
	_run_deal_sequence(starting_owner)


func _run_deal_sequence(starting_owner: int) -> void:
	await animation_director.deal_hands(_player_views, _opponent_views, HAND_STEP_Y)
	if not is_open() or _phase != PHASE_DEALING:
		return
	_phase = PHASE_SELECT_CARD if starting_owner == OWNER_PLAYER else PHASE_AI
	message_label.text = ""
	_refresh_views()
	if _phase == PHASE_AI:
		_schedule_ai()


func _try_player_move() -> void:
	if _selected_hand_index < 0 or _selected_hand_index >= _match.player_hand.size():
		return
	if _selected_cell_index < 0 or _selected_cell_index >= 9:
		return
	if _match.board[_selected_cell_index] != null:
		message_label.text = "That space is occupied."
		return

	var played_card = _match.player_hand[_selected_hand_index]
	var played_rotation: int = _match.get_hand_rotation(OWNER_PLAYER, _selected_hand_index)
	var target_rank_bonus: int = _match.get_cell_rank_bonus(_selected_cell_index)
	var source_view: Control = _player_views[_selected_hand_index]
	var target_view: Control = _board_views[_selected_cell_index]
	var result: Dictionary = _match.place_card(OWNER_PLAYER, _selected_hand_index, _selected_cell_index)
	if not bool(result.get("success", false)):
		message_label.text = "Invalid move."
		return

	_phase = PHASE_ANIMATING
	_last_info_name = str(played_card.display_name)
	_refresh_phase_ui()
	await animation_director.animate_placement(root, source_view, target_view, played_card, OWNER_PLAYER, played_rotation, target_rank_bonus)
	if not is_open():
		return

	_selected_hand_index = clampi(_selected_hand_index, 0, maxi(_match.player_hand.size() - 1, 0))
	message_label.text = _capture_message(result)
	var captured_cells: Array = result.get("captured", [])
	_refresh_views(captured_cells)
	if not captured_cells.is_empty():
		await get_tree().create_timer(CAPTURE_SETTLE_SECONDS, true).timeout
		if not is_open():
			return

	if bool(result.get("game_over", false)):
		_finish_match()
	else:
		_phase = PHASE_AI
		_refresh_views()
		_schedule_ai()


func _on_ai_timer_timeout() -> void:
	if _phase != PHASE_AI or _match.game_over:
		return
	_run_ai_turn()


func _run_ai_turn() -> void:
	var move: Dictionary = _ai.choose_move(_match, OWNER_OPPONENT, _rng, _active_ai_profile)
	if not bool(move.get("valid", false)):
		_finish_match()
		return

	var hand_index: int = int(move.get("hand_index", 0))
	var cell_index: int = int(move.get("cell_index", 0))
	if hand_index < 0 or hand_index >= _match.opponent_hand.size():
		_finish_match()
		return

	if bool(move.get("rotate", false)):
		_match.rotate_hand_card(OWNER_OPPONENT, hand_index)
	var played_card = _match.opponent_hand[hand_index]
	var played_rotation: int = _match.get_hand_rotation(OWNER_OPPONENT, hand_index)
	var target_rank_bonus: int = _match.get_cell_rank_bonus(cell_index)
	var source_view: Control = _opponent_views[hand_index]
	var target_view: Control = _board_views[cell_index]
	var result: Dictionary = _match.place_card(OWNER_OPPONENT, hand_index, cell_index)
	if not bool(result.get("success", false)):
		_finish_match()
		return

	_phase = PHASE_ANIMATING
	_last_info_name = str(played_card.display_name)
	_refresh_phase_ui()
	await animation_director.animate_placement(root, source_view, target_view, played_card, OWNER_OPPONENT, played_rotation, target_rank_bonus)
	if not is_open():
		return

	message_label.text = _capture_message(result)
	var captured_cells: Array = result.get("captured", [])
	_refresh_views(captured_cells)
	if not captured_cells.is_empty():
		await get_tree().create_timer(CAPTURE_SETTLE_SECONDS, true).timeout
		if not is_open():
			return

	if bool(result.get("game_over", false)):
		_finish_match()
	else:
		_phase = PHASE_SELECT_CARD
		_selected_hand_index = clampi(_selected_hand_index, 0, maxi(_match.player_hand.size() - 1, 0))
		_selected_cell_index = _find_nearest_empty_cell(_selected_cell_index)
		_refresh_views()


func _finish_match() -> void:
	_phase = PHASE_RESULT
	_refresh_views()
	var score: Dictionary = _match.get_score()
	_result_winner = _match.get_winner()
	match _result_winner:
		OWNER_PLAYER:
			result_label.text = "YOU WIN!"
		OWNER_OPPONENT:
			result_label.text = "YOU LOSE..."
		_:
			result_label.text = "DRAW"
	result_label.visible = true
	turn_label.text = ""
	help_label.text = "K: Continue"
	selection_arrow.visible = false
	turn_arrow.visible = false
	match_finished.emit({
		"winner": _result_winner,
		"score": score,
	})


func _begin_result_transition() -> void:
	if _phase != PHASE_RESULT:
		return
	_phase = PHASE_ANIMATING
	help_label.text = ""
	_run_result_transition(_result_winner)


func _run_result_transition(winner: int) -> void:
	transition_fade.visible = true
	transition_fade.modulate = Color(1, 1, 1, 0)
	var fade_in: Tween = transition_fade.create_tween()
	fade_in.set_trans(Tween.TRANS_QUAD)
	fade_in.set_ease(Tween.EASE_IN_OUT)
	fade_in.tween_property(transition_fade, "modulate", Color.WHITE, RESULT_FADE_IN_SECONDS)
	await fade_in.finished
	if not is_open():
		return

	result_label.visible = false
	if winner not in [OWNER_PLAYER, OWNER_OPPONENT]:
		# A draw is a replay, not an exit. Re-deal behind the black result fade,
		# then reveal the fresh match using the same active QA/opponent profile.
		_start_new_match(_active_player_deck)
		transition_fade.visible = true
		transition_fade.modulate = Color.WHITE
		var replay_fade: Tween = transition_fade.create_tween()
		replay_fade.set_trans(Tween.TRANS_QUAD)
		replay_fade.set_ease(Tween.EASE_IN_OUT)
		replay_fade.tween_property(transition_fade, "modulate", Color(1, 1, 1, 0), RESULT_FADE_OUT_SECONDS)
		await replay_fade.finished
		if not is_open():
			return
		transition_fade.visible = false
		return

	_phase = PHASE_REWARD
	reward_view.open_reward(
		_starting_opponent_cards,
		_starting_player_cards,
		winner,
		true
	)
	_refresh_phase_ui()

	# Reveal the result screen while both card rows begin sliding into place.
	reward_view.start_entrance()
	var fade_out: Tween = transition_fade.create_tween()
	fade_out.set_trans(Tween.TRANS_QUAD)
	fade_out.set_ease(Tween.EASE_IN_OUT)
	fade_out.tween_property(transition_fade, "modulate", Color(1, 1, 1, 0), RESULT_FADE_OUT_SECONDS)
	await fade_out.finished
	if not is_open():
		return
	transition_fade.visible = false


func _schedule_ai() -> void:
	ai_timer.start(maxf(ai_delay_seconds, 0.01))


func _build_views() -> void:
	for index in range(5):
		var opponent_view: Control = CardViewScene.instantiate() as Control
		opponent_hand_container.add_child(opponent_view)
		opponent_view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
		opponent_view.scale = Vector2(1.05, 1.05)
		opponent_view.z_index = index
		_opponent_views.append(opponent_view)
	for _index in range(9):
		var board_view: Control = CardViewScene.instantiate() as Control
		board_container.add_child(board_view)
		_board_views.append(board_view)
	for index in range(5):
		var player_view: Control = CardViewScene.instantiate() as Control
		player_hand_container.add_child(player_view)
		player_view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
		player_view.scale = Vector2(1.05, 1.05)
		player_view.z_index = index
		_player_views.append(player_view)


func _refresh_views(captured_cells: Array = []) -> void:
	if _match == null:
		return
	var show_opponent_cards: bool = _active_rule_set == null or bool(_active_rule_set.open_rule)

	for index in range(_opponent_views.size()):
		var view: Control = _opponent_views[index]
		view.modulate = Color.WHITE
		view.scale = Vector2(1.05, 1.05)
		if index < _match.opponent_hand.size():
			view.visible = true
			view.configure(_match.opponent_hand[index], OWNER_OPPONENT, not show_opponent_cards, false, _match.get_hand_rotation(OWNER_OPPONENT, index), 0)
			view.set_selected(false)
			view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
			view.z_index = index
		else:
			view.visible = false

	for index in range(_player_views.size()):
		var view: Control = _player_views[index]
		view.modulate = Color.WHITE
		view.scale = Vector2(1.05, 1.05)
		if index < _match.player_hand.size():
			view.visible = true
			view.configure(_match.player_hand[index], OWNER_PLAYER, false, false, _match.get_hand_rotation(OWNER_PLAYER, index), 0)
			var is_selected: bool = (
				_phase in [PHASE_SELECT_CARD, PHASE_SELECT_CELL]
				and index == _selected_hand_index
			)
			# Selection is communicated by the side arrow + a small left nudge.
			# The ownership border remains blue instead of changing to yellow.
			view.set_selected(false)
			view.position = Vector2(
				HAND_SELECTED_X_OFFSET if is_selected else 0.0,
				float(index) * HAND_STEP_Y
			)
			view.z_index = index
		else:
			view.visible = false

	for cell_index in range(_board_views.size()):
		var board_view: Control = _board_views[cell_index]
		var slot_variant = _match.board[cell_index]
		if slot_variant == null:
			board_view.configure(null, OWNER_NONE, false)
		else:
			var slot: Dictionary = slot_variant
			board_view.configure(
				slot["card"],
				int(slot["owner"]),
				false,
				captured_cells.has(cell_index),
				int(slot.get("rotation", 0)),
				_match.get_cell_rank_bonus(cell_index)
			)
		board_view.set_selected(_phase == PHASE_SELECT_CELL and cell_index == _selected_cell_index)

	var score: Dictionary = _match.get_score()
	_set_score_digits(opponent_score_label, int(score["opponent"]))
	_set_score_digits(player_score_label, int(score["player"]))
	_refresh_phase_ui()


func _set_score_digits(target: Control, value: int) -> void:
	if target == null:
		return
	var score_text := str(value)
	target.call("set_text", score_text)
	var score_parent := target.get_parent() as Control
	if score_parent == null:
		return
	var glyph_count: int = score_text.length()
	var unscaled_width := float(glyph_count * 16)
	var scaled_width := unscaled_width * target.scale.x
	var scaled_height := 16.0 * target.scale.y
	target.position = Vector2(
		(score_parent.size.x - scaled_width) * 0.5,
		(score_parent.size.y - scaled_height) * 0.5
	)


func _refresh_phase_ui() -> void:
	selection_arrow.visible = false
	turn_arrow.visible = false
	info_panel.visible = _phase not in [PHASE_CLOSED, PHASE_REWARD]

	match _phase:
		PHASE_DEALING:
			turn_label.text = ""
			help_label.text = ""
			info_label.text = _region_trait_text()
		PHASE_SELECT_CARD:
			turn_label.text = "Your turn"
			help_label.text = _player_help_text(false)
			_update_player_selection_markers()
			_update_selected_card_info()
		PHASE_SELECT_CELL:
			turn_label.text = "Choose a board space"
			help_label.text = _player_help_text(true)
			_update_player_selection_markers()
			_update_selected_card_info()
		PHASE_AI:
			turn_label.text = "Opponent's turn"
			help_label.text = "I: Leave"
			_turn_arrow_for_owner(OWNER_OPPONENT)
			info_label.text = _region_trait_text()
		PHASE_ANIMATING:
			turn_label.text = ""
			help_label.text = ""
			info_label.text = _region_trait_text()
		PHASE_RESULT:
			turn_label.text = ""
			help_label.text = ""
		PHASE_REWARD:
			turn_label.text = ""
			help_label.text = ""
			info_panel.visible = false


func _update_player_selection_markers() -> void:
	if _match.player_hand.is_empty():
		return
	selection_arrow.visible = true
	selection_arrow.position = Vector2(
		player_hand_container.position.x - 16.0,
		player_hand_container.position.y + float(_selected_hand_index) * HAND_STEP_Y + 48.0
	)
	_turn_arrow_for_owner(OWNER_PLAYER)


func _turn_arrow_for_owner(turn_owner: int) -> void:
	turn_arrow.visible = true
	turn_arrow.position = Vector2(58.0, 31.0) if turn_owner == OWNER_OPPONENT else Vector2(574.0, 31.0)


func _update_selected_card_info() -> void:
	# Keep the match header clean for now. Card name/cost can return later once
	# the permanent information hierarchy is decided.
	info_label.text = _region_trait_text()

func _capture_message(result: Dictionary) -> String:
	var combo_captured: Array = result.get("combo_captured", [])
	if bool(result.get("same_triggered", false)):
		if not combo_captured.is_empty():
			return "SAME!  COMBO x%d" % combo_captured.size()
		return "SAME!"
	return ""


func _on_reward_selected(card_definition) -> void:
	if card_definition == null:
		return

	_last_info_name = str(card_definition.display_name)

	if _result_winner == OWNER_PLAYER:
		# This is a real transfer: the selected card leaves this NPC's persistent
		# collection/deck and becomes available to the player again.
		if _opponent_collection_backend != null:
			_opponent_collection_backend.remove_card(card_definition)
		_collection_backend.acquire_card(card_definition)
		card_reward_selected.emit(card_definition)
		return

	if _result_winner == OWNER_OPPONENT:
		# The opponent physically receives the player's lost card. It is marked as
		# priority in that NPC's saved deck so it appears in a later rematch and can
		# actually be won back from the same NPC.
		_collection_backend.remove_card(card_definition)
		if _opponent_collection_backend != null:
			_opponent_collection_backend.acquire_card(card_definition, true)

		if not _collection_backend.owns_card(card_definition):
			deck_setup.remove_card_from_all_profiles(StringName(card_definition.card_id))
			var filtered_active_deck: Array = []
			for card in _active_player_deck:
				if card != null and String(card.card_id) != String(card_definition.card_id):
					filtered_active_deck.append(card)
			_active_player_deck = filtered_active_deck


func _on_reward_completed() -> void:
	reward_view.close_reward()
	close_game()


func _on_reward_leave_requested() -> void:
	close_game()


func _on_deck_confirmed(cards: Array) -> void:
	if _phase != PHASE_DECK_SETUP or cards.size() != 5:
		return
	_active_player_deck = cards.duplicate()
	deck_setup.close_setup()
	_start_new_match(_active_player_deck)


func _on_deck_cancelled() -> void:
	if _phase != PHASE_DECK_SETUP:
		return
	close_game()


func _resolve_active_configuration(opponent_profile_override: Resource) -> void:
	_active_opponent_profile = opponent_profile_override
	_active_region_profile = region_profile
	_active_ai_profile = ai_profile
	_active_rule_set = rule_set
	_active_deck_budget = deck_budget
	_active_min_level = prototype_min_level
	_active_max_level = prototype_max_level

	if _active_opponent_profile != null:
		var profile_region = _active_opponent_profile.get("region_profile")
		if profile_region != null:
			_active_region_profile = profile_region
		var profile_ai = _active_opponent_profile.get("ai_profile")
		if profile_ai != null:
			_active_ai_profile = profile_ai
		var min_level_value = _active_opponent_profile.get("min_card_level")
		var max_level_value = _active_opponent_profile.get("max_card_level")
		if min_level_value != null:
			_active_min_level = clampi(int(min_level_value), 1, 10)
		if max_level_value != null:
			_active_max_level = clampi(int(max_level_value), _active_min_level, 10)

	if _active_region_profile != null:
		var region_rules = _active_region_profile.get("rule_set")
		if region_rules != null:
			_active_rule_set = region_rules
		var region_budget = _active_region_profile.get("deck_budget")
		if region_budget != null:
			_active_deck_budget = maxi(5, int(region_budget))

	if _active_opponent_profile != null:
		var budget_override = _active_opponent_profile.get("deck_budget_override")
		if budget_override != null and int(budget_override) > 0:
			_active_deck_budget = int(budget_override)

	# Keep the NPC configuration as the debug menu's CURRENT/NPC baseline, then
	# layer any temporary QA profile over it.
	_qa_base_summary = _configuration_summary()
	_apply_qa_profile_override()


func _apply_qa_profile_override() -> void:
	_qa_forced_starting_owner = OWNER_NONE
	_qa_hand_seed = 0
	if _qa_profile_override == null:
		return

	var qa_region: Resource = _qa_profile_override.get("region_profile")
	if qa_region != null:
		_active_region_profile = qa_region
		var region_rules = qa_region.get("rule_set")
		if region_rules != null:
			_active_rule_set = region_rules
		var region_budget = qa_region.get("deck_budget")
		if region_budget != null:
			_active_deck_budget = maxi(5, int(region_budget))

	var qa_ai: Resource = _qa_profile_override.get("ai_profile")
	if qa_ai != null:
		_active_ai_profile = qa_ai

	var qa_rules: Resource = _qa_profile_override.get("rule_set_override")
	if qa_rules != null:
		_active_rule_set = qa_rules

	var qa_budget: int = int(_qa_profile_override.get("deck_budget_override"))
	if qa_budget > 0:
		_active_deck_budget = qa_budget

	_active_min_level = clampi(int(_qa_profile_override.get("min_card_level")), 1, 10)
	_active_max_level = clampi(
		int(_qa_profile_override.get("max_card_level")),
		_active_min_level,
		10
	)
	_qa_forced_starting_owner = clampi(
		int(_qa_profile_override.get("starting_owner")),
		OWNER_NONE,
		OWNER_OPPONENT
	)
	_qa_hand_seed = maxi(0, int(_qa_profile_override.get("hand_seed")))


func _on_qa_profile_apply_requested(selected_profile: Resource) -> void:
	_qa_profile_override = selected_profile
	if _qa_profile_override == null:
		_rng.randomize()
	_resolve_active_configuration(_active_opponent_profile)
	_start_new_match(_active_player_deck)


func _active_opponent_id() -> StringName:
	if _active_opponent_profile != null:
		var raw_id = _active_opponent_profile.get("opponent_id")
		if raw_id != null and not str(raw_id).is_empty():
			return StringName(str(raw_id))
	return &"default_opponent"


func _configuration_summary() -> Dictionary:
	return {
		"region": _resource_display_name(_active_region_profile, "Default"),
		"ai": _resource_display_name(_active_ai_profile, "Default"),
		"budget": _active_deck_budget,
		"min_level": _active_min_level,
		"max_level": _active_max_level,
		"rules": _rules_summary(_active_rule_set, _active_region_profile),
	}


func _rules_summary(active_rules: Resource, active_region: Resource) -> String:
	var labels: PackedStringArray = PackedStringArray()
	if active_rules != null:
		if bool(active_rules.get("same_rule")):
			labels.append("Same")
		if bool(active_rules.get("combo_rule")):
			labels.append("Combo")
	if active_region != null and bool(active_region.get("allow_rotate")):
		labels.append("Rotate x1")
	if labels.is_empty():
		return "Normal capture"
	return " + ".join(labels)


func _resource_display_name(resource: Resource, fallback: String) -> String:
	if resource == null:
		return fallback
	var display_name = resource.get("display_name")
	if display_name != null and not str(display_name).is_empty():
		return str(display_name)
	return resource.resource_path.get_file().get_basename()


func _build_budgeted_hand(min_level: int, max_level: int) -> Array:
	if card_catalog.has_method("build_budgeted_hand"):
		return card_catalog.build_budgeted_hand(_rng, min_level, max_level, 5, _active_deck_budget)
	return card_catalog.build_random_hand(_rng, min_level, max_level, 5)


func _try_rotate_selected_card() -> void:
	if _selected_hand_index < 0 or _selected_hand_index >= _match.player_hand.size():
		return
	if _match.rotate_hand_card(OWNER_PLAYER, _selected_hand_index):
		message_label.text = "ROTATE! One use spent."
	else:
		message_label.text = "Rotate already used."
	_refresh_views()


func _player_help_text(board_selection: bool) -> String:
	var rotate_text: String = "   R: Rotate" if _match != null and _match.can_rotate(OWNER_PLAYER) else ""
	if board_selection:
		return "W/A/S/D: Move   K: Place%s   I: Back" % rotate_text
	return "W/S: Card   K: Select%s   I: Leave" % rotate_text


func _region_trait_text() -> String:
	if _active_region_profile == null:
		return ""
	var description = _active_region_profile.get("board_trait_description")
	if description == null:
		return ""
	return str(description)


func _find_nearest_empty_cell(preferred: int) -> int:
	if preferred >= 0 and preferred < 9 and _match.board[preferred] == null:
		return preferred
	var empty_cells: Array[int] = _match.get_empty_cells()
	if empty_cells.is_empty():
		return 0
	return empty_cells[0]


func _move_board_cursor(current: int, dx: int, dy: int) -> int:
	var row: int = floori(float(current) / 3.0)
	var column: int = current % 3
	column = clampi(column + dx, 0, 2)
	row = clampi(row + dy, 0, 2)
	return row * 3 + column


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


func _is_rotate(event: InputEvent) -> bool:
	return _key_matches(event, KEY_R)


func _is_debug_toggle(event: InputEvent) -> bool:
	return _key_matches(event, KEY_F10)


func _hand_step(event: InputEvent) -> int:
	if _is_up(event):
		return -1
	if _is_down(event):
		return 1
	return 0


func _key_matches(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.keycode == key or key_event.physical_keycode == key
