extends RefCounted

const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")
const SessionControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_session_controller.gd"
)

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const PHASE_SELECT_CARD := SessionControllerScript.PHASE_SELECT_CARD
const PHASE_SELECT_CELL := SessionControllerScript.PHASE_SELECT_CELL

const HAND_STEP_Y := 140.0
const HAND_SELECTED_X_OFFSET := -8.0
const PREVIEW_GHOST_ALPHA := 0.72
const PREVIEW_INFLUENCE_COLOR := Color(1.0, 0.76, 0.18, 0.28)
const PREVIEW_PRESSURE_COLOR := Color(1.0, 0.24, 0.20, 0.34)
const ACTIVE_INFLUENCE_PLAYER_FILL := Color(0.18, 0.48, 1.0, 0.13)
const ACTIVE_INFLUENCE_PLAYER_BORDER := Color(0.28, 0.68, 1.0, 0.90)
const ACTIVE_INFLUENCE_OPPONENT_FILL := Color(1.0, 0.18, 0.16, 0.13)
const ACTIVE_INFLUENCE_OPPONENT_BORDER := Color(1.0, 0.34, 0.24, 0.90)
const ACTIVE_INFLUENCE_BOTH_FILL := Color(0.78, 0.34, 0.92, 0.14)
const ACTIVE_INFLUENCE_BOTH_BORDER := Color(0.96, 0.62, 1.0, 0.92)

# CardView's authored internal layout stays 116x132 at native integer scale.
# The canonical portrait board and both hands share exactly this footprint.
const CARD_BASE_SIZE := Vector2(116.0, 132.0)
const CARD_VISUAL_SIZE := Vector2(116.0, 132.0)
const CARD_VISUAL_SCALE := Vector2(
	CARD_VISUAL_SIZE.x / CARD_BASE_SIZE.x,
	CARD_VISUAL_SIZE.y / CARD_BASE_SIZE.y
)

var _root: Control = null
var _opponent_hand_container: Control = null
var _board_container: GridContainer = null
var _player_hand_container: Control = null

var _player_views: Array = []
var _opponent_views: Array = []
var _board_views: Array = []
var _preview_ghost: Control = null
var _influence_preview_overlays: Array[ColorRect] = []
var _active_influence_overlays: Array[Panel] = []


func initialize(
	root: Control,
	opponent_hand_container: Control,
	board_container: GridContainer,
	player_hand_container: Control
) -> void:
	_root = root
	_opponent_hand_container = opponent_hand_container
	_board_container = board_container
	_player_hand_container = player_hand_container
	_build_views()


func get_player_views() -> Array:
	return _player_views


func get_opponent_views() -> Array:
	return _opponent_views


func get_board_views() -> Array:
	return _board_views


func get_player_view(index: int) -> Control:
	if index < 0 or index >= _player_views.size():
		return null
	return _player_views[index] as Control


func get_opponent_view(index: int) -> Control:
	if index < 0 or index >= _opponent_views.size():
		return null
	return _opponent_views[index] as Control


func get_board_view(index: int) -> Control:
	if index < 0 or index >= _board_views.size():
		return null
	return _board_views[index] as Control


func board_cell_visual_rect(cell_index: int) -> Rect2:
	if _board_container == null or cell_index < 0 or cell_index >= _board_views.size():
		return Rect2()
	var view: Control = _board_views[cell_index]
	return Rect2(
		_board_container.position + view.position * _board_container.scale,
		view.size * _board_container.scale
	)


