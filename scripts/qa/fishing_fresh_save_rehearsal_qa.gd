extends RefCounted
class_name FishingFreshSaveRehearsalQA

## Deterministic, save-safe rehearsal of the current playable progression spine.
##
## This QA deliberately does NOT reset, write, or mutate the player's real save.
## It uses live authored catalogs/policies plus isolated in-memory inventory nodes
## to prove that a canonical fresh start can reach the current campaign end,
## mastery capstone, and Gyosil reward layer in the intended order.

const DirectorScript = preload(
	"res://scripts/progression/playable_campaign_progression_director.gd"
)
const FishingInventoryScript = preload(
	"res://scripts/fishing_inventory.gd"
)
const PlayerInventoryScript = preload(
	"res://scripts/items/player_item_inventory.gd"
)
const InventoryFacadeScript = preload(
	"res://scripts/items/game_inventory_facade.gd"
)
const TransactionServiceScript = preload(
	"res://scripts/items/game_item_transaction_service.gd"
)
const CookingServiceScript = preload(
	"res://scripts/economy/fishing_cooking_service.gd"
)
const PreparedBaitServiceScript = preload(
	"res://scripts/economy/fishing_prepared_bait_service.gd"
)
const GyosilPolicy = preload(
	"res://scripts/progression/fishing_master_gyosil_policy.gd"
)
const StarterBundle = preload(
	"res://data/triple_triad/acquisition/bundles/salvaged_card_case.tres"
)

const PLAN_PATH := "res://data/progression/playable_campaign_loop_v1.json"
const WORLD_MAP_PATH := (
	"res://data/triple_triad/acquisition/world_acquisition_map.json"
)
const MAIN_SCENE_PATH := "res://actors/FishingTestScene_V2.tscn"


static func run(session: Node) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
		"save_safe": true,
		"rehearsal_path": PackedStringArray(),
	}
	if session == null:
		_record(report, "Session services exist", false, "Session is null.")
		return report

	var plan: Dictionary = _load_json(PLAN_PATH)
	var world_map: Dictionary = _load_json(WORLD_MAP_PATH)
	var economy_config = null
	if session.has_method("get_economy_config"):
		economy_config = session.call("get_economy_config")

	var live_zenny_before: int = _live_zenny(session)
	var live_mastery_before: Dictionary = _live_mastery_snapshot(session)
	var live_reward_before: Array = _live_reward_statuses(session)

	_test_preconditions(report, session, plan, economy_config)
	_test_fresh_save_contract(report, plan, economy_config)
	_test_starter_case(report)
	_rehearse_campaign_spine(report, plan)
	_rehearse_economy_bridge(report, session, economy_config)
	_rehearse_card_maker(report, session)
	_test_authored_source_reachability(report, world_map)
	_rehearse_mastery_path(report, session)
	_rehearse_gyosil_rewards(report, session)

	_record(
		report,
		"Rehearsal leaves live Zenny untouched",
		_live_zenny(session) == live_zenny_before,
		"The rehearsal must never spend or grant the player's real wallet."
	)
	_record(
		report,
		"Rehearsal leaves live mastery untouched",
		_live_mastery_snapshot(session) == live_mastery_before,
		"The rehearsal must not learn techniques on the player's real save."
	)
	_record(
		report,
		"Rehearsal leaves live reward claims untouched",
		_live_reward_statuses(session) == live_reward_before,
		"The rehearsal must not claim Gyosil or other real rewards."
	)

	report["valid"] = (
		int(report.get("passed_count", 0))
		== int(report.get("test_count", 0))
	)
	return report


