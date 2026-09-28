extends RefCounted
class_name FishingRegressionHarness

const CONTENT_CATALOG: FishingContentCatalog = preload(
	"res://data/bof4/catalogs/all_content.tres"
)
const TECHNIQUE_CATALOG: FishingTechniqueCatalog = preload(
	"res://data/bof4/techniques/all_techniques.tres"
)
const PROGRESSION_CATALOG: FishingProgressionCatalog = preload(
	"res://data/bof4/progression/all_progression.tres"
)
const REWARD_CATALOG: FishingRewardCatalog = preload(
	"res://data/bof4/rewards/all_rewards.tres"
)
const TRADE_CATALOG: FishingTradeCatalog = preload(
	"res://data/bof4/trades/all_trades.tres"
)
const TENSION_PROFILE: FishingTensionProfile = preload(
	"res://data/bof4/fight/default_tension.tres"
)
const CatchScoring = preload(
	"res://scripts/fishing_catch_scoring.gd"
)
const SizeRoller = preload(
	"res://scripts/fishing_size_roller.gd"
)
const BaitScript = preload(
	"res://scripts/bait_V2.gd"
)
const CameraRigScript = preload(
	"res://scripts/camera_rig.gd"
)
const CastInputGateScript = preload(
	"res://scripts/fishing_cast_input_gate.gd"
)
const DebugSettingsScript = preload(
	"res://scripts/fishing_debug_settings.gd"
)
const CatchEvaluatorScript = preload(
	"res://scripts/fishing_catch_evaluator.gd"
)
const ShoreBoundaryScript = preload(
	"res://scripts/fishing_shore_boundary.gd"
)
const FightLifecycleScript = preload(
	"res://scripts/fishing_fight_lifecycle.gd"
)
const FightResolver = preload(
	"res://scripts/fishing_fight_resolver.gd"
)
const TensionScript = preload(
	"res://scripts/tension.gd"
)

const QA_PROFILE_DIRECTORY: String = "res://data/debug/qa_profiles"

const EXPECTED_FISH_COUNT: int = 30
const EXPECTED_LURE_COUNT: int = 20
const EXPECTED_ROD_COUNT: int = 6
const EXPECTED_SPOT_COUNT: int = 11
const EXPECTED_TECHNIQUE_COUNT: int = 4
const EXPECTED_RANK_COUNT: int = 10
const EXPECTED_REWARD_COUNT: int = 2
const EXPECTED_TRADE_COUNT: int = 14
const EXPECTED_MAX_FISHING_POINTS: int = 9999


func run_all() -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var report: Dictionary = {
		"passed": 0,
		"failed": 0,
		"assertions": 0,
		"failures": PackedStringArray(),
		"groups": {},
		"duration_ms": 0.0,
		"summary": "",
	}

	_test_catalog_shape(report)
	_test_fish_database(report)
	_test_lure_database(report)
	_test_rod_database(report)
	_test_spot_database(report)
	_test_specimen_generation(report)
	_test_scoring_invariants(report)
	_test_techniques(report)
	_test_progression(report)
	_test_catch_persistence_regression(report)
	_test_all_species_record_delta_regression(report)
	_test_debug_persistence_gate_regression(report)
	_test_debug_specimen_forcing(report)
	_test_rewards(report)
	_test_trades(report)
	_test_fight_stat_resolution(report)
	_test_tension_profile(report)
	_test_fight_lifecycle_regression(report)
	_test_tension_failure_regression(report)
	_test_landing_regression(report)
	_test_shore_boundary_regression(report)
	_test_camera_return_regression(report)
	_test_cast_input_regression(report)
	_test_qa_profiles(report)

	report["duration_ms"] = (
		float(Time.get_ticks_usec() - started_usec)
		/ 1000.0
	)
	report["summary"] = _build_summary(report)
	_print_report(report)
	return report


func _test_catalog_shape(report: Dictionary) -> void:
	var group: String = "catalog"

	_assert_equal_int(
		report,
		CONTENT_CATALOG.fish.size(),
		EXPECTED_FISH_COUNT,
		"fish count",
		group
	)
	_assert_equal_int(
		report,
		CONTENT_CATALOG.spots.size(),
		EXPECTED_SPOT_COUNT,
		"spot count",
		group
	)
	_assert(
		report,
		CONTENT_CATALOG.tackle != null,
		"tackle catalog exists",
		group
	)

	if CONTENT_CATALOG.tackle == null:
		return

	_assert(
		report,
		CONTENT_CATALOG.tackle.lure_catalog != null,
		"lure catalog exists",
		group
	)

	if CONTENT_CATALOG.tackle.lure_catalog != null:
		_assert_equal_int(
			report,
			CONTENT_CATALOG.tackle.lure_catalog.lures.size(),
			EXPECTED_LURE_COUNT,
			"lure count",
			group
		)

	_assert_equal_int(
		report,
		CONTENT_CATALOG.tackle.rods.size(),
		EXPECTED_ROD_COUNT,
		"rod count",
		group
	)
	_assert_equal_int(
		report,
		TECHNIQUE_CATALOG.techniques.size(),
		EXPECTED_TECHNIQUE_COUNT,
		"technique count",
		group
	)
	_assert_equal_int(
		report,
		PROGRESSION_CATALOG.get_rank_count(),
		EXPECTED_RANK_COUNT,
		"rank count",
		group
	)
	_assert_equal_int(
		report,
		REWARD_CATALOG.get_all_rewards().size(),
		EXPECTED_REWARD_COUNT,
		"reward count",
		group
	)
	_assert_equal_int(
		report,
		TRADE_CATALOG.get_all_recipes().size(),
		EXPECTED_TRADE_COUNT,
		"trade count",
		group
	)


func _test_fish_database(report: Dictionary) -> void:
	var group: String = "fish"
	var seen_ids: Dictionary = {}

	for fish in CONTENT_CATALOG.fish:
		_assert(report, fish != null, "fish resource is non-null", group)
		if fish == null:
			continue

		var species_id: String = (
			fish.get_stable_species_id()
			.strip_edges()
			.to_lower()
		)
		_assert(report, not species_id.is_empty(), "%s stable ID" % fish.fish_name, group)
		_assert(report, not seen_ids.has(species_id), "unique fish ID %s" % species_id, group)
		seen_ids[species_id] = true
		_assert(report, not fish.fish_name.strip_edges().is_empty(), "%s visible name" % species_id, group)
		_assert(report, fish.average_size > 0.0, "%s average size > 0" % species_id, group)
		_assert(report, fish.king_size > fish.average_size, "%s crown > average" % species_id, group)
		_assert(report, fish.max_points > 0, "%s max points > 0" % species_id, group)
		_assert(report, fish.base_stamina > 0.0, "%s stamina > 0" % species_id, group)
		_assert(report, fish.base_strength > 0.0, "%s strength > 0" % species_id, group)
		_assert(report, fish.resistance_rounds >= 1, "%s resistance rounds" % species_id, group)
		_assert(report, fish.recovery_time_min >= 0.0, "%s recovery min" % species_id, group)
		_assert(report, fish.recovery_time_max >= fish.recovery_time_min, "%s ordered recovery window" % species_id, group)
		_assert(report, fish.behavior_profile != null, "%s behavior profile" % species_id, group)
		if fish.behavior_profile != null:
			_assert(
				report,
				fish.behavior_profile.is_valid_profile(),
				"%s valid fight behavior profile" % species_id,
				group
			)
		_assert(report, fish.preferred_depth_min >= 0.0 and fish.preferred_depth_min <= 1.0, "%s depth min" % species_id, group)
		_assert(report, fish.preferred_depth_max >= 0.0 and fish.preferred_depth_max <= 1.0, "%s depth max" % species_id, group)
		_assert(report, fish.preferred_depth_min <= fish.preferred_depth_max, "%s ordered depth band" % species_id, group)

		# Ten deterministic depth probes per species.
		for depth_step in range(11):
			var depth_ratio: float = float(depth_step) / 10.0
			var depth_match: float = fish.get_depth_match_multiplier(depth_ratio, 1.0)
			_assert(
				report,
				depth_match >= 0.0 and depth_match <= 1.0,
				"%s depth probe %d" % [species_id, depth_step],
				group
			)


		# Build deterministic ordinary + crown specimens through the real FishInstance
		# path. Every species must produce usable fight stats at both ends.
		var ordinary := FishInstance.new()
		ordinary.setup(fish, 0, fish.average_size)
		_assert(report, ordinary.max_stamina > 0.0, "%s ordinary stamina" % species_id, group)
		_assert(report, ordinary.strength > 0.0, "%s ordinary strength" % species_id, group)
		_assert(report, ordinary.pull_multiplier > 0.0, "%s ordinary pull" % species_id, group)
		_assert(report, ordinary.stamina_recovery_multiplier > 0.0, "%s ordinary recovery multiplier" % species_id, group)

		var crown := FishInstance.new()
		crown.setup(fish, 1, fish.king_size)
		_assert(report, crown.is_king, "%s crown specimen is king" % species_id, group)
		_assert(report, crown.max_stamina >= ordinary.max_stamina, "%s crown stamina not weaker" % species_id, group)
		_assert(report, crown.strength >= ordinary.strength, "%s crown strength not weaker" % species_id, group)


