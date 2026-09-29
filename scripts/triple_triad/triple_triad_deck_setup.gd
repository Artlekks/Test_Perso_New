extends Control

signal deck_confirmed(cards: Array)
signal cancelled

const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")

const OWNER_PLAYER := 1
const PROFILE_COUNT := 6
const HAND_SIZE := 5
const COLLECTION_COLUMNS := 5
const COLLECTION_ROWS := 3
const PAGE_SIZE := COLLECTION_COLUMNS * COLLECTION_ROWS
const COLLECTION_SCALE := Vector2(0.62, 0.62)
const COLLECTION_STEP_X := 76.0
const COLLECTION_STEP_Y := 91.0
const DECK_SCALE := Vector2(0.58, 0.58)
const DECK_STEP_Y := 61.0
const SAVE_PATH := "user://triple_triad_decks.cfg"

const STATE_BROWSE := 0
const STATE_REPLACE := 1
const STATE_ANIMATING := 2

const COLLECTION_FOCUS_SCALE := Vector2(0.66, 0.66)
const COLLECTION_FOCUS_Y := -5.0
const DECK_SLOT_SIZE := Vector2(74.0, 61.0)
const DECK_CARD_OFFSET := Vector2(3.0, 0.0)
const DECK_SELECTED_X_OFFSET := -7.0
const USED_CARD_MODULATE := Color(0.38, 0.38, 0.38, 1.0)
const CARD_TRANSFER_LIFT_Y := 60.0
const CARD_TRANSFER_LIFT_SECONDS := 0.22
const CARD_TRANSFER_DROP_SECONDS := 0.16

@onready var collection_root: Control = $CollectionRoot
@onready var deck_root: Control = $DeckRoot
@onready var title_label: Label = $InfoPanel/TitleLabel
@onready var profile_label: Label = $DeckPanel/ProfileLabel
@onready var rank_label: Label = $DeckPanel/RankLabel
@onready var card_count_label: Label = $DeckPanel/CardCountLabel
@onready var points_label: Label = $DeckPanel/PointsLabel
@onready var page_label: Label = $CollectionPanel/PageLabel
@onready var card_info_label: Label = $CardInfoLabel
@onready var status_label: Label = $StatusLabel
@onready var help_label: Label = $HelpLabel
@onready var collection_arrow: Polygon2D = $CollectionArrow
@onready var deck_arrow: Polygon2D = $DeckArrow

var _catalog: Resource = null
var _collection_backend = null
var _cards: Array = []
var _deck: Array = []
var _collection_views: Array = []
var _deck_views: Array = []
var _deck_slot_panels: Array = []
var _profile_index: int = 0
var _page_index: int = 0
var _cursor_index: int = 0
var _budget_limit: int = 30
var _player_rank: int = 6
var _status_text: String = ""
var _state: int = STATE_BROWSE
var _replace_card = null
var _replace_source_index: int = -1
var _replace_slot_index: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_views()


func open_setup(catalog: Resource, budget_limit: int, player_rank: int = 6, collection_backend = null) -> void:
	_catalog = catalog
	_collection_backend = collection_backend
	_budget_limit = maxi(5, budget_limit)
	_player_rank = maxi(1, player_rank)
	_cards.clear()
	if _collection_backend != null and _collection_backend.has_method("get_owned_cards"):
		_cards = _collection_backend.call("get_owned_cards")
	elif _catalog != null and _catalog.has_method("get_cards_for_level_range"):
		_cards = _catalog.call("get_cards_for_level_range", 1, 10)
	_profile_index = _load_last_profile_index()
	_load_profile(_profile_index)
	_cursor_index = 0
	_page_index = 0
	_status_text = ""
	_state = STATE_BROWSE
	_replace_card = null
	_replace_source_index = -1
	_replace_slot_index = 0
	visible = true
	_refresh_all()


func close_setup() -> void:
	if visible:
		_save_current_profile()
	_state = STATE_BROWSE
	_replace_card = null
	_replace_source_index = -1
	collection_arrow.visible = false
	deck_arrow.visible = false
	visible = false


