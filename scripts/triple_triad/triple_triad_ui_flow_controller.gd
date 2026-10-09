extends RefCounted

const MatchHUDScene = preload("res://actors/TripleTriadMatchHUD.tscn")
const SurrenderConfirmScene = preload("res://actors/TripleTriadSurrenderConfirm.tscn")
const SessionControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_session_controller.gd"
)
const CARD_GAME_BACKGROUND = preload(
	"res://assets/ui/triple_triad/card_game/CardGame_Background.png"
)

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const PHASE_CLOSED := SessionControllerScript.PHASE_CLOSED
const PHASE_DEALING := SessionControllerScript.PHASE_DEALING
const PHASE_SELECT_CARD := SessionControllerScript.PHASE_SELECT_CARD
const PHASE_SELECT_CELL := SessionControllerScript.PHASE_SELECT_CELL
const PHASE_ANIMATING := SessionControllerScript.PHASE_ANIMATING
const PHASE_AI := SessionControllerScript.PHASE_AI
const PHASE_RESULT := SessionControllerScript.PHASE_RESULT
const PHASE_REWARD := SessionControllerScript.PHASE_REWARD
const PHASE_DECK_SETUP := SessionControllerScript.PHASE_DECK_SETUP
const PHASE_SURRENDER_CONFIRM := SessionControllerScript.PHASE_SURRENDER_CONFIRM

const HAND_STEP_Y := 140.0
const RESULT_DIM_COLOR := Color(0.0, 0.0, 0.0, 0.56)

var _root: Control = null
var _backdrop: TextureRect = null
var _grid_artwork: TextureRect = null
var _opponent_score_digits: Control = null
var _player_score_digits: Control = null
var _turn_label: Label = null
var _message_label: Label = null
var _help_label: Label = null
var _info_panel: Control = null
var _info_label: Label = null
var _selection_arrow: Polygon2D = null
var _turn_arrow: Polygon2D = null
var _result_label: Label = null
var _reward_view = null
var _transition_fade: ColorRect = null
var _animation_director = null
var _debug_menu = null

func bind_optional_overlay(overlay: Node) -> void:
	_debug_menu = overlay
var _deck_setup = null
var _player_hand_container: Control = null

var _default_backdrop_texture: Texture2D = null
var _match_hud: Control = null
var _result_dim: ColorRect = null
var _surrender_confirm: Control = null


func initialize(nodes: Dictionary) -> void:
	_root = nodes.get("root") as Control
	_backdrop = nodes.get("backdrop") as TextureRect
	_grid_artwork = nodes.get("grid_artwork") as TextureRect
	_opponent_score_digits = nodes.get("opponent_score_digits") as Control
	_player_score_digits = nodes.get("player_score_digits") as Control
	_turn_label = nodes.get("turn_label") as Label
	_message_label = nodes.get("message_label") as Label
	_help_label = nodes.get("help_label") as Label
	_info_panel = nodes.get("info_panel") as Control
	_info_label = nodes.get("info_label") as Label
	_selection_arrow = nodes.get("selection_arrow") as Polygon2D
	_turn_arrow = nodes.get("turn_arrow") as Polygon2D
	_result_label = nodes.get("result_label") as Label
	_reward_view = nodes.get("reward_view")
	_transition_fade = nodes.get("transition_fade") as ColorRect
	_animation_director = nodes.get("animation_director")
	_debug_menu = nodes.get("debug_menu")
	_deck_setup = nodes.get("deck_setup")
	_player_hand_container = nodes.get("player_hand_container") as Control

	_default_backdrop_texture = _backdrop.texture if _backdrop != null else null
	_apply_authored_layout()
	_build_runtime_surfaces()


func prepare_closed_state() -> void:
	set_match_skin_visible(false)
	_hide_result_overlay()
	if _root != null:
		_root.visible = false
	reset_transition_fade()


func show_recovery_surface() -> void:
	if _root != null:
		_root.visible = true
	set_match_skin_visible(false)
	_hide_result_overlay()
	reset_transition_fade()


func open_deck_setup(
	card_catalog: Resource,
	deck_budget: int,
	player_rank: int,
	collection_backend,
	acquisition_policy: Resource
) -> void:
	if _root != null:
		_root.visible = true
	set_match_skin_visible(false)
	_hide_result_overlay()
	if _deck_setup != null:
		_deck_setup.call(
			"open_setup",
			card_catalog,
			deck_budget,
			player_rank,
			collection_backend,
			acquisition_policy
		)