func _test_lure_database(report: Dictionary) -> void:
	var group: String = "lures"
	if CONTENT_CATALOG.tackle == null or CONTENT_CATALOG.tackle.lure_catalog == null:
		_assert(report, false, "lure catalog available", group)
		return

	var seen_ids: Dictionary = {}
	var lures: Array[BaitData] = CONTENT_CATALOG.tackle.lure_catalog.lures

	for lure in lures:
		_assert(report, lure != null, "lure resource is non-null", group)
		if lure == null:
			continue

		var lure_id: String = str(lure.lure_id).strip_edges().to_lower()
		_assert(report, not lure_id.is_empty(), "%s stable ID" % lure.display_name, group)
		_assert(report, not seen_ids.has(lure_id), "unique lure ID %s" % lure_id, group)
		seen_ids[lure_id] = true
		_assert(report, not lure.display_name.strip_edges().is_empty(), "%s display name" % lure_id, group)
		_assert(report, lure.level >= 1 and lure.level <= 3, "%s level range" % lure_id, group)
		_assert(report, lure.sink_depth >= 0.0 and lure.sink_depth <= 1.0, "%s sink depth" % lure_id, group)
		_assert(report, lure.sink_speed >= 0.0, "%s sink speed" % lure_id, group)
		_assert(report, lure.reel_speed > 0.0, "%s reel speed" % lure_id, group)
		_assert(report, lure.reel_steer_strength >= 0.0, "%s steer strength" % lure_id, group)
		_assert(report, lure.has_method("get_action_profile"), "%s action-profile API" % lure_id, group)

		if lure.has_method("get_action_profile"):
			_assert(report, lure.get_action_profile() != null, "%s action profile" % lure_id, group)

	# Every species/lure pair must produce a non-negative attraction multiplier.
	for fish in CONTENT_CATALOG.fish:
		if fish == null:
			continue
		for lure in lures:
			if lure == null:
				continue
			var idle_multiplier: float = fish.get_lure_match_multiplier(lure, false)
			var reel_multiplier: float = fish.get_lure_match_multiplier(lure, true)
			_assert(report, idle_multiplier >= 0.0, "%s/%s idle attraction" % [fish.get_stable_species_id(), lure.lure_id], group)
			_assert(report, reel_multiplier >= 0.0, "%s/%s reel attraction" % [fish.get_stable_species_id(), lure.lure_id], group)


func _test_rod_database(report: Dictionary) -> void:
	var group: String = "rods"
	if CONTENT_CATALOG.tackle == null:
		_assert(report, false, "rod catalog available", group)
		return

	var seen_ids: Dictionary = {}

	for rod in CONTENT_CATALOG.tackle.rods:
		_assert(report, rod != null, "rod resource is non-null", group)
		if rod == null:
			continue

		var rod_id: String = str(rod.rod_id).strip_edges().to_lower()
		_assert(report, not rod_id.is_empty(), "%s stable ID" % rod.rod_name, group)
		_assert(report, not seen_ids.has(rod_id), "unique rod ID %s" % rod_id, group)
		seen_ids[rod_id] = true
		_assert(report, rod.cast_speed_multiplier > 0.0, "%s cast multiplier" % rod_id, group)
		_assert(report, rod.reel_speed_multiplier > 0.0, "%s reel multiplier" % rod_id, group)
		_assert(report, rod.line_tolerance_multiplier > 0.0, "%s line tolerance" % rod_id, group)
		_assert(report, rod.counter_steer_multiplier > 0.0, "%s counter-steer" % rod_id, group)
		_assert(report, rod.steering_strength_multiplier > 0.0, "%s steer strength" % rod_id, group)
		_assert(report, rod.steering_response_multiplier > 0.0, "%s steer response" % rod_id, group)
		_assert(report, rod.twitch_strength_multiplier > 0.0, "%s twitch strength" % rod_id, group)
		_assert(report, rod.manual_pull_distance_multiplier > 0.0, "%s pull distance" % rod_id, group)
		_assert(report, rod.manual_pull_response_multiplier > 0.0, "%s pull response" % rod_id, group)


func _test_spot_database(report: Dictionary) -> void:
	var group: String = "spots"
	var seen_ids: Dictionary = {}
	var valid_fish_ids: Dictionary = {}

	for fish in CONTENT_CATALOG.fish:
		if fish != null:
			valid_fish_ids[fish.get_stable_species_id().to_lower()] = true

	for spot in CONTENT_CATALOG.spots:
		_assert(report, spot != null, "spot resource is non-null", group)
		if spot == null:
			continue

		var spot_id: String = str(spot.spot_id).strip_edges().to_lower()
		_assert(report, not spot_id.is_empty(), "%s stable ID" % spot.spot_name, group)
		_assert(report, not seen_ids.has(spot_id), "unique spot ID %s" % spot_id, group)
		seen_ids[spot_id] = true
		_assert(report, spot.get_valid_species_count() > 0, "%s has population" % spot_id, group)
		_assert(report, spot.get_total_base_bite_weight() > 0.0, "%s bite weight > 0" % spot_id, group)
		_assert(report, spot.get_total_ambient_weight() > 0.0, "%s ambient weight > 0" % spot_id, group)
		_assert(report, spot.baseline_concentration > 0.0, "%s concentration baseline" % spot_id, group)

		for entry in spot.get_fish_population():
			_assert(report, entry != null, "%s population entry" % spot_id, group)
			if entry == null:
				continue
			_assert(report, entry.fish != null, "%s population fish" % spot_id, group)
			if entry.fish == null:
				continue
			var species_id: String = entry.fish.get_stable_species_id().to_lower()
			_assert(report, valid_fish_ids.has(species_id), "%s references known fish %s" % [spot_id, species_id], group)
			_assert(report, entry.weight >= 0.0, "%s/%s non-negative weight" % [spot_id, species_id], group)

		for hotspot in spot.get_concentration_hotspots():
			_assert(report, hotspot != null, "%s hotspot resource" % spot_id, group)
			if hotspot != null:
				_assert(report, hotspot.is_valid_definition(), "%s hotspot %s valid" % [spot_id, hotspot.hotspot_id], group)