func is_active() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _pressed(event):
		return

	if _state == STATE_ANIMATING:
		_accept_input()
		return

	if _state == STATE_REPLACE:
		if _is_up(event):
			_move_replace_slot(-1)
			_accept_input()
			return
		if _is_down(event):
			_move_replace_slot(1)
			_accept_input()
			return
		if _is_confirm(event):
			_confirm_replacement()
			_accept_input()
			return
		if _is_back(event):
			_cancel_replacement()
			_accept_input()
			return
		_accept_input()
		return

	var profile_number: int = _profile_number(event)
	if profile_number >= 0:
		_switch_profile(profile_number)
		_accept_input()
		return

	if _is_page_previous(event):
		_change_page(-1)
		_accept_input()
		return
	if _is_page_next(event):
		_change_page(1)
		_accept_input()
		return

	if _is_left(event):
		_move_cursor(-1, 0)
		_accept_input()
		return
	if _is_right(event):
		_move_cursor(1, 0)
		_accept_input()
		return
	if _is_up(event):
		_move_cursor(0, -1)
		_accept_input()
		return
	if _is_down(event):
		_move_cursor(0, 1)
		_accept_input()
		return

	if _is_confirm(event):
		_select_cursor_card()
		_accept_input()
		return

	if _is_start(event):
		_try_confirm_deck()
		_accept_input()
		return

	if _is_back(event):
		_save_current_profile()
		cancelled.emit()
		_accept_input()

func _build_views() -> void:
	for index in range(PAGE_SIZE):
		var view: Control = CardViewScene.instantiate() as Control
		collection_root.add_child(view)
		view.pivot_offset = Vector2.ZERO
		view.scale = COLLECTION_SCALE
		view.position = Vector2(
			float(index % COLLECTION_COLUMNS) * COLLECTION_STEP_X,
			float(floori(float(index) / float(COLLECTION_COLUMNS))) * COLLECTION_STEP_Y
		)
		view.z_index = 20 + index
		_collection_views.append(view)

	for index in range(HAND_SIZE):
		var slot_panel := Panel.new()
		slot_panel.position = Vector2(0.0, float(index) * DECK_STEP_Y)
		slot_panel.size = DECK_SLOT_SIZE
		slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck_root.add_child(slot_panel)
		_deck_slot_panels.append(slot_panel)

		var deck_view: Control = CardViewScene.instantiate() as Control
		deck_root.add_child(deck_view)
		deck_view.pivot_offset = Vector2.ZERO
		deck_view.scale = DECK_SCALE
		deck_view.position = DECK_CARD_OFFSET + Vector2(0.0, float(index) * DECK_STEP_Y)
		deck_view.z_index = 20 + index
		_deck_views.append(deck_view)

	_refresh_slot_styles()

func _refresh_all() -> void:
	_refresh_collection()
	_refresh_deck()
	_refresh_labels()


func _refresh_collection() -> void:
	var page_start: int = _page_index * PAGE_SIZE
	collection_arrow.visible = false
	for local_index in range(_collection_views.size()):
		var view: Control = _collection_views[local_index]
		var card_index: int = page_start + local_index
		if card_index >= 0 and card_index < _cards.size():
			var card = _cards[card_index]
			view.visible = true
			view.configure(card, OWNER_PLAYER, false)
			view.pivot_offset = Vector2.ZERO
			var is_in_deck: bool = _deck_has_card(card)
			view.modulate = USED_CARD_MODULATE if is_in_deck else Color.WHITE
			var is_cursor: bool = card_index == _cursor_index
			var is_replace_source: bool = _state == STATE_REPLACE and card_index == _replace_source_index
			view.scale = COLLECTION_FOCUS_SCALE if is_replace_source else COLLECTION_SCALE
			var base_position := Vector2(
				float(local_index % COLLECTION_COLUMNS) * COLLECTION_STEP_X,
				float(floori(float(local_index) / float(COLLECTION_COLUMNS))) * COLLECTION_STEP_Y
			)
			view.position = base_position + (
				Vector2(0.0, COLLECTION_FOCUS_Y) if is_replace_source else Vector2.ZERO
			)
			view.set_selected(is_cursor or is_replace_source)
			if is_replace_source:
				collection_arrow.visible = true
				collection_arrow.position = collection_root.position + view.position + Vector2(
					(view.size.x * view.scale.x) * 0.5 - 6.0,
					-12.0
				)
		else:
			view.modulate = Color.WHITE
			view.visible = false

