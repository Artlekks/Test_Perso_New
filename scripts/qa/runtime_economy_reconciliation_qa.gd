extends SceneTree

const Simulator = preload("res://scripts/progression/economy_progression_simulator.gd")
const Route = preload("res://scripts/progression/economy_runtime_route.gd")
const Resolver = preload("res://scripts/fishing_fight_resolver.gd")
var checks := 0
var failures: Array[String] = []
var orphan_before: Array[int] = []

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	var name := "CodexEconomyReconciliationQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/custom_user_dir_name", name)
	if not OS.get_user_data_dir().ends_with(name) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		quit(1)
		return
	print("ISOLATED USERDATA: ", OS.get_user_data_dir())
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	orphan_before.assign(Node.get_orphan_node_ids())
	var simulator := Simulator.new()
	var plan := simulator._build_purchase_plan()
	var route := Route.new()
	check(plan[0].source_id == "shyde_baby_frog" and plan[1].source_id == "wyndia_bamboo_rod", "canonical Beach/Bamboo sources")
	var expected := [{"sea_bream": 2}, {"flying_fish": 3}, {"black_bass": 1, "blue_gill": 1, "piranha": 1}, {"salmon": 2, "dorado": 2, "martian_squid": 2}]
	var index := 0
	for purchase in plan:
		if purchase.acquisition != "fish_trade":
			continue
		check(purchase.fish_requirements == expected[index], "exact progression recipe: " + purchase.id)
		check(purchase.fish_requirements == Route.Trades.get_recipe_by_id(StringName(purchase.source_id)).get_cost_dictionary(), "recipe authority: " + purchase.id)
		var batch: Dictionary = purchase.fish_requirements.duplicate(true)
		var state := {"fish_reserved_by_species": {}, "traded_by_species": {}, "sold_by_species": {}}
		var amount := simulator._reserve_trade_target_fish(state, {}, [purchase], batch)
		check(is_equal_approx(amount, simulator._sum_species_amounts(purchase.fish_requirements)) and is_zero_approx(simulator._sum_species_amounts(batch)), "required fish all reserved: " + purchase.id)
		check(is_zero_approx(simulator._sale_revenue(batch, 1.0, state)), "reserved fish generate zero sale income: " + purchase.id)
		check(simulator._can_pay_fish_trade(state, purchase.fish_requirements), "reserved recipe payable: " + purchase.id)
		check(is_equal_approx(simulator._pay_fish_trade(state, purchase.fish_requirements), amount) and simulator._fish_requirements_match(state.traded_by_species, purchase.fish_requirements), "trade consumes exact reservation once: " + purchase.id)
		check(not simulator._can_pay_fish_trade(state, purchase.fish_requirements), "consumed fish cannot fund a second trade: " + purchase.id)
		index += 1
	var inventory := FishingInventory.new()
	var economy := FishingEconomyService.new()
	economy.configure(inventory, Route.Content, Route.Content.tackle, Route.Shops, null, Route.Config)
	for row in plan:
		if row.acquisition == "buy":
			var live := economy.evaluate_purchase(Route.Shops.get_offer_by_id(StringName(row.source_id)))
			check(simulator._resolve_purchase_zenny_cost(row) == live.unit_price_zenny, "live price resolution: " + row.id)
	check(simulator._purchase_source_is_valid({"item_id": "bamboo_rod", "kind": "rod", "acquisition": "buy", "source_type": "shop_offer", "source_id": "faerie_bamboo_rod"}) and route.price(&"faerie_bamboo_rod") == 1000, "alternate Faerie Bamboo source preserved")
	check(route.reachable({}).location_ids == PackedStringArray(["beach"]), "fresh save cannot borrow locked populations")
	check(not route.available(plan[1], {}), "Bamboo source locked before Baby Frog")
	check(route.available(plan[1], {"baby_frog": true}), "Baby Frog unlocks canonical Bamboo source")
	check(route.reachable({}, &"unknown").spots.is_empty(), "unknown origin never invents a population")
	check(route.population({}, {}, {}, &"unknown").weights.is_empty(), "unknown origin has no fallback fish")
	var first: Dictionary = simulator.run_default_suite(false)
	check(first == simulator.run_default_suite(false), "all profiles and guardrails deterministic")
	for profile in first.profiles.values():
		for snapshot in profile.checkpoints.values():
			check(absf(snapshot.fish_accounting_error) < 0.000001, "catches conserved across sale/trade/bait/cards/reserve: " + profile.profile_id + " H" + str(snapshot.hour))
			for species in snapshot.traded_by_species:
				check(float(snapshot.sold_by_species.get(species, 0.0)) + float(snapshot.traded_by_species[species]) <= float(snapshot.caught_by_species.get(species, 0.0)) + 0.000001, "no sold/traded double counting: " + species)
	print("SIMULATOR GUARDRAILS: ", first.summary)
	for guardrail in first.checks:
		if not guardrail.passed:
			print("UNMET GUARDRAIL: ", guardrail.label, " value=", guardrail.value, " target=", guardrail.target)
	print("RUNTIME ROUTE ISSUES: ", JSON.stringify(first.runtime_route.issues))
	var balanced: Dictionary = first.profiles.BALANCED.final
	print("NINE-STEP FRESH-SAVE VIABILITY: ", "PASS" if balanced.purchases.size() == 9 else "FAIL — stops after " + str(balanced.purchases))
	first.salmon_bamboo = await test_salmon_hook()
	# Report content deadlocks separately from algorithm checks; never waive them.
	var report_path := OS.get_cmdline_user_args()
	for arg in report_path:
		if arg.begins_with("--report="):
			var output := FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			output.store_string(JSON.stringify(first, "  "))
	inventory.free()
	economy.free()
	for id in Node.get_orphan_node_ids():
		if not orphan_before.has(id):
			var orphan = instance_from_id(id)
			if is_instance_valid(orphan):
				orphan.free()
	print("RUNTIME ECONOMY RECONCILIATION QA: %d/%d invariant checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func test_salmon_hook() -> Dictionary:
	# Actual Encounter hook path, not a tier-label comparison or a granted catch.
	var scene = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in range(6):
		await process_frame
	var encounter = scene.get_node("Game/Fishing/Encounter")
	var fishing = scene.get_node("Game/Fishing")
	fishing.set_process(false)
	encounter.set_process(false)
	encounter.set_rod_data(load("res://data/bof4/rods/bamboo_rod.tres"))
	encounter.active_bait_data = load("res://data/bof4/lures/popper.tres")
	var salmon = Route.Content.get_fish_by_id(&"salmon")
	var average := FishInstance.new()
	average.setup(salmon, 0, salmon.average_size)
	var average_context := Resolver.resolve_context(average, encounter.active_rod_data, encounter.active_bait_data)
	var average_audit: Dictionary = preload("res://scripts/fishing_fight_accessibility.gd").audit_specimen(salmon, average.get_fight_stats(), encounter.active_rod_data, encounter.tension._get_profile(), false, -1.0, encounter.stamina_drain_speed, encounter.active_bait_data)
	check(average_audit.passes_fairness_envelope, "average Salmon/Bamboo passes actual hook/endurance/line-grace envelope")
	var entry: FishSpawnEntry
	for candidate in load("res://data/bof4/spots/river_2.tres").fish_population:
		if candidate.fish == salmon:
			entry = candidate
	check(entry != null and entry.get_bite_selection_weight(encounter.active_bait_data, 0.1, 1.0, true) > 0.0, "Salmon selectable with a pre-Angling lure")
	seed(71023)
	encounter.lifecycle.begin_cast()
	encounter.lifecycle.open_bite_window()
	encounter.pending_fish_entry = entry
	encounter.bite_active = true
	encounter.bite_hook_ready = true
	check(encounter.try_hook(), "actual Encounter.try_hook accepts Salmon with Bamboo")
	check(encounter.lifecycle.is_hooked() and encounter.active_fish.species == salmon, "Salmon hooked lifecycle established")
	check(Resolver.is_valid_context(encounter.active_fight_context), "Salmon/Bamboo runtime fight context valid")
	print("SALMON BAMBOO CONTEXT: ", JSON.stringify(encounter.active_fight_context))
	var evidence := {"hooked_context": encounter.active_fight_context.duplicate(true), "average_context": average_context, "average_accessibility": average_audit, "tension": encounter.tension.get_debug_snapshot(), "stamina_drain_speed": encounter.stamina_drain_speed, "scope": "actual hook and production fatigue under ideal safe pressure; not human win rate or rendered play-feel"}
	# Prove production fatigue can exhaust all rounds under ideal safe pressure.
	# This isolates mechanical attainability, not human steering or win probability.
	encounter.fish_behavior.set_process(false)
	encounter.tension.set_process(false)
	var elapsed := 0.0
	for frame in range(12000):
		encounter.player_reeling = true
		encounter.current_tension_state = FishingTension.State.SAFE
		encounter._process(1.0 / 60.0)
		elapsed += 1.0 / 60.0
		if encounter.fight_state == encounter.FightState.SPENT:
			break
	check(encounter.fight_state == encounter.FightState.SPENT and encounter.rounds_remaining == 0, "Bamboo can drain all Salmon resistance rounds under ideal safe pressure")
	evidence.seconds_to_spent = elapsed
	evidence.spent_reached = encounter.fight_state == encounter.FightState.SPENT
	encounter.reset_cast_session()
	var session := root.get_node("FishingSessionServices")
	for property in ["campaign_loop_qa_report", "campaign_progression_director_qa_report", "campaign_qa_guide_qa_report", "campaign_presentation_qa_report", "fresh_save_rehearsal_qa_report", "system_stability_qa_report"]:
		var report: Dictionary = session.get(property)
		print(property, ": ", report.passed_count, "/", report.test_count)
	scene.queue_free()
	session.queue_free()
	for frame in range(3):
		await process_frame
	return evidence
