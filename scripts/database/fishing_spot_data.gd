extends Resource
class_name FishingSpotData

@export var spot_id: StringName = &""
@export var spot_name: String = ""
@export_multiline var location_description: String = ""

@export_category("Population")
@export var fish_population: Array[FishSpawnEntry] = []


@export_category("Ambient Shadow Identity")
## Presentation-only controls for how alive this fishing spot feels before a bite.
## Species selection still comes from fish_population; these values only shape
## how that population is presented in the water.
@export_range(1, 3, 1)
var ambient_shadow_min: int = 1

@export_range(1, 3, 1)
var ambient_shadow_max: int = 3

@export_range(0.0, 1.0, 0.05)
var ambient_one_shadow_weight: float = 0.55

@export_range(0.0, 1.0, 0.05)
var ambient_two_shadow_weight: float = 0.32

@export_range(0.0, 1.0, 0.05)
var ambient_three_shadow_weight: float = 0.13

## Added to the species-preferred normalized depth chosen for an ambient shadow.
## Negative = generally shallower; positive = generally deeper.
@export_range(-0.35, 0.35, 0.01)
var ambient_depth_bias: float = 0.0

@export_range(0.5, 1.5, 0.05)
var ambient_speed_multiplier: float = 1.0

@export_range(0.5, 2.0, 0.05)
var ambient_lifetime_multiplier: float = 1.0

@export_category("Notes")
@export_multiline var depth_notes: String = ""


func get_fish_population() -> Array[FishSpawnEntry]:
	return fish_population