func _refresh_deck() -> void:
	deck_arrow.visible = _state == STATE_REPLACE
	for index in range(_deck_views.size()):
		var view: Control = _deck_views[index]
		view.pivot_offset = Vector2.ZERO
		var is_replace_target: bool = _state == STATE_REPLACE and index == _replace_slot_index
		view.position = DECK_CARD_OFFSET + Vector2(
			DECK_SELECTED_X_OFFSET if is_replace_target else 0.0,
			float(index) * DECK_STEP_Y
		)
		if index < _deck.size():
			view.visible = true
			view.configure(_deck[index], OWNER_PLAYER, false)
			view.scale = DECK_SCALE
			view.set_selected(is_replace_target)
		else:
			view.visible = false

	_refresh_slot_styles()
	if _state == STATE_REPLACE:
		deck_arrow.position = deck_root.position + Vector2(
			-14.0,
			float(_replace_slot_index) * DECK_STEP_Y + 26.0
		)

func _refresh_labels() -> void:
	title_label.text = "Choose your deck"
	profile_label.text = "Deck %d / %d" % [_profile_index + 1, PROFILE_COUNT]
	rank_label.text = "Rank %d" % _player_rank
	card_count_label.text = "Cards %d / %d" % [_deck.size(), HAND_SIZE]
	points_label.text = "Points %d / %d" % [_deck_cost(), _budget_limit]
	page_label.text = "Cards  %d / %d" % [_page_index + 1, _page_count()]
	status_label.text = _status_text

	if _cursor_index >= 0 and _cursor_index < _cards.size():
		var card = _cards[_cursor_index]
		var membership: String = "   IN DECK" if _deck_has_card(card) else ""
		card_info_label.text = "%s   Cost %d%s" % [
			str(card.display_name),
			int(card.deck_cost),
			membership,
		]
	else:
		card_info_label.text = ""

	if _state == STATE_REPLACE:
		help_label.text = "W/S: Deck slot   K: Replace   I: Cancel"
	else:
		help_label.text = "W/A/S/D: Card   K: Select   Q/E: Page   1-6: Deck   Enter: Play   I: Leave"


func _move_cursor(dx: int, dy: int) -> void:
	if _cards.is_empty():
		return
	var page_start: int = _page_index * PAGE_SIZE
	var page_count: int = mini(PAGE_SIZE, _cards.size() - page_start)
	if page_count <= 0:
		return
	var local_index: int = clampi(_cursor_index - page_start, 0, page_count - 1)
	var column: int = local_index % COLLECTION_COLUMNS
	var row: int = floori(float(local_index) / float(COLLECTION_COLUMNS))
	column = clampi(column + dx, 0, COLLECTION_COLUMNS - 1)
	row = clampi(row + dy, 0, COLLECTION_ROWS - 1)
	var target_local: int = row * COLLECTION_COLUMNS + column
	if target_local >= page_count:
		target_local = page_count - 1
	_cursor_index = page_start + target_local
	_status_text = ""
	_refresh_collection()
	_refresh_labels()


func _change_page(direction: int) -> void:
	var count: int = _page_count()
	if count <= 1:
		return
	var old_local: int = _cursor_index - _page_index * PAGE_SIZE
	_page_index = wrapi(_page_index + direction, 0, count)
	var page_start: int = _page_index * PAGE_SIZE
	var items_on_page: int = mini(PAGE_SIZE, _cards.size() - page_start)
	_cursor_index = page_start + clampi(old_local, 0, maxi(items_on_page - 1, 0))
	_status_text = ""
	_refresh_all()


