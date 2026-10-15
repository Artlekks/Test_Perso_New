extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const Inventory = preload("res://scripts/fishing_inventory.gd")
const Progress = preload("res://scripts/fishing_progress.gd")
const Rewards = preload("res://scripts/fishing_reward_service.gd")
const ROOT := "user://durability_focus"

func _initialize() -> void:
	if not Isolation.verify([ROOT, ROOT + "/inventory.json", ROOT + "/progress.json", ROOT + "/fault.marker"]):
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	var action := args[0]
	var folder := ROOT + "/" + args[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var inventory: FishingInventory = Inventory.new()
	inventory.configure_save_path(folder + "/inventory.json")
	inventory.initialize()
	var progress: FishingProgress = Progress.new()
	progress.configure_save_path(folder + "/progress.json")
	progress.initialize()
	var ok := true
	match action:
		"first":
			inventory.set_zenny(100)
			inventory.add_fish("qa", 1)
			progress.recent_catch_transaction_ids.append("tx-one")
			ok = progress.save_to_disk()
		"update":
			inventory.set_zenny(200)
			inventory.add_fish("qa", 1)
			progress.recent_catch_transaction_ids.append("tx-two")
			ok = progress.save_to_disk()
		"fault_open", "fault_pre", "fault_promote":
			OS.set_environment("FISHING_QA_FAULT_STAGE", {
				"fault_open": "temporary_open",
				"fault_pre": "before_promotion",
				"fault_promote": "promotion_failure",
			}[action])
			inventory.set_zenny(300)
			ok = false if action == "fault_promote" else true
		"inspect":
			ok = inventory.get_zenny() == 100 and inventory.get_fish_count("qa") == 1 and progress.has_catch_transaction("tx-one")
		"inspect200":
			ok = inventory.get_zenny() == 200 and inventory.get_fish_count("qa") == 2 and progress.has_catch_transaction("tx-two")
		"recover_save":
			ok = inventory.get_zenny() == 200
			inventory.set_zenny(250)
			ok = ok and inventory.get_zenny() == 250
		"recover_temp_save":
			ok = inventory.get_zenny() == 100 and inventory.get_fish_count("qa") == 1
			inventory.set_zenny(150)
			ok = ok and inventory.get_zenny() == 150 and inventory.save_to_disk()
		"inspect150":
			ok = inventory.get_zenny() == 150 and inventory.get_fish_count("qa") == 1
		"seed_progress":
			var record: Dictionary = progress.call("_create_empty_record_from_values", "QA")
			record["caught_count"] = 2
			progress.species_records["qa"] = record
			ok = progress.save_to_disk()
		"inspect_progress":
			ok = int((progress.species_records.get("qa", {}) as Dictionary).get("caught_count", 0)) == 2
		"legacy_progress":
			ok = int((progress.species_records.get("qa", {}) as Dictionary).get("caught_count", 0)) == 2
			ok = ok and progress.save_to_disk()
		"legacy":
			ok = inventory.get_zenny() == 75 and inventory.get_fish_count("qa") == 2
			ok = ok and inventory.save_to_disk()
		"reward_write":
			var rewards: FishingRewardService = Rewards.new()
			rewards.initialize()
			rewards.set("_claimed_reward_keys", {"qa_reward": true})
			ok = rewards.save_to_disk()
			rewards.free()
		"reward_check":
			var rewards: FishingRewardService = Rewards.new()
			rewards.initialize()
			ok = rewards.is_claimed(&"qa_reward")
			rewards.free()
		"blocked":
			ok = not inventory.load_from_disk() and not inventory.save_to_disk()
		_:
			ok = false
	inventory.free()
	progress.free()
	var result := FileAccess.open(folder + "/result.marker", FileAccess.WRITE)
	if result != null:
		result.store_string("ok" if ok else "failed")
		result.close()
	print("DURABILITY_CHILD %s %s" % [action, ok])
	quit(0 if ok else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
