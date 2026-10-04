extends RefCounted
class_name FishingFightCombatQA

const PressurePolicy = preload(
	"res://scripts/fishing_fight_pressure_policy.gd"
)
const FightIntent = preload(
	"res://scripts/fishing_fight_intent.gd"
)
const StructurePolicy = preload(
	"res://scripts/fishing_structure_combat_policy.gd"
)
const LandingPolicy = preload(
	"res://scripts/fishing_landing_policy.gd"
)


static func run() -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	var safe_min := 0.30
	var safe_max := 0.70
	var low := PressurePolicy.get_fatigue_multiplier(0.31, safe_min, safe_max)
	var middle := PressurePolicy.get_fatigue_multiplier(0.50, safe_min, safe_max)
	var high := PressurePolicy.get_fatigue_multiplier(0.69, safe_min, safe_max)

	_record(report, "Safe pressure has continuous leverage", low > 0.0 and middle > low and high > middle, "Higher legal line pressure should exhaust the fish faster without changing failure thresholds.")
	_record(report, "Middle pressure stays near baseline", absf(middle - 1.0) < 0.02, "The middle of the existing safe band should preserve the old fight pace.")
	_record(report, "Slack gives no fatigue leverage", is_zero_approx(PressurePolicy.get_fatigue_multiplier(0.20, safe_min, safe_max)), "A slack line should not tire the fish through reeling pressure.")
	_record(report, "Overload gives no fatigue leverage", is_zero_approx(PressurePolicy.get_fatigue_multiplier(0.80, safe_min, safe_max)), "Unsafe overload is a failure risk, not a secret faster exhaustion exploit.")
	_record(report, "Pressure bands are stable", PressurePolicy.get_band(0.35, safe_min, safe_max) == &"light" and PressurePolicy.get_band(0.50, safe_min, safe_max) == &"working" and PressurePolicy.get_band(0.65, safe_min, safe_max) == &"heavy", "Line Feel and future HUD work need stable light/working/heavy pressure vocabulary.")

	var surge := FightIntent.build_snapshot(FightIntent.SURGE_AWAY, 0.9, 1.0, 0.0, 0.0, 1.0, false)
	_record(report, "Surge intent is readable", surge.get("intent_id", &"") == &"surge_away" and str(surge.get("label", "")) == "RUN", "Fish movement choices should expose a stable intent instead of forcing UI to infer it from velocity.")

	var left_run := FightIntent.build_snapshot(FightIntent.SIDE_RUN, 0.8, 1.0, -1.0, 0.0, 0.6, false)
	var right_run := FightIntent.build_snapshot(FightIntent.SIDE_RUN, 0.8, 1.0, 1.0, 0.0, 0.6, false)
	_record(report, "Side-run direction is readable", str(left_run.get("label", "")) == "RUN LEFT" and str(right_run.get("label", "")) == "RUN RIGHT", "Counter-steering lessons need to know which way the fish is committing.")

	var dive := FightIntent.build_snapshot(FightIntent.DIVE, 0.8, 1.0, 0.1, -1.0, 0.8, false)
	_record(report, "Dive intent stays distinct", dive.get("intent_id", &"") == &"dive" and float(dive.get("depth", 0.0)) < -0.9, "Deep-water control must be able to distinguish a dive from generic resistance.")

	var thrash := FightIntent.build_snapshot(FightIntent.ERRATIC, 1.0, 0.4, 0.7, -0.3, 1.0, true)
	_record(report, "Thrash overrides normal intent label", thrash.get("intent_id", &"") == &"thrash" and str(thrash.get("label", "")) == "THRASH", "Sudden high-risk bursts need an explicit telegraph hook for presentation and mastery systems.")

	var pressure_snapshot := PressurePolicy.build_snapshot(0.69, safe_min, safe_max)
	_record(report, "Pressure snapshot is UI-ready", pressure_snapshot.get("band", &"") == &"heavy" and float(pressure_snapshot.get("safe_ratio", 0.0)) > 0.9, "Future Line Feel presentation should consume one read model rather than recompute fight rules.")

	var bait_pos := Vector3(2.0, 0.0, 0.0)
	var cover_pos := Vector3(1.0, 0.0, 0.0)
	var escape_sign := StructurePolicy.get_escape_steering_sign(bait_pos, cover_pos)
	_record(report, "Structure escape direction is stable", escape_sign > 0.0, "A fish beside cover needs a deterministic side-pressure direction for escape guidance.")
	_record(report, "Steering away is recognized", StructurePolicy.is_steering_away(0.8, escape_sign), "A/D structure fighting should recognize deliberate rod pressure away from cover.")
	_record(report, "Fish drive into cover is recognized", StructurePolicy.is_fish_driving_into_structure(-0.8, escape_sign), "The fight needs to know when the fish is using the opposite side to bury the line in structure.")
	var seek_lateral := StructurePolicy.get_structure_seek_lateral(0.0, escape_sign, 0.75)
	_record(report, "Structure seek biases fish toward cover", seek_lateral < -0.5, "A hooked fish near cover should be able to deliberately choose the dangerous side instead of structure being passive scenery.")
	var low_abrasion := StructurePolicy.get_abrasion_rate_multiplier(0.15, 0.4, false, false, false)
	var high_abrasion := StructurePolicy.get_abrasion_rate_multiplier(0.95, 0.8, true, false, false)
	_record(report, "Heavy pressure increases structure abrasion", high_abrasion > low_abrasion * 1.5, "Brute forcing a fish against coral or rock should be materially more dangerous than controlled pressure.")
	var untrained_escape := StructurePolicy.get_abrasion_rate_multiplier(0.7, 0.7, true, true, false)
	var trained_escape := StructurePolicy.get_abrasion_rate_multiplier(0.7, 0.7, true, true, true)
	_record(report, "Structure Fighting improves deliberate escape", trained_escape < untrained_escape * 0.6, "The taught technique should reward correct side pressure without making structure harmless.")
	_record(report, "Snag Escape improves lure recovery odds", StructurePolicy.get_lure_snag_build_multiplier(true) < 1.0 and StructurePolicy.get_lure_snag_recovery_multiplier(true) > 1.0, "The lure-control mastery should reduce snag buildup and accelerate recovery using the existing snag system.")


	_record(report, "Landing window is distance driven", LandingPolicy.is_in_final_surge_window(1.8, 2.4) and not LandingPolicy.is_in_final_surge_window(3.0, 2.4), "Final-surge eligibility should depend on actually bringing the fish close, not an arbitrary timer.")
	var easy_surge_chance := LandingPolicy.get_final_surge_chance(1, 1.0, false)
	var hard_surge_chance := LandingPolicy.get_final_surge_chance(5, 1.0, false)
	var king_surge_chance := LandingPolicy.get_final_surge_chance(5, 1.25, true)
	_record(report, "Final surge scales with fish difficulty", hard_surge_chance > easy_surge_chance, "More difficult fish should be more likely to make a last run without making every beginner fish do it.")
	_record(report, "King fish are dangerous near landing", king_surge_chance > hard_surge_chance, "King specimens should preserve late-fight drama even after their main stamina is exhausted.")
	_record(report, "Final surge chance stays bounded", easy_surge_chance >= LandingPolicy.MIN_FINAL_SURGE_CHANCE and king_surge_chance <= LandingPolicy.MAX_FINAL_SURGE_CHANCE, "Landing danger needs authored limits so it never becomes guaranteed or vanishingly rare by accident.")
	var easy_surge_stamina := LandingPolicy.get_final_surge_stamina_ratio(1, false)
	var king_surge_stamina := LandingPolicy.get_final_surge_stamina_ratio(5, true)
	_record(report, "Final surge is a short burst, not a full fight reset", easy_surge_stamina > 0.0 and easy_surge_stamina < 0.30 and king_surge_stamina < 0.40, "A last run should reopen pressure management briefly, not secretly refill the entire fish fight.")
	_record(report, "Stronger fish get a stronger final burst", king_surge_stamina > easy_surge_stamina and LandingPolicy.get_final_surge_intensity(5, true) > LandingPolicy.get_final_surge_intensity(1, false), "Late-game fish should express the same mechanic more aggressively through stamina and behavior intensity.")
	var landing_snapshot := LandingPolicy.build_snapshot(1.4, king_surge_chance, king_surge_stamina, 1.0)
	_record(report, "Final surge exposes a stable read model", str(landing_snapshot.get("label", "")) == "FINAL SURGE" and bool(landing_snapshot.get("active", false)), "HUD, tutorials and future Landing Technique insights should consume one stable snapshot rather than infer the event from movement.")

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
