extends Resource
class_name FishingSpotData

@export var spot_id: StringName = &""
@export var spot_name: String = ""
@export_multiline var location_description: String = ""

@export_category("Population")
@export var fish_population: Array[FishSpawnEntry] = []

@export_category("Notes")
@export_multiline var depth_notes: String = ""


func get_fish_population() -> Array[FishSpawnEntry]:
	return fish_population