func refresh(
	match_state,
	phase: int,
	active_rule_set: Resource,
	selected_hand_index: int,
	selected_cell_index: int,
	captured_cells: Array = []
) -> void:
	if match_state == null:
		return
	var show_opponent_cards: bool = (
		active_rule_set == null
		or bool(active_rule_set.open_rule)
	)
	var active_preview: Dictionary = _preview_for_current_selection(
		match_state,
		phase,
		selected_hand_index,
		selected_cell_index
	)
	var preview_modifiers: Dictionary = active_preview.get(
		"influence_modifiers",
		{}
	)
	# Build current board pressure once per UI refresh. Input-driven refreshes are
	# cheap and deterministic; we never rebuild influence state per frame.
	var current_influence_modifiers: Dictionary = (
		{}
		if not active_preview.is_empty()
		else match_state.get_current_influence_modifiers()
	)

	for index in range(_opponent_views.size()):
		var view: Control = _opponent_views[index]
		view.modulate = Color.WHITE
		view.scale = CARD_VISUAL_SCALE
		if index < match_state.opponent_hand.size():
			view.visible = true
			view.configure(
				match_state.opponent_hand[index],
				OWNER_OPPONENT,
				not show_opponent_cards,
				false,
				match_state.get_hand_rotation(OWNER_OPPONENT, index),
				0
			)
			# Ownership is now always readable without baking blue/red variants into
			# every authored card image. Hidden opponent cards keep their red edge.
			view.set_owner_outline_visible(owner_outline_visible_for(OWNER_OPPONENT, true))
			view.set_selected(false)
			view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
			view.z_index = index
		else:
			view.visible = false

	for index in range(_player_views.size()):
		var view: Control = _player_views[index]
		view.modulate = Color.WHITE
		view.scale = CARD_VISUAL_SCALE
		if index < match_state.player_hand.size():
			view.visible = true
			view.configure(
				match_state.player_hand[index],
				OWNER_PLAYER,
				false,
				false,
				match_state.get_hand_rotation(OWNER_PLAYER, index),
				0
			)
			view.set_owner_outline_visible(owner_outline_visible_for(OWNER_PLAYER, true))
			var is_selected: bool = (
				phase in [PHASE_SELECT_CARD, PHASE_SELECT_CELL]
				and index == selected_hand_index
			)
			# Selection stays on the side arrow + nudge. The border is reserved for
			# ownership, so it remains blue instead of changing to yellow.
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
		var slot_variant = match_state.board[cell_index]
		if slot_variant == null:
			board_view.configure(null, OWNER_NONE, false)
			board_view.set_owner_outline_visible(false)
		else:
			var slot: Dictionary = slot_variant
			var slot_owner: int = int(slot["owner"])
			var influence_modifier: int = (
				int(preview_modifiers.get(cell_index, 0))
				if not active_preview.is_empty()
				else int(current_influence_modifiers.get(cell_index, 0))
			)
			board_view.configure(
				slot["card"],
				slot_owner,
				false,
				captured_cells.has(cell_index),
				int(slot.get("rotation", 0)),
				match_state.get_cell_rank_bonus(cell_index) + influence_modifier
			)
			# This is the important ownership read: placed/captured cards stay blue
			# or red according to their current owner, including after capture flips.
			board_view.set_owner_outline_visible(owner_outline_visible_for(slot_owner, true))
		board_view.set_selected(
			phase == PHASE_SELECT_CELL
			and cell_index == selected_cell_index
		)

	_refresh_active_influence_visuals(match_state)
	_refresh_preview_visuals(
		match_state,
		active_preview,
		selected_hand_index,
		selected_cell_index
	)


# Pure policy seam used by QA and by future presentation variants. Empty slots
# never display ownership; any real player/opponent card does.
func get_placement_preview(
	match_state,
	phase: int,
	selected_hand_index: int,
	selected_cell_index: int
) -> Dictionary:
	return _preview_for_current_selection(
		match_state,
		phase,
		selected_hand_index,
		selected_cell_index
	)


func owner_outline_visible_for(owner: int, has_card: bool = true) -> bool:
	return has_card and owner in [OWNER_PLAYER, OWNER_OPPONENT]


func owner_outline_kind(owner: int, has_card: bool = true) -> StringName:
	if not owner_outline_visible_for(owner, has_card):
		return &"none"
	return &"player" if owner == OWNER_PLAYER else &"opponent"


func _build_views() -> void:
	if (
		_root == null
		or _opponent_hand_container == null
		or _board_container == null
		or _player_hand_container == null
	):
		return

	for index in range(5):
		var opponent_view: Control = CardViewScene.instantiate() as Control
		_opponent_hand_container.add_child(opponent_view)
		# CardView centers its pivot for flip animations. Hand cards are scaled, so
		# reset the pivot here to keep their visible top-left aligned to the baked
		# card backs instead of shrinking inward by ~20 px.
		opponent_view.pivot_offset = Vector2.ZERO
		opponent_view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
		opponent_view.scale = CARD_VISUAL_SCALE
		opponent_view.z_index = index
		_opponent_views.append(opponent_view)

	for _index in range(9):
		var board_view: Control = CardViewScene.instantiate() as Control
		_board_container.add_child(board_view)
		_board_views.append(board_view)

	for index in range(5):
		var player_view: Control = CardViewScene.instantiate() as Control
		_player_hand_container.add_child(player_view)
		player_view.pivot_offset = Vector2.ZERO
		player_view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
		player_view.scale = CARD_VISUAL_SCALE
		player_view.z_index = index
		_player_views.append(player_view)

	_build_preview_visuals()


func _build_preview_visuals() -> void:
	_preview_ghost = CardViewScene.instantiate() as Control
	_root.add_child(_preview_ghost)
	_preview_ghost.visible = false
	_preview_ghost.pivot_offset = Vector2.ZERO
	_preview_ghost.modulate = Color(1, 1, 1, PREVIEW_GHOST_ALPHA)
	_preview_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_ghost.z_index = 620

	_influence_preview_overlays.clear()
	for _cell_index in range(9):
		var overlay := ColorRect.new()
		overlay.visible = false
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.z_index = 610
		_root.add_child(overlay)
		_influence_preview_overlays.append(overlay)

	_active_influence_overlays.clear()
	for _cell_index in range(9):
		var active_overlay := Panel.new()
		active_overlay.visible = false
		active_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		active_overlay.z_index = 608
		_root.add_child(active_overlay)
		_active_influence_overlays.append(active_overlay)


func hide_preview_visuals() -> void:
	_hide_preview_visuals()