func _test_specimen_generation(report: Dictionary) -> void:
	var group: String = "specimen_generation"
	var species_index: int = 0

	for fish in CONTENT_CATALOG.fish:
		if fish == null:
			continue

		var species_id: String = fish.get_stable_species_id()
		var bounds: Vector2i = SizeRoller.get_normal_size_bounds(fish)
		_assert(
			report,
			bounds.x > 0 and bounds.y >= bounds.x,
			"%s valid normal size bounds" % species_id,
			group
		)

		var rng := RandomNumberGenerator.new()
		rng.seed = 1597463007 + species_index * 7919
		var seen_sizes: Dictionary = {}
		var smallest_seen: int = bounds.y
		var largest_seen: int = bounds.x

		for _roll_index in range(96):
			var result: Dictionary = SizeRoller.roll_with_rng(
				fish,
				rng,
				0
			)
			var size_cm: int = roundi(float(result.get("size", 0.0)))
			seen_sizes[size_cm] = true
			smallest_seen = mini(smallest_seen, size_cm)
			largest_seen = maxi(largest_seen, size_cm)
			_assert(
				report,
				size_cm >= bounds.x and size_cm <= bounds.y,
				"%s forced-normal roll stays in band" % species_id,
				group
			)
			_assert(
				report,
				not bool(result.get("is_king", false)),
				"%s forced-normal roll is not King" % species_id,
				group
			)

		var authored_span: int = bounds.y - bounds.x
		if authored_span >= 4:
			_assert(
				report,
				seen_sizes.size() >= 4,
				"%s normal rolls produce visible variety" % species_id,
				group
			)
			_assert(
				report,
				largest_seen - smallest_seen >= 3,
				"%s sampled normal spread reaches at least 3cm" % species_id,
				group
			)

		species_index += 1


func _test_scoring_invariants(report: Dictionary) -> void:
	var group: String = "scoring"
	var maximum_total: int = 0

	for fish in CONTENT_CATALOG.fish:
		if fish == null:
			continue

		maximum_total += fish.max_points
		var king_score: Dictionary = CatchScoring.evaluate(fish, fish.king_size)
		_assert(report, bool(king_score.get("is_king", false)), "%s crown classified King" % fish.get_stable_species_id(), group)
		_assert_equal_int(report, int(king_score.get("points", 0)), fish.max_points, "%s crown gives max points" % fish.get_stable_species_id(), group)

		var previous_points: int = 0
		var crown_cm: int = maxi(roundi(fish.king_size), 1)
		for size_cm in range(1, crown_cm + 1):
			var score: Dictionary = CatchScoring.evaluate(fish, float(size_cm))
			var points: int = int(score.get("points", 0))
			_assert(report, points >= previous_points, "%s score monotonic at %dcm" % [fish.get_stable_species_id(), size_cm], group)
			_assert(report, points <= fish.max_points, "%s score capped at %dcm" % [fish.get_stable_species_id(), size_cm], group)

			# When a species has at least one point available per centimetre,
			# adjacent whole-centimetre specimens should no longer collapse onto
			# the same score plateau.
			if size_cm > 1 and fish.max_points >= crown_cm:
				_assert(
					report,
					points > previous_points,
					"%s score distinguishes %dcm from %dcm" % [fish.get_stable_species_id(), size_cm - 1, size_cm],
					group
				)

			previous_points = points

	_assert_equal_int(report, maximum_total, EXPECTED_MAX_FISHING_POINTS, "catalog max score", group)


func _test_techniques(report: Dictionary) -> void:
	var group: String = "techniques"
	_assert(report, TECHNIQUE_CATALOG.is_valid_catalog(), "technique catalog valid", group)
	var expected_groups: Dictionary = {
		1: PackedInt32Array([1, 1, 1]),
		2: PackedInt32Array([1, 2, 1]),
		3: PackedInt32Array([1, 2, 2]),
		4: PackedInt32Array([3, 2, 1]),
	}
	var seen_levels: Dictionary = {}

	for definition in TECHNIQUE_CATALOG.techniques:
		_assert(report, definition != null, "technique resource", group)
		if definition == null:
			continue
		_assert(report, definition.is_valid_definition(), "Tec %d valid" % definition.level, group)
		_assert(report, not seen_levels.has(definition.level), "unique Tec %d" % definition.level, group)
		seen_levels[definition.level] = true
		_assert(report, expected_groups.has(definition.level), "known Tec %d" % definition.level, group)
		if expected_groups.has(definition.level):
			_assert(report, _packed_int_arrays_equal(definition.pulse_groups, expected_groups[definition.level]), "Tec %d rhythm" % definition.level, group)
		_assert(report, definition.attraction_multiplier >= 1.0, "Tec %d attraction" % definition.level, group)
		_assert(report, definition.boost_duration > 0.0, "Tec %d duration" % definition.level, group)


func _test_progression(report: Dictionary) -> void:
	var group: String = "progression"
	_assert(report, PROGRESSION_CATALOG.is_valid_catalog(), "progression catalog valid", group)
	_assert_equal_int(report, PROGRESSION_CATALOG.max_fishing_points, EXPECTED_MAX_FISHING_POINTS, "progression max points", group)
	var expected_thresholds := PackedInt32Array([0, 200, 500, 1000, 2000, 4000, 5000, 7000, 9000, 9500])
	_assert_equal_int(report, PROGRESSION_CATALOG.ranks.size(), expected_thresholds.size(), "rank threshold count", group)
	_assert_equal_string(report, PROGRESSION_CATALOG.get_rank_name(0), "Beginner", "zero points starts at Beginner", group)

	for index in range(mini(PROGRESSION_CATALOG.ranks.size(), expected_thresholds.size())):
		var rank: FishingRankDefinition = PROGRESSION_CATALOG.ranks[index]
		_assert(report, rank != null, "rank %d resource" % index, group)
		if rank != null:
			_assert_equal_int(report, rank.min_points, expected_thresholds[index], "rank %d threshold" % index, group)


func _test_catch_persistence_regression(report: Dictionary) -> void:
	var group: String = "catch_persistence"
	var sweetfish: FishData = null
	var sea_bass: FishData = null

	for fish in CONTENT_CATALOG.fish:
		if fish == null:
			continue
		match fish.get_stable_species_id().to_lower():
			"sweetfish":
				sweetfish = fish
			"sea_bass":
				sea_bass = fish

	_assert(report, sweetfish != null, "Sweetfish exists", group)
	_assert(report, sea_bass != null, "Sea Bass exists", group)
	if sweetfish == null or sea_bass == null:
		return

	var progress := FishingProgress.new()
	progress.progression_catalog = PROGRESSION_CATALOG

	# Exact regression from playtest: an existing 18 cm / 108 pt Sweetfish
	# must be replaced by a later 20 cm / 120 pt Sweetfish.
	var sweet_18: Dictionary = CatchEvaluatorScript.create_snapshot_from_values(
		sweetfish,
		18.0
	)
	var first: Dictionary = progress.record_catch_snapshot(
		sweet_18,
		false,
		false
	)
	_assert(report, bool(first.get("new_species", false)), "first Sweetfish registers", group)
	_assert_equal_int(report, int(first.get("fishing_points", -1)), 108, "18 cm Sweetfish contributes 108 total points", group)

	var sweet_20: Dictionary = CatchEvaluatorScript.create_snapshot_from_values(
		sweetfish,
		20.0
	)
	var second: Dictionary = progress.record_catch_snapshot(
		sweet_20,
		false,
		false
	)
	_assert(report, bool(second.get("new_best_size", false)), "20 cm Sweetfish replaces 18 cm size record", group)
	_assert(report, bool(second.get("new_best_points", false)), "120 pt Sweetfish replaces 108 pt score record", group)
	_assert_equal_int(report, int(second.get("fishing_points", -1)), 120, "Sweetfish best score raises total to 120", group)

	var sweet_record: Dictionary = progress.get_species_record_by_key("sweetfish")
	_assert_equal_int(report, roundi(float(sweet_record.get("best_size", 0.0))), 20, "Sweetfish best size persisted in runtime state", group)
	_assert_equal_int(report, int(sweet_record.get("best_points", 0)), 120, "Sweetfish best points persisted in runtime state", group)

	# A worse specimen still counts as a catch but must not reduce or add to the
	# species' best-score contribution.
	var sweet_17: Dictionary = CatchEvaluatorScript.create_snapshot_from_values(
		sweetfish,
		17.0
	)
	var third: Dictionary = progress.record_catch_snapshot(
		sweet_17,
		false,
		false
	)
	_assert(report, not bool(third.get("new_best_size", true)), "smaller Sweetfish is not a size record", group)
	_assert(report, not bool(third.get("new_best_points", true)), "lower-score Sweetfish is not a point record", group)
	_assert_equal_int(report, int(third.get("fishing_points", -1)), 120, "lower Sweetfish score does not inflate total", group)

	# Lifetime fishing points are the sum of each species' best score, not the
	# sum of every fish caught.
	var bass_52: Dictionary = CatchEvaluatorScript.create_snapshot_from_values(
		sea_bass,
		52.0
	)
	var fourth: Dictionary = progress.record_catch_snapshot(
		bass_52,
		false,
		false
	)
	var expected_bass_points: int = CatchScoring.calculate_points(sea_bass, 52.0)
	_assert_equal_int(
		report,
		int(fourth.get("fishing_points", -1)),
		120 + expected_bass_points,
		"second species adds only its best score to lifetime total",
		group
	)
	_assert_equal_int(
		report,
		int(fourth.get("fishing_points", -1)),
		progress.get_fishing_points(),
		"catch result exposes the same authoritative total used by menus",
		group
	)

	# QA/new-player reset must return the same backend to the exact baseline the
	# player sees in the J menu before any catch: Beginner, 0 points, no records.
	progress.reset_all_progress(false)
	_assert_equal_int(report, progress.get_fishing_points(), 0, "reset clears fishing points", group)
	_assert_equal_int(report, progress.get_total_catches(), 0, "reset clears catch count", group)
	_assert_equal_string(report, progress.get_rank_name(), "Beginner", "reset returns rank to Beginner", group)
	_assert(report, progress.get_all_records().is_empty(), "reset clears species records", group)

	progress.free()