func _select_cursor_card() -> void:
	if _cursor_index < 0 or _cursor_index >= _cards.size():
		return

	var card = _cards[_cursor_index]
	if _deck_has_card(card):
		_status_text = "That card is already in this deck."
		_refresh_labels()
		return

	if _deck.size() < HAND_SIZE:
		var next_cost: int = _deck_cost() + int(card.deck_cost)
		if next_cost > _budget_limit:
			_status_text = "Point limit exceeded: %d / %d" % [next_cost, _budget_limit]
			_refresh_labels()
			return
		var target_slot: int = _deck.size()
		_animate_add_to_deck(card, _cursor_index, target_slot)
		return

	_replace_card = card
	_replace_source_index = _cursor_index
	_replace_slot_index = clampi(_replace_slot_index, 0, HAND_SIZE - 1)
	_state = STATE_REPLACE
	_status_text = "Choose the deck card to replace."
	_refresh_all()


func _move_replace_slot(direction: int) -> void:
	_replace_slot_index = wrapi(_replace_slot_index + direction, 0, HAND_SIZE)
	_status_text = "Choose the deck card to replace."
	_refresh_deck()
	_refresh_labels()


func _cancel_replacement() -> void:
	_state = STATE_BROWSE
	_replace_card = null
	_replace_source_index = -1
	_status_text = ""
	_refresh_all()


func _confirm_replacement() -> void:
	if _replace_card == null or _replace_slot_index < 0 or _replace_slot_index >= _deck.size():
		_cancel_replacement()
		return

	var old_card = _deck[_replace_slot_index]
	var next_cost: int = _deck_cost() - int(old_card.deck_cost) + int(_replace_card.deck_cost)
	if next_cost > _budget_limit:
		_status_text = "Point limit exceeded: %d / %d" % [next_cost, _budget_limit]
		_refresh_labels()
		return

	_animate_replace_deck_card(_replace_card, _replace_source_index, _replace_slot_index)


func _animate_add_to_deck(card, source_index: int, target_slot: int) -> void:
	_state = STATE_ANIMATING
	_status_text = ""
	_refresh_all()
	await _animate_card_transfer(card, source_index, target_slot)
	_deck.append(card)
	_save_current_profile()
	_state = STATE_BROWSE
	_status_text = "Added to deck."
	_refresh_all()


func _animate_replace_deck_card(card, source_index: int, target_slot: int) -> void:
	_state = STATE_ANIMATING
	_status_text = ""
	_refresh_all()
	await _animate_card_transfer(card, source_index, target_slot)
	_deck[target_slot] = card
	_save_current_profile()
	_state = STATE_BROWSE
	_replace_card = null
	_replace_source_index = -1
	_status_text = "Deck updated."
	_refresh_all()


func _animate_card_transfer(card, source_index: int, target_slot: int) -> void:
	var local_source_index: int = source_index - _page_index * PAGE_SIZE
	if local_source_index < 0 or local_source_index >= _collection_views.size():
		return

	var source_view: Control = _collection_views[local_source_index]
	if source_view == null or not is_instance_valid(source_view):
		return

	var target_view: Control = _deck_views[target_slot]
	var target_global: Vector2 = target_view.global_position
	var target_visual_scale: Vector2 = target_view.global_transform.get_scale()

	var ghost: Control = CardViewScene.instantiate() as Control
	add_child(ghost)
	ghost.configure(card, OWNER_PLAYER, false)
	ghost.pivot_offset = Vector2.ZERO
	# Keep one constant visual size for the whole transfer. The old version
	# used local scales after reparenting, which made the card visibly shrink
	# and then pop back to the deck size.
	ghost.scale = target_visual_scale
	ghost.global_position = source_view.global_position
	ghost.z_index = 1200

	var lift_global := Vector2(target_global.x, CARD_TRANSFER_LIFT_Y)

	var tween := ghost.create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		ghost,
		"global_position",
		lift_global,
		CARD_TRANSFER_LIFT_SECONDS
	)

	var drop = tween.tween_property(
		ghost,
		"global_position",
		target_global,
		CARD_TRANSFER_DROP_SECONDS
	)
	drop.set_trans(Tween.TRANS_QUAD)
	drop.set_ease(Tween.EASE_IN)
	await tween.finished
	ghost.queue_free()


