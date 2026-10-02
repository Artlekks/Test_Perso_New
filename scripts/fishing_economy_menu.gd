extends CanvasLayer

signal opened
signal closed

const MODE_BUY := 0
const MODE_SELL := 1

const PAGE_SIZE := 5

const BUY_CATEGORIES = [
	"ALL",
	"RODS",
	"LURES",
]
const SELL_CATEGORIES = [
	"ALL",
	"FISH",
	"MATERIALS",
]

const ROW_START_Y := 160.0
const ROW_HEIGHT := 28.0

@onready var root: Control = $Root
@onready var wallet_label: Label = $Root/WalletLabel
@onready var mode_cursor: Polygon2D = $Root/ModeCursor
@onready var category_label: Label = $Root/CategoryLabel
@onready var page_label: Label = $Root/PageLabel
@onready var selection_bar: ColorRect = $Root/ListSelectionBar
@onready var selection_cursor: Polygon2D = $Root/ListCursor
@onready var info_label: Label = $Root/InfoLabel
@onready var message_label: Label = $Root/MessageLabel
@onready var confirm_panel: Panel = $Root/ConfirmPanel
@onready var confirm_prompt: Label = $Root/ConfirmPanel/Prompt
@onready var confirm_choice: Label = $Root/ConfirmPanel/Choice

@onready var row_name_labels: Array[Label] = [
	$Root/Rows/Row1Name,
	$Root/Rows/Row2Name,
	$Root/Rows/Row3Name,
	$Root/Rows/Row4Name,
	$Root/Rows/Row5Name,
]
@onready var row_owned_labels: Array[Label] = [
	$Root/Rows/Row1Owned,
	$Root/Rows/Row2Owned,
	$Root/Rows/Row3Owned,
	$Root/Rows/Row4Owned,
	$Root/Rows/Row5Owned,
]
@onready var row_price_labels: Array[Label] = [
	$Root/Rows/Row1Price,
	$Root/Rows/Row2Price,
	$Root/Rows/Row3Price,
	$Root/Rows/Row4Price,
	$Root/Rows/Row5Price,
]

var _game_mode: Node = null
var _access = null
var _open: bool = false
var _previous_pause: bool = false
var _input_ready: bool = false

var _mode: int = MODE_BUY
var _category_index: int = 0
var _page_index: int = 0
var _row_index: int = 0

var _source_entries: Array[Dictionary] = []
var _filtered_entries: Array[Dictionary] = []

var _confirm_active: bool = false
var _confirm_yes: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	confirm_panel.visible = false


func configure(game_mode: Node, access) -> void:
	_game_mode = game_mode
	_access = access
	if _access != null and _access.has_signal("changed"):
		var callback := Callable(self, "_on_access_changed")
		if not _access.is_connected("changed", callback):
			_access.connect("changed", callback)
	_refresh()


func is_open() -> bool:
	return _open


func open_menu() -> void:
	if _open or _access == null or not _can_open():
		return

	var tree := get_tree()
	if tree == null or tree.paused:
		return

	_previous_pause = tree.paused
	_open = true
	_input_ready = false

	_mode = MODE_BUY
	_category_index = 0
	_page_index = 0
	_row_index = 0
	_confirm_active = false
	_confirm_yes = false

	root.visible = true
	confirm_panel.visible = false
	_message("")
	_refresh()

	tree.paused = true
	call_deferred("_arm_input")
	opened.emit()


func close_menu() -> void:
	if not _open:
		return

	_open = false
	_input_ready = false
	_confirm_active = false
	confirm_panel.visible = false
	root.visible = false

	var tree := get_tree()
	if tree != null:
		tree.paused = _previous_pause

	closed.emit()


func _arm_input() -> void:
	_input_ready = true