static func _test_preconditions(
	report: Dictionary,
	session: Node,
	plan: Dictionary,
	economy_config
) -> void:
	_record(
		report,
		"Fresh-save campaign plan is available",
		not plan.is_empty()
		and str(plan.get("plan_id", "")) == "playable_campaign_loop_v1",
		"The canonical campaign plan must load before rehearsal."
	)
	_record(
		report,
		"Economy configuration is available",
		economy_config != null,
		"Fresh-start wallet and prepared-bait rules require the economy config."
	)
	_record(
		report,
		"Cross-system stability gate is green",
		_report_passed(session.get("system_stability_qa_report")),
		"The fresh-save rehearsal should only run on top of a stable integrated stack."
	)
	_record(
		report,
		"Campaign-loop contract QA is green",
		_report_passed(session.get("campaign_loop_qa_report")),
		"The authored 0-12h plan must already validate."
	)
	_record(
		report,
		"Card Maker QA is green",
		_report_passed(session.get("card_maker_qa_report")),
		"The fish-to-card bridge must be healthy before end-to-end rehearsal."
	)
	_record(
		report,
		"Mastery QA is green",
		_report_passed(session.get("mastery_qa_report")),
		"The technique catalog must be healthy before testing its full path."
	)


static func _test_fresh_save_contract(
	report: Dictionary,
	plan: Dictionary,
	economy_config
) -> void:
	var fresh: Dictionary = {}
	var raw_fresh = plan.get("fresh_save", {})
	if raw_fresh is Dictionary:
		fresh = raw_fresh

	var starting_zenny: int = -1
	if economy_config != null:
		starting_zenny = int(economy_config.new_game_starting_zenny)

	_record(
		report,
		"Fresh save starts at 100z",
		starting_zenny == 100
		and int(fresh.get("starting_zenny", -1)) == 100,
		"The live economy and campaign contract must agree on the starting wallet."
	)
	_record(
		report,
		"Fresh save starts with Wooden Rod",
		str(FishingInventoryScript.STARTER_ROD_ID) == "wooden_rod"
		and str(fresh.get("starter_rod_id", "")) == "wooden_rod"
		and int(fresh.get("starting_rods", 0)) == 1,
		"Starter tackle must remain exactly one Wooden Rod."
	)
	_record(
		report,
		"Fresh save starts with Straight lure",
		str(FishingInventoryScript.STARTER_LURE_ID) == "straight"
		and str(fresh.get("starter_lure_id", "")) == "straight"
		and int(fresh.get("starting_lures", 0)) == 1,
		"Starter tackle must remain exactly one Straight lure."
	)
	_record(
		report,
		"Fresh save starts with zero cards and locked card play",
		int(fresh.get("starting_cards", -1)) == 0
		and not bool(fresh.get("card_game_unlocked", true)),
		"The card game must still be discovered through fishing."
	)


static func _test_starter_case(report: Dictionary) -> void:
	_record(
		report,
		"Saltworn Card Case grants exactly five starter cards",
		StarterBundle != null and StarterBundle.card_ids.size() == 5,
		"The first fishing discovery must still be the canonical five-card start."
	)
	_record(
		report,
		"Saltworn Card Case unlocks Triple Triad",
		StarterBundle != null and bool(StarterBundle.unlocks_card_game),
		"Starter salvage must unlock card play rather than only grant cards."
	)


