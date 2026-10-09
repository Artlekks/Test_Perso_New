extends SceneTree

const Recorder = preload("res://scripts/telemetry/economy_playtest_recorder.gd")
var checks := 0
var failures := PackedStringArray()
var now_usec := 0
var initial_orphans: Array[int] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void:
	initial_orphans.assign(Node.get_orphan_node_ids())
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	var isolated := "CodexTelemetryQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		quit(1)
		return
	print("ISOLATED TELEMETRY QA USERDATA: ", OS.get_user_data_dir())
	call_deferred("_run")

func _run() -> void:
	var r = Recorder.new()
	r.clock = func(): return now_usec
	check(not r.active, "off by default")
	r.wallet_changed(999)
	r.begin_attempt({})
	r.encounter("salmon")
	check(r.events.is_empty() and r.attempts.is_empty() and r.ledger.is_empty(), "disabled events are inert")
	check(r.start({"zenny": 100, "location": "test", "owned_items": ["baby_frog"]}), "explicit start")
	check(not r.start({}), "double start rejected")
	check(r.acquisitions.baby_frog.pre_existing and r.acquisitions.baby_frog.elapsed_seconds == null, "preexisting item has no invented timestamp")
	r.set_activity("waiting_in_water", ["salmon", "martian_squid"])
	r.begin_attempt({"rod": "bamboo_rod", "location": "test", "lure": "tail"})
	now_usec = 10000000
	r.encounter("salmon")
	r.encounter("salmon")
	check(r.species.salmon.encounters == 1, "one encounter per live bite")
	r.miss_bite()
	r.miss_bite()
	check(r.species.salmon.missed_bites == 1, "missed bite recorded once")
	now_usec = 20000000
	r.encounter("salmon")
	r.hook("salmon", {"size": 80})
	r.hook("salmon")
	check(r.species.salmon.hooks == 1, "hook recorded once")
	r.set_activity("fish_fight", ["salmon", "martian_squid"])
	now_usec = 40000000
	r.finish_attempt("landed", {"canonical_sell_value": 1000})
	r.finish_attempt("landed", {"canonical_sell_value": 1000})
	check(r.attempts.size() == 1 and r.total_landed() == 1, "landing recorded exactly once")
	check(r.attempts[0].encounters.size() == 2 and r.attempts[0].fight_seconds == 20.0, "multiple bites in one attempt and exact fight duration")
	r.wallet_changed(1100)
	r.transaction("fish_sale", "salmon", 100, 1100, {"quantity": 1})
	check(r.ledger.size() == 1 and r.ledger[0].source == "fish_sale", "wallet notification enriched without double counting")
	r.wallet_changed(900)
	r.acquired("bamboo_rod", {"source": "inventory_commit", "location": "test"})
	r.annotate_acquisition("bamboo_rod", "shop:test_offer")
	r.acquired("bamboo_rod", {"source": "duplicate"})
	r.transaction("shop_purchase", "test_offer", 1100, 900)
	check(r.acquisitions.bamboo_rod.source == "shop:test_offer" and r.acquisitions.bamboo_rod.elapsed_seconds == 40.0, "acquisition once with committed source and timing")
	check(r.acquisitions.bamboo_rod.total_landed == 1 and r.acquisitions.bamboo_rod.wallet == 900, "acquisition wallet and landed count")
	r.begin_attempt({"rod": "bamboo_rod"})
	r.encounter("salmon")
	r.hook("salmon")
	now_usec = 50000000
	r.finish_attempt("escaped")
	check(r.species.salmon.lost == 1 and r.total_landed() == 1, "escape distinct from landing")
	for number in [1, 2]:
		r.begin_attempt({"rod": "bamboo_rod"})
		r.encounter("martian_squid")
		r.hook("martian_squid")
		now_usec += 10000000
		r.finish_attempt("landed", {"canonical_sell_value": 100})
	r.begin_attempt({"rod": "bamboo_rod"})
	now_usec += 10000000
	r.finish_attempt("failed", {"reason": "no_bite_reel_back"})
	r.begin_attempt({"rod": "bamboo_rod"})
	r.set_activity("other")
	now_usec += 10000000
	var report: Dictionary = r.stop({"zenny": 900, "location": "test"})
	check(not r.active and r.stop({}).is_empty(), "stop idempotent and releases recording")
	check(report.summary.duration_seconds == 90.0, "short partial session is valid")
	check(report.summary.wallet_reconciliation_error == 0 and report.summary.income == 1000 and report.summary.spent == 200, "economy ledger reconciles exactly")
	check(report.summary.salmon.encounters == 3 and report.summary.salmon.hooks == 2 and report.summary.salmon.landed == 1 and report.summary.salmon.lost == 1, "species aggregation")
	check(is_equal_approx(report.summary.salmon.hook_rate, 2.0 / 3.0) and report.summary.salmon.landing_rate == 0.5, "hook and landing denominators correct")
	check(report.summary.salmon.average_fight_seconds == 15.0 and report.summary.salmon.sell_income == 1000, "Salmon duration and actual sales")
	check(report.summary.salmon.population_exposure_seconds == 80.0 and report.summary.active_fishing_seconds == 80.0, "species exposure includes waiting and active clock conserves time")
	check(report.summary.martian_squid.landing_milestones[0].elapsed_seconds == 60.0 and report.summary.martian_squid.landing_milestones[1].elapsed_seconds == 70.0, "first and second squid timing")
	check(report.summary.martian_squid.landing_milestones[0].session_attempt_number == 3 and report.summary.martian_squid.landing_milestones[1].session_attempt_number == 4, "attempts required for squid x2")
	check(report.summary.failed_or_escaped_attempts == 2 and report.attempts.back().result == "partial", "no-bite failure and incomplete stop distinguished")
	var output: Dictionary = Recorder.save_report(report)
	check(output.ok and output.raw_path.begins_with("user://playtest_telemetry/"), "report isolated from save data")
	check(JSON.parse_string(FileAccess.get_file_as_string(output.raw_path)).summary.wallet_reconciliation_error == 0, "raw JSON readable")
	check(JSON.parse_string(FileAccess.get_file_as_string(output.summary_path)).landed == 3, "summary JSON readable")
	check(not Recorder.save_report(report, "user://fishing_save").ok and not Recorder.save_report(report, "user://playtest_telemetry/../save").ok, "output rejects save paths and traversal")
	print("AUTOMATED SYNTHETIC EXAMPLE: ", output)
	print("AUTOMATED SYNTHETIC SUMMARY: ", JSON.stringify(report.summary))
	check(r.start({"zenny": 10, "owned_items": []}) and r.events.size() == 1 and r.attempts.is_empty() and r.acquisitions.is_empty(), "independent sessions reset metrics")
	check(report.attempts.size() == 6 and report.economy_ledger.size() == 2, "new recording preserves previous in-memory report for retries")
	now_usec += 1000000
	var second: Dictionary = r.stop({"zenny": 10})
	var second_output: Dictionary = Recorder.save_report(second)
	check(second_output.ok and second_output.raw_path != output.raw_path, "independent outputs never overwrite")
	r.start({"zenny": 10})
	r.begin_attempt({"rod": "bamboo_rod"}, true)
	r.join_existing_fight("salmon", {"size": 80})
	now_usec += 1000000
	r.finish_attempt("landed", {"canonical_sell_value": 1000})
	var joined: Dictionary = r.stop({"zenny": 10})
	check(joined.summary.hooks == 0 and joined.summary.encounters == 0 and joined.summary.landed == 1, "joining existing fight does not invent encounter/hook events")
	check(joined.summary.landing_rate == null and joined.summary.salmon.average_fight_seconds == null and joined.summary.completed_attempts == 0, "partial fight excluded from complete attempt/rate/duration denominators")
	r.start({"zenny": 10})
	var mismatch: Dictionary = r.stop({"zenny": 20})
	check(not mismatch.summary.ledger_reconciled and mismatch.summary.wallet_reconciliation_error == -10, "missing wallet event remains an explicit reconciliation diagnostic")
	await _runtime_checks()
	for id in Node.get_orphan_node_ids():
		if not initial_orphans.has(id):
			check(false, "telemetry fixture leaked orphan node %d" % id)
	print("RUNTIME ECONOMY TELEMETRY QA: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _runtime_checks() -> void:
	check(change_scene_to_file("res://actors/FishingTestScene_V2.tscn") == OK, "actual runtime scene loads")
	await scene_changed
	await process_frame
	var session = root.get_node("FishingSessionServices")
	var runtime = current_scene.get_node("Game/Fishing")
	var telemetry = FishingDevelopmentLayer.ensure(session).get_economy_playtest_telemetry()
	check(not telemetry.recorder.active and not telemetry.is_processing(), "runtime recorder and processing disabled by default")
	check(FishingSessionQA.reports(session).campaign_loop_qa_report.valid and FishingSessionQA.reports(session).fresh_save_rehearsal_qa_report.valid, "structural startup remains green")
	var snapshot: Dictionary = session.inventory.create_transaction_snapshot()
	var progress: Dictionary = session.progress.get_progression_snapshot()
	var saved := {}
	for path in DirAccess.get_files_at("user://"):
		if not DirAccess.dir_exists_absolute("user://" + path):
			saved[path] = FileAccess.get_file_as_bytes("user://" + path)
	seed(2468)
	var expected := randi()
	seed(2468)
	check(telemetry.start_recording(), "runtime start")
	telemetry.bind_runtime(runtime)
	telemetry.bind_runtime(runtime)
	check(not telemetry.start_recording(), "runtime double start refused")
	var no_play_output: Dictionary = telemetry.stop_recording()
	check(no_play_output.ok and randi() == expected, "start/stop leaves global RNG unchanged")
	check(session.inventory.create_transaction_snapshot() == snapshot and session.progress.get_progression_snapshot() == progress, "start/stop leaves inventory and progression unchanged")
	for path in saved:
		check(FileAccess.get_file_as_bytes("user://" + path) == saved[path], "normal save bytes untouched: " + path)
	check(runtime.debug_controller.debug_menu._telemetry_button.text == "Start Economy Playtest Recording", "obvious existing-menu control")
	# Exercise real committed transaction signals with isolated gameplay data.
	session.inventory.add_fish_specimen("salmon", "Salmon", 80.0, 0, false, false)
	check(telemetry.start_recording(), "real transaction recording starts")
	telemetry.bind_runtime(runtime)
	var before: int = session.inventory.get_zenny()
	var sale: Dictionary = session.economy_service.sell_fish(&"salmon", 1)
	check(sale.get("reason", "") == "completed", "real fish sale commits")
	check(telemetry.recorder.ledger.size() == 1 and telemetry.recorder.ledger[0].source == "fish_sale", "real committed sale observed exactly once")
	check(telemetry.recorder.ledger[0].wallet_before == before and telemetry.recorder.ledger[0].amount == session.economy_service.get_fish_sell_value(&"salmon"), "real canonical price and wallet")
	var offer = null
	for candidate in session.economy_service.shop_catalog.get_all_offers():
		if candidate.item_id == &"baby_frog":
			offer = candidate
			break
	var purchase: Dictionary = session.economy_service.purchase_offer(offer)
	check(purchase.get("reason", "") == "completed", "real shop purchase commits")
	check(telemetry.recorder.ledger.size() == 2 and telemetry.recorder.ledger[1].source == "shop_purchase", "real purchase counted once")
	check(telemetry.recorder.acquisitions.baby_frog.source.begins_with("shop:") and telemetry.recorder.acquisitions.baby_frog.wallet == session.inventory.get_zenny(), "real acquisition source and committed wallet")
	for i in range(2):
		session.inventory.add_fish_specimen("sea_bream", "Sea Bream", 50.0, 0, false, false)
	var recipe = null
	for candidate in session.trade_service.get_all_recipes():
		if candidate.reward_id == &"bamboo_rod":
			recipe = candidate
			break
	var trade: Dictionary = session.trade_service.execute_trade(recipe)
	check(trade.get("reason", "") == "completed", "real fish trade commits")
	check(telemetry.recorder.ledger.size() == 3 and telemetry.recorder.ledger[2].source == "fish_trade" and telemetry.recorder.ledger[2].amount == 0, "material trade recorded once without fake cash spending")
	check(telemetry.recorder.acquisitions.bamboo_rod.source.begins_with("trade:"), "real trade acquisition attributed")
	session.inventory.add_fish_specimen("trout", "Trout", 20.0, 0, false, false)
	var triad = current_scene.find_child("TripleTriadGame", true, false)
	triad.claim_salvaged_card_case()
	var card: Dictionary = session.card_maker_service.make_card(&"trout_card")
	check(card.get("success", false), "real Card Maker transaction commits: " + str(card))
	check(telemetry.recorder.ledger.size() == 4 and telemetry.recorder.ledger[3].source == "card_maker", "real Card Maker expenditure once")
	telemetry.cast_started()
	var fish := FishInstance.new()
	fish.species = session.economy_service.content_catalog.get_fish_by_id(&"salmon")
	fish.size = 80.0
	runtime.encounter.active_fish = fish
	telemetry._hook()
	check(telemetry.recorder.species.salmon.hooks == 1 and telemetry.recorder.current_attempt.specimen.canonical_sell_value == 1000, "runtime hook reads actual fish species and canonical value")
	runtime.encounter.lifecycle.begin_cast()
	runtime.encounter.lifecycle.confirm_hook()
	runtime.encounter.lifecycle.begin_landing()
	telemetry._returned()
	check(not telemetry.recorder.current_attempt.is_empty() and telemetry.recorder.fight_end >= 0.0, "physical bait return preserves pending landing and ends fight clock")
	telemetry._landed(fish)
	telemetry._returned()
	check(telemetry.recorder.total_landed() == 1 and telemetry.recorder.attempts.size() == 1, "landing completion and subsequent cleanup count once")
	runtime.encounter.lifecycle.finish_cast()
	runtime.encounter.active_fish = null
	var real_output: Dictionary = telemetry.stop_recording()
	check(real_output.ok and telemetry.last_report.summary.wallet_reconciliation_error == 0, "real runtime ledger reconciles")
	check(telemetry._connections.is_empty() and telemetry._runtime_connections.is_empty(), "stop disconnects observers")
	var debug_menu = runtime.debug_controller.debug_menu
	runtime.debug_controller.open()
	debug_menu._selected_row = debug_menu.Row.TELEMETRY
	debug_menu._telemetry_button.pressed.emit()
	check(telemetry.recorder.active and debug_menu._telemetry_button.text.contains("Stop Recording"), "actual existing-menu button starts recording")
	var held := InputEventKey.new()
	held.physical_keycode = KEY_D
	held.pressed = true
	held.echo = true
	debug_menu.handle_input(held)
	check(telemetry.recorder.active, "held keyboard input does not toggle recording repeatedly")
	telemetry._process(0.0)
	check(telemetry.recorder.category == "other", "debug menu excluded from active fishing")
	debug_menu._telemetry_button.pressed.emit()
	check(not telemetry.recorder.active and telemetry.last_output.ok, "actual menu button stops and saves")
	runtime.debug_controller.close(false)
	check(telemetry.start_recording(), "cross-scene recording starts")
	var world = root.get_node("WorldLocations")
	var travel: Dictionary = world.request_travel(&"wyndia_ocean_outpost")
	check(travel.get("success", false), "real authorized travel starts")
	if travel.get("success", false):
		await scene_changed
		await process_frame
		var destination_runtime = current_scene.get_node("Game/Fishing")
		check(telemetry.recorder.active and telemetry._get_runtime() == destination_runtime, "same recorder survives travel and rebinds physical runtime")
		check(telemetry._runtime_connections.size() == 8, "one set of fishing observers after scene change")
		var travel_output: Dictionary = telemetry.stop_recording()
		check(travel_output.ok and telemetry.last_report.ending.location == "wyndia_ocean_outpost", "travel report ends at actual authoritative location")
		check(telemetry.last_report.summary.wallet_reconciliation_error == 0, "wallet reconciles across scenes")
		var locations := 0
		for event in telemetry.last_report.events:
			locations += int(event.kind == "location_changed")
		check(locations >= 1, "actual location changes recorded")
	current_scene.queue_free()
	session.queue_free()
	await process_frame
	await process_frame
