extends Resource
class_name FishingContentCatalog

@export var fish: Array[FishData] = []
@export var spots: Array[FishingSpotData] = []
@export var tackle: FishingTackleCatalog


func get_rods() -> Array[RodData]:
	if tackle == null:
		return []
	return tackle.rods