func _test_all_species_record_delta_regression(report: Dictionary) -> void:
	var group: String = "all_species_progression"
	var crown_progress := FishingProgress.new()
	crown_progress.progression_catalog = PROGRESSION_CATALOG
	var expected_crown_total: int = 0
	var tested_species: int = 0

	for fish in CONTENT_CATALOG.fish:
		if fish == null:
			continue

		tested_species += 1
		var species_id: String = fish.get_stable_species_id().to_lower()
		var species_progress := FishingProgress.new()
		species_progress.progression_catalog = PROGRESSION_CATALOG

		var crown_cm: int = maxi(roundi(fish.king_size), 1)
		var base_cm: int = clampi(roundi(fish.average_size), 1, crown_cm)
		var improved_cm: int = mini(base_cm + 1, crown_cm)
		if improved_cm <= base_cm and crown_cm > 1:
			base_cm = crown_cm - 1
			improved_cm = crown_cm

		var base_snapshot: Dictionary = CatchEvaluatorScript.create_snapshot_from_values(
			fish,
			float(base_cm)
		)
		var first_result: Dictionary = species_progress.record_catch_snapshot(
			base_snapshot,
			false,
			false
		)
		var base_points: int = int(base_snapshot.get("points", 0))
		_assert_equal_int(
			report,
			int(first_result.get("fishing_points", -1)),
			base_points,
			"%s first record owns its score" % species_id,
			group
		)
		_assert_equal_int(
			report,
			int(first_result.get("fishing_points_gained", -1)),
			base_points,
			"%s first record gains its full score" % species_id,
			group
		)

		var improved_snapshot: Dictionary = CatchEvaluatorScript.create_snapshot_from_values(
			fish,
			float(improved_cm)
		)
		var improved_points: int = int(improved_snapshot.get("points", 0))
		var second_result: Dictionary = species_progress.record_catch_snapshot(
			improved_snapshot,
			false,
			false
		)
		var expected_best: int = maxi(base_points, improved_points)
		var expected_gain: int = maxi(improved_points - base_points, 0)
		_assert_equal_int(
			report,
			int(second_result.get("fishing_points", -1)),
			expected_best,
			"%s improved record replaces, not stacks" % species_id,
			group
		)
		_assert_equal_int(
			report,
			int(second_result.get("fishing_points_gained", -1)),
			expected_gain,
			"%s improved record gains only the delta" % species_id,
			group
		)

		var worse_result: Dictionary = species_progress.record_catch_snapshot(
			base_snapshot,
			false,
			false
		)
		_assert_equal_int(
			report,
			int(worse_result.get("fishing_points", -1)),
			expected_best,
			"%s worse repeat does not change total" % species_id,
			group
		)
		_assert_equal_int(
			report,
			int(worse_result.get("fishing_points_gained", -1)),
			0,
			"%s worse repeat gains zero" % species_id,
			group
		)
		species_progress.free()

		var crown_snapshot: Dictionary = CatchEvaluatorScript.create_snapshot_from_values(
			fish,
			fish.king_size
		)
		var crown_result: Dictionary = crown_progress.record_catch_snapshot(
			crown_snapshot,
			false,
			false
		)
		expected_crown_total += maxi(fish.max_points, 0)
		_assert_equal_int(
			report,
			int(crown_result.get("fishing_points", -1)),
			mini(expected_crown_total, EXPECTED_MAX_FISHING_POINTS),
			"%s crown contributes max score to global total" % species_id,
			group
		)

	_assert_equal_int(report, tested_species, EXPECTED_FISH_COUNT, "all fish audited", group)
	_assert_equal_int(report, expected_crown_total, EXPECTED_MAX_FISHING_POINTS, "all species max scores sum to 9999", group)
	_assert_equal_int(report, crown_progress.get_fishing_points(), EXPECTED_MAX_FISHING_POINTS, "all crowns produce 9999 total", group)
	_assert_equal_string(report, crown_progress.get_rank_name(), "The Fish", "9999 points reaches The Fish", group)
	crown_progress.free()


func _test_debug_persistence_gate_regression(report: Dictionary) -> void:
	var group: String = "debug_persistence"
	var settings = DebugSettingsScript.new()
	var controller := FishingDebugController.new()
	controller.settings = settings
	var sweetfish: FishData = null

	for fish in CONTENT_CATALOG.fish:
		if fish != null and fish.get_stable_species_id().to_lower() == "sweetfish":
			sweetfish = fish
			break

	_assert(report, sweetfish != null, "Sweetfish available for QA gate test", group)
	if sweetfish == null:
		return

	# The exact bug found in playtest: SHADOWS / FIVE sets this to 5. That is a
	# presentation override and must NOT turn off legitimate catch persistence.
	settings.set_shadow_count_override(5)
	_assert(report, settings.is_encounter_override_active(), "five-shadow profile is still reported as QA-active", group)
	_assert(report, not settings.is_catch_outcome_override_active(), "shadow count does not alter catch outcome", group)
	_assert(report, settings.is_presentation_override_active(), "shadow count is classified as presentation override", group)
	_assert(report, controller.should_record_catch(), "five-shadow profile allows normal catch recording", group)

	settings.set_shadow_fish_override(sweetfish)
	_assert(report, not settings.is_catch_outcome_override_active(), "shadow species override does not alter caught species RNG", group)

	# Outcome-forcing QA remains protected unless SAVE DBG is explicitly on.
	settings.set_forced_fish(sweetfish)
	_assert(report, settings.is_catch_outcome_override_active(), "forced fish is a catch outcome override", group)
	_assert(report, not controller.should_record_catch(), "forced fish is not persisted by default", group)

	settings.set_record_debug_catches(true)
	_assert(report, controller.should_record_catch(), "SAVE DBG explicitly allows forced catches", group)

	controller.free()