func _refresh_slot_styles() -> void:
	for index in range(_deck_slot_panels.size()):
		var slot_panel: Panel = _deck_slot_panels[index]
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.05, 0.04, 0.06, 0.38)
		slot_style.border_color = Color(1.0, 0.88, 0.30, 1.0) if (
			_state == STATE_REPLACE and index == _replace_slot_index
		) else Color(0.72, 0.67, 0.54, 0.72)
		slot_style.border_width_left = 1
		slot_style.border_width_top = 1
		slot_style.border_width_right = 1
		slot_style.border_width_bottom = 1
		slot_panel.add_theme_stylebox_override("panel", slot_style)

func _try_confirm_deck() -> void:
	if _deck.size() != HAND_SIZE:
		_status_text = "Choose exactly 5 cards."
		_refresh_labels()
		return
	var total_cost: int = _deck_cost()
	if total_cost > _budget_limit:
		_status_text = "Point limit exceeded: %d / %d" % [total_cost, _budget_limit]
		_refresh_labels()
		return
	_save_current_profile()
	deck_confirmed.emit(_deck.duplicate())


func _switch_profile(new_profile_index: int) -> void:
	if new_profile_index < 0 or new_profile_index >= PROFILE_COUNT:
		return
	if new_profile_index == _profile_index:
		return
	_save_current_profile()
	_profile_index = new_profile_index
	_load_profile(_profile_index)
	_status_text = ""
	_refresh_all()


func _load_profile(profile_index: int) -> void:
	_deck.clear()
	var config := ConfigFile.new()
	var load_error: Error = config.load(SAVE_PATH)
	var had_saved_profile: bool = false

	if load_error == OK:
		var id_key: String = "deck_ids_%d" % (profile_index + 1)
		var legacy_key: String = "deck_%d" % (profile_index + 1)

		if config.has_section_key("decks", id_key):
			had_saved_profile = true
			var raw_ids = config.get_value("decks", id_key, PackedStringArray())
			if raw_ids is PackedStringArray or raw_ids is Array:
				for raw_id in raw_ids:
					if _catalog == null or not _catalog.has_method("get_card_by_id"):
						continue
					var card = _catalog.call("get_card_by_id", StringName(str(raw_id)))
					if _can_use_card(card) and not _deck_has_card(card) and _deck.size() < HAND_SIZE:
						_deck.append(card)

		elif config.has_section_key("decks", legacy_key):
			had_saved_profile = true
			var raw_indices = config.get_value("decks", legacy_key, PackedInt32Array())
			if raw_indices is PackedInt32Array or raw_indices is Array:
				for raw_index in raw_indices:
					if _catalog == null:
						continue
					var card = null
					if _catalog.has_method("get_card_by_legacy_source_index"):
						card = _catalog.call("get_card_by_legacy_source_index", int(raw_index))
					elif _catalog.has_method("get_card"):
						card = _catalog.call("get_card", int(raw_index))
					if _can_use_card(card) and not _deck_has_card(card) and _deck.size() < HAND_SIZE:
						_deck.append(card)

	# Only brand-new deck profiles are initialized automatically.
	# A profile missing a card because the player LOST it stays short so the
	# player explicitly chooses a replacement instead of silently receiving one.
	if not had_saved_profile:
		_deck = _build_default_deck()

	_save_current_profile()


func _save_current_profile() -> void:
	if _catalog == null:
		return

	var config := ConfigFile.new()
	config.load(SAVE_PATH)

	var ids := PackedStringArray()
	for card in _deck:
		if card != null and _can_use_card(card):
			ids.append(String(card.card_id))

	config.set_value("decks", "deck_ids_%d" % (_profile_index + 1), ids)
	config.set_value("meta", "last_profile", _profile_index)

	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning("TripleTriadDeckSetup: could not save deck profiles (%s)." % error_string(save_error))


