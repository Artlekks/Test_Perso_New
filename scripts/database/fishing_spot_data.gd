extends Resource
class_name FishingSpotData

enum WaterType {
	RIVER,
	LAKE,
	OCEAN,
	SPECIAL,
}

@export_category("Identity")
@export var spot_id: StringName = &""
@export var spot_name: String = ""
@export_multiline var location_description: String = ""
@export var water_type: WaterType = WaterType.RIVER

@export_category("Population")
@export var fish_population: Array[FishSpawnEntry] = []

@export_category("Spatial Concentration")
## Baseline local fish density away from authored hotspots.
## 1.0 = neutral bite frequency. Lower values make empty water feel emptier.
@export_range(0.25, 1.50, 0.05)
var baseline_concentration: float = 0.72

@export var concentration_hotspots: Array[FishingHotspotDefinition] = []

@export_category("Ambient Shadow Identity")
## Presentation-only profile for how alive this fishing spot feels before a bite.
## Species selection still comes from fish_population.
@export var ambient_profile: AmbientFishProfile

@export_category("Strategy Metadata")
## Recommendations only. They are not hard gameplay gates.
@export_range(0, 3, 1)
var recommended_min_lure_level: int = 0

@export_multiline var strategy_notes: String = ""

@export_category("Notes")
@export_multiline var depth_notes: String = ""


func get_fish_population() -> Array[FishSpawnEntry]:
	return fish_population


func get_ambient_profile() -> AmbientFishProfile:
	return ambient_profile


func get_concentration_hotspots() -> Array[FishingHotspotDefinition]:
	return concentration_hotspots


func get_hotspot_count() -> int:
	var count: int = 0

	for hotspot in concentration_hotspots:
		if (
			hotspot != null
			and hotspot.is_valid_definition()
		):
			count += 1

	return count


func get_valid_species_count() -> int:
	var count: int = 0

	for entry in fish_population:
		if entry == null or entry.fish == null:
			continue
		count += 1

	return count


func get_total_base_bite_weight() -> float:
	var total: float = 0.0

	for entry in fish_population:
		if entry == null:
			continue
		total += entry.get_base_bite_weight()

	return total


func get_total_ambient_weight() -> float:
	var total: float = 0.0

	for entry in fish_population:
		if entry == null:
			continue
		total += entry.get_ambient_weight()

	return total


func get_water_type_label() -> String:
	match water_type:
		WaterType.RIVER:
			return "RIVER"
		WaterType.LAKE:
			return "LAKE"
		WaterType.OCEAN:
			return "OCEAN"
		WaterType.SPECIAL:
			return "SPECIAL"
		_:
			return "UNKNOWN"


func get_population_species_names() -> PackedStringArray:
	var names := PackedStringArray()

	for entry in fish_population:
		if entry == null or entry.fish == null:
			continue
		names.append(entry.fish.fish_name)

	return names


func get_debug_summary() -> String:
	var lure_note: String = ""

	if recommended_min_lure_level > 0:
		lure_note = " | Lure%d+ rec." % recommended_min_lure_level

	return "%s | %s | %d species | %d hotspots | biteW %.1f | ambW %.1f%s" % [
		spot_name,
		get_water_type_label(),
		get_valid_species_count(),
		get_hotspot_count(),
		get_total_base_bite_weight(),
		get_total_ambient_weight(),
		lure_note,
	]