static func _rehearse_campaign_spine(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var fresh_cards: Dictionary = _cards(false, false, 0)
	var fresh: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(0, 0, 1, 1, fresh_cards)
	)
	_record(
		report,
		"Fresh start points at the first catch",
		str(fresh.get("phase_id", "")) == "fresh_start"
		and str(_next_code(fresh)) == "catch_first_fish",
		"A brand-new player should be sent fishing before any card-system task."
	)
	_append_path(report, "Fresh Start")

	var after_catch: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(1, 1, 1, 1, _cards(false, false, 0))
	)
	_record(
		report,
		"First catch advances to starter-glint search",
		str(after_catch.get("phase_id", "")) == "starter_case_search"
		and str(_next_code(after_catch)) == "discover_starter_glint",
		"Fishing must remain the route into the visible starter-card discovery."
	)
	_append_path(report, "Starter Case Search")

	var after_case: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(1, 1, 1, 1, _cards(true, true, 5))
	)
	_record(
		report,
		"Five-card discovery advances to Learn Loop",
		str(after_case.get("phase_id", "")) == "learn_loop"
		and _has_completed(after_case, "first_fishing_trip"),
		"The first-trip milestone should complete immediately after the case."
	)
	_append_path(report, "Learn Loop")

	var learn_cards: Dictionary = _cards(true, true, 8)
	learn_cards["opponents"] = {
		"beach_trader": {"beaten_before": true},
	}
	var after_trader: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(8, 4, 1, 1, learn_cards)
	)
	_record(
		report,
		"Beach Trader win returns the player to shallow salvage",
		str(after_trader.get("phase_id", "")) == "learn_loop"
		and str(_next_code(after_trader)) == "recover_coast_shallows_salvage",
		"The first-hour loop should alternate card play back into fishing."
	)

	_set_source_count(learn_cards, "fishing_salvage:coast_shallows", 1)
	var learn_complete: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(8, 4, 1, 1, learn_cards)
	)
	_record(
		report,
		"Learn Loop reaches Connected Systems",
		str(learn_complete.get("phase_id", "")) == "connected_systems"
		and _has_completed(learn_complete, "learn_loop"),
		"Trader + shallow salvage evidence should unlock the connected-system phase."
	)
	_append_path(report, "Connected Systems")

	var connected_cards: Dictionary = _cards(true, true, 18)
	connected_cards["opponents"] = {
		"beach_trader": {"beaten_before": true},
	}
	_set_source_count(connected_cards, "fishing_salvage:coast_shallows", 1)
	_set_source_count(connected_cards, "card_maker:*", 1)
	var connected_complete: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(24, 10, 2, 4, connected_cards)
	)
	_record(
		report,
		"A real connected route reaches Specialization",
		str(connected_complete.get("phase_id", "")) == "specialization"
		and _has_completed(connected_complete, "connected_systems"),
		"Card Maker must remain a valid alternative to Harbor one-shot routes."
	)
	_append_path(report, "Specialization")

	var end_cards: Dictionary = _cards(true, true, 35)
	end_cards["duel_rank"] = 2
	end_cards["opponents"] = {
		"beach_trader": {"beaten_before": true},
	}
	_set_source_count(end_cards, "fishing_salvage:coast_shallows", 1)
	_set_source_count(end_cards, "card_maker:*", 1)
	_set_source_count(end_cards, "fishing_salvage:coast_deeper", 1)
	var end_state: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(60, 18, 2, 6, end_cards)
	)
	_record(
		report,
		"Current 0-12h foundation reaches free play",
		str(end_state.get("phase_id", "")) == "campaign_foundation_complete"
		and str(_next_code(end_state)) == "choose_free_play_goal"
		and _has_completed(end_state, "specialization"),
		"The current campaign foundation must have a deterministic reachable end."
	)
	_append_path(report, "Campaign Foundation Complete")


