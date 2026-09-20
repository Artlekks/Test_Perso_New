extends Node
class_name FishingLoadout

signal lure_changed(lure: BaitData)
signal rod_changed(rod: RodData)

@export_category("Fishing Database")
@export var lure_catalog: FishingLureCatalog

@export_category("Equipped Fishing Gear")
@export var selected_lure: BaitData
@export var selected_rod: RodData


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


func equip_lure(lure: BaitData) -> void:
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


func equip_rod(rod: RodData) -> void:
	if rod == null or selected_rod == rod:
		return

	selected_rod = rod
	rod_changed.emit(selected_rod)


func select_lure_index(index: int) -> void:
	if lure_catalog == null:
		return

	var lure_count := lure_catalog.get_lure_count()

	if lure_count <= 0:
		return

	var wrapped_index := posmod(index, lure_count)
	equip_lure(lure_catalog.get_lure(wrapped_index))


func select_next_lure() -> void:
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
