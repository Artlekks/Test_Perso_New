extends Node
class_name FishingLoadout

signal lure_changed(lure: BaitData)
signal rod_changed(rod: RodData)

@export_category("Fishing Database")
@export var lure_catalog: FishingLureCatalog

@export_category("Equipped Fishing Gear")
@export var selected_lure: BaitData
@export var selected_rod: RodData

var _inventory: FishingInventory = null


func _ready() -> void:
	if lure_catalog == null:
		push_warning("FishingLoadout: no lure catalog is assigned.")

	if selected_lure == null:
		push_warning("FishingLoadout: no lure is equipped.")
	elif lure_catalog != null and lure_catalog.find_lure(selected_lure) == -1:
		push_warning(
			"FishingLoadout: equipped lure is not present in the lure catalog."
		)

	if selected_rod == null:
		push_warning("FishingLoadout: no rod is equipped.")


func set_inventory(inventory: FishingInventory) -> void:
	_inventory = inventory


func get_inventory() -> FishingInventory:
	return _inventory


# System/debug API: retains the project's existing behavior and deliberately
# bypasses ownership. Player-facing selectors should call equip_owned_lure().
func equip_lure(lure: BaitData) -> void:
	_equip_lure_internal(lure)


func equip_owned_lure(lure: BaitData) -> bool:
	if lure == null:
		return false
	if _inventory != null and not _inventory.owns_lure(lure):
		return false
	_equip_lure_internal(lure)
	return selected_lure == lure


# System/debug API, parallel to equip_lure().
func equip_rod(rod: RodData) -> void:
	_equip_rod_internal(rod)


func equip_owned_rod(rod: RodData) -> bool:
	if rod == null:
		return false
	if _inventory != null and not _inventory.owns_rod(rod):
		return false
	_equip_rod_internal(rod)
	return selected_rod == rod


func select_lure_index(index: int) -> void:
	# Existing/debug behavior: indexes the full catalog.
	if lure_catalog == null:
		return

	var lure_count := lure_catalog.get_lure_count()
	if lure_count <= 0:
		return

	var wrapped_index := posmod(index, lure_count)
	equip_lure(lure_catalog.get_lure(wrapped_index))


func select_owned_lure_index(index: int) -> bool:
	var owned := get_owned_lures()
	if owned.is_empty():
		return false

	var wrapped_index := posmod(index, owned.size())
	return equip_owned_lure(owned[wrapped_index])


func select_next_lure() -> void:
	# Kept as full-catalog/system behavior for backwards compatibility.
	if lure_catalog == null:
		return

	var current_index := get_selected_lure_index()
	if current_index < 0:
		select_lure_index(0)
		return

	select_lure_index(current_index + 1)


func select_previous_lure() -> void:
	if lure_catalog == null:
		return

	var current_index := get_selected_lure_index()
	if current_index < 0:
		select_lure_index(0)
		return

	select_lure_index(current_index - 1)


func get_selected_lure() -> BaitData:
	return selected_lure


func get_selected_rod() -> RodData:
	return selected_rod


func get_selected_lure_index() -> int:
	if lure_catalog == null or selected_lure == null:
		return -1

	return lure_catalog.find_lure(selected_lure)


func get_lure_count() -> int:
	if lure_catalog == null:
		return 0

	return lure_catalog.get_lure_count()


func get_owned_lures() -> Array[BaitData]:
	var result: Array[BaitData] = []
	if lure_catalog == null:
		return result

	# Without an inventory (older scenes/tools), preserve historical behavior.
	if _inventory == null:
		for lure in lure_catalog.lures:
			if lure != null:
				result.append(lure)
		return result

	for lure in lure_catalog.lures:
		if lure != null and _inventory.owns_lure(lure):
			result.append(lure)

	return result


func get_owned_lure_count() -> int:
	return get_owned_lures().size()


func get_owned_lure(index: int) -> BaitData:
	var owned := get_owned_lures()
	if index < 0 or index >= owned.size():
		return null
	return owned[index]


func get_selected_owned_lure_index() -> int:
	if selected_lure == null:
		return -1
	return get_owned_lures().find(selected_lure)


func is_lure_owned(lure: BaitData) -> bool:
	return _inventory == null or _inventory.owns_lure(lure)


func is_rod_owned(rod: RodData) -> bool:
	return _inventory == null or _inventory.owns_rod(rod)


func _equip_lure_internal(lure: BaitData) -> void:
	if lure == null:
		return

	if lure_catalog != null and lure_catalog.find_lure(lure) == -1:
		push_warning(
			"FishingLoadout: refused to equip a lure outside the lure catalog."
		)
		return

	if selected_lure == lure:
		return

	selected_lure = lure
	lure_changed.emit(selected_lure)


func _equip_rod_internal(rod: RodData) -> void:
	if rod == null or selected_rod == rod:
		return

	selected_rod = rod
	rod_changed.emit(selected_rod)
