extends Control

signal deck_confirmed(cards: Array)
signal cancelled

const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")

const OWNER_PLAYER := 1
const PROFILE_COUNT := 6
const VISIBLE_PROFILE_COUNT := 5
const HAND_SIZE := 5
const COLLECTION_COLUMNS := 10
const COLLECTION_ROWS := 2
const PAGE_SIZE := COLLECTION_COLUMNS * COLLECTION_ROWS
const COLLECTION_SCALE := Vector2(0.50, 0.50)
# CardView is 116x132. At 0.50 scale the visible card is 58x66, so a
# 59 px horizontal step gives both deck and collection cards a 1 px gap.
const COLLECTION_STEP_X := 59.0
const COLLECTION_STEP_Y := 69.0
const DECK_SCALE := COLLECTION_SCALE
const DECK_STEP_X := 58.0
const SAVE_PATH := "user://triple_triad_decks.cfg"
const SAVE_VERSION := 1

const SORT_RANK_ASCENDING := 0
const SORT_RANK_DESCENDING := 1
const SORT_NUMBER := 2
const SORT_NAME := 3

const STATE_BROWSE := 0
const STATE_REPLACE := 1
const STATE_ANIMATING := 2

const COLLECTION_FOCUS_SCALE := COLLECTION_SCALE
const COLLECTION_FOCUS_Y := 0.0
const COLLECTION_CARD_OFFSET := Vector2.ZERO
const DECK_SLOT_SIZE := Vector2(58.0, 66.0)
const DECK_CARD_OFFSET := Vector2.ZERO
const DECK_SELECTED_X_OFFSET := -4.0
const USED_CARD_MODULATE := Color(0.46, 0.46, 0.46, 1.0)
const LOCKED_CARD_MODULATE := Color(0.30, 0.30, 0.30, 0.86)
const CARD_TRANSFER_LIFT_Y := 82.0
const CARD_TRANSFER_LIFT_SECONDS := 0.22
const CARD_TRANSFER_DROP_SECONDS := 0.16

@onready var collection_root: Control = $CollectionRoot
@onready var deck_root: Control = $DeckRoot
@onready var current_deck_label: Label = $CurrentDeckLabel
@onready var current_deck_count: Label = $CurrentDeckCount
@onready var cards_owned_label: Label = $CardsOwnedLabel
@onready var detail_card: Control = $DetailCard
@onready var detail_name: Label = $DetailName
@onready var detail_number: Label = $DetailNumber
@onready var detail_rarity: Label = $DetailRarity
@onready var detail_description: Label = $DetailDescription
@onready var status_label: Label = $StatusLabel
@onready var collection_arrow: Polygon2D = $CollectionArrow
@onready var deck_arrow: Polygon2D = $DeckArrow
@onready var profile_selection_arrow: Polygon2D = $DeckList/SelectionArrow
@onready var rank_button: Button = $SortBar/Rank
@onready var rank_arrow: Polygon2D = $SortBar/RankArrow
@onready var number_button: Button = $SortBar/Number
@onready var name_button: Button = $SortBar/Name
@onready var page_indicator: Label = $PageIndicator
@onready var new_deck_button: Button = $DeckList/NewDeckButton

var _profile_name_labels: Array[Label] = []
var _profile_count_labels: Array[Label] = []
var _profile_buttons: Array[Button] = []

var _catalog: Resource = null
var _collection_backend = null
var _acquisition_policy: Resource = null
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
var _sort_mode: int = SORT_RANK_ASCENDING
var _show_extended_details: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_profile_name_labels = [
		$DeckList/Deck1Name, $DeckList/Deck2Name, $DeckList/Deck3Name,
		$DeckList/Deck4Name, $DeckList/Deck5Name,
	]
	_profile_count_labels = [
		$DeckList/Deck1Count, $DeckList/Deck2Count, $DeckList/Deck3Count,
		$DeckList/Deck4Count, $DeckList/Deck5Count,
	]
	_profile_buttons = [
		$DeckList/Deck1Button, $DeckList/Deck2Button, $DeckList/Deck3Button,
		$DeckList/Deck4Button, $DeckList/Deck5Button,
	]
	_build_views()
	for index in range(_profile_buttons.size()):
		_profile_buttons[index].pressed.connect(_on_profile_row_pressed.bind(index))
	new_deck_button.pressed.connect(_on_new_deck_pressed)
	rank_button.pressed.connect(_on_rank_sort_pressed)
	number_button.pressed.connect(_on_sort_mode_pressed.bind(SORT_NUMBER))
	name_button.pressed.connect(_on_sort_mode_pressed.bind(SORT_NAME))
	if detail_card.has_method("set_owner_outline_visible"):
		detail_card.call("set_owner_outline_visible", false)


