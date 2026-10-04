extends RefCounted
class_name FishingFishSignPolicy

## Read Fish Sign v1
##
## Converts existing ambient-fish behavior into qualitative field signs. This
## policy never changes spawn weights, bite odds, fish movement or fight stats.
## The mastery only reveals information already present in the water.

const SIGN_NONE: StringName = &"none"
const SIGN_FEEDING_TURN: StringName = &"feeding_turn"
const SIGN_SURFACE_BOIL: StringName = &"surface_boil"
const SIGN_BAITFISH_SCATTER: StringName = &"baitfish_scatter"
const SIGN_DEEP_BUBBLES: StringName = &"deep_bubbles"
const SIGN_SHADOW_TRACK: StringName = &"shadow_track"

const DEPTH_SURFACE: StringName = &"surface"
const DEPTH_MID: StringName = &"mid"
const DEPTH_DEEP: StringName = &"deep"
const DEPTH_MIXED: StringName = &"mixed"

const ACTIVITY_QUIET: StringName = &"quiet"
const ACTIVITY_ACTIVE: StringName = &"active"
const ACTIVITY_FEEDING: StringName = &"feeding"

const WARINESS_BOLD: StringName = &"bold"
const WARINESS_WARY: StringName = &"wary"
const WARINESS_VERY_WARY: StringName = &"very_wary"

const SIZE_SMALL: StringName = &"small"
const SIZE_MEDIUM: StringName = &"medium"
const SIZE_LARGE: StringName = &"large"

const SIGN_PRIORITY: Array[StringName] = [
	SIGN_FEEDING_TURN,
	SIGN_SURFACE_BOIL,
	SIGN_BAITFISH_SCATTER,
	SIGN_DEEP_BUBBLES,
	SIGN_SHADOW_TRACK,
]


static func build_observation(
	fish: FishData,
	pre_bite_state: String = "ROAM",
	readable: bool = true
) -> Dictionary:
	if fish == null:
		return {}

	var depth_min := clampf(
		minf(fish.preferred_depth_min, fish.preferred_depth_max),
		0.0,
		1.0
	)
	var depth_max := clampf(
		maxf(fish.preferred_depth_min, fish.preferred_depth_max),
		0.0,
		1.0
	)
	var depth_ratio := (depth_min + depth_max) * 0.5
	var lateral_activity := 0.5
	var vertical_activity := 0.5
	var difficulty_tier := 1
	if fish.behavior_profile != null:
		lateral_activity = clampf(fish.behavior_profile.lateral_activity, 0.0, 1.0)
		vertical_activity = clampf(fish.behavior_profile.vertical_activity, 0.0, 1.0)
		difficulty_tier = clampi(int(fish.behavior_profile.difficulty_tier), 1, 5)

	var state_upper := pre_bite_state.strip_edges().to_upper()
	var feeding := state_upper in ["WATCH", "APPROACH", "INSPECT", "BITE_READY"]
	var sign_id := classify_sign(
		depth_ratio,
		fish.average_size,
		lateral_activity,
		vertical_activity,
		feeding,
		readable
	)

	return {
		"species_id": fish.get_stable_species_id(),
		"species_name": fish.get_journal_name(),
		"sign_id": sign_id,
		"depth_ratio": depth_ratio,
		"average_size": maxf(fish.average_size, 0.0),
		"wariness": clampf(fish.approach_wariness, 0.0, 1.0),
		"lateral_activity": lateral_activity,
		"vertical_activity": vertical_activity,
		"difficulty_tier": difficulty_tier,
		"feeding": feeding,
		"readable": readable,
	}


