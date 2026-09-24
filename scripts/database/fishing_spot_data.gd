extends Resource
class_name FishingSpotData

@export var spot_id: StringName = &""
@export var spot_name: String = ""
@export_multiline var location_description: String = ""

@export_category("Population")
@export var fish_population: Array[FishSpawnEntry] = []

@export_category("Ambient Shadow Identity")
## Presentation-only profile for how alive this fishing spot feels before a bite.
## Species selection still comes from fish_population.
@export var ambient_profile: AmbientFishProfile

@export_category("Notes")
@export_multiline var depth_notes: String = ""


func get_fish_population() -> Array[FishSpawnEntry]:
	return fish_population


func get_ambient_profile() -> AmbientFishProfile:
	return ambient_profile
