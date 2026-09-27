extends Node
class_name FishingManilloLedger

signal changed(summary: Dictionary)

const UNITS_PER_STAMP: int = 100
const STAMPS_PER_CARD: int = 20
const MAX_STAMP_CARDS: int = 99

var inventory: FishingInventory = null


func configure(
	new_inventory: FishingInventory
) -> void:
	if inventory == new_inventory:
		return

	_disconnect_inventory()
	inventory = new_inventory
	_connect_inventory()


func add_trade_value_units(
	amount: int,
	persist: bool = true
) -> int:
	if inventory == null or amount <= 0:
		return get_point_units()

	return inventory.add_manillo_point_units(
		amount,
		persist
	)


func get_point_units() -> int:
	if inventory == null:
		return 0

	return inventory.get_manillo_point_units()


func get_stamps() -> int:
	if inventory == null:
		return 0

	return inventory.get_manillo_stamps()


func get_stamp_cards() -> int:
	if inventory == null:
		return 0

	return inventory.get_manillo_stamp_cards()


func get_display_points() -> float:
	return (
		float(get_point_units())
		/ float(UNITS_PER_STAMP)
	)


func get_stamp_capacity_remaining() -> int:
	var cards: int = get_stamp_cards()
	var stamps: int = get_stamps()

	if cards > MAX_STAMP_CARDS:
		return 0

	# 99 completed cards plus up to 19 stamps toward the next card.
	return maxi(
		(MAX_STAMP_CARDS - cards)
		* STAMPS_PER_CARD
		+ (STAMPS_PER_CARD - 1 - stamps),
		0
	)


func convert_points_to_stamps(
	max_stamps: int = -1,
	persist: bool = true
) -> Dictionary:
	var result: Dictionary = {
		"converted_stamps": 0,
		"cards_created": 0,
		"point_units_before": get_point_units(),
		"point_units_after": get_point_units(),
		"stamps_before": get_stamps(),
		"stamps_after": get_stamps(),
		"cards_before": get_stamp_cards(),
		"cards_after": get_stamp_cards(),
		"reason": "",
	}

	if inventory == null:
		result["reason"] = "inventory_unavailable"
		return result

	var point_units: int = get_point_units()
	var available_stamps: int = floori(
		float(point_units)
		/ float(UNITS_PER_STAMP)
	)
	var capacity: int = get_stamp_capacity_remaining()

	var convertible: int = mini(
		available_stamps,
		capacity
	)

	if max_stamps >= 0:
		convertible = mini(
			convertible,
			max_stamps
		)

	if convertible <= 0:
		result["reason"] = (
			"stamp_capacity_full"
			if capacity <= 0
			else "not_enough_points"
		)
		return result

	var cards_before: int = get_stamp_cards()
	var total_stamps: int = (
		get_stamps()
		+ convertible
	)
	var cards_to_create: int = mini(
		floori(
			float(total_stamps)
			/ float(STAMPS_PER_CARD)
		),
		MAX_STAMP_CARDS - cards_before
	)
	var stamps_after: int = (
		total_stamps
		- cards_to_create * STAMPS_PER_CARD
	)
	var cards_after: int = (
		cards_before
		+ cards_to_create
	)
	var points_after: int = (
		point_units
		- convertible * UNITS_PER_STAMP
	)

	inventory.set_manillo_balance(
		points_after,
		stamps_after,
		cards_after,
		persist
	)

	result["converted_stamps"] = convertible
	result["cards_created"] = cards_to_create
	result["point_units_after"] = points_after
	result["stamps_after"] = stamps_after
	result["cards_after"] = cards_after
	result["reason"] = "ok"
	return result


func spend_stamp_cards(
	amount: int,
	persist: bool = true
) -> bool:
	if inventory == null or amount <= 0:
		return amount <= 0

	var current: int = get_stamp_cards()

	if current < amount:
		return false

	inventory.set_manillo_balance(
		get_point_units(),
		get_stamps(),
		current - amount,
		persist
	)
	return true


func get_summary() -> Dictionary:
	return {
		"point_units": get_point_units(),
		"display_points": get_display_points(),
		"stamps": get_stamps(),
		"stamp_cards": get_stamp_cards(),
		"stamp_capacity_remaining": get_stamp_capacity_remaining(),
		"units_per_stamp": UNITS_PER_STAMP,
		"stamps_per_card": STAMPS_PER_CARD,
		"max_stamp_cards": MAX_STAMP_CARDS,
	}


func get_debug_summary() -> String:
	var summary: Dictionary = get_summary()

	return "%.2f pts | %d stamps | %d cards" % [
		float(summary.get("display_points", 0.0)),
		int(summary.get("stamps", 0)),
		int(summary.get("stamp_cards", 0)),
	]


func _connect_inventory() -> void:
	if inventory == null:
		return

	var callback := Callable(
		self,
		"_on_inventory_balance_changed"
	)

	if not inventory.manillo_balance_changed.is_connected(
		callback
	):
		inventory.manillo_balance_changed.connect(
			callback
		)


func _disconnect_inventory() -> void:
	if inventory == null:
		return

	var callback := Callable(
		self,
		"_on_inventory_balance_changed"
	)

	if inventory.manillo_balance_changed.is_connected(
		callback
	):
		inventory.manillo_balance_changed.disconnect(
			callback
		)


func _on_inventory_balance_changed(
	_point_units: int,
	_stamps: int,
	_stamp_cards: int
) -> void:
	changed.emit(
		get_summary()
	)
