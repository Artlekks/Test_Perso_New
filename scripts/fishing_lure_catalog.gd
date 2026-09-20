extends Resource
class_name FishingLureCatalog

@export var lures: Array[BaitData] = []


func get_lure_count() -> int:
	return lures.size()


func get_lure(index: int) -> BaitData:
	if index < 0 or index >= lures.size():
		return null

	return lures[index]


func find_lure(lure: BaitData) -> int:
	return lures.find(lure)
