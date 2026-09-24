extends Resource
class_name FishingTackleCatalog

@export var lure_catalog: FishingLureCatalog
@export var rods: Array[RodData] = []


func get_lure_by_id(lure_id: StringName) -> BaitData:
	if lure_catalog == null or lure_id == &"":
		return null

	for lure in lure_catalog.lures:
		if lure != null and lure.lure_id == lure_id:
			return lure

	return null


func get_rod_by_id(rod_id: StringName) -> RodData:
	if rod_id == &"":
		return null

	for rod in rods:
		if rod != null and rod.rod_id == rod_id:
			return rod

	return null


func has_lure(lure_id: StringName) -> bool:
	return get_lure_by_id(lure_id) != null


func has_rod(rod_id: StringName) -> bool:
	return get_rod_by_id(rod_id) != null
