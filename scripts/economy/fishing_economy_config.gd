extends Resource
class_name FishingEconomyConfig

## Canonical live economy tuning for the fishing vertical slice.
##
## BOF4 source resources still preserve reference values, but runtime economy
## code reads prices from this resource first. This keeps balance tuning in one
## place and lets shops/regions later add modifiers without rewriting item data.

@export_category("Version")
@export var economy_version: String = "1.0"
@export_range(0, 999999, 1) var new_game_starting_zenny: int = 100

@export_category("Fish Sell Prices")
@export var fish_ids: PackedStringArray = PackedStringArray()
@export var fish_sell_prices_zenny: PackedInt32Array = PackedInt32Array()

@export_category("Lure Base Prices")
@export var lure_ids: PackedStringArray = PackedStringArray()
@export var lure_buy_prices_zenny: PackedInt32Array = PackedInt32Array()

@export_category("Rod Base Prices")
@export var rod_ids: PackedStringArray = PackedStringArray()
@export var rod_buy_prices_zenny: PackedInt32Array = PackedInt32Array()

@export_category("Prepared Bait")
@export var prepared_bait_item_domain_id: StringName = &"prepared_bait"
@export var prepared_bait_display_name: String = "Prepared Bait"
@export_multiline var prepared_bait_description: String = "A cooked fishing bait made from a common fish and aromatic coastal herbs."
@export_range(0, 9999, 1) var prepared_bait_sell_price_zenny: int = 0
@export var bait_herb_material_id: StringName = &"coastal_herb"
@export_range(1, 99, 1) var fish_per_bait_batch: int = 1
@export_range(1, 99, 1) var herbs_per_bait_batch: int = 2
@export_range(1, 99, 1) var portions_per_bait_batch: int = 3
@export var common_bait_fish_ids: PackedStringArray = PackedStringArray()

@export_category("Prepared Bait Gameplay")
@export var prepared_bait_auto_use_default: bool = true
@export_range(1.0, 2.0, 0.01)
var prepared_bait_bite_attraction_multiplier: float = 1.20
@export_range(0.0, 0.75, 0.01)
var prepared_bait_quality_bonus_roll_chance: float = 0.30
@export_range(0, 2, 1)
var prepared_bait_quality_bonus_rolls: int = 1


func get_fish_sell_price(
	species_id: StringName,
	fallback: int = 0
) -> int:
	return _lookup_price(
		fish_ids,
		fish_sell_prices_zenny,
		species_id,
		fallback
	)


func get_lure_buy_price(
	lure_id: StringName,
	fallback: int = 0
) -> int:
	return _lookup_price(
		lure_ids,
		lure_buy_prices_zenny,
		lure_id,
		fallback
	)


func get_rod_buy_price(
	rod_id: StringName,
	fallback: int = 0
) -> int:
	return _lookup_price(
		rod_ids,
		rod_buy_prices_zenny,
		rod_id,
		fallback
	)


func get_offer_buy_price(
	item_type: int,
	item_id: StringName,
	fallback: int = 0
) -> int:
	match item_type:
		0:
			return get_lure_buy_price(item_id, fallback)
		1:
			return get_rod_buy_price(item_id, fallback)
		_:
			return maxi(0, fallback)


func is_common_bait_fish(species_id: StringName) -> bool:
	var key: String = String(species_id).strip_edges().to_lower()
	if key.is_empty():
		return false
	for raw_id in common_bait_fish_ids:
		if str(raw_id).strip_edges().to_lower() == key:
			return true
	return false


func get_prepared_bait_recipe_snapshot() -> Dictionary:
	return {
		"prepared_bait_item_domain_id": String(prepared_bait_item_domain_id),
		"herb_material_id": String(bait_herb_material_id),
		"fish_per_batch": maxi(1, fish_per_bait_batch),
		"herbs_per_batch": maxi(1, herbs_per_bait_batch),
		"portions_per_batch": maxi(1, portions_per_bait_batch),
		"common_bait_fish_ids": common_bait_fish_ids.duplicate(),
		"auto_use_default": prepared_bait_auto_use_default,
		"bite_attraction_multiplier": prepared_bait_bite_attraction_multiplier,
		"quality_bonus_roll_chance": prepared_bait_quality_bonus_roll_chance,
		"quality_bonus_rolls": prepared_bait_quality_bonus_rolls,
	}


func validate_shape() -> Dictionary:
	var errors := PackedStringArray()
	if fish_ids.size() != fish_sell_prices_zenny.size():
		errors.append("fish price ids/values size mismatch")
	if lure_ids.size() != lure_buy_prices_zenny.size():
		errors.append("lure price ids/values size mismatch")
	if rod_ids.size() != rod_buy_prices_zenny.size():
		errors.append("rod price ids/values size mismatch")
	if prepared_bait_item_domain_id == &"":
		errors.append("prepared bait item id is empty")
	if bait_herb_material_id == &"":
		errors.append("prepared bait herb material id is empty")
	if common_bait_fish_ids.is_empty():
		errors.append("prepared bait has no eligible common fish")
	if prepared_bait_bite_attraction_multiplier < 1.0:
		errors.append("prepared bait attraction multiplier must not reduce bites")
	if prepared_bait_quality_bonus_roll_chance < 0.0:
		errors.append("prepared bait quality chance cannot be negative")
	if prepared_bait_quality_bonus_rolls < 0:
		errors.append("prepared bait quality rolls cannot be negative")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
	}


func _lookup_price(
	ids: PackedStringArray,
	values: PackedInt32Array,
	requested_id: StringName,
	fallback: int
) -> int:
	var key: String = String(requested_id).strip_edges().to_lower()
	if key.is_empty():
		return maxi(0, fallback)
	var count: int = mini(ids.size(), values.size())
	for index in range(count):
		if str(ids[index]).strip_edges().to_lower() == key:
			return maxi(0, int(values[index]))
	return maxi(0, fallback)