func open_setup(
	catalog: Resource,
	budget_limit: int,
	player_rank: int = 6,
	collection_backend = null,
	acquisition_policy: Resource = null
) -> void:
	_catalog = catalog
	_collection_backend = collection_backend
	_acquisition_policy = acquisition_policy
	_budget_limit = maxi(5, budget_limit)
	_player_rank = maxi(1, player_rank)
	_sort_mode = _load_sort_mode()
	_cards.clear()
	if _collection_backend != null and _collection_backend.has_method("get_owned_cards"):
		_cards = _collection_backend.call("get_owned_cards")
	elif _catalog != null and _catalog.has_method("get_cards_for_level_range"):
		_cards = _catalog.call("get_cards_for_level_range", 1, 10)
	_sort_cards()
	_sanitize_all_saved_profiles()
	_profile_index = mini(_load_last_profile_index(), VISIBLE_PROFILE_COUNT - 1)
	_load_profile(_profile_index)
	_cursor_index = 0
	_page_index = 0
	_status_text = ""
	_state = STATE_BROWSE
	_replace_card = null
	_replace_source_index = -1
	_replace_slot_index = 0
	_show_extended_details = false
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
		if _is_left(event):
			_move_replace_slot(-1)
			_accept_input()
			return
		if _is_right(event):
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

	if _is_view_details(event):
		_toggle_detail_mode()
		_accept_input()
		return

	if _is_save_deck(event):
		_save_current_profile()
		_status_text = "Deck saved."
		_refresh_labels()
		_accept_input()
		return

	if _is_delete_deck(event):
		_delete_current_deck()
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
		if view.has_method("set_owner_outline_visible"):
			view.call("set_owner_outline_visible", false)
		view.position = COLLECTION_CARD_OFFSET + Vector2(
			float(index % COLLECTION_COLUMNS) * COLLECTION_STEP_X,
			float(floori(float(index) / float(COLLECTION_COLUMNS))) * COLLECTION_STEP_Y
		)
		view.z_index = 20 + index
		_collection_views.append(view)

	for index in range(HAND_SIZE):
		var slot_panel := Panel.new()
		slot_panel.position = DECK_CARD_OFFSET + Vector2(float(index) * DECK_STEP_X, 0.0)
		slot_panel.size = DECK_SLOT_SIZE
		slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.visible = false
		deck_root.add_child(slot_panel)
		_deck_slot_panels.append(slot_panel)

		var deck_view: Control = CardViewScene.instantiate() as Control
		deck_root.add_child(deck_view)
		deck_view.pivot_offset = Vector2.ZERO
		deck_view.scale = DECK_SCALE
		if deck_view.has_method("set_owner_outline_visible"):
			deck_view.call("set_owner_outline_visible", false)
		deck_view.position = DECK_CARD_OFFSET + Vector2(float(index) * DECK_STEP_X, 0.0)
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
			if not _can_use_card(card):
				view.modulate = LOCKED_CARD_MODULATE
			else:
				view.modulate = USED_CARD_MODULATE if is_in_deck else Color.WHITE
			var is_cursor: bool = card_index == _cursor_index
			var is_replace_source: bool = _state == STATE_REPLACE and card_index == _replace_source_index
			view.scale = COLLECTION_FOCUS_SCALE if is_replace_source else COLLECTION_SCALE
			var base_position := COLLECTION_CARD_OFFSET + Vector2(
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
			float(index) * DECK_STEP_X + (DECK_SELECTED_X_OFFSET if is_replace_target else 0.0),
			0.0
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
		deck_arrow.position = deck_root.position + DECK_CARD_OFFSET + Vector2(
			float(_replace_slot_index) * DECK_STEP_X - 14.0,
			(DECK_SLOT_SIZE.y * 0.5) - 6.0
		)

func _refresh_labels() -> void:
	current_deck_label.text = "Deck #%d" % (_profile_index + 1)
	current_deck_count.text = "%d / %d" % [_deck.size(), HAND_SIZE]
	cards_owned_label.text = "Cards Owned  %d / %d" % [
		_cards.size(),
		_total_catalog_card_count(),
	]
	page_indicator.text = "%d / %d" % [_page_index + 1, _page_count()]
	status_label.text = _status_text
	_refresh_sort_ui()

	for index in range(_profile_name_labels.size()):
		_profile_name_labels[index].text = "Deck #%d" % (index + 1)
		var count: int = _deck.size() if index == _profile_index else _saved_profile_count(index)
		_profile_count_labels[index].text = "%d / %d" % [count, HAND_SIZE]
	profile_selection_arrow.position = Vector2(19.0, 84.0 + float(_profile_index) * 25.0)

	if _cursor_index >= 0 and _cursor_index < _cards.size():
		var card = _cards[_cursor_index]
		detail_card.visible = true
		detail_card.configure(card, OWNER_PLAYER, false)
		detail_card.pivot_offset = Vector2.ZERO
		detail_card.set_selected(false)
		if detail_card.has_method("set_owner_outline_visible"):
			detail_card.call("set_owner_outline_visible", false)
		detail_name.text = str(card.display_name)
		detail_number.text = "No. %03d" % (int(card.source_index) + 1)
		detail_rarity.text = String(card.rarity_id).capitalize()
		detail_description.text = _detail_description(card)
	else:
		detail_card.visible = false
		detail_name.text = ""
		detail_number.text = ""
		detail_rarity.text = ""
		detail_description.text = ""


func _detail_description(card) -> String:
	if card == null:
		return ""
	var lines: Array[String] = []
	var flavor_text: String = str(card.get("flavor_text")).strip_edges()
	if not flavor_text.is_empty():
		lines.append(flavor_text)
	lines.append("Cost %d" % int(card.deck_cost))
	if _show_extended_details:
		lines.append(
			"Ranks %d / %d / %d / %d   Total %d"
			% [
				int(card.top_rank),
				int(card.right_rank),
				int(card.bottom_rank),
				int(card.left_rank),
				int(card.rank_total()),
			]
		)
	if card.has_method("get_influence_description"):
		var influence_text: String = str(card.call("get_influence_description")).strip_edges()
		if not influence_text.is_empty():
			lines.append(influence_text)
	return "\n".join(lines)


func _total_catalog_card_count() -> int:
	if _catalog != null and _catalog.has_method("get_total_source_count"):
		return maxi(_cards.size(), int(_catalog.call("get_total_source_count")))
	return _cards.size()


func _saved_profile_count(profile_index: int) -> int:
	if profile_index == _profile_index:
		return _deck.size()
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return 0
	var id_key: String = "deck_ids_%d" % (profile_index + 1)
	if config.has_section_key("decks", id_key):
		var raw_ids = config.get_value("decks", id_key, PackedStringArray())
		return mini(HAND_SIZE, raw_ids.size()) if raw_ids is PackedStringArray or raw_ids is Array else 0
	var legacy_key: String = "deck_%d" % (profile_index + 1)
	if config.has_section_key("decks", legacy_key):
		var raw_indices = config.get_value("decks", legacy_key, PackedInt32Array())
		return mini(HAND_SIZE, raw_indices.size()) if raw_indices is PackedInt32Array or raw_indices is Array else 0
	return 0


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
	if not _can_use_card(card):
		_status_text = _card_lock_reason(card)
		_refresh_labels()
		return
	if _deck_has_card(card):
		var deck_index: int = _deck_index_of(card)
		if deck_index >= 0:
			_deck.remove_at(deck_index)
			_save_current_profile()
			_status_text = "Removed from deck."
			_refresh_all()
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
	var target_visual_scale: Vector2 = target_view.scale

	var ghost: Control = CardViewScene.instantiate() as Control
	add_child(ghost)
	ghost.configure(card, OWNER_PLAYER, false)
	if ghost.has_method("set_owner_outline_visible"):
		ghost.call("set_owner_outline_visible", false)
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
	# Deck_Screen.png is the authoritative visual grid.
	# The generated slot panels stay hidden and are used only as internal geometry.
	pass

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


func _on_rank_sort_pressed() -> void:
	if _sort_mode == SORT_RANK_ASCENDING:
		_apply_sort_mode(SORT_RANK_DESCENDING)
	else:
		_apply_sort_mode(SORT_RANK_ASCENDING)


func _on_sort_mode_pressed(mode: int) -> void:
	_apply_sort_mode(clampi(mode, SORT_RANK_ASCENDING, SORT_NAME))


func _apply_sort_mode(mode: int) -> void:
	_sort_mode = mode
	_save_sort_preference()
	_sort_cards_preserving_cursor()
	_status_text = ""
	_refresh_all()


func _refresh_sort_ui() -> void:
	# The BOF bitmap font does not contain the Unicode triangle glyphs, which is
	# why the old Rank buttons rendered garbage such as "25C". The word Rank
	# stays text and a real Polygon2D supplies the arrow instead.
	rank_button.text = "Rank"
	rank_arrow.rotation_degrees = 180.0 if _sort_mode == SORT_RANK_DESCENDING else 0.0


func _toggle_detail_mode() -> void:
	_show_extended_details = not _show_extended_details
	_status_text = "Detailed card stats shown." if _show_extended_details else "Card details collapsed."
	_refresh_labels()


func _delete_current_deck() -> void:
	_deck.clear()
	_save_current_profile()
	_state = STATE_BROWSE
	_replace_card = null
	_replace_source_index = -1
	_status_text = "Deck #%d deleted." % (_profile_index + 1)
	_refresh_all()


func _on_profile_row_pressed(profile_index: int) -> void:
	_switch_profile(profile_index)


func _on_new_deck_pressed() -> void:
	for profile_index in range(VISIBLE_PROFILE_COUNT):
		if _saved_profile_count(profile_index) == 0:
			_switch_profile(profile_index)
			_status_text = "New deck slot selected."
			_refresh_all()
			return
	_status_text = "All five deck slots are already in use."
	_refresh_labels()


func _sort_cards_preserving_cursor() -> void:
	var selected_id: String = ""
	if _cursor_index >= 0 and _cursor_index < _cards.size():
		selected_id = String(_cards[_cursor_index].card_id)

	_sort_cards()
	_cursor_index = 0
	if not selected_id.is_empty():
		for index in range(_cards.size()):
			if String(_cards[index].card_id) == selected_id:
				_cursor_index = index
				break
	_page_index = floori(float(_cursor_index) / float(PAGE_SIZE))


func _sort_cards() -> void:
	_cards.sort_custom(func(card_a, card_b):
		match _sort_mode:
			SORT_NUMBER:
				return int(card_a.source_index) < int(card_b.source_index)
			SORT_NAME:
				var name_compare: int = str(card_a.display_name).nocasecmp_to(str(card_b.display_name))
				if name_compare != 0:
					return name_compare < 0
				return int(card_a.source_index) < int(card_b.source_index)
			SORT_RANK_DESCENDING:
				return _rank_sort_before(card_a, card_b, true)
			_:
				return _rank_sort_before(card_a, card_b, false)
	)


func _rank_sort_before(card_a, card_b, descending: bool) -> bool:
	var cost_a: int = int(card_a.deck_cost)
	var cost_b: int = int(card_b.deck_cost)
	if cost_a != cost_b:
		return cost_a > cost_b if descending else cost_a < cost_b
	var strength_a: int = int(card_a.rank_total()) if card_a.has_method("rank_total") else 0
	var strength_b: int = int(card_b.rank_total()) if card_b.has_method("rank_total") else 0
	if strength_a != strength_b:
		return strength_a > strength_b if descending else strength_a < strength_b
	return int(card_a.source_index) > int(card_b.source_index) if descending else int(card_a.source_index) < int(card_b.source_index)


func _stamp_config(config: ConfigFile) -> void:
	config.set_value("meta", "version", SAVE_VERSION)


func _load_sort_mode() -> int:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return SORT_RANK_ASCENDING
	if config.has_section_key("meta", "sort_mode"):
		return clampi(int(config.get_value("meta", "sort_mode", SORT_RANK_ASCENDING)), SORT_RANK_ASCENDING, SORT_NAME)
	return SORT_RANK_DESCENDING if bool(config.get_value("meta", "sort_descending", false)) else SORT_RANK_ASCENDING


func _save_sort_preference() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("meta", "sort_mode", _sort_mode)
	_stamp_config(config)
	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning("TripleTriadDeckSetup: could not save sort preference (%s)." % error_string(save_error))


func _switch_profile(new_profile_index: int) -> void:
	if new_profile_index < 0 or new_profile_index >= VISIBLE_PROFILE_COUNT:
		return
	if new_profile_index == _profile_index:
		return
	_save_current_profile()
	_profile_index = new_profile_index
	_load_profile(_profile_index)
	_status_text = ""
	_refresh_all()


func _sanitize_all_saved_profiles() -> void:
	if _catalog == null:
		return
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var changed: bool = false
	for profile_index in range(PROFILE_COUNT):
		var id_key: String = "deck_ids_%d" % (profile_index + 1)
		var legacy_key: String = "deck_%d" % (profile_index + 1)
		var source_cards: Array = []
		var had_profile: bool = false
		if config.has_section_key("decks", id_key):
			had_profile = true
			var raw_ids = config.get_value("decks", id_key, PackedStringArray())
			if raw_ids is PackedStringArray or raw_ids is Array:
				for raw_id in raw_ids:
					if _catalog.has_method("get_card_by_id"):
						var card = _catalog.call("get_card_by_id", StringName(str(raw_id)))
						if card != null:
							source_cards.append(card)
		elif config.has_section_key("decks", legacy_key):
			had_profile = true
			var raw_indices = config.get_value("decks", legacy_key, PackedInt32Array())
			if raw_indices is PackedInt32Array or raw_indices is Array:
				for raw_index in raw_indices:
					var card = null
					if _catalog.has_method("get_card_by_legacy_source_index"):
						card = _catalog.call("get_card_by_legacy_source_index", int(raw_index))
					elif _catalog.has_method("get_card"):
						card = _catalog.call("get_card", int(raw_index))
					if card != null:
						source_cards.append(card)

		if not had_profile:
			continue
		var clean_cards: Array = _sanitize_card_array(source_cards)
		var clean_ids := PackedStringArray()
		for card in clean_cards:
			clean_ids.append(String(card.card_id))
		var current_ids = config.get_value("decks", id_key, PackedStringArray())
		if current_ids != clean_ids:
			config.set_value("decks", id_key, clean_ids)
			changed = true

	if changed:
		_stamp_config(config)
		var save_error: Error = config.save(SAVE_PATH)
		if save_error != OK:
			push_warning("TripleTriadDeckSetup: could not sanitize deck profiles (%s)." % error_string(save_error))


func _sanitize_card_array(cards: Array) -> Array:
	var clean: Array = []
	var seen_ids: Dictionary = {}
	var running_cost: int = 0
	for card in cards:
		if card == null or not _can_use_card(card):
			continue
		var card_id := StringName(card.card_id)
		if seen_ids.has(card_id):
			continue
		if clean.size() >= HAND_SIZE:
			break
		var card_cost: int = int(card.deck_cost)
		if running_cost + card_cost > _budget_limit:
			continue
		clean.append(card)
		seen_ids[card_id] = true
		running_cost += card_cost
	return clean


func _load_profile(profile_index: int) -> void:
	_deck.clear()
	var running_cost: int = 0
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
					if (
						_can_use_card(card)
						and not _deck_has_card(card)
						and _deck.size() < HAND_SIZE
						and running_cost + int(card.deck_cost) <= _budget_limit
					):
						_deck.append(card)
						running_cost += int(card.deck_cost)

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
					if (
						_can_use_card(card)
						and not _deck_has_card(card)
						and _deck.size() < HAND_SIZE
						and running_cost + int(card.deck_cost) <= _budget_limit
					):
						_deck.append(card)
						running_cost += int(card.deck_cost)

	# Deck #1 starts with the safe starter deck. The other visible deck slots
	# intentionally begin empty so the deck-builder screen reads 0 / 5 until the
	# player actually builds them. A profile missing a card because the player
	# lost it still stays short; we never silently refill an existing profile.
	if not had_saved_profile:
		if profile_index == 0:
			_deck = _build_default_deck()
		else:
			_deck.clear()

	_save_current_profile()


func _save_current_profile() -> void:
	if _catalog == null:
		return

	var config := ConfigFile.new()
	config.load(SAVE_PATH)

	_deck = _sanitize_card_array(_deck)
	var ids := PackedStringArray()
	for card in _deck:
		ids.append(String(card.card_id))

	config.set_value("decks", "deck_ids_%d" % (_profile_index + 1), ids)
	config.set_value("meta", "last_profile", _profile_index)

	_stamp_config(config)
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

	_stamp_config(config)
	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning("TripleTriadDeckSetup: could not prune deck profiles (%s)." % error_string(save_error))

	if visible:
		_refresh_all()


func _can_use_card(card) -> bool:
	if card == null:
		return false
	if (
		_collection_backend != null
		and _collection_backend.has_method("owns_card")
		and not bool(_collection_backend.call("owns_card", card))
	):
		return false
	if (
		_acquisition_policy != null
		and _acquisition_policy.has_method("can_use_card")
	):
		return bool(_acquisition_policy.call(
			"can_use_card",
			card,
			_player_rank
		))
	if card.has_method("is_usable_at_player_rank"):
		return bool(card.call("is_usable_at_player_rank", _player_rank))
	return true


func _card_lock_reason(card) -> String:
	if _can_use_card(card):
		return ""
	if (
		_acquisition_policy != null
		and _acquisition_policy.has_method("get_card_lock_reason")
	):
		return str(_acquisition_policy.call(
			"get_card_lock_reason",
			card,
			_player_rank
		))
	return "Card unavailable at this Duel Rank."


func _load_last_profile_index() -> int:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return 0
	return clampi(int(config.get_value("meta", "last_profile", 0)), 0, PROFILE_COUNT - 1)


func _build_default_deck() -> Array:
	var candidates: Array = []
	for card in _cards:
		if card != null and _can_use_card(card):
			candidates.append(card)
	if candidates.size() < HAND_SIZE:
		return []

	# A fresh save used to auto-build Deck #1 from the cheapest, weakest cards.
	# Keep the automatic deck legal, but choose a useful five-card starter deck
	# instead. Cap the search set so this stays cheap even if a missing profile is
	# rebuilt after the collection has grown far beyond the original ten cards.
	candidates.sort_custom(func(card_a, card_b):
		var total_a: int = int(card_a.rank_total())
		var total_b: int = int(card_b.rank_total())
		if total_a == total_b:
			if int(card_a.deck_cost) == int(card_b.deck_cost):
				return int(card_a.source_index) < int(card_b.source_index)
			return int(card_a.deck_cost) < int(card_b.deck_cost)
		return total_a > total_b
	)
	if candidates.size() > 14:
		candidates.resize(14)

	var best: Array = []
	var best_rank_total: int = -1
	var best_influence_count: int = -1
	var best_cost: int = 999999
	var count: int = candidates.size()

	for a in range(0, count - 4):
		for b in range(a + 1, count - 3):
			for c in range(b + 1, count - 2):
				for d in range(c + 1, count - 1):
					for e in range(d + 1, count):
						var candidate_deck: Array = [
							candidates[a],
							candidates[b],
							candidates[c],
							candidates[d],
							candidates[e],
						]
						var candidate_cost: int = 0
						var candidate_rank_total: int = 0
						var candidate_influence_count: int = 0
						for candidate_card in candidate_deck:
							candidate_cost += int(candidate_card.deck_cost)
							candidate_rank_total += int(candidate_card.rank_total())
							if int(candidate_card.get("influence_strength")) > 0:
								candidate_influence_count += 1
						if candidate_cost > _budget_limit:
							continue

						if (
							candidate_rank_total > best_rank_total
							or (
								candidate_rank_total == best_rank_total
								and candidate_influence_count > best_influence_count
							)
							or (
								candidate_rank_total == best_rank_total
								and candidate_influence_count == best_influence_count
								and candidate_cost < best_cost
							)
						):
							best = candidate_deck.duplicate()
							best_rank_total = candidate_rank_total
							best_influence_count = candidate_influence_count
							best_cost = candidate_cost

	if best.size() == HAND_SIZE:
		return best

	# Defensive fallback; normally unreachable because the starter collection is
	# statically validated to contain a legal five-card deck.
	var result: Array = []
	var running_cost: int = 0
	for card in candidates:
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
		_:
			return -1


func _pressed(event: InputEvent) -> bool:
	return event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo


func _is_confirm(event: InputEvent) -> bool:
	return _key_matches(event, KEY_K)


func _is_view_details(event: InputEvent) -> bool:
	return _key_matches(event, KEY_J)


func _is_save_deck(event: InputEvent) -> bool:
	return _key_matches(event, KEY_L)


func _is_delete_deck(event: InputEvent) -> bool:
	return _key_matches(event, KEY_R)


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