func _test_debug_specimen_forcing(report: Dictionary) -> void:
	var group: String = "debug_specimen"
	var settings = DebugSettingsScript.new()
	var fish: FishData = CONTENT_CATALOG.fish[0] if not CONTENT_CATALOG.fish.is_empty() else null
	_assert(report, fish != null, "QA specimen test fish exists", group)
	if fish == null:
		return

	var normal_bounds := SizeRoller.get_normal_size_bounds(fish)
	var king_bounds := SizeRoller.get_king_size_bounds(fish)

	settings.set_specimen_mode(DebugSettingsScript.SpecimenMode.SMALL)
	_assert_equal_int(report, roundi(settings.get_forced_specimen_size(fish)), normal_bounds.x, "small forces normal minimum", group)
	settings.set_specimen_mode(DebugSettingsScript.SpecimenMode.LARGE)
	_assert_equal_int(report, roundi(settings.get_forced_specimen_size(fish)), normal_bounds.y, "large forces normal maximum", group)
	settings.set_specimen_mode(DebugSettingsScript.SpecimenMode.KING)
	_assert_equal_int(report, roundi(settings.get_forced_specimen_size(fish)), king_bounds.x, "king forces crown threshold", group)
	_assert(report, settings.is_catch_outcome_override_active(), "specimen forcing is persistence-protected QA", group)

	var progress := FishingProgress.new()
	progress.progression_catalog = PROGRESSION_CATALOG
	var baseline_size: int = normal_bounds.x
	progress.record_catch_snapshot(
		CatchEvaluatorScript.create_snapshot_from_values(fish, float(baseline_size)),
		false,
		false
	)
	settings.configure_progress(progress)
	settings.set_specimen_mode(DebugSettingsScript.SpecimenMode.NEW_RECORD)
	_assert_equal_int(
		report,
		roundi(settings.get_forced_specimen_size(fish)),
		mini(baseline_size + 1, king_bounds.y),
		"new-record mode targets one centimetre above current record",
		group
	)

	var specimen := FishInstance.new()
	specimen.setup(fish, -1, float(normal_bounds.x))
	_assert_equal_int(report, roundi(specimen.size), normal_bounds.x, "FishInstance accepts deterministic size override", group)
	_assert(report, not specimen.is_king, "small deterministic specimen remains normal", group)
	progress.free()

func _test_rewards(report: Dictionary) -> void:
	var group: String = "rewards"
	var seen_keys: Dictionary = {}
	var rewards: Array[FishingRewardDefinition] = REWARD_CATALOG.get_all_rewards()

	for reward in rewards:
		_assert(report, reward.is_valid_definition(), "%s valid reward" % reward.reward_key, group)
		var key: String = str(reward.reward_key)
		_assert(report, not seen_keys.has(key), "unique reward %s" % key, group)
		seen_keys[key] = true

		match reward.reward_type:
			FishingRewardDefinition.RewardType.LURE:
				_assert(report, CONTENT_CATALOG.tackle.has_lure(reward.reward_item_id), "%s lure exists" % key, group)
			FishingRewardDefinition.RewardType.ROD:
				_assert(report, CONTENT_CATALOG.tackle.has_rod(reward.reward_item_id), "%s rod exists" % key, group)
			FishingRewardDefinition.RewardType.UNLOCK_FLAG:
				_assert(report, reward.reward_item_id != &"", "%s unlock flag" % key, group)

	var spanner: FishingRewardDefinition = REWARD_CATALOG.get_reward_by_key(&"gyosil_spanner_6000")
	var master: FishingRewardDefinition = REWARD_CATALOG.get_reward_by_key(&"gyosil_masters_rod_9500")
	_assert(report, spanner != null and spanner.threshold == 6000, "Spanner 6000 milestone", group)
	_assert(report, master != null and master.threshold == 9500, "Master's Rod 9500 milestone", group)


func _test_trades(report: Dictionary) -> void:
	var group: String = "trades"
	var seen_ids: Dictionary = {}
	var valid_fish_ids: Dictionary = {}
	var shop_counts: Dictionary = {}

	for fish in CONTENT_CATALOG.fish:
		if fish != null:
			valid_fish_ids[fish.get_stable_species_id().to_lower()] = true

	for recipe in TRADE_CATALOG.get_all_recipes():
		_assert(report, recipe.is_valid_definition(), "%s valid trade" % recipe.recipe_id, group)
		var recipe_id: String = str(recipe.recipe_id)
		_assert(report, not seen_ids.has(recipe_id), "unique trade %s" % recipe_id, group)
		seen_ids[recipe_id] = true
		var shop_id: String = str(recipe.shop_id)
		shop_counts[shop_id] = int(shop_counts.get(shop_id, 0)) + 1

		for fish_id in recipe.required_fish_ids:
			_assert(report, valid_fish_ids.has(str(fish_id).to_lower()), "%s cost fish %s exists" % [recipe_id, fish_id], group)

		match recipe.reward_type:
			FishingTradeRecipe.RewardType.LURE:
				_assert(report, CONTENT_CATALOG.tackle.has_lure(recipe.reward_id), "%s lure reward exists" % recipe_id, group)
			FishingTradeRecipe.RewardType.ROD:
				_assert(report, CONTENT_CATALOG.tackle.has_rod(recipe.reward_id), "%s rod reward exists" % recipe_id, group)
				if recipe.unique_reward:
					_assert(report, not recipe.repeatable, "%s unique rod is non-repeatable" % recipe_id, group)

	_assert_equal_int(report, int(shop_counts.get("wyndia", 0)), 7, "Wyndia trade count", group)
	_assert_equal_int(report, int(shop_counts.get("lyp", 0)), 7, "Lyp trade count", group)


