extends RefCounted
class_name FishingWeatherSenseQA

const Policy = preload("res://scripts/fishing_weather_sense_policy.gd")
const EnvironmentServiceScript = preload(
	"res://scripts/fishing_environment_service.gd"
)
const MasteryServiceScript = preload(
	"res://scripts/mastery/fishing_mastery_service.gd"
)
const UnlockStateScript = preload(
	"res://scripts/fishing_unlock_state.gd"
)


static func run(
	environment_catalog,
	mastery_catalog: FishingMasteryTechniqueCatalog
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	var weather_definition = (
		mastery_catalog.get_technique(&"weather_sense")
		if mastery_catalog != null
		else null
	)
	_record(
		report,
		"Weather Sense is authored",
		weather_definition != null,
		"The read mechanic must stay attached to the canonical mastery catalog."
	)
	_record(
		report,
		"Weather Sense exposes a stable capability",
		weather_definition != null
		and weather_definition.has_capability(&"weather_sense"),
		"Runtime systems should query a capability tag instead of a tutorial flag."
	)

	var unlock = UnlockStateScript.new()
	unlock.reset_unlocks(false)
	var mastery = MasteryServiceScript.new()
	mastery.configure(mastery_catalog, unlock)
	var environment = EnvironmentServiceScript.new()
	environment.configure(environment_catalog)
	environment.set_mastery_service(mastery)

	var locked := environment.get_weather_sense_snapshot(5.0, 10.0)
	_record(
		report,
		"Fishing interpretation is hidden before learning",
		not bool(locked.get("available", true))
		and str(locked.get("reason", "")) == "weather_sense_not_learned",
		"Visible weather can exist before mastery, but its fishing meaning should be learned knowledge."
	)
	_record(
		report,
		"Visible conditions are not hidden by mastery",
		locked.get("condition_ids", PackedStringArray()).has("calm"),
		"Weather Sense must reveal interpretation, not pretend the player cannot see calm/rain/storms."
	)

	var learned := mastery.learn_technique(
		&"weather_sense",
		weather_definition.teacher_id if weather_definition != null else &"",
		false
	)
	_record(
		report,
		"Correct master unlocks Weather Sense",
		bool(learned.get("success", false))
		and mastery.has_capability(&"weather_sense"),
		"The runtime read must use the same persistent mastery backbone as the other techniques."
	)

	var calm := environment.get_weather_sense_snapshot(5.0, 10.0)
	_record(
		report,
		"Calm becomes a readable Weather Sense snapshot",
		bool(calm.get("available", false))
		and calm.get("condition_ids", PackedStringArray()).has("calm"),
		"Learning the technique should immediately produce a stable observation model."
	)
	_record(
		report,
		"Calm reads as normal activity",
		calm.get("activity", &"") == Policy.ACTIVITY_NORMAL,
		"Neutral baseline weather should not falsely advertise a feeding window."
	)
	_record(
		report,
		"Calm reads as even water-column activity",
		calm.get("favored_depth", &"") == Policy.DEPTH_EVEN,
		"The technique should not invent a depth preference where none exists."
	)
	_record(
		report,
		"Calm reads as ordinary specimen opportunity",
		calm.get("specimen_outlook", &"") == Policy.SPECIMEN_NORMAL,
		"Quality information must reflect the existing environment quality rolls."
	)
	_record(
		report,
		"Calm reads as stable fight conditions",
		calm.get("fight_outlook", &"") == Policy.FIGHT_NORMAL,
		"Neutral line/fight modifiers need a neutral qualitative read."
	)

	environment.activate_condition(&"rain")
	var rain := environment.get_weather_sense_snapshot(5.0, 10.0)
	var rain_resolved: Dictionary = rain.get("resolved", {})
	_record(
		report,
		"Rain replaces calm inside the weather group",
		rain.get("condition_ids", PackedStringArray()).has("rain")
		and not rain.get("condition_ids", PackedStringArray()).has("calm"),
		"Weather Sense must consume the same stacking-group rules as fishing gameplay."
	)
	_record(
		report,
		"Rain reports a restrained feeding change",
		rain.get("activity", &"") == Policy.ACTIVITY_NORMAL
		and float(rain_resolved.get("bite_activity_multiplier", 0.0)) > 1.0
		and float(rain_resolved.get("bite_activity_multiplier", 0.0)) < 1.08,
		"Rain slightly changes bite activity without advertising a universal feeding window."
	)
	_record(
		report,
		"Rain reports a nearly even water column",
		rain.get("favored_depth", &"") == Policy.DEPTH_EVEN
		and float(rain_resolved.get("deep_activity_multiplier", 0.0)) > float(rain_resolved.get("surface_activity_multiplier", 0.0))
		and float(rain_resolved.get("deep_activity_multiplier", 0.0)) - float(rain_resolved.get("surface_activity_multiplier", 0.0)) <= Policy.DEPTH_EVEN_TOLERANCE,
		"A small authored deep-water difference should remain below the advice threshold."
	)
	_record(
		report,
		"Rain keeps ordinary specimen outlook",
		rain.get("specimen_outlook", &"") == Policy.SPECIMEN_NORMAL
		and float(rain_resolved.get("quality_bonus_roll_chance", 0.0)) > 0.0
		and float(rain_resolved.get("quality_bonus_roll_chance", 0.0)) < 0.04
		and int(rain_resolved.get("quality_bonus_rolls", 0)) == 1,
		"A small extra quality-roll chance should not promise better specimens."
	)
	_record(
		report,
		"Rain reports a modestly harder fight",
		rain.get("fight_outlook", &"") == Policy.FIGHT_DEMANDING,
		"Weather Sense should communicate authored pressure risk without adding a buff or penalty."
	)

	environment.activate_condition(&"tempest")
	var tempest := environment.get_weather_sense_snapshot(5.0, 10.0)
	var tempest_resolved: Dictionary = tempest.get("resolved", {})
	_record(
		report,
		"Tempest avoids a universal feeding promise",
		tempest.get("activity", &"") == Policy.ACTIVITY_NORMAL
		and float(tempest_resolved.get("bite_activity_multiplier", 0.0)) >= 0.93
		and float(tempest_resolved.get("bite_activity_multiplier", 0.0)) < 1.08
		and float(tempest_resolved.get("bite_activity_multiplier", 0.0)) < float(rain_resolved.get("bite_activity_multiplier", 0.0)),
		"Severe weather shifts depth and tackle risk without making all fish feed faster."
	)
	_record(
		report,
		"Tempest reports limited specimen opportunity",
		tempest.get("specimen_outlook", &"") == Policy.SPECIMEN_PROMISING
		and float(tempest_resolved.get("quality_bonus_roll_chance", 0.0)) >= 0.04
		and float(tempest_resolved.get("quality_bonus_roll_chance", 0.0)) < 0.15
		and float(tempest_resolved.get("quality_bonus_roll_chance", 0.0)) > float(rain_resolved.get("quality_bonus_roll_chance", 0.0))
		and int(tempest_resolved.get("quality_bonus_rolls", 0)) == 1,
		"A modest quality chance is promising, not an exceptional-specimen guarantee."
	)
	_record(
		report,
		"Tempest reports harsh fight conditions",
		tempest.get("fight_outlook", &"") == Policy.FIGHT_HARSH,
		"Pressure plus reduced line/hook margins should read as a genuine combat warning."
	)
	_record(
		report,
		"Tempest exposes its trophy-fish bias",
		tempest.get("tier_bias", &"") == Policy.TIER_TROPHY,
		"Weather Sense should reveal the existing high-tier selection bias instead of modifying spawn tables."
	)

	environment.activate_condition(&"dawn")
	var composed := environment.get_weather_sense_snapshot(5.0, 10.0)
	var composed_ids: PackedStringArray = composed.get(
		"condition_ids",
		PackedStringArray()
	)
	_record(
		report,
		"Weather and light/time information compose",
		composed_ids.has("tempest") and composed_ids.has("dawn"),
		"Weather Sense should read the resolved environment, not only one condition resource."
	)

	environment.activate_condition(&"night")
	var night := environment.get_weather_sense_snapshot(8.0, 10.0)
	var night_ids: PackedStringArray = night.get(
		"condition_ids",
		PackedStringArray()
	)
	_record(
		report,
		"Time conditions replace one another without replacing weather",
		night_ids.has("tempest")
		and night_ids.has("night")
		and not night_ids.has("dawn"),
		"The interpretation layer must preserve the environment service stacking contract."
	)
	_record(
		report,
		"Weather Sense produces concise qualitative read lines",
		night.get("read_lines", PackedStringArray()).size() == 5,
		"Future menu/HUD presentation should consume short fishing observations rather than raw multipliers."
	)

	environment.free()
	mastery.free()
	unlock.free()
	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


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
