extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const ROOT := "user://beach_craft_qa"

func _initialize() -> void:
	if not Isolation.verify([ROOT, "user://craft_fault.marker"]):
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	for frame in range(2):
		await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var action := args[0] if args.size() > 0 else ""
	var fixture := SessionTestFixture.new()
	fixture.mount(self)
	for frame in range(12):
		await process_frame
	var service: BeachCraftingService = fixture.session.beach_crafting_service
	var result := {}
	match action:
		"setup":
			result = service.grant_qa_material_bundle(3)
		"craft":
			result = service.craft(&"beach_minnow", &"driftwood", &"shell", &"seaweed_fibre")
		"recover":
			result = service.call("recover_pending_craft")
		"load":
			result = {"success": true}
		"inspect_records":
			result = {"success": true,
				"records": service.get_crafted_records(),
				"next_instance_number": service.get_debug_snapshot().next_instance_number,
				"runtime_lure_present": service.get_runtime_lure(&"crafted_beach_minnow_001") != null}
		"load_status":
			result = {"success": service.load_from_disk(),
				"records": service.get_crafted_records()}
		"conflict":
			result = fixture.session.item_transaction_service.sell_player_item_for_zenny(&"player/driftwood", 1, 1)
		"conflict_catch":
			result = fixture.session.catch_repository.commit_snapshot({"transaction_id": "qa_conflicting_catch"})
		"conflict_card_maker":
			result = fixture.session.card_maker_service.make_card(&"qa_conflicting_recipe")
		"direct_writes":
			result = {"item": fixture.session.player_item_inventory.save_to_disk(),
				"fish": fixture.session.inventory.save_to_disk(),
				"record": service.save_to_disk()}
	var output := FileAccess.open(ROOT + "/child_result.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(result))
		output.close()
	fixture.release()
	for frame in range(4):
		await process_frame
	quit(0)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