static func classify_sign(
	depth_ratio: float,
	average_size: float,
	lateral_activity: float,
	vertical_activity: float,
	feeding: bool,
	readable: bool
) -> StringName:
	var depth := clampf(depth_ratio, 0.0, 1.0)
	var lateral := clampf(lateral_activity, 0.0, 1.0)
	var vertical := clampf(vertical_activity, 0.0, 1.0)

	if feeding:
		return SIGN_FEEDING_TURN
	if depth <= 0.32 and vertical >= 0.62:
		return SIGN_SURFACE_BOIL
	if average_size <= 48.0 and lateral >= 0.72:
		return SIGN_BAITFISH_SCATTER
	if depth >= 0.68:
		return SIGN_DEEP_BUBBLES
	if readable:
		return SIGN_SHADOW_TRACK
	return SIGN_NONE


static func build_read_snapshot(observations: Array) -> Dictionary:
	var valid: Array[Dictionary] = []
	for raw_item in observations:
		if not (raw_item is Dictionary):
			continue
		var item := raw_item as Dictionary
		if item.is_empty():
			continue
		valid.append(item)

	if valid.is_empty():
		return {
			"available": true,
			"sign_count": 0,
			"dominant_sign": SIGN_NONE,
			"activity": ACTIVITY_QUIET,
			"depth_hint": DEPTH_MIXED,
			"wariness_hint": WARINESS_BOLD,
			"size_hint": SIZE_SMALL,
			"likely_species": PackedStringArray(),
			"read_lines": PackedStringArray([
				"Sign: The water is quiet.",
				"Activity: No clear feeding movement.",
				"Depth: No reliable depth sign.",
				"Species: No readable sign yet.",
			]),
			"resolved_debug": {"observation_count": 0},
		}

	var sign_counts: Dictionary = {}
	var species_scores: Dictionary = {}
	var species_names: Dictionary = {}
	var depth_sum := 0.0
	var depth_min := 1.0
	var depth_max := 0.0
	var wariness_sum := 0.0
	var size_sum := 0.0
	var activity_sum := 0.0
	var feeding_count := 0

	for item in valid:
		var sign_id := StringName(str(item.get("sign_id", SIGN_NONE)))
		sign_counts[sign_id] = int(sign_counts.get(sign_id, 0)) + 1

		var depth := clampf(float(item.get("depth_ratio", 0.5)), 0.0, 1.0)
		depth_sum += depth
		depth_min = minf(depth_min, depth)
		depth_max = maxf(depth_max, depth)
		wariness_sum += clampf(float(item.get("wariness", 0.5)), 0.0, 1.0)
		size_sum += maxf(float(item.get("average_size", 0.0)), 0.0)
		activity_sum += (
			clampf(float(item.get("lateral_activity", 0.5)), 0.0, 1.0)
			+ clampf(float(item.get("vertical_activity", 0.5)), 0.0, 1.0)
		) * 0.5

		var feeding := bool(item.get("feeding", false))
		if feeding:
			feeding_count += 1

		var species_id := str(item.get("species_id", "")).strip_edges()
		if not species_id.is_empty():
			var species_weight := 1.0
			if feeding:
				species_weight += 0.75
			if bool(item.get("readable", false)):
				species_weight += 0.25
			species_scores[species_id] = float(species_scores.get(species_id, 0.0)) + species_weight
			species_names[species_id] = str(item.get("species_name", species_id))

	var count := float(valid.size())
	var average_depth := depth_sum / count
	var average_wariness := wariness_sum / count
	var average_size := size_sum / count
	var average_activity := activity_sum / count
	var dominant_sign := _get_dominant_sign(sign_counts)
	var depth_hint := _get_depth_hint(average_depth, depth_min, depth_max)
	var activity := _get_activity_hint(average_activity, feeding_count, valid.size())
	var wariness_hint := _get_wariness_hint(average_wariness)
	var size_hint := _get_size_hint(average_size)
	var likely_species := _get_likely_species(species_scores, species_names)

	return {
		"available": true,
		"sign_count": valid.size(),
		"dominant_sign": dominant_sign,
		"activity": activity,
		"depth_hint": depth_hint,
		"wariness_hint": wariness_hint,
		"size_hint": size_hint,
		"likely_species": likely_species,
		"read_lines": PackedStringArray([
			"Sign: %s" % _get_sign_label(dominant_sign),
			"Activity: %s" % _get_activity_label(activity),
			"Depth: %s" % _get_depth_label(depth_hint),
			"Species: %s" % _get_species_label(likely_species),
		]),
		"resolved_debug": {
			"observation_count": valid.size(),
			"feeding_count": feeding_count,
			"average_depth": average_depth,
			"average_wariness": average_wariness,
			"average_size": average_size,
			"average_activity": average_activity,
			"sign_counts": sign_counts.duplicate(true),
		},
	}


