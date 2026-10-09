extends SceneTree

## Isolated regression tests for save-path and inventory subscription ownership.
var checks := 0
var failures := PackedStringArray()
var facade_events := 0
class ModifierFixture:
	extends Node
	signal modifiers_changed(snapshot: Dictionary)

func _initialize() -> void:
	var isolated := "CodexArchitectureOwnershipQA-%s" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Architecture ownership QA requires isolated userdata")
		quit(1)
		return
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	_test_save_paths()
	_test_facade_rebinding()
	_test_gathering_rebinding()
	_test_economy_access_rebinding()
	check(Node.get_orphan_node_ids().is_empty(), "fixture creators release all detached nodes")
	print("Architecture Ownership QA: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _test_save_paths() -> void:
	# These default paths are in this process's disposable namespace, never the player's.
	var primary := FishingInventory.new()
	primary.initialize()
	primary.set_zenny(713, true)
	var primary_bytes := FileAccess.get_file_as_bytes(primary.get_save_path())
	var isolated := FishingInventory.new()
	isolated.configure_save_path("user://custom_inventory.json")
	isolated.initialize()
	isolated.set_zenny(99, true)
	isolated.reset_inventory(true)
	check(FileAccess.file_exists(primary.get_save_path()), "custom inventory reset preserves default save")
	check(FileAccess.get_file_as_bytes(primary.get_save_path()) == primary_bytes, "default inventory bytes unchanged")
	var reloaded := FishingInventory.new()
	reloaded.configure_save_path(isolated.get_save_path())
	reloaded.initialize()
	check(reloaded.get_zenny() == 0, "custom inventory reset persists to its own path")
	check(reloaded.owns_lure(FishingInventory.STARTER_LURE_ID) and reloaded.owns_rod(FishingInventory.STARTER_ROD_ID), "reset preserves starter tackle")
	primary.free()
	isolated.free()
	reloaded.free()

	# With no default progress file, deletion must still use the configured path.
	var progress := FishingProgress.new()
	progress.configure_save_path("user://custom_progress.json")
	var custom_file := FileAccess.open(progress.get_save_path(), FileAccess.WRITE)
	custom_file.store_string("{\"version\":1}")
	custom_file.close()
	progress.reset_all_progress(true)
	check(not FileAccess.file_exists(progress.get_save_path()), "custom progress reset deletes configured save even without default")
	progress.free()

func _test_facade_rebinding() -> void:
	var old_items := PlayerItemInventory.new()
	var new_items := PlayerItemInventory.new()
	var old_fishing := FishingInventory.new()
	var new_fishing := FishingInventory.new()
	var facade := GameInventoryFacade.new()
	facade.changed.connect(func(): facade_events += 1)
	facade.configure(null, old_items, old_fishing)
	old_items.grant(&"fixture", 1, false)
	check(facade_events == 1, "initial player inventory subscription works")
	facade.configure(null, new_items, new_fishing)
	facade_events = 0
	old_items.grant(&"fixture", 1, false)
	old_fishing.set_zenny(20, false)
	check(facade_events == 0, "former inventory owners cannot notify rebound facade")
	new_items.grant(&"fixture", 1, false)
	new_fishing.set_zenny(30, false)
	check(facade_events == 2, "new inventory owners notify exactly once")
	facade.configure(null, new_items, new_fishing)
	facade_events = 0
	new_items.grant(&"fixture", 1, false)
	check(facade_events == 1, "same-owner configure remains idempotent")
	facade.configure(null, null, null)
	facade_events = 0
	new_items.grant(&"fixture", 1, false)
	new_fishing.set_zenny(40, false)
	check(facade_events == 0, "unbind releases subscriptions")
	for inventory in [old_items, old_fishing, new_items, new_fishing]:
		var stale_subscription := false
		for signal_info in inventory.get_signal_list():
			for connection in inventory.get_signal_connection_list(signal_info.name):
				stale_subscription = stale_subscription or connection.callable.get_object() == facade
		check(not stale_subscription, "no former signal retains facade receiver")
	facade.free()
	old_items.free()
	new_items.free()
	old_fishing.free()
	new_fishing.free()

func _test_economy_access_rebinding() -> void:
	var old_inventory := FishingInventory.new()
	var new_inventory := FishingInventory.new()
	var old_modifiers := ModifierFixture.new()
	var new_modifiers := ModifierFixture.new()
	var old_facade := GameInventoryFacade.new()
	var new_facade := GameInventoryFacade.new()
	var access = preload("res://scripts/fishing_economy_access.gd").new()
	access.changed.connect(func(): facade_events += 1)
	access.configure(old_inventory, null, null, null, old_modifiers, null, null, null)
	access.configure_item_backbone(null, old_facade, null)
	access.configure(new_inventory, null, null, null, new_modifiers, null, null, null)
	access.configure_item_backbone(null, new_facade, null)
	facade_events = 0
	old_inventory.set_zenny(10, false)
	old_modifiers.modifiers_changed.emit({})
	old_facade.changed.emit()
	check(facade_events == 0, "economy access releases every former signal source")
	facade_events = 0
	new_inventory.set_zenny(20, false)
	new_modifiers.modifiers_changed.emit({})
	new_facade.changed.emit()
	check(facade_events == 3, "economy access replacement sources each notify once")
	access.configure(new_inventory, null, null, null, new_modifiers, null, null, null)
	access.configure_item_backbone(null, new_facade, null)
	facade_events = 0
	new_inventory.set_zenny(30, false)
	new_modifiers.modifiers_changed.emit({})
	new_facade.changed.emit()
	check(facade_events == 3, "economy access same-owner configure is idempotent")
	access.configure(null, null, null, null, null, null, null, null)
	access.configure_item_backbone(null, null, null)
	facade_events = 0
	new_inventory.set_zenny(40, false)
	new_modifiers.modifiers_changed.emit({})
	new_facade.changed.emit()
	check(facade_events == 0, "economy access unbind releases all sources")
	access.free()
	for fixture in [old_inventory, new_inventory, old_modifiers, new_modifiers, old_facade, new_facade]:
		fixture.free()

func _test_gathering_rebinding() -> void:
	var old_items := PlayerItemInventory.new()
	var new_items := PlayerItemInventory.new()
	var gathering := BeachGatheringInventory.new()
	var callback := Callable(gathering, "_on_backbone_item_count_changed")
	gathering.configure_backbone(old_items, null, null)
	check(old_items.item_count_changed.is_connected(callback), "gathering subscribes to initial backbone")
	gathering.configure_backbone(new_items, null, null)
	check(not old_items.item_count_changed.is_connected(callback), "gathering releases former backbone")
	check(new_items.item_count_changed.is_connected(callback), "gathering subscribes to replacement backbone")
	gathering.configure_backbone(new_items, null, null)
	check(new_items.item_count_changed.get_connections().size() == 1, "gathering same-owner configure is idempotent")
	gathering.configure_backbone(null, null, null)
	check(not new_items.item_count_changed.is_connected(callback), "gathering unbind releases backbone")
	gathering.free()
	old_items.free()
	new_items.free()