func _test_fight_stat_resolution(report: Dictionary) -> void:
	var group: String = "fight_stats"
	var archetypes: Dictionary = {}
	var dominant_actions: Dictionary = {}
	var personality_signatures: Dictionary = {}
	var resolved_species: int = 0

	for fish_data in CONTENT_CATALOG.fish:
		if fish_data == null:
			continue

		var fish_name: String = fish_data.fish_name
		var profile = fish_data.behavior_profile

		_assert(report, profile != null, "%s has fight profile" % fish_name, group)
		if profile == null:
			continue

		_assert(report, profile.is_valid_profile(), "%s profile valid" % fish_name, group)
		archetypes[profile.get_archetype_label()] = true
		dominant_actions[profile.get_dominant_action_label()] = true
		personality_signatures[profile.get_personality_signature()] = true

		var distribution: Dictionary = profile.get_action_distribution()
		var distribution_total := (
			float(distribution.get("surge", 0.0))
			+ float(distribution.get("side_run", 0.0))
			+ float(distribution.get("dive", 0.0))
			+ float(distribution.get("rise", 0.0))
			+ float(distribution.get("erratic", 0.0))
		)
		_assert(
			report,
			absf(distribution_total - 1.0) <= 0.001,
			"%s action distribution normalized" % fish_name,
			group
		)

		var small_size := maxf(
			fish_data.average_size * fish_data.normal_min_average_multiplier,
			1.0
		)
		var average_size := maxf(fish_data.average_size, small_size)
		var large_size := minf(
			lerpf(fish_data.average_size, fish_data.king_size, 0.75),
			maxf(fish_data.king_size - 1.0, fish_data.average_size)
		)
		var king_size := maxf(fish_data.king_size, large_size)

		var small := FishInstance.new()
		small.setup(fish_data, -1, small_size)
		var average := FishInstance.new()
		average.setup(fish_data, -1, average_size)
		var large := FishInstance.new()
		large.setup(fish_data, -1, large_size)
		var king := FishInstance.new()
		king.setup(fish_data, -1, king_size)

		for specimen in [small, average, large, king]:
			_assert(
				report,
				FightResolver.is_valid_specimen_stats(specimen.get_fight_stats()),
				"%s %.0fcm resolved fight stats valid" % [fish_name, specimen.size],
				group
			)

		_assert(
			report,
			average.max_stamina >= small.max_stamina,
			"%s average stamina >= small" % fish_name,
			group
		)
		_assert(
			report,
			large.max_stamina >= average.max_stamina,
			"%s large stamina >= average" % fish_name,
			group
		)
		_assert(
			report,
			king.max_stamina >= large.max_stamina,
			"%s king stamina >= large" % fish_name,
			group
		)
		_assert(
			report,
			large.strength >= average.strength,
			"%s large strength >= average" % fish_name,
			group
		)
		_assert(
			report,
			king.strength >= large.strength,
			"%s king strength >= large" % fish_name,
			group
		)
		_assert(
			report,
			large.pull_multiplier >= average.pull_multiplier,
			"%s large pull >= average" % fish_name,
			group
		)
		_assert(
			report,
			king.pull_multiplier >= large.pull_multiplier,
			"%s king pull >= large" % fish_name,
			group
		)
		_assert(
			report,
			large.pressure_multiplier >= average.pressure_multiplier,
			"%s large pressure >= average" % fish_name,
			group
		)
		_assert(
			report,
			king.behavior_intensity_multiplier >= large.behavior_intensity_multiplier,
			"%s king behavior >= large" % fish_name,
			group
		)

		# Stress the entire authored specimen range. This catches bad exponents,
		# negative multipliers and future data edits before they reach Encounter.
		var stress_max := fish_data.king_size * fish_data.king_max_size_multiplier
		for step_index in range(13):
			var t := float(step_index) / 12.0
			var stress_size := lerpf(small_size, stress_max, t)
			var stress_stats: Dictionary = FightResolver.resolve_specimen(
				fish_data,
				stress_size,
				stress_size >= fish_data.king_size
			)
			_assert(
				report,
				FightResolver.is_valid_specimen_stats(stress_stats),
				"%s stress specimen %d valid" % [fish_name, step_index],
				group
			)

		# Every rod must resolve through the same context without rewriting fish
		# stats. This makes rod differentiation additive and prevents hidden fish
		# balance changes in Encounter.
		if CONTENT_CATALOG.tackle != null:
			for rod in CONTENT_CATALOG.tackle.rods:
				if rod == null:
					continue
				var context: Dictionary = FightResolver.resolve_context(
					average,
					rod,
					null
				)
				_assert(
					report,
					FightResolver.is_valid_context(context),
					"%s + %s context valid" % [fish_name, rod.rod_name],
					group
				)
				_assert(
					report,
					absf(float(context.get("max_stamina", 0.0)) - average.max_stamina) <= 0.001,
					"%s rod does not secretly rewrite stamina" % fish_name,
					group
				)

		# Lures currently own attraction/retrieve behavior, not hooked-fish
		# strength. Verify that contract explicitly so a future lure trait must be
		# added in the resolver rather than as an Encounter special case.
		if (
			CONTENT_CATALOG.tackle != null
			and CONTENT_CATALOG.tackle.lure_catalog != null
		):
			var base_context: Dictionary = FightResolver.resolve_context(
				average,
				null,
				null
			)
			for lure in CONTENT_CATALOG.tackle.lure_catalog.lures:
				if lure == null:
					continue
				var lure_context: Dictionary = FightResolver.resolve_context(
					average,
					null,
					lure
				)
				_assert(
					report,
					absf(
						float(lure_context.get("strength", 0.0))
						- float(base_context.get("strength", 0.0))
					) <= 0.001,
					"%s lure %s keeps fish strength authoritative" % [fish_name, lure.display_name],
					group
				)

		resolved_species += 1

	_assert_equal_int(
		report,
		resolved_species,
		EXPECTED_FISH_COUNT,
		"all species resolve fight stats",
		group
	)
	_assert(
		report,
		archetypes.size() >= 5,
		"all five fight archetypes represented",
		group
	)
	_assert(
		report,
		dominant_actions.size() >= 5,
		"all five dominant movement identities represented",
		group
	)
	_assert(
		report,
		personality_signatures.size() >= 20,
		"species behavior data has broad personality variety",
		group
	)


func _test_tension_profile(report: Dictionary) -> void:
	var group: String = "tension"
	_assert(report, TENSION_PROFILE != null, "default tension profile exists", group)
	if TENSION_PROFILE == null:
		return
	_assert(report, TENSION_PROFILE.is_valid_profile(), "default tension profile valid", group)
	_assert(report, TENSION_PROFILE.safe_min < TENSION_PROFILE.safe_max, "ordered safe zone", group)
	_assert(report, TENSION_PROFILE.line_break_delay >= 0.0, "non-negative snap delay", group)
	_assert(report, TENSION_PROFILE.hook_off_threshold >= 0.0 and TENSION_PROFILE.hook_off_threshold <= 1.0, "hook-off threshold range", group)
	_assert(report, TENSION_PROFILE.hook_off_delay >= 0.0, "hook-off delay non-negative", group)

	if CONTENT_CATALOG.tackle != null:
		for rod in CONTENT_CATALOG.tackle.rods:
			if rod == null:
				continue
			var effective_delay: float = TENSION_PROFILE.line_break_delay * rod.line_tolerance_multiplier
			_assert(report, effective_delay > 0.0, "%s effective snap delay" % rod.rod_id, group)


func _test_fight_lifecycle_regression(report: Dictionary) -> void:
	var group: String = "fight_lifecycle"
	var lifecycle = FightLifecycleScript.new()

	_assert_equal_int(
		report,
		lifecycle.state,
		FightLifecycleScript.State.IDLE,
		"new lifecycle starts idle",
		group
	)

	# Direct-hit path: WAITING_BITE -> HOOKED without a bite window.
	_assert(report, lifecycle.begin_cast(), "cast begins", group)
	_assert(
		report,
		not lifecycle.begin_cast(),
		"active cast rejects a second begin",
		group
	)
	_assert(
		report,
		lifecycle.confirm_hook(),
		"direct hit hooks from waiting state",
		group
	)
	_assert(
		report,
		not lifecycle.open_bite_window(),
		"hooked fight rejects stale bite-window activation",
		group
	)
	_assert(
		report,
		lifecycle.begin_landing(),
		"hooked fight enters landing",
		group
	)
	_assert(
		report,
		lifecycle.begin_landing(),
		"landing transition is idempotent",
		group
	)
	_assert(
		report,
		lifecycle.resolve_catch(),
		"landing resolves catch exactly once",
		group
	)
	_assert(
		report,
		not lifecycle.resolve_catch(),
		"resolved catch cannot commit twice",
		group
	)
	_assert(
		report,
		not lifecycle.resolve_line_break(),
		"resolved catch rejects late failure",
		group
	)
	_assert(
		report,
		not lifecycle.cancel_cast(),
		"resolved catch cannot be rewritten as cancellation",
		group
	)
	_assert_equal_int(
		report,
		lifecycle.resolution,
		FightLifecycleScript.Resolution.CATCH,
		"catch resolution remains immutable",
		group
	)
	lifecycle.finish_cast()

	# Bite-window path: WAIT -> WINDOW -> MISS -> WAIT -> WINDOW -> HOOK.
	_assert(report, lifecycle.begin_cast(), "second cast begins", group)
	_assert(report, lifecycle.open_bite_window(), "bite window opens", group)
	_assert(report, lifecycle.miss_bite(), "miss returns to waiting", group)
	_assert(
		report,
		not lifecycle.miss_bite(),
		"stale miss callback is ignored",
		group
	)
	_assert(report, lifecycle.open_bite_window(), "retry window opens", group)
	_assert(report, lifecycle.confirm_hook(), "retry hooks", group)
	_assert(report, lifecycle.resolve_line_break(), "line break resolves fight", group)
	_assert(
		report,
		not lifecycle.resolve_hook_off(),
		"second terminal failure cannot override first",
		group
	)
	_assert_equal_int(
		report,
		lifecycle.resolution,
		FightLifecycleScript.Resolution.LINE_BREAK,
		"line-break resolution remains authoritative",
		group
	)
	lifecycle.finish_cast()

	# Stress many cast lifecycles so state never leaks across recasts.
	for index in range(128):
		lifecycle.begin_cast()
		_assert(
			report,
			lifecycle.resolution == FightLifecycleScript.Resolution.NONE,
			"stress cast %d clears previous resolution" % index,
			group
		)

		if index % 3 == 0:
			lifecycle.open_bite_window()
			lifecycle.miss_bite()
			lifecycle.cancel_cast()
		elif index % 3 == 1:
			lifecycle.confirm_hook()
			lifecycle.resolve_hook_off()
		else:
			lifecycle.confirm_hook()
			lifecycle.begin_landing()
			lifecycle.resolve_catch()

		_assert(
			report,
			lifecycle.is_resolved(),
			"stress cast %d reaches one terminal state" % index,
			group
		)
		lifecycle.finish_cast()
		_assert_equal_int(
			report,
			lifecycle.state,
			FightLifecycleScript.State.IDLE,
			"stress cast %d returns idle" % index,
			group
		)


