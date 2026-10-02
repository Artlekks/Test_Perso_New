extends CanvasLayer

signal opened
signal closed

const MODE_NAMES: PackedStringArray = ["SELL", "BUY", "TRADE", "USE"]

@onready var root: Control = $Root
@onready var wallet_label: Label = $Root/Panel/WalletLabel
@onready var mode_label: Label = $Root/Panel/ModeLabel
@onready var item_list: ItemList = $Root/Panel/ItemList
@onready var detail_label: Label = $Root/Panel/DetailLabel
@onready var message_label: Label = $Root/Panel/MessageLabel

var _game_mode: Node = null
var _access = null
var _open: bool = false
var _previous_pause: bool = false
var _mode: int = 0
var _entries: Array[Dictionary] = []
var _selection: int = 0

# Temporary UI-art integration state. Until the UX pass, only opening and
# closing are active; invisible legacy controls cannot mutate game state.
@export var presentation_only_background: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	item_list.item_selected.connect(_on_item_selected)


func configure(game_mode: Node, access) -> void:
	_game_mode = game_mode
	_access = access
	if _access != null and _access.has_signal("changed"):
		var callback = Callable(self, "_refresh")
		if not _access.is_connected("changed", callback):
			_access.connect("changed", callback)
	_refresh()


func is_open() -> bool:
	return _open


func open_menu() -> void:
	if _open or _access == null or not _can_open():
		return
	var tree = get_tree()
	if tree == null or tree.paused:
		return
	_previous_pause = tree.paused
	_open = true
	root.visible = true
	_message("")
	_refresh()
	tree.paused = true
	opened.emit()


func close_menu() -> void:
	if not _open:
		return
	_open = false
	root.visible = false
	var tree = get_tree()
	if tree != null:
		tree.paused = _previous_pause
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _is_toggle(event):
		if _open:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
		return

	if not _open:
		return

	if _is_back(event):
		close_menu()
		get_viewport().set_input_as_handled()
		return

	if presentation_only_background:
		get_viewport().set_input_as_handled()
		return

	var horizontal: int = _horizontal_step(event)
	if horizontal != 0:
		_mode = posmod(_mode + horizontal, MODE_NAMES.size())
		_selection = 0
		_message("")
		_refresh()
		get_viewport().set_input_as_handled()
		return

	var vertical: int = _vertical_step(event)
	if vertical != 0 and not _entries.is_empty():
		_selection = clampi(_selection + vertical, 0, _entries.size() - 1)
		item_list.select(_selection)
		item_list.ensure_current_is_visible()
		_update_detail()
		get_viewport().set_input_as_handled()
		return

	if _is_confirm(event):
		_execute_selected()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if not is_instance_valid(root) or _access == null:
		return
	var wallet: Dictionary = _access.get_wallet_snapshot()
	wallet_label.text = "Zenny %d   Manillo %.2f" % [
		int(wallet.get("zenny", 0)),
		float(wallet.get("manillo_point_units", 0)) / 100.0,
	]
	mode_label.text = "<  %s  >" % MODE_NAMES[_mode]

	match _mode:
		0:
			_entries = _access.get_sell_entries()
		1:
			_entries = _access.get_buy_entries()
		2:
			_entries = _access.get_trade_entries()
		3:
			_entries = _access.get_use_entries()

	item_list.clear()
	for entry in _entries:
		item_list.add_item(_row_text(entry))

	if _entries.is_empty():
		_selection = 0
		detail_label.text = "Nothing available in this category."
		return

	_selection = clampi(_selection, 0, _entries.size() - 1)
	item_list.select(_selection)
	item_list.ensure_current_is_visible()
	_update_detail()


