extends SceneTree

const Acquisition = preload("res://scripts/progression/early_tackle_acquisition.gd")
const Director = preload("res://scripts/progression/playable_campaign_progression_director.gd")
const Content = preload("res://data/bof4/catalogs/all_content.tres")
const Shops = preload("res://data/bof4/shops/all_shops.tres")
const Trades = preload("res://data/bof4/trades/all_trades.tres")
const Config = preload("res://data/economy/economy_foundation_v1.tres")
const Beach = preload("res://data/economy/contexts/beach_merchant.tres")
const Ocean2 = preload("res://data/bof4/spots/ocean_2.tres")
const Access = preload("res://scripts/fishing_economy_access.gd")
const Context = preload("res://scripts/economy/merchant_economy_context.gd")

class MemoryInventory:
	extends FishingInventory
	func save_to_disk() -> bool:
		return true

class WorldProvider:
	extends Node
	var economy_context = Beach

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func report(label: String, result: Dictionary) -> void:
	print("%s: %d/%d" % [label, result.passed_count, result.test_count])
	check(result.passed_count == result.test_count, label)
	for failure in result.get("failures", []):
		push_error(str(failure))

func _run() -> void:
	var inventory := MemoryInventory.new()
	inventory.set_zenny(100, false)
	var economy := FishingEconomyService.new()
	economy.configure(inventory, Content, Content.tackle, Shops, null, Config)
	var access := Access.new()
	var trade := FishingTradeService.new()
	trade.configure(inventory, Content.tackle, Trades)
	access.configure(inventory, economy, trade, null, null, Content, Shops, Trades)
	var guidance := Acquisition.new()
	guidance.configure(inventory, economy, Content, Shops, Trades)
	var providers := [{"context": Beach, "path": "BeachMerchantNPC"}]
	var before := inventory.create_transaction_snapshot()
	var snapshot := guidance.get_snapshot(providers, [Ocean2])
	var rows: Array = snapshot.targets
	check(rows.size() == 4, "four ownership targets")
	check(snapshot.next_target.item_id == "baby_frog", "fresh next acquisition")
	check(rows[0].source_id == "shyde_baby_frog" and rows[0].source_exists and rows[0].accessible, "real Beach offer reachable")
	check(rows[0].price_zenny == 250 and not rows[0].requirements_met, "canonical Baby Frog 250z, fresh 100z insufficient")
	check(rows[0].hint.contains("Beach Merchant"), "data-driven purchase guidance")
	check(rows[1].source_id == "wyndia_bamboo_rod" and rows[1].source_exists, "intentional Bamboo trade")
	var expected := [{"sea_bream": 2}, {"flying_fish": 3}, {"black_bass": 1, "blue_gill": 1, "piranha": 1}]
	for index in range(1, 4):
		var actual := {}
		for cost: Dictionary in rows[index].requirements:
			actual[cost.species_id] = cost.required
			check(cost.owned == 0 and cost.missing == cost.required, "fresh fish counts: " + cost.species_id)
			check(not cost.available_in_current_spots and not cost.authored_spot_ids.is_empty(), "authored fish exists but absent at Ocean 2: " + cost.species_id)
		check(actual == expected[index - 1], "exact authored trade ingredients " + rows[index].source_id)
		check(not rows[index].accessible and rows[index].reason == "world_context_unavailable", "missing world provider " + rows[index].source_id)
	check(before == inventory.create_transaction_snapshot(), "guidance is read-only")
	check(access.get_buy_entries().is_empty(), "guidance does not open economy access")
	check(access.buy_one(&"shyde_baby_frog").reason == "shop_not_available", "guidance cannot bypass contextual purchase")
	check(access.trade_one(&"wyndia_bamboo_rod").reason == "shop_not_available", "guidance cannot bypass contextual trade")
	access.enable_vertical_slice_full_access()
	check(guidance.get_snapshot(providers, [Ocean2]).targets == rows, "debug facade access independent of guidance")
	var full := Context.new()
	full.full_catalog_access = true
	check(not guidance.get_snapshot([{"context": full}], [Ocean2]).targets[0].accessible, "debug world provider cannot prove normal access")
	Beach.apply_to(access)
	var sea_bass = Content.get_fish_by_id(&"sea_bass")
	check(sea_bass.get_lure_match_multiplier(preload("res://data/bof4/lures/straight.tres")) > 0 and guidance._spot_has_species(Ocean2, "sea_bass"), "starter Straight has a positive bite path to Ocean 2 Sea Bass")
	inventory.add_fish("sea_bass", 4, false)
	var sales_ok := true
	for catch_index in range(4):
		sales_ok = bool(access.sell_one("sea_bass").get("can_sell", false)) and sales_ok
	check(sales_ok and inventory.get_zenny() == 260, "four Sea Bass sales at 40z fund Baby Frog from 100z start")
	check(bool(access.buy_one(&"shyde_baby_frog").get("can_purchase", false)) and inventory.get_lure_count(&"baby_frog") == 1 and inventory.get_zenny() == 10, "actual contextual Baby Frog purchase charges 250z")
	inventory.add_fish("sea_bream", 1, false)
	snapshot = guidance.get_snapshot(providers, [Ocean2])
	check(snapshot.next_target.item_id == "bamboo_rod", "ownership advances without elapsed time")
	check(snapshot.next_target.requirements[0].owned == 1 and snapshot.next_target.requirements[0].required == 2 and snapshot.next_target.requirements[0].missing == 1, "Sea Bream 1/2 snapshot")
	inventory.grant_lure(&"tail", 1, false) # Legitimate ownership before intended order.
	access.set_access_context(PackedStringArray(["faerie_diligent"]), PackedStringArray(), {"faerie_diligent_shop": true})
	inventory.set_zenny(1000, false)
	check(bool(access.buy_one(&"faerie_bamboo_rod").get("can_purchase", false)) and inventory.get_rod_count(&"bamboo_rod") == 1 and inventory.get_zenny() == 0, "alternate authored cash ownership recognized")
	check(guidance.get_snapshot(providers).next_target.item_id == "crab", "alternate early ownership skips already-owned targets")
	inventory.grant_lure(&"crab", 1, false)
	check(guidance.get_snapshot(providers).complete, "all ownership completes plan")
	check(not guidance.get_snapshot().targets[0].accessible, "scene departure removes access evidence")
	var faerie := Shops.get_offer_by_id(&"faerie_bamboo_rod")
	check(economy.evaluate_purchase(faerie).unit_price_zenny == 1000 and String(faerie.availability_tag) == "faerie_diligent_shop", "cash alternative preserved at 1000z with authored tag")
	var director := Director.new()
	director.configure(null, inventory)
	director.configure_tackle_acquisition(economy, Content, Shops, Trades)
	check(director.get_snapshot().tackle_acquisition.complete, "campaign director exposes runtime API")
	check(not director.get_tackle_acquisition_snapshot().targets[0].accessible, "no scene means no world source")
	var fixture := Node.new()
	root.add_child(fixture)
	current_scene = fixture
	fixture.add_child(director)
	var provider := WorldProvider.new()
	fixture.add_child(provider)
	provider.add_to_group(&"world_economy_sources")
	check(director.get_tackle_acquisition_snapshot().targets[0].accessible, "live scene provider collected")
	var foreign := WorldProvider.new()
	root.add_child(foreign)
	foreign.add_to_group(&"world_economy_sources")
	provider.queue_free()
	check(not director.get_tackle_acquisition_snapshot().targets[0].accessible, "queued and foreign scene providers excluded")
	var guide = preload("res://actors/PlayableCampaignQAGuide.tscn").instantiate()
	fixture.add_child(guide)
	guide.open_menu({"tackle_acquisition": {"next_target": rows[0]}}, [{"id": "live", "name": "LIVE"}])
	check(guide.guide_label.text.contains("Beach Merchant") and guide.guide_label.text.contains("250z"), "LIVE guide renders data-driven acquisition hint")
	var missing := Acquisition.new()
	missing.configure(inventory, null, null, null, null)
	check(not missing.get_snapshot().targets[0].source_exists, "missing backend reports unresolved without granting access")
	_run_campaign_qa()
	foreign.free()
	fixture.queue_free()
	await process_frame
	access.free()
	trade.free()
	economy.free()
	inventory.free()
	print("Early Tackle Acquisition QA: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _run_campaign_qa() -> void:
	report("Campaign Loop", preload("res://scripts/progression/playable_campaign_loop_qa.gd").run(Config))
	report("Campaign Director", preload("res://scripts/progression/playable_campaign_progression_director_qa.gd").run())
	report("Campaign Guide", preload("res://scripts/progression/playable_campaign_qa_guide_qa.gd").run())
	report("Campaign Presentation", preload("res://scripts/progression/playable_campaign_presentation_qa.gd").run())