func remove_card_from_all_profiles(card_id: StringName) -> void:
	if String(card_id).is_empty():
		return

	var config := ConfigFile.new()
	config.load(SAVE_PATH)

	for profile_index in range(PROFILE_COUNT):
		var id_key: String = "deck_ids_%d" % (profile_index + 1)
		var legacy_key: String = "deck_%d" % (profile_index + 1)
		var ids := PackedStringArray()

		if config.has_section_key("decks", id_key):
			var raw_ids = config.get_value("decks", id_key, PackedStringArray())
			if raw_ids is PackedStringArray or raw_ids is Array:
				for raw_id in raw_ids:
					var saved_id: String = str(raw_id)
					if saved_id != String(card_id):
						ids.append(saved_id)

		elif config.has_section_key("decks", legacy_key):
			var raw_indices = config.get_value("decks", legacy_key, PackedInt32Array())
			if raw_indices is PackedInt32Array or raw_indices is Array:
				for raw_index in raw_indices:
					if _catalog == null:
						continue
					var legacy_card = null
					if _catalog.has_method("get_card_by_legacy_source_index"):
						legacy_card = _catalog.call("get_card_by_legacy_source_index", int(raw_index))
					elif _catalog.has_method("get_card"):
						legacy_card = _catalog.call("get_card", int(raw_index))
					if legacy_card != null and String(legacy_card.card_id) != String(card_id):
						ids.append(String(legacy_card.card_id))

		config.set_value("decks", id_key, ids)

	var filtered_deck: Array = []
	for card in _deck:
		if card != null and String(card.card_id) != String(card_id):
			filtered_deck.append(card)
	_deck = filtered_deck

	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning("TripleTriadDeckSetup: could not prune deck profiles (%s)." % error_string(save_error))

	if visible:
		_refresh_all()


func _can_use_card(card) -> bool:
	if card == null:
		return false
	if _collection_backend == null or not _collection_backend.has_method("owns_card"):
		return true
	return bool(_collection_backend.call("owns_card", card))


func _load_last_profile_index() -> int:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return 0
	return clampi(int(config.get_value("meta", "last_profile", 0)), 0, PROFILE_COUNT - 1)


func _build_default_deck() -> Array:
	var sorted_cards: Array = _cards.duplicate()
	sorted_cards.sort_custom(func(card_a, card_b):
		if int(card_a.deck_cost) == int(card_b.deck_cost):
			if int(card_a.rank_total()) == int(card_b.rank_total()):
				return int(card_a.source_index) < int(card_b.source_index)
			return int(card_a.rank_total()) < int(card_b.rank_total())
		return int(card_a.deck_cost) < int(card_b.deck_cost)
	)
	var result: Array = []
	var running_cost: int = 0
	for card in sorted_cards:
		if not _can_use_card(card):
			continue
		var card_cost: int = int(card.deck_cost)
		if running_cost + card_cost > _budget_limit:
			continue
		result.append(card)
		running_cost += card_cost
		if result.size() == HAND_SIZE:
			break
	return result


func _deck_cost() -> int:
	var total: int = 0
	for card in _deck:
		if card != null:
			total += int(card.deck_cost)
	return total


func _deck_has_card(card) -> bool:
	return _deck_index_of(card) >= 0


func _deck_index_of(card) -> int:
	if card == null:
		return -1
	for index in range(_deck.size()):
		var deck_card = _deck[index]
		if deck_card != null and String(deck_card.card_id) == String(card.card_id):
			return index
	return -1


func _page_count() -> int:
	if _cards.is_empty():
		return 1
	return maxi(1, ceili(float(_cards.size()) / float(PAGE_SIZE)))


func _profile_number(event: InputEvent) -> int:
	if not (event is InputEventKey):
		return -1
	var key_event := event as InputEventKey
	match key_event.keycode:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		KEY_5:
			return 4
		KEY_6:
			return 5
		_:
			return -1


func _pressed(event: InputEvent) -> bool:
	return event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo


func _is_confirm(event: InputEvent) -> bool:
	return _key_matches(event, KEY_K)


func _is_start(event: InputEvent) -> bool:
	return _key_matches(event, KEY_ENTER)


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


func _is_page_previous(event: InputEvent) -> bool:
	return _key_matches(event, KEY_Q) or _key_matches(event, KEY_PAGEUP)


func _is_page_next(event: InputEvent) -> bool:
	return _key_matches(event, KEY_E) or _key_matches(event, KEY_PAGEDOWN)


func _key_matches(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.keycode == key or key_event.physical_keycode == key


func _accept_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