func _test_tension_failure_regression(report: Dictionary) -> void:
	var group: String = "fight_tension"
	var profile := TENSION_PROFILE.duplicate(true) as FishingTensionProfile

	_assert(report, profile != null, "tension profile duplicates", group)
	if profile == null:
		return

	# Deliberately short deterministic values for regression simulation. Runtime
	# balance remains authored in the real profile/scene; these are test-only.
	profile.safe_min = 0.30
	profile.safe_max = 0.40
	profile.tension_response_speed = 10.0
	profile.release_tension_speed = 10.0
	profile.line_break_delay = 0.30
	profile.hook_off_threshold = 0.10
	profile.hook_off_delay = 0.20

	var line_break_30 := _simulate_tension_failure_time(
		profile,
		FishingTension.FailureReason.LINE_BREAK,
		1.0 / 30.0
	)
	var line_break_60 := _simulate_tension_failure_time(
		profile,
		FishingTension.FailureReason.LINE_BREAK,
		1.0 / 60.0
	)

	_assert(report, line_break_30 > 0.0, "line break occurs at 30 Hz", group)
	_assert(report, line_break_60 > 0.0, "line break occurs at 60 Hz", group)
	_assert(
		report,
		absf(line_break_30 - line_break_60) <= 0.08,
		"line-break timing is frame-rate stable",
		group
	)

	var hook_off_30 := _simulate_tension_failure_time(
		profile,
		FishingTension.FailureReason.HOOK_OFF,
		1.0 / 30.0
	)
	var hook_off_60 := _simulate_tension_failure_time(
		profile,
		FishingTension.FailureReason.HOOK_OFF,
		1.0 / 60.0
	)

	_assert(report, hook_off_30 > 0.0, "hook off occurs at 30 Hz", group)
	_assert(report, hook_off_60 > 0.0, "hook off occurs at 60 Hz", group)
	_assert(
		report,
		absf(hook_off_30 - hook_off_60) <= 0.08,
		"hook-off timing is frame-rate stable",
		group
	)

	# Free-reel mode must never invoke fight failures no matter how violently a
	# lure twitch changes the gauge before any fish is hooked.
	var free_reel: FishingTension = TensionScript.new()
	free_reel.configure_profile(profile)
	free_reel.start_free_reel()
	free_reel.add_impulse(1.0)
	for _index in range(120):
		free_reel.advance(1.0 / 60.0)
	_assert_equal_int(
		report,
		free_reel.last_failure_reason,
		FishingTension.FailureReason.NONE,
		"free reel cannot trigger fight failure",
		group
	)
	_assert(report, free_reel.active, "free reel remains active", group)
	free_reel.stop()
	_assert_equal_int(
		report,
		free_reel.current_state,
		FishingTension.State.SAFE,
		"stop clears stale tension state",
		group
	)
	_assert(
		report,
		is_zero_approx(free_reel.value),
		"stop clears stale tension value",
		group
	)
	free_reel.free()


func _simulate_tension_failure_time(
	profile: FishingTensionProfile,
	reason: int,
	step: float
) -> float:
	var tension: FishingTension = TensionScript.new()
	tension.configure_profile(profile)
	tension.start()

	if reason == FishingTension.FailureReason.LINE_BREAK:
		tension.set_player_reeling(true)
		tension.set_fish_resistance(1.0)
	else:
		tension.set_player_reeling(false)
		tension.set_fish_resistance(0.0)

	var elapsed := 0.0
	var max_time := 5.0

	while elapsed < max_time and tension.last_failure_reason == FishingTension.FailureReason.NONE:
		tension.advance(step)
		elapsed += step

	var result := -1.0
	if tension.last_failure_reason == reason:
		result = elapsed

	# Once terminal, extra updates must not mutate the reason or restart timers.
	var terminal_reason := tension.last_failure_reason
	for _index in range(30):
		tension.advance(step)
	if tension.last_failure_reason != terminal_reason:
		result = -1.0

	tension.free()
	return result


func _test_landing_regression(
	report: Dictionary
) -> void:
	var group: String = "landing"
	var bait = BaitScript.new()

	_assert(
		report,
		bait != null,
		"bait runtime instantiates",
		group
	)

	if bait == null:
		return

	bait.return_distance = 0.5
	bait.fight_mode = true
	bait.fish_pull_strength = 1.0

	_assert(
		report,
		bait.can_complete_return(0.49),
		"high pull cannot veto landing inside radius",
		group
	)
	_assert(
		report,
		bait.can_complete_return(0.50),
		"landing threshold is inclusive",
		group
	)
	_assert(
		report,
		not bait.can_complete_return(0.51),
		"outside landing radius does not complete",
		group
	)

	bait.free()


func _test_shore_boundary_regression(
	report: Dictionary
) -> void:
	var group: String = "shore_boundary"
	var boundary = ShoreBoundaryScript.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()

	box.size = Vector3(10.0, 2.0, 0.35)
	shape_node.shape = box
	shape_node.name = "CollisionShape3D"
	boundary.add_child(shape_node)
	boundary.position = Vector3(0.0, 0.0, -0.45)
	boundary.water_side_sign = -1
	boundary.water_clearance = 0.0

	var clamped: Vector3 = boundary.constrain_water_motion(
		Vector3(0.0, 0.0, -1.0),
		Vector3(0.0, 0.0, 0.25)
	)

	_assert(
		report,
		clamped.z <= -0.6249,
		"hooked fish cannot cross the shore plane",
		group
	)

	var lateral_clamped: Vector3 = boundary.constrain_water_motion(
		Vector3(8.0, 0.0, -1.0),
		Vector3(8.0, 0.0, 0.25)
	)

	_assert(
		report,
		lateral_clamped.z <= -0.6249,
		"shore plane remains authoritative during hard lateral runs",
		group
	)

	var bait = BaitScript.new()
	var reel_target := Node3D.new()
	reel_target.position = Vector3.ZERO
	bait.position = Vector3(0.0, 0.0, 0.20)
	bait.set_reel_target(reel_target)
	bait.set_shore_boundary(boundary)
	bait.state = BaitScript.State.IN_WATER
	bait.fight_mode = true

	bait._finish_return(reel_target.global_position)

	_assert(
		report,
		bait.position.z <= -0.6249,
		"fight landing does not teleport fish onto dry land",
		group
	)

	bait.free()
	reel_target.free()
	boundary.free()


