extends RefCounted
class_name FishingTideSenseQA

const TideServiceScript = preload(
	"res://scripts/fishing_tide_service.gd"
)
const EnvironmentServiceScript = preload(
	"res://scripts/fishing_environment_service.gd"
)
const TidePolicyScript = preload(
	"res://scripts/fishing_tide_sense_policy.gd"
)
const TideTechniqueResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/tide_sense.tres"
)


static func run(
	environment_catalog,
	mastery_catalog: FishingMasteryTechniqueCatalog,
	ocean_spot: FishingSpotData
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	if mastery_catalog != null and mastery_catalog.has_method("ensure_technique"):
		mastery_catalog.ensure_technique(TideTechniqueResource)

	var tide_definition := (
		mastery_catalog.get_technique(&"tide_sense")
		if mastery_catalog != null
		else null
	)
	_record(
		report,
		"Tide Sense is registered without replacing the catalog",
		tide_definition != null,
		"The incremental pass must append Tide Sense while preserving every existing mastery technique."
	)
	_record(
		report,
		"Tide Sense has both environmental prerequisites",
		_has_prerequisite(tide_definition, &"read_current")
		and _has_prerequisite(tide_definition, &"weather_sense"),
		"Tide Sense should build on current-reading and weather-reading knowledge."
	)

	var tide := TideServiceScript.new() as FishingTideService
	var current := FishingCurrentService.new()
	current.set_spot(ocean_spot)
	current.set_tide_service(tide)
	tide.set_spot(ocean_spot)

	_record(
		report,
		"Ocean spot activates tides",
		tide.is_active(),
		"Tide mechanics should exist on coastal/ocean water even before Tide Sense is learned."
	)

	var lake := FishingSpotData.new()
	lake.spot_id = &"qa_lake"
	lake.water_type = FishingSpotData.WaterType.LAKE
	tide.set_spot(lake)
	_record(
		report,
		"Lake water stays non-tidal",
		not tide.is_active()
		and is_equal_approx(tide.get_current_multiplier(), 1.0),
		"Tide v1 must not silently alter rivers or lakes."
	)
	tide.set_spot(ocean_spot)

	tide.set_cycle_position(0.0)
	var low := tide.get_snapshot()
	_record(
		report,
		"Low slack is a real cycle phase",
		low.get("phase_id", &"") == FishingTideService.PHASE_LOW_SLACK
		and float(low.get("flow_strength_ratio", 1.0)) < 0.05,
		"Low water should settle into readable slack rather than remain a generic current multiplier."
	)
	_record(
		report,
		"Low slack weakens coastal current",
		float(low.get("current_multiplier", 1.0)) < 0.75,
		"Slack tide should materially reduce the authored ocean current."
	)

	tide.set_cycle_position(0.25)
	var incoming := tide.get_snapshot()
	_record(
		report,
		"Incoming tide reaches strong flow",
		incoming.get("phase_id", &"") == FishingTideService.PHASE_INCOMING
		and float(incoming.get("flow_strength_ratio", 0.0)) > 0.95
		and float(incoming.get("current_multiplier", 1.0)) > 1.15,
		"Mid-incoming water should be a distinctly stronger current window."
	)
	var incoming_zones: Dictionary = incoming.get("zone_multipliers", {}) as Dictionary
	_record(
		report,
		"Incoming tide opens shoreline feeding lanes",
		float(incoming_zones.get("shore", 1.0))
		> float(incoming_zones.get("outer", 1.0)),
		"Rising coastal water should make near-shore water comparatively more productive."
	)
	var incoming_depth: Dictionary = incoming.get("depth_activity", {}) as Dictionary
	_record(
		report,
		"Incoming tide pushes activity shallower",
		float(incoming_depth.get("surface", 1.0))
		> float(incoming_depth.get("deep", 1.0)),
		"Flood tide should change where fish feed, not only the speed of the current."
	)

	tide.set_cycle_position(0.50)
	var high := tide.get_snapshot()
	_record(
		report,
		"High slack reaches high water with soft flow",
		high.get("phase_id", &"") == FishingTideService.PHASE_HIGH_SLACK
		and float(high.get("water_level_ratio", 0.0)) > 0.95
		and float(high.get("flow_strength_ratio", 1.0)) < 0.05,
		"High water should be distinct from the moving incoming/outgoing phases."
	)
	var high_zones: Dictionary = high.get("zone_multipliers", {}) as Dictionary
	_record(
		report,
		"High water keeps shoreline water open",
		float(high_zones.get("shore", 1.0))
		> float(high_zones.get("outer", 1.0)),
		"The high-tide window should preserve access to near-shore feeding water."
	)

	tide.set_cycle_position(0.75)
	var outgoing := tide.get_snapshot()
	_record(
		report,
		"Outgoing tide reaches strong flow",
		outgoing.get("phase_id", &"") == FishingTideService.PHASE_OUTGOING
		and float(outgoing.get("flow_strength_ratio", 0.0)) > 0.95,
		"Falling water needs a real outgoing phase rather than sharing the incoming read."
	)
	var outgoing_zones: Dictionary = outgoing.get("zone_multipliers", {}) as Dictionary
	_record(
		report,
		"Outgoing tide favors outer water",
		float(outgoing_zones.get("outer", 1.0))
		> float(outgoing_zones.get("shore", 1.0)),
		"Falling water should move productive fishing away from the bank."
	)
	var outgoing_depth: Dictionary = outgoing.get("depth_activity", {}) as Dictionary
	_record(
		report,
		"Outgoing tide favors deeper activity",
		float(outgoing_depth.get("deep", 1.0))
		> float(outgoing_depth.get("surface", 1.0)),
		"Species/depth movement should visibly differ between flood and ebb."
	)

	var shallow_fish := FishData.new()
	shallow_fish.fish_name = "QA Shallow"
	shallow_fish.species_id = &"qa_shallow"
	shallow_fish.preferred_depth_min = 0.05
	shallow_fish.preferred_depth_max = 0.25
	var deep_fish := FishData.new()
	deep_fish.fish_name = "QA Deep"
	deep_fish.species_id = &"qa_deep"
	deep_fish.preferred_depth_min = 0.75
	deep_fish.preferred_depth_max = 0.95

	tide.set_cycle_position(0.25)
	_record(
		report,
		"Incoming tide biases shallow species",
		tide.get_species_selection_multiplier(shallow_fish)
		> tide.get_species_selection_multiplier(deep_fish),
		"Tides should change species opportunity through authored depth preferences rather than hard-coded species names."
	)
	tide.set_cycle_position(0.75)
	_record(
		report,
		"Outgoing tide biases deep species",
		tide.get_species_selection_multiplier(deep_fish)
		> tide.get_species_selection_multiplier(shallow_fish),
		"Ebb tide should invert the flood-tide depth opportunity."
	)

	tide.set_cycle_position(0.0)
	var low_bite := tide.get_bite_activity_multiplier(0.5)
	tide.set_cycle_position(0.25)
	var incoming_bite := tide.get_bite_activity_multiplier(0.5)
	_record(
		report,
		"Moving tide improves feeding activity over low slack",
		incoming_bite > low_bite,
		"Feeding behavior must react to tide movement rather than making tide a presentation-only clock."
	)

	# The same authored current must physically speed up/slow down with tide.
	tide.set_cycle_position(0.0)
	var low_current := current.sample_current_at_uv(Vector2(0.5, 0.95), 2.0).length()
	tide.set_cycle_position(0.25)
	var flood_current := current.sample_current_at_uv(Vector2(0.5, 0.95), 2.0).length()
	_record(
		report,
		"Tide changes real lure current physics",
		ocean_spot == null
		or ocean_spot.current_speed <= 0.0
		or flood_current > low_current * 1.4,
		"Tide Sense must read a real change in lure drift, not fabricate a UI-only current forecast."
	)

	var unlock := FishingUnlockState.new()
	unlock.reset_unlocks(false)
	var mastery := FishingMasteryService.new()
	mastery.configure(mastery_catalog, unlock)
	var read_current := mastery_catalog.get_technique(&"read_current") if mastery_catalog != null else null
	var weather_sense := mastery_catalog.get_technique(&"weather_sense") if mastery_catalog != null else null
	if read_current != null:
		mastery.learn_technique(&"read_current", read_current.teacher_id, false)
	if weather_sense != null:
		mastery.learn_technique(&"weather_sense", weather_sense.teacher_id, false)

	var environment := EnvironmentServiceScript.new()
	environment.configure(environment_catalog)
	environment.set_mastery_service(mastery)
	environment.set_tide_service(tide)
	environment.set_spot(ocean_spot)

	var locked_read := environment.get_tide_sense_snapshot()
	_record(
		report,
		"Tide exists before Tide Sense is learned",
		not bool(locked_read.get("available", false))
		and str(locked_read.get("reason", "")) == "tide_sense_not_learned"
		and tide.is_active(),
		"Mastery should reveal tides, never create or enable them."
	)

	var tide_learned := mastery.learn_technique(
		&"tide_sense",
		tide_definition.teacher_id if tide_definition != null else &"",
		false
	)
	_record(
		report,
		"Correct master unlocks Tide Sense",
		bool(tide_learned.get("success", false))
		and mastery.has_capability(&"tide_sense")
		and bool(mastery.get_snapshot().get("can_read_tide", false)),
		"Tide Sense should persist through the same mastery/unlock backbone as every other technique."
	)

	tide.set_cycle_position(0.0)
	var low_read := environment.get_tide_sense_snapshot()
	_record(
		report,
		"Low slack read points away from the shoreline",
		bool(low_read.get("available", false))
		and low_read.get("current_strength", &"") == TidePolicyScript.FLOW_SLACK
		and low_read.get("favored_zone", &"") == TidePolicyScript.ZONE_OUTER
		and low_read.get("species_bias", &"") == TidePolicyScript.SPECIES_DEEP,
		"A learned Tide Sense should convert low-water mechanics into useful fishing advice."
	)

	tide.set_cycle_position(0.25)
	var incoming_read := environment.get_tide_sense_snapshot()
	_record(
		report,
		"Incoming read reports strong active shoreline water",
		incoming_read.get("current_strength", &"") == TidePolicyScript.FLOW_STRONG
		and incoming_read.get("feeding_window", &"") == TidePolicyScript.FEEDING_ACTIVE
		and incoming_read.get("favored_zone", &"") == TidePolicyScript.ZONE_SHORE
		and incoming_read.get("species_bias", &"") == TidePolicyScript.SPECIES_SHALLOW,
		"The flood-tide read should expose current, feeding, zone access and species movement together."
	)

	tide.set_cycle_position(0.50)
	var high_read := environment.get_tide_sense_snapshot()
	_record(
		report,
		"High slack read distinguishes high water from strong flow",
		high_read.get("water_level", &"") == TidePolicyScript.LEVEL_HIGH
		and high_read.get("current_strength", &"") == TidePolicyScript.FLOW_SLACK
		and high_read.get("favored_zone", &"") == TidePolicyScript.ZONE_SHORE,
		"High tide should not be mislabeled as a fast-current phase."
	)

	tide.set_cycle_position(0.75)
	var outgoing_read := environment.get_tide_sense_snapshot()
	_record(
		report,
		"Outgoing read reports deep outer-water opportunity",
		outgoing_read.get("current_strength", &"") == TidePolicyScript.FLOW_STRONG
		and outgoing_read.get("favored_zone", &"") == TidePolicyScript.ZONE_OUTER
		and outgoing_read.get("species_bias", &"") == TidePolicyScript.SPECIES_DEEP,
		"Ebb tide should produce a different tactical recommendation from incoming tide."
	)
	_record(
		report,
		"Tide Sense provides five concise read lines",
		outgoing_read.get("read_lines", PackedStringArray()).size() == 5,
		"The technique needs a compact presentation payload for a later HUD/menu without exposing raw multipliers."
	)
	_record(
		report,
		"Tide read keeps exact math under debug-resolved data",
		outgoing_read.has("resolved")
		and not outgoing_read.has("current_multiplier")
		and not outgoing_read.has("bite_activity_multiplier"),
		"Player-facing Tide Sense should remain qualitative while QA can inspect exact values."
	)

	# Weather Sense should continue to report weather only; learning Tide Sense is
	# what reveals the separate tidal layer.
	environment.activate_condition(&"rain")
	tide.set_cycle_position(0.0)
	var weather_low := environment.get_weather_sense_snapshot(5.0, 10.0)
	tide.set_cycle_position(0.25)
	var weather_flood := environment.get_weather_sense_snapshot(5.0, 10.0)
	_record(
		report,
		"Weather Sense does not leak Tide Sense information",
		weather_low.get("activity", &"") == weather_flood.get("activity", &"")
		and weather_low.get("favored_depth", &"") == weather_flood.get("favored_depth", &""),
		"The two environmental masteries should remain complementary instead of one revealing the other's hidden layer."
	)

	tide.set_cycle_position(0.25)
	var selection_in := environment.get_selection_context([
		_make_entry(shallow_fish),
		_make_entry(deep_fish),
	])
	tide.set_cycle_position(0.75)
	var selection_out := environment.get_selection_context([
		_make_entry(shallow_fish),
		_make_entry(deep_fish),
	])
	var in_species: Dictionary = selection_in.get("species_multipliers", {}) as Dictionary
	var out_species: Dictionary = selection_out.get("species_multipliers", {}) as Dictionary
	_record(
		report,
		"Encounter selection context carries tide species bias",
		float(in_species.get("qa_shallow", 1.0)) > float(in_species.get("qa_deep", 1.0))
		and float(out_species.get("qa_deep", 1.0)) > float(out_species.get("qa_shallow", 1.0)),
		"The existing fish-selection pipeline must receive tide effects without a parallel spawn system."
	)
	var in_zones: Dictionary = selection_in.get("tide_zone_multipliers", {}) as Dictionary
	var out_zones: Dictionary = selection_out.get("tide_zone_multipliers", {}) as Dictionary
	_record(
		report,
		"Encounter concentration context carries accessible-zone changes",
		float(in_zones.get("shore", 1.0)) > float(in_zones.get("outer", 1.0))
		and float(out_zones.get("outer", 1.0)) > float(out_zones.get("shore", 1.0)),
		"The existing concentration field should know whether shoreline or outer water is currently more productive."
	)

	tide.set_cycle_position(0.25)
	_record(
		report,
		"Tide phase forecasts its next transition",
		tide.get_next_phase_id() == FishingTideService.PHASE_HIGH_SLACK
		and tide.get_time_to_next_phase_seconds() > 0.0,
		"The readout needs deterministic forward context for a future clock/HUD."
	)

	tide.set_cycle_position(1.25)
	_record(
		report,
		"Tide cycle wraps deterministically",
		tide.get_phase_id() == FishingTideService.PHASE_INCOMING,
		"Long sessions must loop cleanly through repeated tides."
	)

	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


static func _make_entry(fish: FishData) -> FishSpawnEntry:
	var entry := FishSpawnEntry.new()
	entry.fish = fish
	entry.weight = 1.0
	return entry


static func _has_prerequisite(
	technique: FishingMasteryTechniqueDefinition,
	prerequisite_id: StringName
) -> bool:
	if technique == null:
		return false
	for raw_id in technique.prerequisite_ids:
		if str(raw_id) == str(prerequisite_id):
			return true
	return false


static func _record(
	report: Dictionary,
	name: String,
	passed: bool,
	detail: String
) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [name, detail])
	report["failures"] = failures
