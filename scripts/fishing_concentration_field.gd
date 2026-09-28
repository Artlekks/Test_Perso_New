extends RefCounted
class_name FishingConcentrationField

const DEFAULT_BASELINE_CONCENTRATION: float = 0.72
const MIN_BITE_DENSITY_MULTIPLIER: float = 0.45
const MAX_BITE_DENSITY_MULTIPLIER: float = 1.55
const RADAR_MIN_DOTS: int = 2
const RADAR_MAX_DOTS: int = 14

var fishing_spot: FishingSpotData = null
var swim_bounds: FishSwimBounds = null
var environment_context: Dictionary = {}


func configure(
	new_spot: FishingSpotData,
	new_swim_bounds: FishSwimBounds
) -> void:
	fishing_spot = new_spot
	swim_bounds = new_swim_bounds


func set_environment_context(context: Dictionary) -> void:
	environment_context = context.duplicate(true)


func sample(
	world_position: Vector3,
	current_depth: float,
	total_depth: float
) -> Dictionary:
	if fishing_spot == null or swim_bounds == null:
		return _empty_sample()

	var uv: Vector2 = (
		swim_bounds.world_to_normalized_uv(
			world_position
		)
	)
	var depth_ratio: float = 0.0

	if total_depth > 0.0:
		depth_ratio = clampf(
			current_depth / total_depth,
			0.0,
			1.0
		)

	var baseline: float = maxf(
		fishing_spot.baseline_concentration,
		0.01
	)
	var density: float = baseline
	var species_multipliers: Dictionary = {}
	var active_hotspots := PackedStringArray()

	for hotspot in fishing_spot.get_concentration_hotspots():
		if (
			hotspot == null
			or not hotspot.is_valid_definition()
		):
			continue

		var horizontal_strength: float = (
			hotspot.get_horizontal_strength(uv)
		)

		if horizontal_strength <= 0.0:
			continue

		var local_density: float = lerpf(
			baseline,
			hotspot.density_multiplier,
			horizontal_strength
		)
		density = maxf(
			density,
			local_density
		)

		if horizontal_strength >= 0.20:
			active_hotspots.append(
				str(hotspot.hotspot_id)
			)

		var depth_strength: float = (
			hotspot.get_depth_strength(
				depth_ratio
			)
		)
		var combined_strength: float = (
			horizontal_strength
			* depth_strength
		)

		if combined_strength <= 0.0:
			continue

		_apply_hotspot_species_multipliers(
			species_multipliers,
			hotspot,
			combined_strength
		)

	return {
		"uv": uv,
		"depth_ratio": depth_ratio,
		"baseline_concentration": baseline,
		"local_concentration": density,
		"bite_density_multiplier": clampf(
			density,
			MIN_BITE_DENSITY_MULTIPLIER,
			MAX_BITE_DENSITY_MULTIPLIER
		),
		"species_multipliers": species_multipliers,
		"active_hotspots": active_hotspots,
	}


