extends Node
class_name FishingLoadout

signal lure_changed(lure: BaitData)
signal rod_changed(rod: RodData)

@export_category("Equipped Fishing Gear")
@export var selected_lure: BaitData
@export var selected_rod: RodData


func _ready() -> void:
	if selected_lure == null:
		push_warning("FishingLoadout: no lure is equipped.")

	if selected_rod == null:
		push_warning("FishingLoadout: no rod is equipped.")


func equip_lure(lure: BaitData) -> void:
	if selected_lure == lure:
		return

	selected_lure = lure
	lure_changed.emit(selected_lure)


func equip_rod(rod: RodData) -> void:
	if selected_rod == rod:
		return

	selected_rod = rod
	rod_changed.emit(selected_rod)


func get_selected_lure() -> BaitData:
	return selected_lure


func get_selected_rod() -> RodData:
	return selected_rod