func _input(event: InputEvent) -> void:
	if not _open or not _input_ready or not _pressed(event):
		return

	if _confirm_active:
		_handle_confirmation_input(event)
		return

	if _is_back(event):
		close_menu()
		_accept_input()
		return

	if _is_mode_toggle(event):
		_toggle_mode()
		_accept_input()
		return

	var category_step: int = _category_step(event)
	if category_step != 0:
		_change_category(category_step)
		_accept_input()
		return

	var page_step: int = _page_step(event)
	if page_step != 0:
		_change_page(page_step)
		_accept_input()
		return

	var vertical_step: int = _vertical_step(event)
	if vertical_step != 0:
		_move_selection(vertical_step)
		_accept_input()
		return

	if _is_confirm(event):
		_begin_confirmation()
		_accept_input()


func _handle_confirmation_input(event: InputEvent) -> void:
	if _is_back(event):
		_cancel_confirmation()
		_accept_input()
		return

	if (
		_is_left(event)
		or _is_right(event)
		or _is_up(event)
		or _is_down(event)
	):
		_confirm_yes = not _confirm_yes
		_refresh_confirmation()
		_accept_input()
		return

	if _is_confirm(event):
		if _confirm_yes:
			_execute_confirmed_transaction()
		else:
			_cancel_confirmation()
		_accept_input()


func _toggle_mode() -> void:
	if _mode == MODE_BUY:
		_mode = MODE_SELL
	else:
		_mode = MODE_BUY

	_category_index = 0
	_page_index = 0
	_row_index = 0
	_message("")
	_refresh()


func _change_category(direction: int) -> void:
	var categories: Array = _current_categories()
	if categories.is_empty():
		return

	_category_index = wrapi(
		_category_index + direction,
		0,
		categories.size()
	)
	_page_index = 0
	_row_index = 0
	_message("")
	_refresh()


func _change_page(direction: int) -> void:
	var count: int = _page_count()
	if count <= 1:
		return

	_page_index = wrapi(
		_page_index + direction,
		0,
		count
	)
	_row_index = 0
	_message("")
	_refresh_visible_rows()
	_update_info()


func _move_selection(direction: int) -> void:
	var page_entries: Array[Dictionary] = _current_page_entries()
	if page_entries.is_empty():
		return

	_row_index = clampi(
		_row_index + direction,
		0,
		page_entries.size() - 1
	)
	_message("")
	_refresh_selection_feedback()
	_update_info()


func _begin_confirmation() -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty():
		return

	if not bool(entry.get("can_execute", false)):
		var reason: String = str(entry.get("reason", "unavailable"))
		_message("Cannot: %s" % _friendly_reason(reason))
		return

	_confirm_active = true
	_confirm_yes = false
	confirm_panel.visible = true
	_refresh_confirmation()


func _cancel_confirmation() -> void:
	_confirm_active = false
	_confirm_yes = false
	confirm_panel.visible = false


func _refresh_confirmation() -> void:
	if not _confirm_active:
		confirm_panel.visible = false
		return

	var entry: Dictionary = _selected_entry()
	if entry.is_empty():
		_cancel_confirmation()
		return

	var display_name: String = str(
		entry.get("display_name", "item")
	)
	var value: int = _entry_unit_value(entry)

	if _mode == MODE_BUY:
		confirm_prompt.text = "Buy %s for %dz?" % [
			display_name,
			value,
		]
	else:
		confirm_prompt.text = "Sell %s for %dz?" % [
			display_name,
			value,
		]

	if _confirm_yes:
		confirm_choice.text = "> YES        NO"
	else:
		confirm_choice.text = "  YES      > NO"


func _execute_confirmed_transaction() -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty():
		_cancel_confirmation()
		return

	var display_name: String = str(
		entry.get("display_name", "item")
	)

	# Close the modal before calling the backend. The access façade emits
	# `changed` synchronously after a successful transaction.
	_confirm_active = false
	_confirm_yes = false
	confirm_panel.visible = false

	var result: Dictionary = {}
	if _mode == MODE_BUY:
		result = _access.buy_one(
			StringName(str(entry.get("id", "")))
		)
	else:
		var sell_id: String = str(
			entry.get("unified_item_id", "")
		)
		if sell_id.is_empty():
			sell_id = str(entry.get("id", ""))
		result = _access.sell_one(
			StringName(sell_id)
		)

	var success: bool = bool(result.get("success", false))
	if not success:
		success = str(result.get("reason", "")) == "completed"

	if success:
		if _mode == MODE_BUY:
			_message("Purchased %s." % display_name)
		else:
			_message("Sold %s." % display_name)
	else:
		_message(
			"Cannot: %s"
			% _friendly_reason(
				str(result.get("reason", "unknown"))
			)
		)

	_refresh()


