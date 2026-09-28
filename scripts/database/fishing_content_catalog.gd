extends Resource
class_name FishingContentCatalog

@export var fish: Array[FishData] = []
@export var spots: Array[FishingSpotData] = []
@export var tackle: FishingTackleCatalog


func get_rods() -> Array[RodData]:
	if tackle == null:
		return []
	return tackle.rods


func get_fish_by_id(species_id: StringName) -> FishData:
	if species_id == &"":
		return null
	var key := str(species_id).strip_edges().to_lower()
	for entry in fish:
		if entry != null and entry.get_stable_species_id().to_lower() == key:
			return entry
	return null


func has_fish(species_id: StringName) -> bool:
	return get_fish_by_id(species_id) != null