func build_radar_snapshot(
	world_position: Vector3
) -> Dictionary:
	if fishing_spot == null or swim_bounds == null:
		return {
			"uv": Vector2(0.5, 0.5),
			"density": 0.0,
			"dot_count": 0,
			"dots": [],
			"active_hotspots": PackedStringArray(),
		}

	var uv: Vector2 = (
		swim_bounds.world_to_normalized_uv(
			world_position
		)
	)
	var baseline: float = maxf(
		fishing_spot.baseline_concentration,
		0.01
	)
	var density: float = baseline
	var horizontal_species: Dictionary = {}
	var active_hotspots := PackedStringArray()

	for hotspot in fishing_spot.get_concentration_hotspots():
		if (
			hotspot == null
			or not hotspot.is_valid_definition()
		):
			continue

		var strength: float = (
			hotspot.get_horizontal_strength(uv)
		)

		if strength <= 0.0:
			continue

		density = maxf(
			density,
			lerpf(
				baseline,
				hotspot.density_multiplier,
				strength
			)
		)

		if strength >= 0.20:
			active_hotspots.append(
				str(hotspot.hotspot_id)
			)

		_apply_hotspot_species_multipliers(
			horizontal_species,
			hotspot,
			strength
		)

	var weighted_species: Array[Dictionary] = []
	var total_weight: float = 0.0

	for entry in fishing_spot.get_fish_population():
		if entry == null or entry.fish == null:
			continue

		var species_id: String = (
			entry.fish.get_stable_species_id()
			.strip_edges()
			.to_lower()
		)
		var local_multiplier: float = maxf(
			float(
				horizontal_species.get(
					species_id,
					1.0
				)
			),
			0.0
		)
		var weight: float = (
			entry.get_ambient_weight(environment_context)
			* local_multiplier
		)

		if weight <= 0.0:
			continue

		weighted_species.append(
			{
				"fish": entry.fish,
				"weight": weight,
			}
		)
		total_weight += weight

	if total_weight <= 0.0:
		return {
			"uv": uv,
			"density": density,
			"dot_count": 0,
			"dots": [],
			"active_hotspots": active_hotspots,
		}

	var density_ratio: float = clampf(
		inverse_lerp(
			0.45,
			1.55,
			density
		),
		0.0,
		1.0
	)
	var dot_count: int = clampi(
		roundi(
			lerpf(
				float(RADAR_MIN_DOTS),
				float(RADAR_MAX_DOTS),
				density_ratio
			)
		),
		RADAR_MIN_DOTS,
		RADAR_MAX_DOTS
	)
	var dots: Array[Dictionary] = []
	var uv_bucket_x: int = roundi(uv.x * 20.0)
	var uv_bucket_y: int = roundi(uv.y * 20.0)

	for dot_index in range(dot_count):
		var seed_prefix: String = "%s:%d:%d:%d" % [
			str(fishing_spot.spot_id),
			uv_bucket_x,
			uv_bucket_y,
			dot_index,
		]
		var roll: float = (
			_stable_unit(seed_prefix + ":species")
			* total_weight
		)
		var fish: FishData = _choose_weighted_fish(
			weighted_species,
			roll
		)

		if fish == null:
			continue

		var depth_min: float = clampf(
			minf(
				fish.preferred_depth_min,
				fish.preferred_depth_max
			),
			0.0,
			1.0
		)
		var depth_max: float = clampf(
			maxf(
				fish.preferred_depth_min,
				fish.preferred_depth_max
			),
			0.0,
			1.0
		)
		var depth_ratio: float = lerpf(
			depth_min,
			depth_max,
			_stable_unit(
				seed_prefix + ":depth"
			)
		)
		var x_ratio: float = lerpf(
			0.12,
			0.88,
			_stable_unit(
				seed_prefix + ":x"
			)
		)

		dots.append(
			{
				"x_ratio": x_ratio,
				"depth_ratio": depth_ratio,
				"species_id": (
					fish.get_stable_species_id()
				),
			}
		)

	return {
		"uv": uv,
		"density": density,
		"dot_count": dots.size(),
		"dots": dots,
		"active_hotspots": active_hotspots,
	}


func _apply_hotspot_species_multipliers(
	target: Dictionary,
	hotspot: FishingHotspotDefinition,
	strength: float
) -> void:
	var applied_strength: float = clampf(
		strength,
		0.0,
		1.0
	)
	var candidate_multiplier: float = lerpf(
		1.0,
		hotspot.species_weight_multiplier,
		applied_strength
	)

	if hotspot.species_ids.is_empty():
		for entry in fishing_spot.get_fish_population():
			if entry == null or entry.fish == null:
				continue

			var species_id: String = (
				entry.fish.get_stable_species_id()
				.strip_edges()
				.to_lower()
			)
			target[species_id] = maxf(
				float(
					target.get(
						species_id,
						1.0
					)
				),
				candidate_multiplier
			)
		return

	for raw_id in hotspot.species_ids:
		var species_id: String = (
			str(raw_id)
			.strip_edges()
			.to_lower()
		)

		if species_id.is_empty():
			continue

		target[species_id] = maxf(
			float(
				target.get(
					species_id,
					1.0
				)
			),
			candidate_multiplier
		)


func _choose_weighted_fish(
	weighted_species: Array[Dictionary],
	roll: float
) -> FishData:
	var remaining: float = maxf(
		roll,
		0.0
	)

	for item in weighted_species:
		var weight: float = maxf(
			float(item.get("weight", 0.0)),
			0.0
		)
		remaining -= weight

		if remaining <= 0.0:
			return item.get("fish") as FishData

	if weighted_species.is_empty():
		return null

	return (
		weighted_species[
			weighted_species.size() - 1
		].get("fish")
		as FishData
	)


func _stable_unit(
	seed_text: String
) -> float:
	var hashed: int = absi(
		hash(seed_text)
	)
	return float(
		hashed % 10000
	) / 9999.0


func _empty_sample() -> Dictionary:
	return {
		"uv": Vector2(0.5, 0.5),
		"depth_ratio": 0.0,
		"baseline_concentration": 1.0,
		"local_concentration": 1.0,
		"bite_density_multiplier": 1.0,
		"species_multipliers": {},
		"active_hotspots": PackedStringArray(),
	}