func close_session_surfaces() -> void:
	close_reward()
	if _debug_menu != null:
		_debug_menu.call("close_menu")
	close_deck_setup()
	close_surrender_confirm()
	reset_transition_fade()
	_hide_result_overlay()
	set_match_skin_visible(false)
	if _root != null:
		_root.visible = false


func prepare_new_match() -> void:
	close_surrender_confirm()
	set_match_skin_visible(true)
	close_reward()
	_hide_result_overlay()
	reset_transition_fade()
	if _message_label != null:
		_message_label.text = ""
	if _help_label != null:
		_help_label.text = ""


func set_match_skin_visible(enabled: bool) -> void:
	if _backdrop != null: _backdrop.visible = false
	if _match_hud != null:
		_match_hud.visible = enabled
	if not enabled:
		_hide_result_overlay()


func reset_transition_fade() -> void:
	if _animation_director != null and _transition_fade != null:
		_animation_director.call("reset_transition_fade", _transition_fade)


func show_result(winner: int, surrendered: bool) -> void:
	if _result_label != null:
		_result_label.text = result_text_for(winner, surrendered)
		_result_label.visible = true
	if _result_dim != null:
		_result_dim.visible = true
	if _turn_label != null:
		_turn_label.text = ""
	if _help_label != null:
		_help_label.text = "K: Continue"
	if _selection_arrow != null:
		_selection_arrow.visible = false
	if _turn_arrow != null:
		_turn_arrow.visible = false


func begin_result_transition_ui() -> void:
	if _help_label != null:
		_help_label.text = ""


func hide_result_overlay() -> void:
	_hide_result_overlay()


func open_reward(
	opponent_cards: Array,
	player_cards: Array,
	winner: int,
	allow_interaction: bool,
	opponent_take_index: int,
	eligible_reward_ids: PackedStringArray,
	animate_entrance: bool = true
) -> void:
	if _reward_view == null:
		return
	_reward_view.call(
		"open_reward",
		opponent_cards,
		player_cards,
		winner,
		allow_interaction,
		opponent_take_index,
		eligible_reward_ids
	)
	if animate_entrance:
		_reward_view.call("start_entrance")


func close_reward() -> void:
	if _reward_view != null:
		_reward_view.call("close_reward")


func resolve_reward_transfer(success: bool) -> void:
	if _reward_view != null:
		_reward_view.call("resolve_transfer_request", success)


func close_deck_setup() -> void:
	if _deck_setup != null:
		_deck_setup.call("close_setup")


func open_surrender_confirm() -> bool:
	if _surrender_confirm == null:
		return false
	_surrender_confirm.call("open_confirm")
	return true


func close_surrender_confirm() -> void:
	if _surrender_confirm != null:
		_surrender_confirm.call("close_confirm")


func move_surrender_selection() -> void:
	if _surrender_confirm != null:
		_surrender_confirm.call("move_selection", 1)


func is_surrender_yes_selected() -> bool:
	return (
		_surrender_confirm != null
		and bool(_surrender_confirm.call("is_yes_selected"))
	)


func has_surrender_confirm() -> bool:
	return _surrender_confirm != null


func refresh_match_state(
	phase: int,
	round_number: int,
	match_backend,
	selected_hand_index: int,
	top_message: String,
	region_trait_text: String,
	help_entries: Array,
	score: Dictionary
) -> int:
	if _selection_arrow != null:
		_selection_arrow.visible = false
	if _turn_arrow != null:
		_turn_arrow.visible = false
	if _info_panel != null:
		_info_panel.visible = false
	if _turn_label != null:
		_turn_label.text = ""
	if _info_label != null:
		_info_label.text = ""
	if _help_label != null:
		_help_label.text = ""

	var resolved_index := selected_hand_index
	if phase_uses_player_selection(phase) and match_backend != null:
		resolved_index = _update_player_selection_marker(
			match_backend,
			selected_hand_index
		)
	elif phase == PHASE_AI:
		_turn_arrow_for_owner(OWNER_OPPONENT)

	_refresh_match_hud(
		phase,
		round_number,
		match_backend,
		resolved_index,
		top_message,
		region_trait_text,
		help_entries,
		score
	)
	return resolved_index


func result_text_for(winner: int, surrendered: bool) -> String:
	match winner:
		OWNER_PLAYER:
			return "YOU WIN!"
		OWNER_OPPONENT:
			return "YOU SURRENDER..." if surrendered else "YOU LOSE..."
		_:
			return "DRAW"


func turn_text_for_phase(phase: int) -> String:
	match phase:
		PHASE_SELECT_CARD, PHASE_SELECT_CELL:
			return "Your Turn"
		PHASE_AI:
			return "Opponent Turn"
		PHASE_DEALING:
			return "Dealing"
		PHASE_RESULT:
			return "Result"
		_:
			return ""