func _test_camera_return_regression(
	report: Dictionary
) -> void:
	var group: String = "camera_return"
	var rig = CameraRigScript.new()

	_assert(
		report,
		rig != null,
		"camera rig runtime instantiates",
		group
	)

	if rig == null:
		return

	# Airborne casts are still allowed to use lure-centric framing.
	rig.fishing_follow_active = true
	rig.fishing_follow_has_reached_water = false
	_assert(
		report,
		not rig.should_hand_off_fishing_follow_to_player(true),
		"airborne visible player does not reclaim camera",
		group
	)

	# Water + visible player must transfer ownership even if follow is already
	# active. This is the long-cast path.
	rig.fishing_follow_has_reached_water = true
	_assert(
		report,
		rig.should_hand_off_fishing_follow_to_player(true),
		"active waterborne cast can hand off to player",
		group
	)

	# Exact regression from the reported bug: the player notifier can fire while
	# the cast is still ARMED and has never activated fish-centric camera follow.
	# That state used to refuse the handoff, leaving a latent tracking boundary
	# that A/D spam could activate later.
	rig.fishing_follow_active = false
	rig.fishing_follow_armed = true
	rig.fishing_player_return_active = false
	rig.fishing_player_camera_locked = false
	rig.fishing_follow_has_reached_water = true
	_assert(
		report,
		rig.should_hand_off_fishing_follow_to_player(true),
		"armed waterborne cast hands off before any tracking threshold",
		group
	)

	# Off-screen player still permits fish-centric framing until the player has
	# actually reclaimed the shot.
	_assert(
		report,
		not rig.should_hand_off_fishing_follow_to_player(false),
		"off-screen player keeps cast tracking ownership",
		group
	)

	# Once ownership is latched, it is one-way for the rest of the cast.
	rig.fishing_player_camera_locked = true
	_assert(
		report,
		not rig.should_hand_off_fishing_follow_to_player(true),
		"latched player ownership cannot be reclaimed by fish tracking",
		group
	)

	# A new cast is the only normal path that releases the ownership latch. The
	# public arm method needs scene nodes, so verify the state contract directly:
	# unlocked + waterborne + visible becomes eligible again.
	rig.fishing_player_camera_locked = false
	rig.fishing_player_return_active = false
	rig.fishing_follow_has_reached_water = true
	_assert(
		report,
		rig.should_hand_off_fishing_follow_to_player(true),
		"new-cast state may establish fresh player ownership",
		group
	)

	rig.free()


func _test_cast_input_regression(
	report: Dictionary
) -> void:
	var group: String = "cast_input"
	var gate: FishingCastInputGate = (
		CastInputGateScript.new()
	)

	gate.reset(false)

	_assert(
		report,
		gate.press(
			FishingCastInputGate.Stage.AIM
		)
		== FishingCastInputGate.PressResult.CONSUMED,
		"first K consumes AIM",
		group
	)
	_assert(
		report,
		gate.press(
			FishingCastInputGate.Stage.PREP_THROW
		)
		== FishingCastInputGate.PressResult.IGNORED,
		"held/repeated K cannot advance another stage",
		group
	)

	gate.release(
		FishingCastInputGate.Stage.PREP_THROW
	)

	_assert(
		report,
		gate.press(
			FishingCastInputGate.Stage.PREP_THROW
		)
		== FishingCastInputGate.PressResult.BUFFERED,
		"fast second physical K buffers during Prep_Throw",
		group
	)
	_assert(
		report,
		gate.press(
			FishingCastInputGate.Stage.PREP_THROW
		)
		== FishingCastInputGate.PressResult.IGNORED,
		"buffered press cannot double-consume",
		group
	)

	gate.release(
		FishingCastInputGate.Stage.PREP_THROW
	)

	_assert(
		report,
		gate.take_prep_buffer(),
		"buffer survives until Prep_Throw completion",
		group
	)
	_assert(
		report,
		not gate.take_prep_buffer(),
		"buffer is consumed exactly once",
		group
	)
	_assert(
		report,
		gate.press(
			FishingCastInputGate.Stage.CURVE
		)
		== FishingCastInputGate.PressResult.CONSUMED,
		"fresh K after buffered lock can confirm cast",
		group
	)

	gate.reset(true)

	_assert(
		report,
		gate.press(
			FishingCastInputGate.Stage.AIM
		)
		== FishingCastInputGate.PressResult.IGNORED,
		"entering AIM while K held cannot auto-confirm",
		group
	)

	gate.release(
		FishingCastInputGate.Stage.AIM
	)

	_assert(
		report,
		gate.press(
			FishingCastInputGate.Stage.AIM
		)
		== FishingCastInputGate.PressResult.CONSUMED,
		"release rearms held-key protection",
		group
	)


func _test_qa_profiles(report: Dictionary) -> void:
	var group: String = "qa_profiles"
	var directory := DirAccess.open(QA_PROFILE_DIRECTORY)
	_assert(report, directory != null, "QA profile directory opens", group)
	if directory == null:
		return

	var profile_count: int = 0
	for file_name in directory.get_files():
		if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
			continue
		var resource: Resource = ResourceLoader.load(QA_PROFILE_DIRECTORY.path_join(file_name))
		_assert(report, resource is FishingQAProfile, "%s loads as FishingQAProfile" % file_name, group)
		if not (resource is FishingQAProfile):
			continue
		profile_count += 1
		var profile := resource as FishingQAProfile
		_assert(report, not profile.profile_name.strip_edges().is_empty(), "%s has name" % file_name, group)
		_assert(report, not profile.purpose.strip_edges().is_empty(), "%s has purpose" % file_name, group)

	_assert(report, profile_count >= 10, "at least 10 QA scenarios", group)


func _packed_int_arrays_equal(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if a[index] != b[index]:
			return false
	return true


func _assert_equal_int(
	report: Dictionary,
	actual: int,
	expected: int,
	label: String,
	group: String
) -> void:
	_assert(
		report,
		actual == expected,
		"%s (%d == %d)" % [label, actual, expected],
		group
	)


func _assert_equal_string(
	report: Dictionary,
	actual: String,
	expected: String,
	label: String,
	group: String
) -> void:
	_assert(
		report,
		actual == expected,
		'%s ("%s" == "%s")' % [label, actual, expected],
		group
	)


func _assert(
	report: Dictionary,
	condition: bool,
	label: String,
	group: String
) -> void:
	report["assertions"] = int(report.get("assertions", 0)) + 1
	var groups: Dictionary = report.get("groups", {}) as Dictionary
	var group_result: Dictionary = groups.get(group, {"passed": 0, "failed": 0}) as Dictionary

	if condition:
		report["passed"] = int(report.get("passed", 0)) + 1
		group_result["passed"] = int(group_result.get("passed", 0)) + 1
	else:
		report["failed"] = int(report.get("failed", 0)) + 1
		group_result["failed"] = int(group_result.get("failed", 0)) + 1
		var failures: PackedStringArray = report.get("failures", PackedStringArray())
		failures.append("[%s] %s" % [group, label])
		report["failures"] = failures

	groups[group] = group_result
	report["groups"] = groups


func _build_summary(report: Dictionary) -> String:
	var failed: int = int(report.get("failed", 0))
	var passed: int = int(report.get("passed", 0))
	var assertions: int = int(report.get("assertions", 0))
	var duration_ms: float = float(report.get("duration_ms", 0.0))

	if failed <= 0:
		return "PASS %d / %d  (%.1f ms)" % [passed, assertions, duration_ms]

	return "FAIL %d | PASS %d / %d  (%.1f ms)" % [failed, passed, assertions, duration_ms]


func _print_report(report: Dictionary) -> void:
	print("[Fishing QA] ", str(report.get("summary", "")))
	var groups: Dictionary = report.get("groups", {}) as Dictionary
	var group_names: Array = groups.keys()
	group_names.sort()

	for raw_name in group_names:
		var group_name: String = str(raw_name)
		var result: Dictionary = groups[group_name] as Dictionary
		print(
			"[Fishing QA] %-12s PASS %d  FAIL %d" % [
				group_name,
				int(result.get("passed", 0)),
				int(result.get("failed", 0)),
			]
		)

	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	for failure in failures:
		push_warning("Fishing QA: " + failure)