static func _get_dominant_sign(sign_counts: Dictionary) -> StringName:
	var best := SIGN_NONE
	var best_count := 0
	for sign_id in SIGN_PRIORITY:
		var count := int(sign_counts.get(sign_id, 0))
		if count > best_count:
			best = sign_id
			best_count = count
	return best


static func _get_depth_hint(
	average_depth: float,
	minimum_depth: float,
	maximum_depth: float
) -> StringName:
	if maximum_depth - minimum_depth >= 0.42:
		return DEPTH_MIXED
	if average_depth <= 0.34:
		return DEPTH_SURFACE
	if average_depth >= 0.67:
		return DEPTH_DEEP
	return DEPTH_MID


static func _get_activity_hint(
	average_activity: float,
	feeding_count: int,
	observation_count: int
) -> StringName:
	if feeding_count > 0 and feeding_count * 2 >= maxi(observation_count, 1):
		return ACTIVITY_FEEDING
	if average_activity >= 0.70 or feeding_count > 0:
		return ACTIVITY_ACTIVE
	return ACTIVITY_QUIET


static func _get_wariness_hint(average_wariness: float) -> StringName:
	if average_wariness >= 0.76:
		return WARINESS_VERY_WARY
	if average_wariness >= 0.48:
		return WARINESS_WARY
	return WARINESS_BOLD


static func _get_size_hint(average_size: float) -> StringName:
	if average_size >= 110.0:
		return SIZE_LARGE
	if average_size >= 50.0:
		return SIZE_MEDIUM
	return SIZE_SMALL


static func _get_likely_species(
	species_scores: Dictionary,
	species_names: Dictionary
) -> PackedStringArray:
	var result := PackedStringArray()
	var used: Dictionary = {}
	for _slot in range(2):
		var best_id := ""
		var best_score := -1.0
		for raw_id in species_scores.keys():
			var species_id := str(raw_id)
			if used.has(species_id):
				continue
			var score := float(species_scores.get(raw_id, 0.0))
			if score > best_score:
				best_score = score
				best_id = species_id
		if best_id.is_empty():
			break
		used[best_id] = true
		result.append(str(species_names.get(best_id, best_id)))
	return result


static func _get_sign_label(sign_id: StringName) -> String:
	match sign_id:
		SIGN_FEEDING_TURN:
			return "Fish are turning on food."
		SIGN_SURFACE_BOIL:
			return "Surface boils and rising movement."
		SIGN_BAITFISH_SCATTER:
			return "Small fish are scattering."
		SIGN_DEEP_BUBBLES:
			return "Deep bubbles and bottom movement."
		SIGN_SHADOW_TRACK:
			return "A readable shadow track."
		_:
			return "The water is quiet."


static func _get_activity_label(activity: StringName) -> String:
	match activity:
		ACTIVITY_FEEDING:
			return "Fish are actively feeding."
		ACTIVITY_ACTIVE:
			return "Fish are moving with purpose."
		_:
			return "No strong feeding push."


static func _get_depth_label(depth_hint: StringName) -> String:
	match depth_hint:
		DEPTH_SURFACE:
			return "Activity is high in the water."
		DEPTH_DEEP:
			return "Activity is holding deep."
		DEPTH_MID:
			return "Activity is centered in mid-water."
		_:
			return "Signs are spread through the water column."


static func _get_species_label(likely_species: PackedStringArray) -> String:
	if likely_species.is_empty():
		return "No reliable species read."
	if likely_species.size() == 1:
		return likely_species[0]
	return "%s / %s" % [likely_species[0], likely_species[1]]