static func _rehearse_economy_bridge(
	report: Dictionary,
	session: Node,
	economy_config
) -> void:
	var item_catalog = session.get("item_catalog")
	if economy_config == null or item_catalog == null:
		_record(report, "Prepared-bait rehearsal backend is available", false, "Missing economy config or item catalog.")
		return

	var fishing = FishingInventoryScript.new()
	var items = PlayerInventoryScript.new()
	var facade = InventoryFacadeScript.new()
	var transaction = TransactionServiceScript.new()
	var cooking = CookingServiceScript.new()
	var prepared = PreparedBaitServiceScript.new()

	fishing.set_zenny(int(economy_config.new_game_starting_zenny), false)
	fishing.add_fish("sea_bass", 2, false)
	facade.configure(item_catalog, items, fishing)
	transaction.configure(item_catalog, items, facade, fishing)
	cooking.configure(economy_config, item_catalog, items, fishing, transaction)
	prepared.configure(economy_config, item_catalog, items, transaction)

	var herb_id = item_catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		economy_config.bait_herb_material_id
	)
	var bait_id = item_catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		economy_config.prepared_bait_item_domain_id
	)
	items.grant(herb_id, 2, false)

	var cooked: Dictionary = cooking.cook_prepared_bait(&"sea_bass", 1, false)
	_record(
		report,
		"Fresh progression can convert fish + herbs into prepared bait",
		bool(cooked.get("success", false))
		and fishing.get_fish_count("sea_bass") == 1
		and items.get_count(herb_id) == 0
		and items.get_count(bait_id) == 3,
		"One common fish + two herbs must still produce exactly three portions."
	)

	var cast_use: Dictionary = prepared.try_begin_cast(false)
	_record(
		report,
		"Prepared bait can be consumed by the next committed cast",
		bool(cast_use.get("used", false))
		and items.get_count(bait_id) == 2
		and float(cast_use.get("bite_attraction_multiplier", 1.0)) > 1.0,
		"The prepared-bait bridge must remain usable after crafting."
	)
	_record(
		report,
		"Prepared bait preserves the authored quality-roll model",
		float(cast_use.get("quality_bonus_roll_chance", 0.0)) > 0.0
		and int(cast_use.get("quality_bonus_rolls", 0)) > 0,
		"Prepared bait should improve expected quality, not directly modify fish price."
	)

	var sale_value: int = int(
		economy_config.get_fish_sell_price(&"sea_bass", 0)
	)
	_record(
		report,
		"A common catch still has positive sell value",
		sale_value > 0,
		"The player must retain a meaningful fish-versus-crafting economy choice."
	)

	prepared.free()
	cooking.free()
	transaction.free()
	facade.free()
	items.free()
	fishing.free()


static func _rehearse_card_maker(
	report: Dictionary,
	session: Node
) -> void:
	var service = session.get("card_maker_service")
	if service == null:
		_record(report, "Card Maker rehearsal service is available", false, "Card Maker service is null.")
		return
	var catalog = service.get("recipe_catalog")
	if catalog == null or not catalog.has_method("get_recipe"):
		_record(report, "Card Maker recipe catalog is available", false, "Recipe catalog is unavailable.")
		return
	var recipe = catalog.call("get_recipe", &"bass_card")
	if recipe == null:
		var recipes = catalog.call("get_all_recipes")
		if recipes is Array and not recipes.is_empty():
			recipe = recipes[0]
	_record(
		report,
		"A starter-era Card Maker recipe is reachable",
		recipe != null,
		"At least one fish-to-card recipe must survive the fresh-save path."
	)
	if recipe == null:
		return

	var first_quote: Dictionary = service.call(
		"build_quote_from_state",
		recipe,
		1,
		140,
		0,
		1
	)
	_record(
		report,
		"First Card Maker conversion remains 1 fish + 75z",
		bool(first_quote.get("can_make", false))
		and int(first_quote.get("fish_required", -1)) == 1
		and int(first_quote.get("zenny_required", -1)) == 75,
		"The first print must preserve the fish/economy decision."
	)

	var duplicate_quote: Dictionary = service.call(
		"build_quote_from_state",
		recipe,
		0,
		150,
		1,
		1
	)
	_record(
		report,
		"Duplicate Card Maker conversion remains 0 fish + 150z",
		bool(duplicate_quote.get("can_make", false))
		and int(duplicate_quote.get("fish_required", -1)) == 0
		and int(duplicate_quote.get("zenny_required", -1)) == 150,
		"Duplicates should remain a money sink, not another specimen sink."
	)


static func _test_authored_source_reachability(
	report: Dictionary,
	world_map: Dictionary
) -> void:
	var required := [
		["opponent_win", "beach_trader"],
		["fishing_salvage", "coast_shallows"],
		["card_maker", "bass_card"],
		["fishing_salvage", "coast_deeper"],
	]
	for pair in required:
		var source_type: String = str(pair[0])
		var source_id: String = str(pair[1])
		_record(
			report,
			"Authored source remains reachable: %s:%s" % [source_type, source_id],
			_world_source_exists(world_map, source_type, source_id),
			"The campaign must not point at a deleted or unmapped acquisition route."
		)

	_record(
		report,
		"Harbor Request world interaction still exists",
		ResourceLoader.exists("res://actors/HarborRequestBoard.tscn"),
		"The connected-system alternate route must remain physically authored."
	)
	_record(
		report,
		"Harbor Lockbox world interaction still exists",
		ResourceLoader.exists("res://actors/HarborLockbox.tscn"),
		"The connected-system alternate route must remain physically authored."
	)
	_record(
		report,
		"Regional Championship world interaction still exists",
		ResourceLoader.exists("res://actors/RegionalChampionshipRegistrar.tscn"),
		"Tournament progression must remain accessible from the world slice."
	)