func _refresh() -> void:
	if not is_instance_valid(root) or _access == null:
		return

	_refresh_wallet()
	_refresh_mode_feedback()
	_refresh_source_entries()
	_refresh_category_filter()
	_clamp_page_and_selection()
	_refresh_visible_rows()
	_update_info()
	_refresh_confirmation()


func _refresh_wallet() -> void:
	var wallet: Dictionary = _access.get_wallet_snapshot()
	wallet_label.text = "Zenny  %d      Manillo  %.2f" % [
		int(wallet.get("zenny", 0)),
		float(wallet.get("manillo_point_units", 0)) / 100.0,
	]


func _refresh_mode_feedback() -> void:
	if _mode == MODE_BUY:
		mode_cursor.position = Vector2(187.0, 110.0)
	else:
		mode_cursor.position = Vector2(337.0, 110.0)


func _refresh_source_entries() -> void:
	if _mode == MODE_BUY:
		_source_entries = _access.get_buy_entries()
	else:
		_source_entries = _access.get_sell_entries()


func _refresh_category_filter() -> void:
	_filtered_entries.clear()

	var categories: Array = _current_categories()
	if categories.is_empty():
		return

	_category_index = clampi(
		_category_index,
		0,
		categories.size() - 1
	)
	var category: String = str(
		categories[_category_index]
	)

	for entry in _source_entries:
		if category == "ALL":
			_filtered_entries.append(
				entry.duplicate(true)
			)
			continue

		if str(entry.get("category", "")) == category:
			_filtered_entries.append(
				entry.duplicate(true)
			)


func _clamp_page_and_selection() -> void:
	var count: int = _page_count()
	_page_index = clampi(
		_page_index,
		0,
		count - 1
	)

	var page_entries: Array[Dictionary] = _current_page_entries()
	if page_entries.is_empty():
		_row_index = 0
	else:
		_row_index = clampi(
			_row_index,
			0,
			page_entries.size() - 1
		)


func _refresh_visible_rows() -> void:
	for index in range(PAGE_SIZE):
		row_name_labels[index].text = ""
		row_owned_labels[index].text = ""
		row_price_labels[index].text = ""

	var page_entries: Array[Dictionary] = _current_page_entries()
	for index in range(page_entries.size()):
		var entry: Dictionary = page_entries[index]
		row_name_labels[index].text = str(
			entry.get("display_name", "---")
		)
		row_owned_labels[index].text = "x%d" % int(
			entry.get("owned_count", 0)
		)
		row_price_labels[index].text = "%dz" % (
			_entry_unit_value(entry)
		)

	var categories: Array = _current_categories()
	var category: String = "ALL"
	if not categories.is_empty():
		category = str(categories[_category_index])

	category_label.text = "CATEGORY  %s" % category
	page_label.text = "%d / %d" % [
		_page_index + 1,
		_page_count(),
	]

	_refresh_selection_feedback()


func _refresh_selection_feedback() -> void:
	var page_entries: Array[Dictionary] = _current_page_entries()
	var has_selection: bool = not page_entries.is_empty()

	selection_bar.visible = has_selection
	selection_cursor.visible = has_selection

	if not has_selection:
		return

	var y: float = (
		ROW_START_Y
		+ float(_row_index) * ROW_HEIGHT
	)
	selection_bar.position.y = y
	selection_cursor.position.y = y + 13.0


