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
const ShopCatalogScript = preload(
	"res://scripts/fishing_shop_catalog.gd"
)
const ShopOfferScript = preload(
	"res://scripts/database/fishing_shop_offer.gd"
)
const SHOP_CATALOG: ShopCatalogScript = preload(
	"res://data/bof4/shops/all_shops.tres"
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
const SpecimenGenerator = preload(
	"res://scripts/fishing_specimen_generator.gd"
)
const RECORD_MERCY_POLICY = preload(
	"res://data/bof4/progression/default_record_mercy.tres"
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
const FightAccessibility = preload(
	"res://scripts/fishing_fight_accessibility.gd"
)
const DIFFICULTY_POLICY = preload(
	"res://data/bof4/fight/default_difficulty_policy.tres"
)
const TensionScript = preload(
	"res://scripts/tension.gd"
)
const OutcomeServiceScript = preload(
	"res://scripts/fishing_outcome_service.gd"
)
const OUTCOME_POLICY = preload(
	"res://data/bof4/outcomes/default_outcome_policy.tres"
)
const ProgressionIntegrityScript = preload(
	"res://scripts/fishing_progression_integrity.gd"
)
const RewardServiceScript = preload(
	"res://scripts/fishing_reward_service.gd"
)
const EconomyIntegrityScript = preload(
	"res://scripts/fishing_economy_integrity.gd"
)
const FishEffectCatalogScript = preload(
	"res://scripts/fishing_fish_effect_catalog.gd"
)
const FISH_EFFECT_CATALOG: FishEffectCatalogScript = preload(
	"res://data/bof4/effects/all_fish_effects.tres"
)
const SessionModifierServiceScript = preload(
	"res://scripts/fishing_session_modifier_service.gd"
)
const FishEffectIntegrityScript = preload(
	"res://scripts/fishing_fish_effect_integrity.gd"
)
const EnvironmentServiceScript = preload(
	"res://scripts/fishing_environment_service.gd"
)
const EnvironmentIntegrityScript = preload(
	"res://scripts/fishing_environment_integrity.gd"
)
const ENVIRONMENT_CATALOG = preload(
	"res://data/bof4/environment/all_environment_conditions.tres"
)
const FishInstanceScript = preload(
	"res://scripts/fish_instance.gd"
)
const TradeServiceScript = preload(
	"res://scripts/fishing_trade_service.gd"
)
const EconomyServiceScript = preload(
	"res://scripts/fishing_economy_service.gd"
)
const EconomyAccessScript = preload(
	"res://scripts/fishing_economy_access.gd"
)
const FishConsumableServiceScript = preload(
	"res://scripts/fishing_fish_consumable_service.gd"
)
const SaveIntegrityServiceScript = preload(
	"res://scripts/fishing_save_integrity_service.gd"
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
const EXPECTED_SHOP_OFFER_COUNT: int = 16
const EXPECTED_FISH_EFFECT_COUNT: int = 30
const EXPECTED_ENVIRONMENT_CONDITION_COUNT: int = 5
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
	_test_record_mercy_system(report)
	_test_catch_persistence_regression(report)
	_test_all_species_record_delta_regression(report)
	_test_debug_persistence_gate_regression(report)
	_test_debug_specimen_forcing(report)
	_test_rewards(report)
	_test_progression_reward_contract(report)
	_test_outcome_loop(report)
	_test_trades(report)
	_test_economy_contract(report)
	_test_fish_consumable_effects(report)
	_test_environment_conditions(report)
	_test_player_economy_access_and_save_integrity(report)
	_test_fight_stat_resolution(report)
	_test_tackle_differentiation(report)
	_test_difficulty_accessibility_curve(report)
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
		_assert(report, not lure.fight_role_label.strip_edges().is_empty(), "%s fight role" % lure_id, group)
		_assert(report, lure.fight_fatigue_multiplier >= 0.80 and lure.fight_fatigue_multiplier <= 1.20, "%s fight fatigue range" % lure_id, group)
		_assert(report, lure.hook_security_multiplier >= 0.80 and lure.hook_security_multiplier <= 1.20, "%s hook security range" % lure_id, group)
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
		_assert(report, not rod.fight_role_label.strip_edges().is_empty(), "%s fight role" % rod_id, group)
		_assert(report, rod.fight_fatigue_multiplier >= 0.75 and rod.fight_fatigue_multiplier <= 1.35, "%s fight fatigue range" % rod_id, group)
		_assert(report, rod.hook_security_multiplier >= 0.75 and rod.hook_security_multiplier <= 1.35, "%s hook security range" % rod_id, group)
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


func _test_record_mercy_system(report: Dictionary) -> void:
	var group: String = "record_mercy"
	_assert(report, RECORD_MERCY_POLICY != null, "record mercy policy exists", group)
	if RECORD_MERCY_POLICY == null:
		return

	_assert(
		report,
		RECORD_MERCY_POLICY.has_method("is_valid_policy")
		and bool(RECORD_MERCY_POLICY.call("is_valid_policy")),
		"record mercy policy valid",
		group
	)

	var sweetfish: FishData = null
	for fish in CONTENT_CATALOG.fish:
		if (
			fish != null
			and fish.get_stable_species_id().to_lower() == "sweetfish"
		):
			sweetfish = fish
			break

	_assert(report, sweetfish != null, "Sweetfish exists for mercy test", group)
	if sweetfish == null:
		return

	var progress := FishingProgress.new()
	progress.progression_catalog = PROGRESSION_CATALOG
	progress.record_mercy_policy = RECORD_MERCY_POLICY

	# A real first record starts clean. Only completed non-record catches advance
	# the per-species dry streak.
	progress.record_catch_snapshot(
		CatchEvaluatorScript.create_snapshot_from_values(sweetfish, 18.0),
		false,
		false
	)
	_assert_equal_int(
		report,
		progress.get_record_miss_streak(sweetfish),
		0,
		"first record starts with zero miss streak",
		group
	)

	for expected_streak in range(1, 4):
		progress.record_catch_snapshot(
			CatchEvaluatorScript.create_snapshot_from_values(sweetfish, 17.0),
			false,
			false
		)
		_assert_equal_int(
			report,
			progress.get_record_miss_streak(sweetfish),
			expected_streak,
			"non-record catch advances streak to %d" % expected_streak,
			group
		)

	var mercy_context: Dictionary = progress.get_record_mercy_context(sweetfish)
	_assert(report, bool(mercy_context.get("active", false)), "mercy activates after configured dry streak", group)
	_assert_float_close(
		report,
		float(mercy_context.get("bonus_roll_chance", 0.0)),
		0.10,
		0.0001,
		"first mercy step grants ten-percent bonus-roll chance",
		group
	)

	progress.record_catch_snapshot(
		CatchEvaluatorScript.create_snapshot_from_values(sweetfish, 17.0),
		false,
		false
	)
	mercy_context = progress.get_record_mercy_context(sweetfish)
	_assert_float_close(
		report,
		float(mercy_context.get("bonus_roll_chance", 0.0)),
		0.20,
		0.0001,
		"mercy chance grows after another failed record catch",
		group
	)

	# A genuine improved record immediately clears the dry streak.
	var improved: Dictionary = progress.record_catch_snapshot(
		CatchEvaluatorScript.create_snapshot_from_values(sweetfish, 20.0),
		false,
		false
	)
	_assert(report, bool(improved.get("record_improved", false)), "improved specimen is recognized as record improvement", group)
	_assert_equal_int(report, progress.get_record_miss_streak(sweetfish), 0, "new record resets mercy streak", group)
	_assert(report, not bool(progress.get_record_mercy_context(sweetfish).get("active", true)), "new record disables mercy again", group)

	# A completed/crown score can never accumulate anti-bad-luck pressure because
	# there is no higher score left to chase.
	progress.record_catch_snapshot(
		CatchEvaluatorScript.create_snapshot_from_values(sweetfish, sweetfish.king_size),
		false,
		false
	)
	for _index in range(4):
		progress.record_catch_snapshot(
			CatchEvaluatorScript.create_snapshot_from_values(sweetfish, 17.0),
			false,
			false
		)
	_assert_equal_int(report, progress.get_record_miss_streak(sweetfish), 0, "completed species never accumulates mercy", group)
	_assert(report, not bool(progress.get_record_mercy_context(sweetfish).get("active", true)), "completed species keeps mercy disabled", group)

	# Pressure-test the generator at maximum mercy. It may add one extra roll and
	# select the larger candidate, but the 65% cap means neither the bonus roll
	# nor a crown is guaranteed.
	var maximum_context: Dictionary = RECORD_MERCY_POLICY.call(
		"build_generation_context",
		99,
		1,
		maxi(sweetfish.max_points, 2)
	) as Dictionary
	var mercy_applied_count: int = 0
	var no_mercy_count: int = 0
	var non_king_count: int = 0

	for seed in range(256):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed + 1001
		var generated: Dictionary = SpecimenGenerator.roll_with_rng(
			sweetfish,
			rng,
			-1,
			maximum_context
		)
		var bonus_rolls: int = int(generated.get("mercy_bonus_rolls_used", 0))
		if bonus_rolls > 0:
			mercy_applied_count += 1
			var candidate_sizes = generated.get("candidate_sizes", []) as Array
			var largest_candidate: float = 0.0
			for raw_size in candidate_sizes:
				largest_candidate = maxf(largest_candidate, float(raw_size))
			_assert_float_close(
				report,
				float(generated.get("size", 0.0)),
				largest_candidate,
				0.001,
				"mercy keeps the larger specimen candidate",
				group
			)
		else:
			no_mercy_count += 1

		if not bool(generated.get("is_king", false)):
			non_king_count += 1

	_assert(report, mercy_applied_count > 0, "maximum mercy sometimes grants bonus roll", group)
	_assert(report, no_mercy_count > 0, "maximum mercy still sometimes grants no bonus roll", group)
	_assert(report, non_king_count > 0, "maximum mercy never guarantees a crown", group)

	# Explicit QA band forcing must bypass mercy so deterministic QA stays
	# deterministic instead of being secretly modified by player progression.
	var forced_rng := RandomNumberGenerator.new()
	forced_rng.seed = 42
	var forced_king: Dictionary = SpecimenGenerator.roll_with_rng(
		sweetfish,
		forced_rng,
		1,
		maximum_context
	)
	_assert(report, bool(forced_king.get("is_king", false)), "forced king remains king under mercy context", group)
	_assert_equal_int(report, int(forced_king.get("mercy_bonus_rolls_used", -1)), 0, "QA king override bypasses mercy bonus roll", group)
	_assert(report, not bool(forced_king.get("mercy_active", true)), "QA king override marks mercy inactive", group)

	# Every species must cleanly disable mercy after its own maximum score is
	# achieved; this catches catalog/resource mismatches across all 30 fish.
	for fish in CONTENT_CATALOG.fish:
		if fish == null:
			continue
		var complete_context: Dictionary = RECORD_MERCY_POLICY.call(
			"build_generation_context",
			99,
			maxi(fish.max_points, 0),
			maxi(fish.max_points, 0)
		) as Dictionary
		_assert(
			report,
			not bool(complete_context.get("active", true)),
			"%s completed record disables mercy" % fish.get_stable_species_id(),
			group
		)

	progress.free()


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
	_assert(report, REWARD_CATALOG.is_valid_catalog(), "reward catalog valid", group)
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


func _test_progression_reward_contract(report: Dictionary) -> void:
	var group: String = "progression_reward_contract"

	var audit: Dictionary = ProgressionIntegrityScript.audit(
		PROGRESSION_CATALOG,
		REWARD_CATALOG,
		CONTENT_CATALOG
	)
	_assert(report, bool(audit.get("ok", false)), "cross-catalog progression audit passes", group)
	var audit_details: Dictionary = audit.get("details", {}) as Dictionary
	_assert_equal_int(
		report,
		int(audit_details.get("species_max_points_total", -1)),
		EXPECTED_MAX_FISHING_POINTS,
		"all species max scores close exactly at 9999",
		group
	)

	# Every rank changes exactly on its inclusive threshold, never one point early.
	for index in range(PROGRESSION_CATALOG.ranks.size()):
		var rank: FishingRankDefinition = PROGRESSION_CATALOG.ranks[index]
		if rank == null:
			continue
		_assert_equal_int(
			report,
			PROGRESSION_CATALOG.get_rank_index(rank.min_points),
			index,
			"rank %s activates at threshold" % rank.display_name,
			group
		)
		if index > 0:
			_assert_equal_int(
				report,
				PROGRESSION_CATALOG.get_rank_index(rank.min_points - 1),
				index - 1,
				"rank %s does not activate early" % rank.display_name,
				group
			)

	var crossed: Array[Dictionary] = PROGRESSION_CATALOG.get_crossed_ranks(0, 1000)
	_assert_equal_int(report, crossed.size(), 3, "0 to 1000 crosses three rank milestones", group)
	if crossed.size() == 3:
		_assert_equal_string(report, str(crossed[0].get("name", "")), "Beginner+", "first crossed rank", group)
		_assert_equal_string(report, str(crossed[1].get("name", "")), "Beginner++", "second crossed rank", group)
		_assert_equal_string(report, str(crossed[2].get("name", "")), "Rodman", "third crossed rank", group)

	# Reward availability is tied to the same authoritative point total. The
	# rewards remain manual Gyosil claims; this verifies only availability.
	var progress := FishingProgress.new()
	progress.progression_catalog = PROGRESSION_CATALOG
	var rewards = RewardServiceScript.new()
	rewards.progress = progress
	rewards.reward_catalog = REWARD_CATALOG
	rewards.tackle_catalog = CONTENT_CATALOG.tackle

	progress.fishing_points = 5999
	_assert_equal_string(
		report,
		str(rewards.get_reward_status(&"gyosil_spanner_6000").get("state_label", "")),
		"LOCKED",
		"Spanner remains locked at 5999",
		group
	)
	progress.fishing_points = 6000
	_assert_equal_string(
		report,
		str(rewards.get_reward_status(&"gyosil_spanner_6000").get("state_label", "")),
		"AVAILABLE",
		"Spanner becomes available at 6000",
		group
	)
	progress.fishing_points = 9499
	_assert_equal_string(
		report,
		str(rewards.get_reward_status(&"gyosil_masters_rod_9500").get("state_label", "")),
		"LOCKED",
		"Master's Rod remains locked at 9499",
		group
	)
	progress.fishing_points = 9500
	_assert_equal_string(
		report,
		str(rewards.get_reward_status(&"gyosil_masters_rod_9500").get("state_label", "")),
		"AVAILABLE",
		"Master's Rod becomes available at 9500",
		group
	)

	progress.free()
	rewards.free()


func _test_outcome_loop(report: Dictionary) -> void:
	var group: String = "outcomes"

	_assert(
		report,
		OUTCOME_POLICY != null,
		"default outcome policy exists",
		group
	)
	if OUTCOME_POLICY == null:
		return

	_assert(
		report,
		bool(OUTCOME_POLICY.call("is_valid_policy")),
		"default outcome policy is valid",
		group
	)

	var miss_rule: Dictionary = OUTCOME_POLICY.call("get_rule", &"miss")
	var hook_rule: Dictionary = OUTCOME_POLICY.call("get_rule", &"hook_off")
	var break_rule: Dictionary = OUTCOME_POLICY.call("get_rule", &"line_break")
	var catch_rule: Dictionary = OUTCOME_POLICY.call("get_rule", &"catch")

	_assert(report, not bool(miss_rule.get("terminal", true)), "miss is non-terminal", group)
	_assert(report, not bool(miss_rule.get("consume_lure", true)), "miss keeps lure", group)
	_assert(report, bool(hook_rule.get("terminal", false)), "hook off is terminal", group)
	_assert(report, not bool(hook_rule.get("consume_lure", true)), "hook off keeps lure", group)
	_assert(report, bool(break_rule.get("terminal", false)), "line break is terminal", group)
	_assert(report, bool(break_rule.get("consume_lure", false)), "line break requests lure loss", group)
	_assert(report, bool(catch_rule.get("record_catch", false)), "catch records progress", group)
	_assert(report, bool(catch_rule.get("evaluate_rewards", false)), "catch evaluates rewards", group)
	_assert(report, bool(OUTCOME_POLICY.get("protect_last_owned_lure")), "last lure soft-lock protection enabled", group)
	_assert(report, OutcomeServiceScript.should_protect_last_lure(true, 1), "one remaining lure is protected", group)
	_assert(report, not OutcomeServiceScript.should_protect_last_lure(true, 2), "two remaining lures allow one loss", group)
	_assert(report, not OutcomeServiceScript.should_protect_last_lure(false, 1), "protection can be disabled when economy is ready", group)

	var service = OutcomeServiceScript.new()
	service.configure(null, null, null, OUTCOME_POLICY)
	var first_serial: int = service.begin_cast()
	_assert_equal_int(report, first_serial, 1, "first outcome cast serial", group)

	var miss_one: Dictionary = service.resolve_miss()
	var miss_two: Dictionary = service.resolve_miss()
	_assert(report, bool(miss_one.get("applied", false)), "first miss applies", group)
	_assert(report, not bool(miss_one.get("terminal", true)), "first miss keeps cast alive", group)
	_assert_equal_int(report, int(miss_two.get("miss_count", 0)), 2, "multiple misses stay in same cast", group)

	var hook_off: Dictionary = service.resolve_hook_off()
	_assert(report, bool(hook_off.get("applied", false)), "hook off applies once", group)
	_assert(report, bool(hook_off.get("terminal", false)), "hook off resolves cast", group)
	var hook_loss: Dictionary = hook_off.get("lure_loss", {})
	_assert_equal_string(report, str(hook_loss.get("reason", "")), "kept_by_outcome_policy", "hook off does not consume lure", group)

	var late_break: Dictionary = service.resolve_line_break()
	_assert(report, bool(late_break.get("duplicate", false)), "late line break cannot overwrite hook off", group)

	service.begin_cast()
	var line_break: Dictionary = service.resolve_line_break()
	_assert(report, bool(line_break.get("applied", false)), "line break applies once", group)
	var no_loadout_loss: Dictionary = line_break.get("lure_loss", {})
	_assert_equal_string(report, str(no_loadout_loss.get("reason", "")), "loadout_unavailable", "line break reports missing loadout instead of faking loss", group)

	service.begin_cast()
	var cancelled: Dictionary = service.resolve_cancelled()
	_assert(report, bool(cancelled.get("terminal", false)), "cancel resolves cast", group)
	var cancel_loss: Dictionary = cancelled.get("lure_loss", {})
	_assert_equal_string(report, str(cancel_loss.get("reason", "")), "kept_by_outcome_policy", "cancel keeps lure", group)

	service.begin_cast()
	var sample_fish := FishInstance.new()
	var sample_species: FishData = CONTENT_CATALOG.fish[0]
	sample_fish.setup(
		sample_species,
		0,
		maxf(sample_species.average_size, 1.0),
		{}
	)
	var debug_catch: Dictionary = service.resolve_catch(sample_fish, {}, false)
	_assert(report, bool(debug_catch.get("applied", false)), "debug catch resolves terminal outcome", group)
	_assert(report, bool(debug_catch.get("recording_skipped", false)), "debug catch explicitly reports skipped persistence", group)
	_assert(report, bool(debug_catch.get("backend_ok", false)), "intentional debug skip is not treated as backend failure", group)
	var debug_record: Dictionary = debug_catch.get("catch_result", {})
	_assert_equal_string(report, str(debug_record.get("reason", "")), "debug_recording_disabled", "debug catch skip reason is explicit", group)

	service.begin_cast()
	var king_fish := FishInstance.new()
	king_fish.setup(
		sample_species,
		1,
		maxf(sample_species.king_size, 1.0),
		{}
	)
	var debug_king: Dictionary = service.resolve_catch(king_fish, {}, false)
	_assert(report, bool(debug_king.get("is_king", false)), "king catch remains explicit in outcome", group)

	service.begin_cast()
	var missing_repo: Dictionary = service.resolve_catch(sample_fish, {}, true)
	_assert(report, not bool(missing_repo.get("backend_ok", true)), "missing catch backend cannot report success", group)
	var missing_repo_record: Dictionary = missing_repo.get("catch_result", {})
	_assert_equal_string(report, str(missing_repo_record.get("reason", "")), "repository_unavailable", "missing repository failure is explicit", group)


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


func _test_economy_contract(report: Dictionary) -> void:
	var group: String = "economy"
	var audit: Dictionary = EconomyIntegrityScript.audit(
		CONTENT_CATALOG,
		SHOP_CATALOG,
		TRADE_CATALOG
	)
	_assert(report, bool(audit.get("ok", false)), "economy integrity audit passes", group)
	_assert_equal_int(report, SHOP_CATALOG.get_all_offers().size(), EXPECTED_SHOP_OFFER_COUNT, "shop offer count", group)

	var seen_offer_ids: Dictionary = {}
	for offer in SHOP_CATALOG.get_all_offers():
		var offer_id := str(offer.offer_id)
		_assert(report, offer.is_valid_definition(), "%s valid shop offer" % offer_id, group)
		_assert(report, not seen_offer_ids.has(offer_id), "unique shop offer %s" % offer_id, group)
		seen_offer_ids[offer_id] = true
		_assert(report, offer.price_zenny >= 0, "%s non-negative price" % offer_id, group)

	var spoon_offer: ShopOfferScript = SHOP_CATALOG.get_offer_by_id(&"faerie_spoon")
	_assert(report, spoon_offer != null, "Faerie Spoon offer exists", group)
	if spoon_offer != null:
		_assert_equal_int(report, spoon_offer.price_zenny, 120, "Spoon BOF4 price", group)
		_assert_equal_string(report, str(spoon_offer.availability_tag), "faerie_lazy_shop", "Spoon availability tag", group)

	var king_frog_offer: ShopOfferScript = SHOP_CATALOG.get_offer_by_id(&"clear_king_frog")
	_assert(report, king_frog_offer != null, "clear-game King Frog offer exists", group)
	if king_frog_offer != null:
		_assert_equal_int(report, king_frog_offer.price_zenny, 800, "King Frog BOF4 price", group)
		_assert_equal_string(report, str(king_frog_offer.availability_tag), "clear_game", "King Frog clear-game gate", group)

	for fish in CONTENT_CATALOG.fish:
		if fish == null:
			continue
		_assert(report, fish.get_sell_value_zenny() > 0, "%s has sell value" % fish.fish_name, group)
		_assert(report, not fish.get_legacy_item_effect().strip_edges().is_empty(), "%s preserves BOF4 item effect" % fish.fish_name, group)

	var sweetfish := CONTENT_CATALOG.get_fish_by_id(&"sweetfish")
	_assert(report, sweetfish != null, "Sweetfish economy data exists", group)
	if sweetfish != null:
		_assert_equal_int(report, sweetfish.get_sell_value_zenny(), 20, "Sweetfish worth", group)

	var whale := CONTENT_CATALOG.get_fish_by_id(&"whale")
	_assert(report, whale != null, "Whale economy data exists", group)
	if whale != null:
		_assert_equal_int(report, whale.get_sell_value_zenny(), 2000, "Whale worth", group)

	# Manillo trade value is dynamic in BOF4: the current record score for each
	# required species is multiplied by the number of those fish spent.
	var progress := FishingProgress.new()
	var service = TradeServiceScript.new()
	service.progress = progress
	var tail_recipe := TRADE_CATALOG.get_recipe_by_id(&"wyndia_tail")
	_assert(report, tail_recipe != null, "Wyndia Tail recipe exists", group)
	if tail_recipe != null:
		progress.record_catch_snapshot({
			"species_id": "flying_fish",
			"fish_name": "Flying Fish",
			"size": 20.0,
			"points": 123,
			"max_points": 150,
			"is_king": false,
		}, false, false)
		_assert_equal_int(report, service.get_current_trade_value_units(tail_recipe), 369, "Manillo uses current record score", group)
		progress.record_catch_snapshot({
			"species_id": "flying_fish",
			"fish_name": "Flying Fish",
			"size": 30.0,
			"points": 150,
			"max_points": 150,
			"is_king": true,
		}, false, false)
		_assert_equal_int(report, service.get_current_trade_value_units(tail_recipe), 450, "Manillo value rises with improved record", group)


func _test_player_economy_access_and_save_integrity(report: Dictionary) -> void:
	var group: String = "economy_access_save_integrity"

	var inventory = FishingInventory.new()
	inventory.grant_lure(&"straight", 1, false)
	inventory.grant_rod(&"wooden_rod", 1, false)
	inventory.zenny_balance = 500
	inventory.add_fish_specimen(
		"sweetfish",
		"Sweetfish",
		20.0,
		120,
		false,
		false
	)

	var progress = FishingProgress.new()
	progress.configure_progression_catalog(PROGRESSION_CATALOG)
	progress.record_catch_snapshot({
		"species_id": "sweetfish",
		"fish_name": "Sweetfish",
		"size": 20.0,
		"points": 120,
		"max_points": 150,
		"is_king": false,
	}, false, false)

	var trade_service = TradeServiceScript.new()
	trade_service.configure(
		inventory,
		CONTENT_CATALOG.tackle,
		TRADE_CATALOG,
		null,
		progress
	)

	var economy_service = EconomyServiceScript.new()
	economy_service.configure(
		inventory,
		CONTENT_CATALOG,
		CONTENT_CATALOG.tackle,
		SHOP_CATALOG,
		trade_service
	)

	var modifiers = SessionModifierServiceScript.new()
	modifiers.configure(FISH_EFFECT_CATALOG, false)
	var consumables = FishConsumableServiceScript.new()
	consumables.configure(inventory, FISH_EFFECT_CATALOG, modifiers)

	var access = EconomyAccessScript.new()
	access.configure(
		inventory,
		economy_service,
		trade_service,
		consumables,
		modifiers,
		CONTENT_CATALOG,
		SHOP_CATALOG,
		TRADE_CATALOG
	)
	access.enable_vertical_slice_full_access()

	var sell_entries: Array[Dictionary] = access.get_sell_entries()
	_assert(report, not sell_entries.is_empty(), "owned fish appear in Sell access", group)
	if not sell_entries.is_empty():
		_assert_equal_string(report, str(sell_entries[0].get("id", "")), "sweetfish", "Sell entry species", group)
		_assert_equal_int(report, int(sell_entries[0].get("unit_value_zenny", 0)), 20, "Sell entry BOF4 value", group)

	var buy_entries: Array[Dictionary] = access.get_buy_entries()
	_assert_equal_int(report, buy_entries.size(), EXPECTED_SHOP_OFFER_COUNT, "full-access Buy exposes authored offers", group)

	var trade_entries: Array[Dictionary] = access.get_trade_entries()
	_assert_equal_int(report, trade_entries.size(), EXPECTED_TRADE_COUNT, "full-access Trade exposes authored recipes", group)

	var use_entries: Array[Dictionary] = access.get_use_entries()
	_assert(report, not use_entries.is_empty(), "owned fish with effects appear in Use access", group)

	# Corrupt only derived state and specimen ids; the integrity service must
	# repair both without writing test data to disk.
	progress.fishing_points = 999
	var second_specimen = inventory.add_fish_specimen(
		"sweetfish",
		"Sweetfish",
		17.0,
		102,
		false,
		false
	)
	if second_specimen != null:
		var raw_specimens: Array = inventory.fish_specimens.get("sweetfish", [])
		if raw_specimens.size() >= 2:
			var first = raw_specimens[0] as FishingFishSpecimen
			var second = raw_specimens[1] as FishingFishSpecimen
			if first != null and second != null:
				second.specimen_id = first.specimen_id

	var integrity = SaveIntegrityServiceScript.new()
	integrity.configure(
		progress,
		inventory,
		null,
		null,
		null,
		modifiers,
		CONTENT_CATALOG,
		CONTENT_CATALOG.tackle,
		false
	)
	var integrity_report: Dictionary = integrity.get_last_report()
	_assert(report, bool(integrity_report.get("ok", false)), "save integrity audit repairs recoverable state", group)
	_assert_equal_int(report, progress.get_fishing_points(), 120, "derived fishing points repaired from records", group)

	var ids: Dictionary = {}
	var duplicate_ids: int = 0
	for specimen_value in inventory.fish_specimens.get("sweetfish", []):
		var specimen = specimen_value as FishingFishSpecimen
		if specimen == null:
			continue
		if ids.has(specimen.specimen_id):
			duplicate_ids += 1
		ids[specimen.specimen_id] = true
	_assert_equal_int(report, duplicate_ids, 0, "duplicate specimen ids repaired", group)


func _test_fish_consumable_effects(report: Dictionary) -> void:
	var group: String = "fish_consumable_effects"

	_assert(report, FISH_EFFECT_CATALOG.is_valid_catalog(), "effect catalog valid", group)
	_assert_equal_int(
		report,
		FISH_EFFECT_CATALOG.get_species_ids().size(),
		EXPECTED_FISH_EFFECT_COUNT,
		"all fish have effect mappings",
		group
	)

	var integrity: Dictionary = FishEffectIntegrityScript.audit(
		CONTENT_CATALOG,
		FISH_EFFECT_CATALOG
	)
	_assert(report, bool(integrity.get("valid", false)), "effect integrity audit passes", group)
	_assert_equal_int(
		report,
		int(integrity.get("fish_count", 0)),
		EXPECTED_FISH_COUNT,
		"effect audit sees all fish",
		group
	)

	for fish in CONTENT_CATALOG.fish:
		if fish == null:
			continue
		var effect = FISH_EFFECT_CATALOG.get_effect_for_species(
			fish.get_stable_species_id()
		)
		_assert(report, effect != null, "%s has mapped fishing effect" % fish.fish_name, group)
		if effect != null:
			_assert(report, effect.is_valid_definition(), "%s effect valid" % fish.fish_name, group)

	var modifiers = SessionModifierServiceScript.new()
	modifiers.configure(FISH_EFFECT_CATALOG, false)

	var focus = FISH_EFFECT_CATALOG.get_effect_by_id(&"focus_ii")
	var guard = FISH_EFFECT_CATALOG.get_effect_by_id(&"line_guard")
	var frenzy = FISH_EFFECT_CATALOG.get_effect_by_id(&"toxic_frenzy")
	var cleanse = FISH_EFFECT_CATALOG.get_effect_by_id(&"cleanse_all")
	var dispel = FISH_EFFECT_CATALOG.get_effect_by_id(&"dispel_positive")
	_assert(report, focus != null and guard != null and frenzy != null and cleanse != null and dispel != null, "core effects load", group)

	if focus != null and guard != null:
		modifiers.apply_modifier(focus, &"qa", "focus")
		modifiers.apply_modifier(guard, &"qa", "guard")
		var combined: Dictionary = modifiers.get_composite_snapshot()
		_assert(report, float(combined.get("bite_attraction_multiplier", 1.0)) > 1.0, "focus raises bite activity", group)
		_assert(report, float(combined.get("quality_bonus_roll_chance", 0.0)) > 0.0, "focus raises specimen quality odds", group)
		_assert(report, float(combined.get("line_tolerance_multiplier", 1.0)) > 1.0, "guard raises line tolerance", group)
		_assert_equal_int(report, int(combined.get("active_count", 0)), 2, "different effect groups stack", group)

	# Same-group effects replace rather than multiply forever.
	var steady = FISH_EFFECT_CATALOG.get_effect_by_id(&"steady_hands_i")
	if guard != null and steady != null:
		modifiers.apply_modifier(steady, &"qa", "steady")
		var active_after_replace := modifiers.get_active_effects()
		var safety_count := 0
		for effect_snapshot in active_after_replace:
			if str(effect_snapshot.get("stacking_group", "")) == "safety":
				safety_count += 1
		_assert_equal_int(report, safety_count, 1, "one active effect per stacking group", group)

	# Harmful/mixed effects can be cleaned without touching unrelated positive groups.
	if frenzy != null and cleanse != null:
		modifiers.apply_modifier(frenzy, &"qa", "frenzy")
		_assert(report, float(modifiers.get_composite_snapshot().get("fish_pressure_multiplier", 1.0)) > 1.0, "frenzy increases pressure", group)
		modifiers.apply_modifier(cleanse, &"qa", "cleanse")
		_assert(report, float(modifiers.get_composite_snapshot().get("fish_pressure_multiplier", 1.0)) <= 1.0001, "cleanse removes harmful pressure modifier", group)

	# BOF4-style dispel is intentionally still a downside: it clears positive buffs.
	if focus != null and dispel != null:
		modifiers.clear_all()
		modifiers.apply_modifier(focus, &"qa", "focus")
		_assert(report, int(modifiers.get_composite_snapshot().get("active_count", 0)) > 0, "positive modifier active before dispel", group)
		modifiers.apply_modifier(dispel, &"qa", "dispel")
		_assert_equal_int(report, int(modifiers.get_composite_snapshot().get("active_count", 0)), 0, "dispel clears positive modifiers", group)

	# Timed effects expire deterministically.
	if focus != null:
		modifiers.apply_modifier(focus, &"qa", "focus")
		modifiers.advance(float(focus.duration_seconds) + 0.01)
		_assert_equal_int(report, int(modifiers.get_composite_snapshot().get("active_count", 0)), 0, "timed modifier expires", group)

	# Specimen-quality buffs add natural rolls rather than fabricating a record.
	var sample_fish = CONTENT_CATALOG.fish[0] if not CONTENT_CATALOG.fish.is_empty() else null
	if sample_fish != null:
		var saw_session_bonus := false
		for seed in range(1, 96):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed
			var generated: Dictionary = SpecimenGenerator.roll_with_rng(
				sample_fish,
				rng,
				-1,
				{
					"session_quality_active": true,
					"session_quality_bonus_chance": 0.50,
					"session_quality_bonus_rolls": 2,
				}
			)
			if int(generated.get("session_quality_bonus_rolls_used", 0)) <= 0:
				continue
			saw_session_bonus = true
			var candidate_sizes = generated.get("candidate_sizes", [])
			var largest_candidate := 0.0
			for candidate_size in candidate_sizes:
				largest_candidate = maxf(largest_candidate, float(candidate_size))
			_assert_float_close(report, float(generated.get("size", 0.0)), largest_candidate, 0.001, "quality bonus keeps largest natural candidate", group)
			break
		_assert(report, saw_session_bonus, "quality bonus can produce an extra roll", group)

	# Fight modifiers are composed without rewriting immutable fish stats.
	if sample_fish != null:
		var instance = FishInstanceScript.new()
		instance.setup(sample_fish, 0, sample_fish.average_size, {})
		var base_context: Dictionary = FightResolver.resolve_context(instance, null, null)
		var buffed_context: Dictionary = FightResolver.resolve_context(
			instance,
			null,
			null,
			{
				"stamina_drain_multiplier": 1.20,
				"hook_off_delay_multiplier": 1.10,
				"line_tolerance_multiplier": 1.10,
				"counter_steer_multiplier": 1.05,
				"fish_pressure_multiplier": 0.90,
			}
		)
		_assert_float_close(report, float(buffed_context.get("max_stamina", 0.0)), float(base_context.get("max_stamina", 0.0)), 0.001, "session buff does not rewrite fish stamina", group)
		_assert(report, float(buffed_context.get("stamina_drain_multiplier", 1.0)) > float(base_context.get("stamina_drain_multiplier", 1.0)), "session buff changes player exhaustion efficiency", group)
		_assert(report, float(buffed_context.get("session_fish_pressure_multiplier", 1.0)) < 1.0, "session pressure modifier is explicit", group)

	modifiers.free()


func _test_fight_stat_resolution(report: Dictionary) -> void:
	var group: String = "fight_stats"
	var archetypes: Dictionary = {}
	var dominant_actions: Dictionary = {}
	var personality_labels: Dictionary = {}
	var difficulty_tiers: Dictionary = {}
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
		personality_labels[profile.get_personality_label()] = true
		difficulty_tiers[profile.difficulty_tier] = true
		personality_signatures[profile.get_personality_signature()] = true
		_assert(
			report,
			profile.difficulty_tier >= 1 and profile.difficulty_tier <= 5,
			"%s difficulty tier in range" % fish_name,
			group
		)

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
				_assert_equal_int(
					report,
					int(context.get("difficulty_tier", 0)),
					profile.difficulty_tier,
					"%s context preserves difficulty tier" % fish_name,
					group
				)
				_assert_equal_string(
					report,
					str(context.get("personality", "")),
					profile.get_personality_label(),
					"%s context preserves personality" % fish_name,
					group
				)

		# Lures may alter bounded tackle traits after the hook, but they must never
		# rewrite the fish's authored strength/stamina/personality. All changes pass
		# through FightResolver rather than Encounter-side lure special cases.
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
				_assert(
					report,
					absf(
						float(lure_context.get("max_stamina", 0.0))
						- float(base_context.get("max_stamina", 0.0))
					) <= 0.001,
					"%s lure %s keeps fish stamina authoritative" % [fish_name, lure.display_name],
					group
				)
				_assert(report, float(lure_context.get("stamina_drain_multiplier", 0.0)) > 0.0, "%s lure %s resolved fatigue" % [fish_name, lure.display_name], group)
				_assert(report, float(lure_context.get("hook_off_delay_multiplier", 0.0)) > 0.0, "%s lure %s resolved hook security" % [fish_name, lure.display_name], group)

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
	_assert_equal_int(
		report,
		personality_labels.size(),
		EXPECTED_FISH_COUNT,
		"every species has a distinct design personality label",
		group
	)
	_assert_equal_int(
		report,
		difficulty_tiers.size(),
		5,
		"all five design difficulty tiers represented",
		group
	)
	_assert(
		report,
		personality_signatures.size() >= 20,
		"species behavior data has broad personality variety",
		group
	)



func _test_tackle_differentiation(report: Dictionary) -> void:
	var group: String = "tackle_differentiation"
	if CONTENT_CATALOG.tackle == null or CONTENT_CATALOG.tackle.lure_catalog == null:
		_assert(report, false, "tackle data available", group)
		return

	var rods = CONTENT_CATALOG.tackle.rods
	var lures: Array[BaitData] = CONTENT_CATALOG.tackle.lure_catalog.lures
	var rod_pairs: Dictionary = {}
	var lure_pairs: Dictionary = {}
	var rod_roles: Dictionary = {}
	var lure_roles: Dictionary = {}

	for rod in rods:
		if rod == null:
			continue
		rod_roles[rod.fight_role_label] = true
		rod_pairs["%.2f/%.2f" % [rod.fight_fatigue_multiplier, rod.hook_security_multiplier]] = true

	for lure in lures:
		if lure == null:
			continue
		lure_roles[lure.fight_role_label] = true
		lure_pairs["%.2f/%.2f" % [lure.fight_fatigue_multiplier, lure.hook_security_multiplier]] = true

	_assert(report, rod_roles.size() >= 5, "rods expose multiple design roles", group)
	_assert(report, rod_pairs.size() >= 5, "rods have meaningful fight-stat variety", group)
	_assert(report, lure_roles.size() >= 12, "lures expose broad design roles", group)
	_assert(report, lure_pairs.size() >= 10, "lures have meaningful fight-stat variety", group)

	# Use one ordinary fish as a deterministic matrix probe. Tackle may change
	# exhaustion efficiency and failure grace, but never fish-authored stats.
	var probe_data = CONTENT_CATALOG.fish[0] if not CONTENT_CATALOG.fish.is_empty() else null
	_assert(report, probe_data != null, "matrix probe fish exists", group)
	if probe_data == null:
		return
	var probe := FishInstance.new()
	probe.setup(probe_data, -1, probe_data.average_size)

	for rod in rods:
		if rod == null:
			continue
		for lure in lures:
			if lure == null:
				continue
			var context: Dictionary = FightResolver.resolve_context(probe, rod, lure)
			_assert(report, FightResolver.is_valid_context(context), "%s/%s context valid" % [rod.rod_id, lure.lure_id], group)
			_assert(report, absf(float(context.get("strength", 0.0)) - probe.strength) <= 0.001, "%s/%s preserves fish strength" % [rod.rod_id, lure.lure_id], group)
			_assert(report, absf(float(context.get("max_stamina", 0.0)) - probe.max_stamina) <= 0.001, "%s/%s preserves fish stamina" % [rod.rod_id, lure.lure_id], group)
			var drain_mult := float(context.get("stamina_drain_multiplier", 0.0))
			var hook_mult := float(context.get("hook_off_delay_multiplier", 0.0))
			_assert(report, drain_mult >= 0.50 and drain_mult <= 1.65, "%s/%s bounded fatigue" % [rod.rod_id, lure.lure_id], group)
			_assert(report, hook_mult >= 0.50 and hook_mult <= 1.65, "%s/%s bounded hook security" % [rod.rod_id, lure.lure_id], group)
			var effective_hook := TENSION_PROFILE.hook_off_delay * hook_mult
			_assert(report, effective_hook + 0.0001 >= DIFFICULTY_POLICY.minimum_hook_off_grace_seconds, "%s/%s preserves readable hook-off grace" % [rod.rod_id, lure.lure_id], group)

	# Explicitly verify the intended tradeoff: high-action surface/spinner lures
	# can exhaust faster while secure worm/frog styles retain longer slack grace.
	var straight = null
	var popper = null
	for lure in lures:
		if lure == null:
			continue
		if lure.lure_id == &"straight":
			straight = lure
		elif lure.lure_id == &"popper":
			popper = lure
	if straight != null and popper != null:
		_assert(report, straight.hook_security_multiplier > popper.hook_security_multiplier, "worm is more hook-secure than popper", group)
		_assert(report, popper.fight_fatigue_multiplier > straight.fight_fatigue_multiplier, "popper exhausts faster than baseline worm", group)


func _test_difficulty_accessibility_curve(report: Dictionary) -> void:
	var group: String = "difficulty_accessibility"
	_assert(report, DIFFICULTY_POLICY != null, "difficulty policy exists", group)
	if DIFFICULTY_POLICY == null:
		return
	_assert(report, DIFFICULTY_POLICY.is_valid_policy(), "difficulty policy valid", group)

	var wooden_rod = null
	var deluxe_rod = null
	var spanner_rod = null
	var masters_rod = null
	var starter_lure = null
	var neutral_lure = null
	if CONTENT_CATALOG.tackle != null:
		wooden_rod = CONTENT_CATALOG.tackle.get_rod_by_id(&"wooden_rod")
		deluxe_rod = CONTENT_CATALOG.tackle.get_rod_by_id(&"deluxe_rod")
		spanner_rod = CONTENT_CATALOG.tackle.get_rod_by_id(&"spanner")
		masters_rod = CONTENT_CATALOG.tackle.get_rod_by_id(&"masters_rod")
		if CONTENT_CATALOG.tackle.lure_catalog != null:
			for candidate_lure in CONTENT_CATALOG.tackle.lure_catalog.lures:
				if candidate_lure == null:
					continue
				if candidate_lure.lure_id == &"straight":
					starter_lure = candidate_lure
				elif candidate_lure.lure_id == &"spoon":
					neutral_lure = candidate_lure
	_assert(report, wooden_rod != null, "Wooden Rod exists for starter audit", group)
	_assert(report, deluxe_rod != null, "Deluxe Rod exists for tier-2 audit", group)
	_assert(report, spanner_rod != null, "Spanner exists for tier-3 audit", group)
	_assert(report, masters_rod != null, "Master's Rod exists for endgame audit", group)
	_assert(report, starter_lure != null, "Straight exists for starter audit", group)
	_assert(report, neutral_lure != null, "Spoon exists for endgame neutral audit", group)

	var tier_duration_totals: Dictionary = {}
	var tier_counts: Dictionary = {}

	for fish_data in CONTENT_CATALOG.fish:
		if fish_data == null or fish_data.behavior_profile == null:
			continue

		var fish_name: String = fish_data.fish_name
		var tier := clampi(int(fish_data.behavior_profile.difficulty_tier), 1, 5)
		var average := FishInstance.new()
		average.setup(fish_data, -1, fish_data.average_size)
		var king_max_size := fish_data.king_size * fish_data.king_max_size_multiplier
		var king := FishInstance.new()
		king.setup(fish_data, 1, king_max_size)

		var reference_rod = wooden_rod
		var reference_lure = starter_lure
		if tier == 3:
			reference_rod = deluxe_rod
			reference_lure = neutral_lure
		elif tier == 4:
			reference_rod = spanner_rod
			reference_lure = neutral_lure
		elif tier >= 5:
			reference_rod = masters_rod
			reference_lure = neutral_lure

		var average_audit: Dictionary = FightAccessibility.audit_specimen(
			fish_data,
			average.get_fight_stats(),
			reference_rod,
			TENSION_PROFILE,
			false,
			-1.0,
			-1.0,
			reference_lure
		)
		var king_audit: Dictionary = FightAccessibility.audit_specimen(
			fish_data,
			king.get_fight_stats(),
			masters_rod,
			TENSION_PROFILE,
			true,
			-1.0,
			-1.0,
			neutral_lure
		)

		_assert(report, bool(average_audit.get("valid", false)), "%s average audit valid" % fish_name, group)
		_assert(report, bool(king_audit.get("valid", false)), "%s king audit valid" % fish_name, group)
		_assert(report, bool(average_audit.get("bite_accessible", false)), "%s hook window respects tier floor" % fish_name, group)
		_assert(report, bool(average_audit.get("duration_accessible", false)), "%s average endurance fits tier budget" % fish_name, group)
		_assert(report, bool(king_audit.get("duration_accessible", false)), "%s max king endurance fits tier budget" % fish_name, group)
		_assert(report, bool(average_audit.get("line_failure_readable", false)), "%s starter line-break grace readable" % fish_name, group)
		_assert(report, bool(average_audit.get("hook_failure_readable", false)), "%s slack failure has grace" % fish_name, group)
		_assert(report, bool(king_audit.get("rod_meets_recommendation", false)), "%s Master's Rod meets recommendation" % fish_name, group)

		if DIFFICULTY_POLICY.starter_rod_should_support(tier):
			_assert(report, bool(average_audit.get("rod_meets_recommendation", false)), "%s starter rod supports early tier" % fish_name, group)

		var total := float(tier_duration_totals.get(tier, 0.0))
		tier_duration_totals[tier] = total + float(average_audit.get("active_reel_seconds", 0.0))
		tier_counts[tier] = int(tier_counts.get(tier, 0)) + 1

	# The broad curve must rise from beginner to endgame. Individual personalities
	# may overlap; forcing every single fish to be harder than the previous tier
	# would destroy variety, so compare tier averages instead.
	var previous_average := -1.0
	for tier in range(1, 6):
		var count := maxi(int(tier_counts.get(tier, 0)), 1)
		var tier_average := float(tier_duration_totals.get(tier, 0.0)) / float(count)
		_assert(report, tier_average > previous_average, "tier %d average endurance rises" % tier, group)
		previous_average = tier_average

	if CONTENT_CATALOG.tackle != null:
		for rod in CONTENT_CATALOG.tackle.rods:
			if rod == null:
				continue
			var grace := TENSION_PROFILE.line_break_delay * rod.line_tolerance_multiplier
			_assert(
				report,
				grace + 0.0001 >= DIFFICULTY_POLICY.minimum_line_break_grace_seconds,
				"%s preserves minimum line-break grace" % rod.rod_name,
				group
			)

	_assert(
		report,
		TENSION_PROFILE.hook_off_delay + 0.0001 >= DIFFICULTY_POLICY.minimum_hook_off_grace_seconds,
		"default hook-off has sustained slack grace",
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
			if CONTENT_CATALOG.tackle.lure_catalog != null:
				for lure in CONTENT_CATALOG.tackle.lure_catalog.lures:
					if lure == null:
						continue
					var hook_delay := TENSION_PROFILE.hook_off_delay * rod.hook_security_multiplier * lure.hook_security_multiplier
					_assert(report, hook_delay + 0.0001 >= DIFFICULTY_POLICY.minimum_hook_off_grace_seconds, "%s/%s hook-off grace" % [rod.rod_id, lure.lure_id], group)


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


func _test_environment_conditions(report: Dictionary) -> void:
	var group: String = "environment"
	var integrity: Dictionary = EnvironmentIntegrityScript.audit(
		ENVIRONMENT_CATALOG,
		CONTENT_CATALOG
	)
	_assert(report, bool(integrity.get("valid", false)), "environment catalog integrity", group)
	_assert_equal_int(
		report,
		int(integrity.get("condition_count", 0)),
		EXPECTED_ENVIRONMENT_CONDITION_COUNT,
		"environment condition count",
		group
	)

	var service = EnvironmentServiceScript.new()
	service.configure(ENVIRONMENT_CATALOG)
	var defaults: PackedStringArray = service.get_active_condition_ids()
	_assert(report, defaults.has("calm"), "calm is the default weather", group)

	var ocean_two: FishingSpotData = null
	for spot in CONTENT_CATALOG.spots:
		if spot != null and str(spot.spot_id) == "ocean_2":
			ocean_two = spot
			break
	_assert(report, ocean_two != null, "Ocean 2 exists for environment QA", group)
	if ocean_two == null:
		service.free()
		return

	service.set_spot(ocean_two)
	var calm_context: Dictionary = service.get_selection_context(ocean_two.get_fish_population())
	_assert_float_close(
		report,
		service.get_bite_activity_multiplier(5.0, 10.0),
		1.0,
		0.0001,
		"calm bite activity is neutral",
		group
	)

	_assert(report, service.activate_condition(&"tempest"), "tempest activates", group)
	var tempest_ids: PackedStringArray = service.get_active_condition_ids()
	_assert(report, tempest_ids.has("tempest"), "tempest is active", group)
	_assert(report, not tempest_ids.has("calm"), "tempest replaces calm in weather group", group)
	_assert(report, service.get_bite_activity_multiplier(5.0, 10.0) > 1.0, "tempest raises bite activity", group)

	var tempest_context: Dictionary = service.get_selection_context(ocean_two.get_fish_population())
	var calm_weights: Dictionary = calm_context.get("species_multipliers", {}) as Dictionary
	var tempest_weights: Dictionary = tempest_context.get("species_multipliers", {}) as Dictionary
	var sea_bass_weight: float = float(tempest_weights.get("sea_bass", 1.0))
	var whale_weight: float = float(tempest_weights.get("whale", 1.0))
	_assert(report, whale_weight > sea_bass_weight, "tempest biases higher-tier species", group)
	_assert(report, float(calm_weights.get("whale", 1.0)) == 1.0, "calm species weighting is neutral", group)

	var generation_context: Dictionary = service.get_specimen_generation_context()
	_assert(report, bool(generation_context.get("environment_quality_active", false)), "tempest enables quality rolls", group)
	_assert(report, float(generation_context.get("environment_quality_bonus_chance", 0.0)) > 0.0, "tempest quality chance is positive", group)

	var fight_modifiers: Dictionary = service.get_fight_modifiers()
	_assert(report, float(fight_modifiers.get("fish_pressure_multiplier", 1.0)) > 1.0, "tempest raises fight pressure", group)
	_assert(report, float(fight_modifiers.get("line_tolerance_multiplier", 1.0)) < 1.0, "tempest reduces line forgiveness", group)

	_assert(report, service.activate_condition(&"night"), "night activates independently", group)
	var composed_ids: PackedStringArray = service.get_active_condition_ids()
	_assert(report, composed_ids.has("tempest") and composed_ids.has("night"), "weather and time conditions compose", group)

	var test_entry: FishSpawnEntry = FishSpawnEntry.new()
	test_entry.fish = CONTENT_CATALOG.get_fish_by_id(&"sea_bass")
	test_entry.weight = 1.0
	test_entry.required_environment_conditions = PackedStringArray(["tempest"])
	_assert(report, test_entry.get_base_bite_weight(tempest_context) > 0.0, "required tempest entry is available in tempest", group)
	service.reset_to_defaults()
	var reset_context: Dictionary = service.get_selection_context([test_entry])
	_assert_float_close(report, test_entry.get_base_bite_weight(reset_context), 0.0, 0.0001, "required tempest entry is hidden in calm", group)

	service.free()


func _packed_int_arrays_equal(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if a[index] != b[index]:
			return false
	return true


func _assert_float_close(
	report: Dictionary,
	actual: float,
	expected: float,
	tolerance: float,
	label: String,
	group: String
) -> void:
	_assert(
		report,
		absf(actual - expected) <= maxf(tolerance, 0.0),
		"%s (expected %.4f, got %.4f)" % [label, expected, actual],
		group
	)


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