static func _rehearse_mastery_path(
	report: Dictionary,
	session: Node
) -> void:
	var mastery_service = session.get("mastery_service")
	if mastery_service == null or not mastery_service.has_method("get_catalog"):
		_record(report, "Mastery rehearsal catalog is available", false, "Mastery service/catalog is unavailable.")
		return
	var catalog = mastery_service.call("get_catalog")
	if catalog == null or not catalog.has_method("get_technique"):
		_record(report, "Mastery rehearsal catalog is available", false, "Mastery catalog is unavailable.")
		return

	var learned: Dictionary = {}
	var teacher_scenes: Dictionary = _teacher_scene_paths()
	for technique_id in _mastery_order():
		var technique = catalog.call("get_technique", StringName(technique_id))
		var valid: bool = technique != null
		var detail: String = ""
		if not valid:
			detail = "Technique is missing from the live catalog."
		else:
			for raw_prerequisite in technique.prerequisite_ids:
				var prerequisite: String = str(raw_prerequisite)
				if not learned.has(prerequisite):
					valid = false
					detail = "Prerequisite %s is not reachable earlier in the rehearsal." % prerequisite
					break
			if valid:
				var teacher_id: String = str(technique.teacher_id)
				var scene_path: String = str(teacher_scenes.get(teacher_id, ""))
				if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
					valid = false
					detail = "Teacher %s has no reachable authored NPC scene." % teacher_id
				elif not _main_scene_contains(scene_path):
					valid = false
					detail = "Teacher scene exists but is not placed in FishingTestScene_V2."
		_record(
			report,
			"Mastery path is reachable: %s" % technique_id,
			valid,
			detail if not detail.is_empty() else "The teacher/prerequisite chain must remain reachable."
		)
		if valid:
			learned[technique_id] = true

	_record(
		report,
		"One With Nature capstone is reachable from a blank mastery state",
		learned.has("one_with_nature"),
		"The current master chain must terminate in the authored fieldcraft capstone."
	)
	_append_path(report, "One With Nature")


static func _rehearse_gyosil_rewards(
	report: Dictionary,
	session: Node
) -> void:
	var reward_service = session.get("reward_service")
	var reward_catalog = null
	if reward_service != null:
		reward_catalog = reward_service.get("reward_catalog")
	if reward_catalog == null or not reward_catalog.has_method("get_reward_by_key"):
		_record(report, "Gyosil reward catalog is available", false, "Reward catalog is unavailable.")
		return

	var spanner = reward_catalog.call("get_reward_by_key", &"gyosil_spanner_6000")
	var master_rod = reward_catalog.call("get_reward_by_key", &"gyosil_masters_rod_9500")
	_record(
		report,
		"Gyosil Spanner milestone remains reachable at 6000 points",
		spanner != null
		and int(spanner.threshold) == 6000
		and not bool(spanner.auto_claim)
		and str(spanner.reward_item_id) == "spanner",
		"The first long-term point reward must remain a manual Gyosil claim."
	)
	_record(
		report,
		"Gyosil Master's Rod milestone remains reachable at 9500 points",
		master_rod != null
		and int(master_rod.threshold) == 9500
		and not bool(master_rod.auto_claim)
		and str(master_rod.reward_item_id) == "masters_rod",
		"The current high-end point reward must remain a manual Gyosil claim."
	)

	var status_6000: Array[Dictionary] = []
	status_6000.append(_reward_status(GyosilPolicy.SPANNER_KEY, 6000, 6000, true))
	status_6000.append(_reward_status(GyosilPolicy.MASTERS_ROD_KEY, 9500, 6000, false))
	var claimable_6000: PackedStringArray = GyosilPolicy.get_claimable_keys(status_6000)
	_record(
		report,
		"At 6000 points Gyosil exposes Spanner before Master's Rod",
		claimable_6000.size() == 1
		and claimable_6000[0] == GyosilPolicy.SPANNER_KEY,
		"Reward order must remain threshold-driven."
	)

	var status_9500: Array[Dictionary] = []
	status_9500.append(_reward_status(GyosilPolicy.SPANNER_KEY, 6000, 9500, true))
	status_9500.append(_reward_status(GyosilPolicy.MASTERS_ROD_KEY, 9500, 9500, true))
	var claimable_9500: PackedStringArray = GyosilPolicy.get_claimable_keys(status_9500)
	_record(
		report,
		"At 9500 points both unclaimed Gyosil milestones are resolvable in order",
		claimable_9500.size() == 2
		and claimable_9500[0] == GyosilPolicy.SPANNER_KEY
		and claimable_9500[1] == GyosilPolicy.MASTERS_ROD_KEY,
		"A player who visits late must not lose the earlier reward."
	)
	_record(
		report,
		"Master Gyosil is physically present in the current beach slice",
		ResourceLoader.exists("res://actors/FishingMasterGyosilNPC.tscn")
		and _main_scene_contains("res://actors/FishingMasterGyosilNPC.tscn"),
		"The reward endpoint must be reachable in-world, not backend-only."
	)
	_append_path(report, "Gyosil Long-Term Rewards")