func _update_info() -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty():
		info_label.text = "Nothing available."
		return

	var value: int = _entry_unit_value(entry)
	var owned: int = int(
		entry.get("owned_count", 0)
	)

	info_label.text = "%dz each     owned %d" % [
		value,
		owned,
	]

	if not bool(entry.get("can_execute", false)):
		var reason: String = str(
			entry.get("reason", "")
		)
		if not reason.is_empty():
			info_label.text += "\n%s" % _friendly_reason(
				reason
			)


func _selected_entry() -> Dictionary:
	var page_entries: Array[Dictionary] = _current_page_entries()
	if page_entries.is_empty():
		return {}

	if _row_index < 0 or _row_index >= page_entries.size():
		return {}

	return page_entries[_row_index]


func _current_page_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _filtered_entries.is_empty():
		return result

	var start: int = _page_index * PAGE_SIZE
	var end: int = mini(
		start + PAGE_SIZE,
		_filtered_entries.size()
	)

	for index in range(start, end):
		result.append(
			_filtered_entries[index]
		)

	return result


func _page_count() -> int:
	return maxi(
		1,
		ceili(
			float(_filtered_entries.size())
			/ float(PAGE_SIZE)
		)
	)


func _current_categories() -> Array:
	if _mode == MODE_BUY:
		return BUY_CATEGORIES
	return SELL_CATEGORIES


func _entry_unit_value(entry: Dictionary) -> int:
	if _mode == MODE_BUY:
		return int(entry.get("price_zenny", 0))
	return int(entry.get("unit_value_zenny", 0))


func _friendly_reason(reason: String) -> String:
	match reason:
		"not_enough_zenny", "wallet_changed":
			return "Not enough Zenny."
		"already_owned_unique_item":
			return "Already owned."
		"availability_locked":
			return "Not available yet."
		"not_enough_fish":
			return "You no longer own that fish."
		"not_enough_items":
			return "You no longer own that item."
		"not_sellable":
			return "That item cannot be sold."
		"shop_not_available":
			return "Not sold at this shop."
		_:
			return reason.replace("_", " ").capitalize()


func _message(value: String) -> void:
	message_label.text = value


func _on_access_changed() -> void:
	if _open:
		_refresh()


func _can_open() -> bool:
	if _game_mode == null:
		return true
	if _game_mode.has_method("is_fishing"):
		return not bool(_game_mode.call("is_fishing"))
	return true


func _is_mode_toggle(event: InputEvent) -> bool:
	return _pressed_key(event, KEY_J)


func _is_back(event: InputEvent) -> bool:
	return (
		_pressed_key(event, KEY_I)
		or _pressed_key(event, KEY_ESCAPE)
	)


func _is_confirm(event: InputEvent) -> bool:
	return (
		_pressed_key(event, KEY_K)
		or _pressed_key(event, KEY_ENTER)
	)


func _category_step(event: InputEvent) -> int:
	if _pressed_key(event, KEY_Q):
		return -1
	if _pressed_key(event, KEY_E):
		return 1
	return 0


func _page_step(event: InputEvent) -> int:
	if _is_left(event):
		return -1
	if _is_right(event):
		return 1
	return 0


func _vertical_step(event: InputEvent) -> int:
	if _is_up(event):
		return -1
	if _is_down(event):
		return 1
	return 0


func _is_left(event: InputEvent) -> bool:
	return (
		_pressed_key(event, KEY_A)
		or _pressed_key(event, KEY_LEFT)
	)


func _is_right(event: InputEvent) -> bool:
	return (
		_pressed_key(event, KEY_D)
		or _pressed_key(event, KEY_RIGHT)
	)


func _is_up(event: InputEvent) -> bool:
	return (
		_pressed_key(event, KEY_W)
		or _pressed_key(event, KEY_UP)
	)


func _is_down(event: InputEvent) -> bool:
	return (
		_pressed_key(event, KEY_S)
		or _pressed_key(event, KEY_DOWN)
	)


func _pressed(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
	)


func _pressed_key(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey
	return (
		key_event.pressed
		and not key_event.echo
		and (
			key_event.keycode == key
			or key_event.physical_keycode == key
		)
	)


func _accept_input() -> void:
	get_viewport().set_input_as_handled()