func _row_text(entry: Dictionary) -> String:
	var display_name: String = str(entry.get("display_name", "---"))
	match str(entry.get("kind", "")):
		"sell":
			return "%s  x%d   %dz" % [display_name, int(entry.get("owned_count", 0)), int(entry.get("unit_value_zenny", 0))]
		"buy":
			return "%s  %dz   [%s]" % [display_name, int(entry.get("price_zenny", 0)), str(entry.get("state_label", ""))]
		"trade":
			return "%s   [%s]" % [display_name, str(entry.get("state_label", ""))]
		"use":
			return "%s  x%d   %s" % [display_name, int(entry.get("owned_count", 0)), str(entry.get("effect_name", ""))]
		_:
			return display_name


func _update_detail() -> void:
	if _entries.is_empty() or _selection < 0 or _selection >= _entries.size():
		detail_label.text = ""
		return
	var entry: Dictionary = _entries[_selection]
	var lines = PackedStringArray()
	lines.append(str(entry.get("detail", "")))
	if str(entry.get("kind", "")) == "trade":
		lines.append("Cost: %s" % str(entry.get("cost_text", "")))
		lines.append("Trade value: %.2f" % float(entry.get("manillo_value", 0.0)))
	elif str(entry.get("kind", "")) == "use":
		lines.append(str(entry.get("effect_description", "")))
		var duration: float = float(entry.get("duration_seconds", 0.0))
		if duration > 0.0:
			lines.append("Duration: %ds" % roundi(duration))
	elif str(entry.get("kind", "")) == "buy":
		lines.append("Shop: %s | owned %d" % [str(entry.get("shop_name", "")), int(entry.get("owned_count", 0))])
		if not bool(entry.get("can_execute", false)):
			lines.append("Unavailable: %s" % str(entry.get("reason", "")))
	detail_label.text = "\n".join(lines)


func _execute_selected() -> void:
	if _entries.is_empty() or _selection < 0 or _selection >= _entries.size():
		return
	var entry: Dictionary = _entries[_selection]
	var result: Dictionary = {}
	match str(entry.get("kind", "")):
		"sell":
			result = _access.sell_one(StringName(str(entry.get("id", ""))))
		"buy":
			result = _access.buy_one(StringName(str(entry.get("id", ""))))
		"trade":
			result = _access.trade_one(StringName(str(entry.get("id", ""))))
		"use":
			result = _access.use_one(str(entry.get("id", "")))

	var success: bool = (
		bool(result.get("success", false))
		or str(result.get("reason", "")) == "completed"
		or str(result.get("state_label", "")) == "COMPLETED"
	)
	_message("Done." if success else "Cannot: %s" % str(result.get("reason", "unknown")))
	_refresh()


func _message(value: String) -> void:
	if is_instance_valid(message_label):
		message_label.text = value


func _on_item_selected(index: int) -> void:
	_selection = index
	_update_detail()


func _can_open() -> bool:
	if _game_mode == null:
		return true
	if _game_mode.has_method("is_fishing"):
		return not bool(_game_mode.call("is_fishing"))
	return true


func _is_toggle(event: InputEvent) -> bool:
	return _pressed_key(event, KEY_M)


func _is_back(event: InputEvent) -> bool:
	return _pressed_key(event, KEY_I) or _pressed_key(event, KEY_ESCAPE)


func _is_confirm(event: InputEvent) -> bool:
	return _pressed_key(event, KEY_K) or _pressed_key(event, KEY_ENTER)


func _horizontal_step(event: InputEvent) -> int:
	if _pressed_key(event, KEY_A) or _pressed_key(event, KEY_LEFT):
		return -1
	if _pressed_key(event, KEY_D) or _pressed_key(event, KEY_RIGHT):
		return 1
	return 0


func _vertical_step(event: InputEvent) -> int:
	if _pressed_key(event, KEY_W) or _pressed_key(event, KEY_UP):
		return -1
	if _pressed_key(event, KEY_S) or _pressed_key(event, KEY_DOWN):
		return 1
	return 0


func _pressed_key(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event = event as InputEventKey
	return (
		key_event.pressed
		and not key_event.echo
		and (key_event.keycode == key or key_event.physical_keycode == key)
	)