static func _state(
	total_catches: int,
	species_discovered: int,
	rods_owned: int,
	lures_owned: int,
	card_state: Dictionary
) -> Dictionary:
	return {
		"zenny": 100,
		"total_catches": total_catches,
		"species_discovered": species_discovered,
		"rods_owned": rods_owned,
		"lures_owned": lures_owned,
		"prepared_bait": {},
		"card_maker_recipe_statuses": [],
		"card_state": card_state,
	}


static func _cards(
	unlocked: bool,
	starter_case_discovered: bool,
	owned_unique: int
) -> Dictionary:
	return {
		"backend_available": true,
		"card_game_unlocked": unlocked,
		"starter_case_discovered": starter_case_discovered,
		"cards_owned_unique": owned_unique,
		"cards_owned_total": owned_unique,
		"duel_rank": 1,
		"duel_points": 0,
		"matches": 0,
		"wins": 0,
		"beaten_opponent_ids": PackedStringArray(),
		"opponents": {},
		"claimed_world_event_ids": PackedStringArray(),
		"pending_world_reward_count": 0,
		"active_competition": {},
		"regional_championship": {},
		"world_progression": {},
		"source_acquisition_counts": {},
	}


static func _set_source_count(
	cards: Dictionary,
	source_key: String,
	count: int
) -> void:
	var counts: Dictionary = cards.get("source_acquisition_counts", {})
	counts[source_key] = maxi(0, count)
	cards["source_acquisition_counts"] = counts


static func _next_code(snapshot: Dictionary) -> String:
	var raw = snapshot.get("next_objective", {})
	if raw is Dictionary:
		return str((raw as Dictionary).get("code", ""))
	return ""


static func _has_completed(snapshot: Dictionary, milestone_id: String) -> bool:
	var raw_ids = snapshot.get("completed_milestone_ids", [])
	if not (raw_ids is PackedStringArray or raw_ids is Array):
		return false
	for raw_id in raw_ids:
		if str(raw_id) == milestone_id:
			return true
	return false


static func _world_source_exists(
	world_map: Dictionary,
	source_type: String,
	source_id: String
) -> bool:
	var raw_sources = world_map.get("sources", [])
	if not (raw_sources is Array):
		return false
	for raw_source in raw_sources:
		if not (raw_source is Dictionary):
			continue
		var source: Dictionary = raw_source
		if (
			str(source.get("source_type", "")) == source_type
			and str(source.get("source_id", "")) == source_id
		):
			return true
	return false


