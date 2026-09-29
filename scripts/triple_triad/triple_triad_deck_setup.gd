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
const COLLECTION_SCALE := Vector2(0.46, 0.46)
const COLLECTION_STEP_X := 76.0
const COLLECTION_STEP_Y := 94.0
const DECK_SCALE := Vector2(0.42, 0.42)
const DECK_STEP_Y := 61.0
const SAVE_PATH := "user://triple_triad_decks.cfg"

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

var _catalog: Resource = null
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_views()


func open_setup(catalog: Resource, budget_limit: int, player_rank: int = 6) -> void:
	_catalog = catalog
	_budget_limit = maxi(5, budget_limit)
	_player_rank = maxi(1, player_rank)
	_cards.clear()
	if _catalog != null and _catalog.has_method("get_cards_for_level_range"):
		_cards = _catalog.call("get_cards_for_level_range", 1, 10)
	_profile_index = _load_last_profile_index()
	_load_profile(_profile_index)
	_cursor_index = 0
	_page_index = 0
	_status_text = ""
	visible = true
	_refresh_all()


func close_setup() -> void:
	if visible:
		_save_current_profile()
	visible = false


func is_active() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _pressed(event):
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
		_toggle_cursor_card()
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
		slot_panel.size = Vector2(58.0, 57.0)
		slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.05, 0.04, 0.06, 0.38)
		slot_style.border_color = Color(0.72, 0.67, 0.54, 0.72)
		slot_style.border_width_left = 1
		slot_style.border_width_top = 1
		slot_style.border_width_right = 1
		slot_style.border_width_bottom = 1
		slot_panel.add_theme_stylebox_override("panel", slot_style)
		deck_root.add_child(slot_panel)
		_deck_slot_panels.append(slot_panel)

		var deck_view: Control = CardViewScene.instantiate() as Control
		deck_root.add_child(deck_view)
		deck_view.scale = DECK_SCALE
		deck_view.position = Vector2(2.0, float(index) * DECK_STEP_Y + 1.0)
		deck_view.z_index = 20 + index
		_deck_views.append(deck_view)


func _refresh_all() -> void:
	_refresh_collection()
	_refresh_deck()
	_refresh_labels()


func _refresh_collection() -> void:
	var page_start: int = _page_index * PAGE_SIZE
	for local_index in range(_collection_views.size()):
		var view: Control = _collection_views[local_index]
		var card_index: int = page_start + local_index
		if card_index >= 0 and card_index < _cards.size():
			var card = _cards[card_index]
			view.visible = true
			view.configure(card, OWNER_PLAYER, false)
			view.scale = COLLECTION_SCALE
			view.set_selected(card_index == _cursor_index)
		else:
			view.visible = false


func _refresh_deck() -> void:
	for index in range(_deck_views.size()):
		var view: Control = _deck_views[index]
		if index < _deck.size():
			view.visible = true
			view.configure(_deck[index], OWNER_PLAYER, false)
			view.scale = DECK_SCALE
			view.set_selected(false)
		else:
			view.visible = false


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

	help_label.text = "W/A/S/D: Card   K: Add/Remove   Q/E: Page   1-6: Deck   Enter: Play   I: Leave"


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


func _toggle_cursor_card() -> void:
	if _cursor_index < 0 or _cursor_index >= _cards.size():
		return
	var card = _cards[_cursor_index]
	var deck_index: int = _deck_index_of(card)
	if deck_index >= 0:
		_deck.remove_at(deck_index)
		_status_text = "Removed from deck."
		_save_current_profile()
		_refresh_all()
		return

	if _deck.size() >= HAND_SIZE:
		_status_text = "Deck already has 5 cards."
		_refresh_labels()
		return
	var next_cost: int = _deck_cost() + int(card.deck_cost)
	if next_cost > _budget_limit:
		_status_text = "Point limit exceeded: %d / %d" % [next_cost, _budget_limit]
		_refresh_labels()
		return

	_deck.append(card)
	_status_text = "Added to deck."
	_save_current_profile()
	_refresh_all()


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
	if load_error == OK:
		var key: String = "deck_%d" % (profile_index + 1)
		var raw_indices = config.get_value("decks", key, PackedInt32Array())
		if raw_indices is PackedInt32Array or raw_indices is Array:
			for raw_index in raw_indices:
				var source_index: int = int(raw_index)
				if _catalog == null or not _catalog.has_method("get_card"):
					continue
				var card = _catalog.call("get_card", source_index)
				if card != null and not _deck_has_card(card) and _deck.size() < HAND_SIZE:
					_deck.append(card)

	if _deck.is_empty():
		_deck = _build_default_deck()


func _save_current_profile() -> void:
	if _catalog == null:
		return
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	var indices := PackedInt32Array()
	for card in _deck:
		if card != null:
			indices.append(int(card.source_index))
	config.set_value("decks", "deck_%d" % (_profile_index + 1), indices)
	config.set_value("meta", "last_profile", _profile_index)
	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning("TripleTriadDeckSetup: could not save deck profiles (%s)." % error_string(save_error))


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
