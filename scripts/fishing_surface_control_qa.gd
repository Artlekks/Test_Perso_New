extends RefCounted
class_name FishingSurfaceControlQA

const SurfacePolicy = preload(
	"res://scripts/fishing_surface_control_policy.gd"
)
const SurfaceTechniqueResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/surface_control.tres"
)


static func run(
	mastery_catalog: FishingMasteryTechniqueCatalog
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	if mastery_catalog != null and mastery_catalog.has_method("ensure_technique"):
		mastery_catalog.ensure_technique(SurfaceTechniqueResource)

	var side_run := {
		"intent_id": &"side_run",
		"label": "RUN RIGHT",
		"intensity": 0.78,
		"duration": 1.0,
		"lateral": 0.85,
		"depth": 0.0,
		"pressure": 0.72,
		"thrashing": false,
	}
	var surge := {
		"intent_id": &"surge_away",
		"label": "RUN",
		"intensity": 0.74,
		"duration": 1.0,
		"lateral": 0.0,
		"depth": 0.0,
		"pressure": 0.70,
		"thrashing": false,
	}
	var rise := {
		"intent_id": &"rise",
		"label": "RISE",
		"intensity": 0.68,
		"duration": 1.0,
		"lateral": 0.0,
		"depth": 0.75,
		"pressure": 0.55,
		"thrashing": false,
	}
	var erratic := {
		"intent_id": &"erratic",
		"label": "ERRATIC",
		"intensity": 0.70,
		"duration": 1.0,
		"lateral": 0.0,
		"depth": 0.0,
		"pressure": 0.62,
		"thrashing": false,
	}
	var thrash := {
		"intent_id": &"erratic",
		"label": "THRASH",
		"intensity": 0.86,
		"duration": 0.8,
		"lateral": 0.30,
		"depth": 0.0,
		"pressure": 0.92,
		"thrashing": true,
	}

	_record(
		report,
		"Absolute surface depth qualifies",
		SurfacePolicy.is_near_surface(0.60, 5.0),
		"A fish fighting less than a metre below the surface should enter the surface layer."
	)
	_record(
		report,
		"Relative surface depth qualifies",
		SurfacePolicy.is_near_surface(1.00, 5.0),
		"Deep venues need a ratio fallback so the top water layer scales with total depth."
	)
	_record(
		report,
		"Deep bait does not qualify",
		not SurfacePolicy.is_near_surface(2.5, 5.0),
		"Surface Control must stay distinct from Deep-Water Control."
	)
	_record(
		report,
		"Unknown total depth uses absolute threshold safely",
		SurfacePolicy.is_near_surface(0.50, 0.0)
		and not SurfacePolicy.is_near_surface(1.50, 0.0),
		"Missing depth-floor data must not turn every fight into surface control."
	)

	_record(
		report,
		"Side run qualifies near surface",
		SurfacePolicy.should_start(side_run, 0.55, 4.0, 0.0),
		"Fast lateral fish need a low-rod counter-pressure response in the top layer."
	)
	_record(
		report,
		"Surge qualifies near surface",
		SurfacePolicy.should_start(surge, 0.45, 4.0, 0.0),
		"A straight surface run should become a readable low-rod ease moment."
	)
	_record(
		report,
		"Rise qualifies when it stays in water",
		SurfacePolicy.should_start(rise, 0.35, 4.0, 0.0),
		"A non-aerial rise can still require surface line control."
	)
	_record(
		report,
		"Erratic surface movement qualifies",
		SurfacePolicy.should_start(erratic, 0.50, 4.0, 0.0),
		"Surface wobble should reward a low rod without random steering."
	)
	_record(
		report,
		"Thrash qualifies as low-rod ease",
		SurfacePolicy.should_start(thrash, 0.40, 4.0, 0.0)
		and SurfacePolicy.get_expected_response(thrash) == SurfacePolicy.RESPONSE_LOW_EASE,
		"Head-shakes at the surface should prioritize giving line and lowering the rod."
	)

	var dive := side_run.duplicate(true)
	dive["intent_id"] = &"dive"
	dive["depth"] = -0.9
	_record(
		report,
		"Dive is excluded from Surface Control",
		not SurfacePolicy.should_start(dive, 0.40, 4.0, 0.0),
		"DIVE already belongs to Reading the Run and Deep-Water Control."
	)
	var weak_run := side_run.duplicate(true)
	weak_run["intensity"] = 0.20
	_record(
		report,
		"Weak surface movement stays ordinary",
		not SurfacePolicy.should_start(weak_run, 0.40, 4.0, 0.0),
		"Small top-water corrections should not spam a mastery challenge."
	)
	_record(
		report,
		"Cooldown prevents surface spam",
		not SurfacePolicy.should_start(side_run, 0.40, 4.0, 0.25),
		"Repeated fish intents need spacing so the top-water response remains readable."
	)

	_record(
		report,
		"Side run maps to low counter",
		SurfacePolicy.get_expected_response(side_run) == SurfacePolicy.RESPONSE_LOW_COUNTER,
		"Surface Control should refine the existing counter-steer response rather than replace it."
	)
	_record(
		report,
		"Counter response requires K W and opposite steering",
		SurfacePolicy.is_response_matching(
			SurfacePolicy.RESPONSE_LOW_COUNTER,
			side_run,
			true,
			-0.80,
			-0.80
		),
		"A right-running fish should be controlled with low rod plus left side pressure while reeling."
	)
	_record(
		report,
		"Counter response rejects same-side steering",
		not SurfacePolicy.is_response_matching(
			SurfacePolicy.RESPONSE_LOW_COUNTER,
			side_run,
			true,
			0.80,
			-0.80
		),
		"Steering with the run must not count as trained surface counter-pressure."
	)
	_record(
		report,
		"Counter response rejects high rod",
		not SurfacePolicy.is_response_matching(
			SurfacePolicy.RESPONSE_LOW_COUNTER,
			side_run,
			true,
			-0.80,
			0.80
		),
		"Surface Control specifically teaches a lowered rod position."
	)

	_record(
		report,
		"Surface surge uses release K plus W",
		SurfacePolicy.is_response_matching(
			SurfacePolicy.RESPONSE_LOW_EASE,
			surge,
			false,
			0.0,
			-0.75
		),
		"The technique should layer low rod onto the existing ease-off response."
	)
	_record(
		report,
		"Surface surge rejects release without low rod",
		not SurfacePolicy.is_response_matching(
			SurfacePolicy.RESPONSE_LOW_EASE,
			surge,
			false,
			0.0,
			0.0
		),
		"Simply releasing K is still Reading the Run; Surface Control adds rod position."
	)
	_record(
		report,
		"Surface rise uses K plus W",
		SurfacePolicy.is_response_matching(
			SurfacePolicy.RESPONSE_LOW_REEL,
			rise,
			true,
			0.0,
			-0.75
		),
		"A fish rising without breaching should keep contact while the rod stays low."
	)
	_record(
		report,
		"Erratic response requires neutral steering",
		SurfacePolicy.is_response_matching(
			SurfacePolicy.RESPONSE_LOW_STEADY,
			erratic,
			true,
			0.0,
			-0.75
		),
		"The player should not chase every wobble with random side input."
	)
	_record(
		report,
		"Erratic response rejects steering noise",
		not SurfacePolicy.is_response_matching(
			SurfacePolicy.RESPONSE_LOW_STEADY,
			erratic,
			true,
			0.80,
			-0.75
		),
		"Surface steadiness should mean actual steady rod control."
	)

	var response_time := SurfacePolicy.advance_match_time(0.0, true, 0.08)
	response_time = SurfacePolicy.advance_match_time(response_time, true, 0.08)
	_record(
		report,
		"Held surface response completes deterministically",
		SurfacePolicy.is_response_complete(response_time),
		"The technique should reward a short stable hold rather than a one-frame input."
	)
	var reset_time := SurfacePolicy.advance_match_time(0.10, false, 0.02)
	_record(
		report,
		"Broken surface response resets hold",
		is_zero_approx(reset_time),
		"A partial input sequence must not bank hidden progress."
	)
	var calm_window := SurfacePolicy.get_window_seconds(weak_run)
	var hard_window := SurfacePolicy.get_window_seconds(thrash)
	_record(
		report,
		"Hard surface behavior tightens the read window",
		hard_window < calm_window
		and hard_window >= SurfacePolicy.WINDOW_MIN_SECONDS
		and calm_window <= SurfacePolicy.WINDOW_MAX_SECONDS,
		"More violent top-water behavior should be harder without becoming unreadable."
	)

	var instability := SurfacePolicy.get_surface_instability_impulse(
		thrash,
		0.25,
		4.0
	)
	_record(
		report,
		"Surface instability is bounded",
		instability >= SurfacePolicy.INSTABILITY_IMPULSE_MIN
		and instability <= SurfacePolicy.INSTABILITY_IMPULSE_MAX,
		"The baseline surface load must stay small enough to preserve the existing tension economy."
	)
	var relief := SurfacePolicy.get_success_relief_impulse(instability, thrash)
	_record(
		report,
		"Successful control relieves but does not erase surface load",
		relief < 0.0
		and absf(relief) < instability,
		"Mastery should stabilize the top layer without making surface behavior disappear."
	)
	var stamina_bonus := SurfacePolicy.get_stamina_bonus_ratio(thrash)
	_record(
		report,
		"Surface stamina reward stays deliberately small",
		stamina_bonus >= SurfacePolicy.STAMINA_BONUS_MIN
		and stamina_bonus <= SurfacePolicy.STAMINA_BONUS_MAX,
		"Surface Control should support the fight rather than replace Pump & Reel or pressure management."
	)

	var technique := (
		mastery_catalog.get_technique(&"surface_control")
		if mastery_catalog != null
		else null
	)
	_record(
		report,
		"Surface Control registers incrementally",
		technique != null
		and technique.has_capability(&"surface_control"),
		"The new mastery must append safely without replacing the user's existing technique catalog."
	)

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