static func _mastery_order() -> Array[String]:
	return [
		"read_current",
		"quiet_approach",
		"drift_casting",
		"read_depth",
		"read_structure",
		"line_feel",
		"weather_sense",
		"tide_sense",
		"deep_water_control",
		"surface_control",
		"landing_technique",
		"read_fish_sign",
		"one_with_nature",
	]


static func _teacher_scene_paths() -> Dictionary:
	return {
		"master_current_reader": "res://actors/FishingMasterCurrentReaderNPC.tscn",
		"master_still_water": "res://actors/FishingMasterStillWaterNPC.tscn",
		"master_drift_angler": "res://actors/FishingMasterDriftAnglerNPC.tscn",
		"master_depth_reader": "res://actors/FishingMasterDepthReaderNPC.tscn",
		"master_structure_hunter": "res://actors/FishingMasterStructureHunterNPC.tscn",
		"master_line_fighter": "res://actors/FishingMasterLineFighterNPC.tscn",
		"master_weather_watcher": "res://actors/FishingMasterWeatherWatcherNPC.tscn",
		"master_tide_reader": "res://actors/FishingMasterTideReaderNPC.tscn",
		"master_deepwater_veteran": "res://actors/FishingMasterDeepwaterVeteranNPC.tscn",
		"master_surface_angler": "res://actors/FishingMasterSurfaceAnglerNPC.tscn",
		"master_landing_guide": "res://actors/FishingMasterLandingGuideNPC.tscn",
		"master_sign_reader": "res://actors/FishingMasterSignReaderNPC.tscn",
		"master_nature_guide": "res://actors/FishingMasterNatureGuideNPC.tscn",
	}


static func _main_scene_contains(scene_path: String) -> bool:
	if not FileAccess.file_exists(MAIN_SCENE_PATH):
		return false
	var file := FileAccess.open(MAIN_SCENE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	return text.contains(scene_path)


static func _reward_status(
	reward_key: String,
	threshold: int,
	current_points: int,
	can_claim: bool
) -> Dictionary:
	return {
		"reward_key": reward_key,
		"claim_source_id": GyosilPolicy.SOURCE_ID,
		"threshold": threshold,
		"claimed": false,
		"can_claim": can_claim,
		"condition": {
			"current": current_points,
			"target": threshold,
		},
	}


static func _live_zenny(session: Node) -> int:
	var inventory = session.get("inventory")
	if inventory != null and inventory.has_method("get_zenny"):
		return int(inventory.call("get_zenny"))
	return -1


static func _live_mastery_snapshot(session: Node) -> Dictionary:
	var mastery = session.get("mastery_service")
	if mastery != null and mastery.has_method("get_snapshot"):
		var raw = mastery.call("get_snapshot")
		if raw is Dictionary:
			return (raw as Dictionary).duplicate(true)
	return {}


static func _live_reward_statuses(session: Node) -> Array:
	var rewards = session.get("reward_service")
	if rewards != null and rewards.has_method("get_all_reward_statuses"):
		var raw = rewards.call("get_all_reward_statuses")
		if raw is Array:
			return (raw as Array).duplicate(true)
	return []


static func _report_passed(value) -> bool:
	if not (value is Dictionary):
		return false
	var report: Dictionary = value
	var test_count: int = int(report.get("test_count", 0))
	var raw_failures = report.get("failures", PackedStringArray())
	var failure_count: int = 1
	if raw_failures is PackedStringArray or raw_failures is Array:
		failure_count = raw_failures.size()
	return (
		test_count > 0
		and int(report.get("passed_count", -1)) == test_count
		and failure_count == 0
	)


static func _append_path(report: Dictionary, label: String) -> void:
	var path: PackedStringArray = report.get(
		"rehearsal_path",
		PackedStringArray()
	)
	path.append(label)
	report["rehearsal_path"] = path


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


static func _record(
	report: Dictionary,
	label: String,
	passed: bool,
	failure_detail: String
) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get(
		"failures",
		PackedStringArray()
	)
	failures.append("%s — %s" % [label, failure_detail])
	report["failures"] = failures
