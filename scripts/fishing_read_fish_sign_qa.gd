extends RefCounted
class_name FishingReadFishSignQA

const Policy = preload("res://scripts/fishing_fish_sign_policy.gd")
const TechniqueResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/read_fish_sign.tres"
)
const TroutResource: FishData = preload("res://data/bof4/fish/trout.tres")
const AnglerResource: FishData = preload("res://data/bof4/fish/angler.tres")


static func run(
	mastery_catalog: FishingMasteryTechniqueCatalog
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	if mastery_catalog != null and mastery_catalog.has_method("ensure_technique"):
		mastery_catalog.ensure_technique(TechniqueResource)

	var definition := (
		mastery_catalog.get_technique(&"read_fish_sign")
		if mastery_catalog != null
		else null
	)
	_record(
		report,
		"Read Fish Sign registers incrementally",
		definition != null,
		"The observation skill should append without replacing the canonical mastery catalog."
	)
	_record(
		report,
		"Read Fish Sign exposes one stable capability",
		definition != null and definition.has_capability(&"read_fish_sign"),
		"Runtime observation should query a capability rather than special-case a tutorial flag."
	)
	_record(
		report,
		"Read Fish Sign keeps a future master identity",
		definition != null and definition.teacher_id == &"master_sign_reader",
		"The skill must remain master-taught instead of becoming a hidden rank unlock."
	)

	var unlock := FishingUnlockState.new()
	unlock.reset_unlocks(false)
	var mastery := FishingMasteryService.new()
	mastery.configure(mastery_catalog, unlock)
	var wrong_teacher := mastery.learn_technique(
		&"read_fish_sign",
		&"wrong_master",
		false
	)
	_record(
		report,
		"Wrong master cannot teach Read Fish Sign",
		str(wrong_teacher.get("reason", "")) == "wrong_teacher",
		"Master identity must be enforced by the shared mastery service."
	)
	var learned := mastery.learn_technique(
		&"read_fish_sign",
		definition.teacher_id if definition != null else &"",
		false
	)
	_record(
		report,
		"Read Fish Sign becomes a persistent capability",
		bool(learned.get("success", false))
		and mastery.has_capability(&"read_fish_sign")
		and bool(mastery.get_snapshot().get("can_read_fish_sign", false)),
		"The live field-sign read needs one persistent capability gate."
	)

	var trout_observation := Policy.build_observation(
		TroutResource,
		"ROAM",
		true
	)
	_record(
		report,
		"Surface-active trout produce a surface sign",
		trout_observation.get("sign_id", &"") == Policy.SIGN_SURFACE_BOIL,
		"A shallow, vertically active fish should create a readable surface clue."
	)
	var feeding_observation := Policy.build_observation(
		TroutResource,
		"APPROACH",
		true
	)
	_record(
		report,
		"Feeding movement overrides the generic surface clue",
		feeding_observation.get("sign_id", &"") == Policy.SIGN_FEEDING_TURN
		and bool(feeding_observation.get("feeding", false)),
		"Watch/approach/inspect behavior should be interpreted as active feeding interest."
	)
	var deep_observation := Policy.build_observation(
		AnglerResource,
		"ROAM",
		false
	)
	_record(
		report,
		"Deep fish produce a deep-water sign",
		deep_observation.get("sign_id", &"") == Policy.SIGN_DEEP_BUBBLES,
		"Deep-holding fish should remain readable through indirect signs even when the shadow itself is faint."
	)

	var scatter_sign := Policy.classify_sign(0.50, 30.0, 0.90, 0.45, false, true)
	_record(
		report,
		"Small fast fish create baitfish scatter",
		scatter_sign == Policy.SIGN_BAITFISH_SCATTER,
		"Fast small-fish movement should read differently from one large shadow."
	)
	var shadow_sign := Policy.classify_sign(0.50, 80.0, 0.45, 0.45, false, true)
	_record(
		report,
		"Readable neutral fish leave a shadow track",
		shadow_sign == Policy.SIGN_SHADOW_TRACK,
		"A visible ambient fish still provides a basic sign when no stronger clue applies."
	)
	var hidden_neutral := Policy.classify_sign(0.50, 80.0, 0.45, 0.45, false, false)
	_record(
		report,
		"Hidden neutral fish do not fabricate a sign",
		hidden_neutral == Policy.SIGN_NONE,
		"Read Fish Sign should interpret evidence, not reveal every hidden fish for free."
	)

	var feeding_snapshot := Policy.build_read_snapshot([
		_make_observation("trout", "Trout", Policy.SIGN_FEEDING_TURN, 0.20, 30.0, 0.35, 0.90, 0.85, true, true),
		_make_observation("blue_gill", "Blue Gill", Policy.SIGN_FEEDING_TURN, 0.35, 37.0, 0.50, 0.90, 0.80, true, true),
	])
	_record(
		report,
		"Multiple feeding signs resolve as active feeding",
		feeding_snapshot.get("activity", &"") == Policy.ACTIVITY_FEEDING,
		"The read should summarize repeated feeding behavior rather than expose raw counters only."
	)
	_record(
		report,
		"Shallow signs resolve to surface depth",
		feeding_snapshot.get("depth_hint", &"") == Policy.DEPTH_SURFACE,
		"The technique should convert observed depth into a useful qualitative fishing read."
	)
	var likely_species: PackedStringArray = feeding_snapshot.get(
		"likely_species",
		PackedStringArray()
	)
	_record(
		report,
		"Likely species are ranked from the observed signs",
		likely_species.size() == 2,
		"Read Fish Sign should point toward likely species without changing their spawn odds."
	)

	var deep_snapshot := Policy.build_read_snapshot([
		_make_observation("angler", "Angler", Policy.SIGN_DEEP_BUBBLES, 0.78, 105.0, 0.82, 0.45, 0.85, false, false),
		_make_observation("flatfish", "Flatfish", Policy.SIGN_DEEP_BUBBLES, 0.84, 37.0, 0.60, 0.55, 0.40, false, false),
	])
	_record(
		report,
		"Deep signs resolve to deep activity",
		deep_snapshot.get("depth_hint", &"") == Policy.DEPTH_DEEP,
		"Deep bubbles should communicate that the productive layer is below the surface."
	)
	_record(
		report,
		"Very wary water is identified",
		deep_snapshot.get("wariness_hint", &"") == Policy.WARINESS_WARY,
		"Sign reading should convey how cautious the observed fish seem without reducing their wariness."
	)

	var mixed_snapshot := Policy.build_read_snapshot([
		_make_observation("surface", "Surface Fish", Policy.SIGN_SURFACE_BOIL, 0.12, 25.0, 0.20, 0.80, 0.80, false, true),
		_make_observation("deep", "Deep Fish", Policy.SIGN_DEEP_BUBBLES, 0.86, 140.0, 0.90, 0.45, 0.55, false, false),
	])
	_record(
		report,
		"Separated signs resolve to mixed depth",
		mixed_snapshot.get("depth_hint", &"") == Policy.DEPTH_MIXED,
		"The read should not lie by averaging surface and deep activity into mid-water."
	)
	_record(
		report,
		"Large-fish signs can be recognized",
		mixed_snapshot.get("size_hint", &"") == Policy.SIZE_MEDIUM,
		"The size read should stay qualitative rather than leaking exact specimen measurements."
	)

	var quiet_snapshot := Policy.build_read_snapshot([])
	_record(
		report,
		"Empty water still produces a valid quiet read",
		bool(quiet_snapshot.get("available", false))
		and int(quiet_snapshot.get("sign_count", -1)) == 0
		and quiet_snapshot.get("dominant_sign", &"") == Policy.SIGN_NONE,
		"No current evidence is itself useful information and must not crash the observation layer."
	)
	var read_lines: PackedStringArray = feeding_snapshot.get(
		"read_lines",
		PackedStringArray()
	)
	_record(
		report,
		"Read Fish Sign produces four concise read lines",
		read_lines.size() == 4,
		"Future UI should consume a compact observation summary rather than raw simulation values."
	)
	_record(
		report,
		"Exact values stay under resolved debug data",
		feeding_snapshot.has("resolved_debug")
		and not feeding_snapshot.has("bite_multiplier")
		and not feeding_snapshot.has("spawn_multiplier")
		and not feeding_snapshot.has("king_chance"),
		"Learning to read signs must not become a disguised catch-rate or specimen buff."
	)

	mastery.free()
	unlock.free()
	return report


static func _make_observation(
	species_id: String,
	species_name: String,
	sign_id: StringName,
	depth_ratio: float,
	average_size: float,
	wariness: float,
	lateral_activity: float,
	vertical_activity: float,
	feeding: bool,
	readable: bool
) -> Dictionary:
	return {
		"species_id": species_id,
		"species_name": species_name,
		"sign_id": sign_id,
		"depth_ratio": depth_ratio,
		"average_size": average_size,
		"wariness": wariness,
		"lateral_activity": lateral_activity,
		"vertical_activity": vertical_activity,
		"feeding": feeding,
		"readable": readable,
	}


static func _record(
	report: Dictionary,
	name: String,
	passed: bool,
	failure_message: String
) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [name, failure_message])
	report["failures"] = failures