func phase_uses_player_selection(phase: int) -> bool:
	return phase in [PHASE_SELECT_CARD, PHASE_SELECT_CELL]


func _apply_authored_layout() -> void:
	preload("res://scripts/ui/triple_triad_portrait_layout.gd").battle(_root)
	if _grid_artwork != null:
		_grid_artwork.visible = false
	if _info_panel != null:
		_info_panel.visible = false
		_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _opponent_score_digits != null:
		var opponent_score_parent := _opponent_score_digits.get_parent() as CanvasItem
		if opponent_score_parent != null:
			opponent_score_parent.visible = false
	if _player_score_digits != null:
		var player_score_parent := _player_score_digits.get_parent() as CanvasItem
		if player_score_parent != null:
			player_score_parent.visible = false
	if _message_label != null:
		_message_label.visible = false
	if _help_label != null:
		_help_label.visible = false
	if _backdrop != null:
		_backdrop.z_index = -100


func _build_runtime_surfaces() -> void:
	if _root == null:
		return
	if _match_hud == null:
		_match_hud = MatchHUDScene.instantiate() as Control
		if _match_hud != null:
			_match_hud.z_index = 580
			_root.add_child(_match_hud)
			_match_hud.visible = false

	if _result_dim == null:
		_result_dim = ColorRect.new()
		_result_dim.name = "ResultDim"
		_result_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_result_dim.color = RESULT_DIM_COLOR
		_result_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_result_dim.z_index = 790
		_result_dim.visible = false
		_root.add_child(_result_dim)

	if _result_label != null:
		_result_label.add_theme_font_size_override("font_size", 40)
		_result_label.add_theme_constant_override("outline_size", 7)

	if _surrender_confirm == null:
		var instance = SurrenderConfirmScene.instantiate()
		if instance is Control:
			_surrender_confirm = instance as Control
			_surrender_confirm.z_index = 4000
			_root.add_child(_surrender_confirm)
			_surrender_confirm.call("close_confirm")


func _hide_result_overlay() -> void:
	if _result_label != null:
		_result_label.visible = false
	if _result_dim != null:
		_result_dim.visible = false


func _refresh_match_hud(
	phase: int,
	round_number: int,
	match_backend,
	selected_hand_index: int,
	top_message: String,
	region_trait_text: String,
	help_entries: Array,
	score: Dictionary
) -> void:
	if _match_hud == null:
		return

	_match_hud.call(
		"set_scores",
		int(score.get("opponent", 0)),
		int(score.get("player", 0))
	)
	_match_hud.call("set_turn_text", turn_text_for_phase(phase))
	var top_info_text := top_message.strip_edges()
	if top_info_text.is_empty():
		top_info_text = region_trait_text
	_match_hud.call("set_top_info_text", top_info_text)
	_match_hud.call("set_round_number", round_number)
	_match_hud.call("set_help_entries", help_entries)

	if (
		match_backend != null
		and phase not in [PHASE_RESULT, PHASE_REWARD, PHASE_CLOSED]
		and not match_backend.player_hand.is_empty()
	):
		var clamped_index := clampi(
			selected_hand_index,
			0,
			match_backend.player_hand.size() - 1
		)
		var selected_card = match_backend.player_hand[clamped_index]
		var selected_rotation: int = match_backend.get_hand_rotation(
			OWNER_PLAYER,
			clamped_index
		)
		_match_hud.call("set_card_info", selected_card, selected_rotation)
	else:
		_match_hud.call("clear_card_info")


func _update_player_selection_marker(
	match_backend,
	selected_hand_index: int
) -> int:
	if match_backend == null or match_backend.player_hand.is_empty():
		return selected_hand_index
	var resolved_index := clampi(
		selected_hand_index,
		0,
		match_backend.player_hand.size() - 1
	)
	if _selection_arrow != null and _player_hand_container != null:
		_selection_arrow.visible = true
		_selection_arrow.position = Vector2(
			_player_hand_container.position.x - 16.0,
			_player_hand_container.position.y
			+ float(resolved_index) * HAND_STEP_Y
			+ 44.0
		)
	_turn_arrow_for_owner(OWNER_PLAYER)
	return resolved_index


func _turn_arrow_for_owner(turn_owner: int) -> void:
	if _turn_arrow == null:
		return
	_turn_arrow.visible = true
	_turn_arrow.position = (
		Vector2(58.0, 31.0)
		if turn_owner == OWNER_OPPONENT
		else Vector2(574.0, 31.0)
	)