func _hide_preview_visuals() -> void:
	if is_instance_valid(_preview_ghost):
		_preview_ghost.visible = false
	for overlay in _influence_preview_overlays:
		if is_instance_valid(overlay):
			overlay.visible = false


func _refresh_active_influence_visuals(match_state) -> void:
	for overlay in _active_influence_overlays:
		if is_instance_valid(overlay):
			overlay.visible = false
	if (
		match_state == null
		or not match_state.has_method("get_influence_board_snapshot")
	):
		return

	var influence_snapshot: Array = match_state.call(
		"get_influence_board_snapshot"
	)
	for cell_index in range(
		mini(
			influence_snapshot.size(),
			_active_influence_overlays.size()
		)
	):
		var cell_state: Dictionary = influence_snapshot[cell_index]
		var player_pressure: int = int(
			cell_state.get("player_pressure", 0)
		)
		var opponent_pressure: int = int(
			cell_state.get("opponent_pressure", 0)
		)
		if player_pressure <= 0 and opponent_pressure <= 0:
			continue

		var overlay: Panel = _active_influence_overlays[cell_index]
		var board_rect: Rect2 = board_cell_visual_rect(cell_index)
		overlay.position = board_rect.position
		overlay.size = board_rect.size
		overlay.add_theme_stylebox_override(
			"panel",
			_active_influence_style(
				player_pressure > 0,
				opponent_pressure > 0
			)
		)
		overlay.visible = true


func _active_influence_style(
	has_player_pressure: bool,
	has_opponent_pressure: bool
) -> StyleBoxFlat:
	var fill: Color = ACTIVE_INFLUENCE_PLAYER_FILL
	var border: Color = ACTIVE_INFLUENCE_PLAYER_BORDER
	if has_player_pressure and has_opponent_pressure:
		fill = ACTIVE_INFLUENCE_BOTH_FILL
		border = ACTIVE_INFLUENCE_BOTH_BORDER
	elif has_opponent_pressure:
		fill = ACTIVE_INFLUENCE_OPPONENT_FILL
		border = ACTIVE_INFLUENCE_OPPONENT_BORDER

	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.set_corner_radius_all(2)
	return style


func _preview_for_current_selection(
	match_state,
	phase: int,
	selected_hand_index: int,
	selected_cell_index: int
) -> Dictionary:
	if (
		phase != PHASE_SELECT_CELL
		or match_state == null
		or selected_hand_index < 0
		or selected_hand_index >= match_state.player_hand.size()
		or selected_cell_index < 0
		or selected_cell_index >= 9
		or match_state.board[selected_cell_index] != null
	):
		return {}
	var card = match_state.player_hand[selected_hand_index]
	var rotation_quarters: int = match_state.get_hand_rotation(
		OWNER_PLAYER,
		selected_hand_index
	)
	return match_state.preview_move(
		card,
		OWNER_PLAYER,
		selected_cell_index,
		rotation_quarters
	)


func _refresh_preview_visuals(
	match_state,
	preview: Dictionary,
	selected_hand_index: int,
	selected_cell_index: int
) -> void:
	_hide_preview_visuals()
	if preview.is_empty() or not bool(preview.get("valid", false)):
		return
	if (
		selected_hand_index < 0
		or selected_hand_index >= match_state.player_hand.size()
	):
		return

	var card = match_state.player_hand[selected_hand_index]
	var rotation_quarters: int = match_state.get_hand_rotation(
		OWNER_PLAYER,
		selected_hand_index
	)
	var target_view: Control = get_board_view(selected_cell_index)
	if target_view == null:
		return
	var target_rect: Rect2 = board_cell_visual_rect(selected_cell_index)
	_preview_ghost.visible = true
	_preview_ghost.modulate = Color(1, 1, 1, PREVIEW_GHOST_ALPHA)
	_preview_ghost.position = target_rect.position
	_preview_ghost.size = target_view.size
	_preview_ghost.scale = _board_container.scale
	_preview_ghost.configure(
		card,
		OWNER_PLAYER,
		false,
		false,
		rotation_quarters,
		int(preview.get("placed_total_modifier", 0))
	)
	_preview_ghost.set_owner_outline_visible(owner_outline_visible_for(OWNER_PLAYER, true))
	_preview_ghost.set_selected(false)

	for raw_cell in preview.get("influence_cells", []):
		var cell_index: int = int(raw_cell)
		if (
			cell_index < 0
			or cell_index >= _influence_preview_overlays.size()
		):
			continue
		var overlay: ColorRect = _influence_preview_overlays[cell_index]
		var board_rect: Rect2 = board_cell_visual_rect(cell_index)
		overlay.position = board_rect.position
		overlay.size = board_rect.size
		var slot_variant = match_state.board[cell_index]
		var pressures_enemy: bool = false
		if slot_variant != null:
			var preview_slot: Dictionary = slot_variant
			pressures_enemy = (
				int(preview_slot.get("owner", OWNER_NONE))
				== OWNER_OPPONENT
			)
		overlay.color = (
			PREVIEW_PRESSURE_COLOR
			if pressures_enemy
			else PREVIEW_INFLUENCE_COLOR
		)
		overlay.visible = true
