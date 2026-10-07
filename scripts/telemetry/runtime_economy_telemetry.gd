extends Node

const Recorder = preload("res://scripts/telemetry/economy_playtest_recorder.gd")
var recorder = Recorder.new()
var last_report: Dictionary = {}
var last_output: Dictionary = {}
var _session: Node
var _runtime: WeakRef
var _connections: Array = []
var _runtime_connections: Array = []
var _menus: Array = []
var _scene: WeakRef
var _indicator: CanvasLayer

func _ready() -> void:
	set_process(recorder.active)

func configure(session: Node) -> void:
	_session = session
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func bind_runtime(runtime: Node) -> void:
	if _runtime != null and _runtime.get_ref() == runtime:
		return
	if recorder.active:
		recorder.finish_attempt("partial", {"reason": "scene_changed"})
	_disconnect(_runtime_connections)
	_runtime = weakref(runtime)
	_scene = null
	if recorder.active:
		_connect_runtime()

func _connect_signal(object: Object, signal_name: String, callback: Callable, bucket: Array) -> void:
	if is_instance_valid(object) and object.has_signal(signal_name) and not object.is_connected(signal_name, callback):
		object.connect(signal_name, callback)
		bucket.append([weakref(object), signal_name, callback])

func _disconnect(bucket: Array) -> void:
	for entry in bucket:
		var object = entry[0].get_ref()
		if is_instance_valid(object) and object.is_connected(entry[1], entry[2]):
			object.disconnect(entry[1], entry[2])
	bucket.clear()

func start_recording() -> bool:
	if recorder.active or not is_instance_valid(_session) or _session.inventory == null:
		return false
	if not recorder.start(_snapshot()):
		return false
	_connect_signal(_session.inventory, "zenny_changed", _wallet_changed, _connections)
	_connect_signal(_session.inventory, "lure_count_changed", _owned_changed, _connections)
	_connect_signal(_session.inventory, "rod_count_changed", _owned_changed, _connections)
	_connect_signal(_session.economy_service, "fish_sold", _sale, _connections)
	_connect_signal(_session.economy_service, "item_purchased", _purchase, _connections)
	_connect_signal(_session.trade_service, "trade_completed", _trade, _connections)
	_connect_signal(_session.card_maker_service, "card_made", _card, _connections)
	_connect_signal(_session.beach_crafting_service, "crafted_lure_created", _crafted, _connections)
	_connect_signal(_world(), "location_changed", _location_changed, _connections)
	_connect_runtime()
	if _indicator == null:
		_indicator = CanvasLayer.new()
		_indicator.layer = 130
		add_child(_indicator)
		var label := Label.new()
		label.text = "REC  Economy playtest"
		label.position = Vector2(12, 8)
		label.modulate = Color(1.0, 0.45, 0.35)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_indicator.add_child(label)
	_indicator.show()
	set_process(true)
	_process(0.0)
	return true

func stop_recording() -> Dictionary:
	if not recorder.active:
		return last_output
	_process(0.0)
	last_report = recorder.stop(_snapshot())
	if not last_report.summary.ledger_reconciled:
		push_warning("Economy telemetry wallet mismatch: %s; raw evidence retained" % last_report.summary.wallet_reconciliation_error)
	_disconnect(_connections)
	_disconnect(_runtime_connections)
	_menus.clear()
	set_process(false)
	if _indicator != null:
		_indicator.hide()
	last_output = Recorder.save_report(last_report)
	if not last_output.get("ok", false):
		push_warning("Economy telemetry report failed: " + str(last_output) + "; report remains in memory for retry")
	else:
		print("Economy playtest report: ", ProjectSettings.globalize_path(last_output.raw_path))
	return last_output

func retry_save_report() -> Dictionary:
	last_output = Recorder.save_report(last_report)
	return last_output

func _exit_tree() -> void:
	if recorder.active:
		stop_recording()
	_disconnect(_connections)
	_disconnect(_runtime_connections)

func _get_runtime():
	return _runtime.get_ref() if _runtime != null else null

func _world():
	return get_node_or_null("/root/WorldLocations")

func _location() -> String:
	var world = _world()
	return str(world.current_location.location_id) if world != null and world.current_location != null else "unknown_or_transitioning"

func _snapshot() -> Dictionary:
	var items: Array = []
	items.append_array(_session.inventory.get_owned_lure_ids())
	items.append_array(_session.inventory.get_owned_rod_ids())
	var runtime = _get_runtime()
	return {"zenny": _session.inventory.get_zenny(), "location": _location(), "owned_items": items, "progression": _session.progress.get_progression_snapshot(), "unlock_flags": _session.unlock_state.get_all_flags(), "equipment": _gear(runtime)}

func _gear(runtime) -> Dictionary:
	if not is_instance_valid(runtime) or runtime.loadout == null:
		return {"rod": "unknown", "lure": "unknown"}
	var rod = runtime.loadout.get_selected_rod()
	var lure = runtime.loadout.get_selected_lure()
	return {"rod": str(rod.rod_id) if rod != null else "none", "lure": str(lure.lure_id) if lure != null else "none"}

func _attempt_context() -> Dictionary:
	var runtime = _get_runtime()
	var context := _gear(runtime)
	context["location"] = _location()
	if is_instance_valid(runtime):
		context.merge(runtime._build_catch_record_context())
		var zone = runtime.game_mode.active_fish_zone
		context["zone_path"] = str(zone.get_path()) if is_instance_valid(zone) else "unknown"
		context["population_species"] = _population(runtime)
		context["debug_forced_fish"] = runtime.debug_controller.settings.get_forced_fish() != null if runtime.debug_controller != null and runtime.debug_controller.settings.has_method("get_forced_fish") else false
	return context

func cast_started() -> void:
	if recorder.active:
		recorder.begin_attempt(_attempt_context())

func _connect_runtime() -> void:
	var runtime = _get_runtime()
	if not is_instance_valid(runtime):
		return
	_connect_signal(runtime.encounter, "bite_opportunity_started", _encounter, _runtime_connections)
	_connect_signal(runtime.encounter, "fish_hooked", _hook, _runtime_connections)
	_connect_signal(runtime.encounter, "bite_missed", _miss, _runtime_connections)
	_connect_signal(runtime.encounter, "fish_caught", _landed, _runtime_connections)
	_connect_signal(runtime.encounter, "hook_off", _escaped, _runtime_connections)
	_connect_signal(runtime.encounter, "line_broken", _failed, _runtime_connections)
	_connect_signal(runtime.caster, "bait_returned", _returned, _runtime_connections)
	_connect_signal(runtime.game_mode, "mode_changed", _mode_changed, _runtime_connections)
	if is_instance_valid(runtime.caster.active_bait):
		recorder.begin_attempt(_attempt_context(), true)
		if runtime.encounter.lifecycle.is_hooked():
			var specimen := _specimen(runtime.encounter.active_fish)
			recorder.join_existing_fight(str(specimen.get("species_id", "")), specimen)

func _encounter() -> void:
	var runtime = _get_runtime()
	if is_instance_valid(runtime):
		recorder.encounter(str(runtime.encounter.get_bite_timing_snapshot().get("species_id", "")))

func _specimen(fish) -> Dictionary:
	if fish == null or fish.species == null:
		return {}
	return {"species_id": fish.species.get_stable_species_id(), "size": fish.size, "size_band": fish.size_band, "is_king": fish.is_king, "points": fish.points, "score_tier": fish.score_tier}

func _hook() -> void:
	var runtime = _get_runtime()
	if not is_instance_valid(runtime):
		return
	var details := _specimen(runtime.encounter.active_fish)
	details["canonical_sell_value"] = _session.economy_service.get_fish_sell_value(StringName(details.get("species_id", "")))
	recorder.hook(str(details.get("species_id", "")), details)

func _miss() -> void:
	recorder.miss_bite()

func _landed(fish) -> void:
	var details := _specimen(fish)
	var id := str(details.get("species_id", ""))
	details["canonical_sell_value"] = _session.economy_service.get_fish_sell_value(StringName(id))
	var runtime = _get_runtime()
	details["outcome"] = _plain(runtime.last_outcome_result) if is_instance_valid(runtime) else {}
	recorder.finish_attempt("landed", details)

func _escaped() -> void:
	recorder.finish_attempt("escaped", {"reason": "hook_off"})

func _failed() -> void:
	recorder.finish_attempt("failed", {"reason": "line_break"})

func _returned() -> void:
	var runtime = _get_runtime()
	if is_instance_valid(runtime) and runtime.encounter.lifecycle.is_landing():
		recorder.begin_landing()
		return
	recorder.finish_attempt("failed", {"reason": "reel_back_without_landing"})

func _mode_changed(_mode) -> void:
	var runtime = _get_runtime()
	if is_instance_valid(runtime) and runtime.game_mode.is_exploration():
		recorder.finish_attempt("failed", {"reason": "left_fishing_without_landing"})

func _wallet_changed(balance: int) -> void:
	recorder.wallet_changed(balance, get_stack())

func _location_changed(location) -> void:
	recorder.event("location_changed", {"location": str(location.location_id) if location != null else "unbound", "travel_in_progress": _world().transitioning})
	recorder.set_activity("travel" if _world().transitioning else "other")

func _owned_changed(id: StringName, count: int) -> void:
	if count > 0:
		recorder.acquired(str(id), {"source": "inventory_commit", "location": _location(), "wallet": _session.inventory.get_zenny()})

func _sale(result: Dictionary) -> void:
	recorder.transaction("fish_sale", str(result.species_id), int(result.zenny_before), int(result.zenny_after), _plain(result))

func _purchase(result: Dictionary) -> void:
	recorder.transaction("shop_purchase", str(result.offer_id), int(result.zenny_before), int(result.zenny_after), _plain(result))
	recorder.annotate_acquisition(str(result.item_id), "shop:" + str(result.offer_id))

func _trade(recipe, result: Dictionary) -> void:
	var balance: int = _session.inventory.get_zenny()
	recorder.transaction("fish_trade", str(recipe.recipe_id), balance, balance, _plain(result))
	recorder.annotate_acquisition(str(result.reward_id), "trade:" + str(recipe.recipe_id))

func _card(result: Dictionary) -> void:
	recorder.transaction("card_maker", str(result.recipe_id), int(result.zenny_owned), int(result.zenny_after), _plain(result))

func _crafted(lure, record: Dictionary) -> void:
	var balance: int = _session.inventory.get_zenny()
	recorder.transaction("crafting", str(record.get("recipe_id", "unknown")), balance, balance, _plain(record))
	recorder.annotate_acquisition(str(lure.lure_id), "craft:" + str(record.get("recipe_id", "unknown")))

func _plain(value):
	if value is Dictionary:
		var result := {}
		for key in value:
			result[str(key)] = _plain(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_plain(item))
		return result
	if value is Object:
		if value.has_method("to_dictionary"):
			return _plain(value.to_dictionary())
		if value is Resource:
			return {"resource_path": value.resource_path}
		return null
	return value

func _population(runtime) -> Array:
	var result: Array = []
	var zone = runtime.game_mode.active_fish_zone
	if is_instance_valid(zone):
		for entry in zone.get_fish_population():
			if entry != null and entry.fish != null:
				var id: String = entry.fish.get_stable_species_id()
				if not result.has(id):
					result.append(id)
	return result

func _process(_delta: float) -> void:
	if not recorder.active:
		return
	var runtime = _get_runtime()
	var world = _world()
	var scene = get_tree().current_scene
	if _scene == null or _scene.get_ref() != scene:
		_menus.clear()
		_scene = weakref(scene) if scene != null else null
		if scene != null:
			_cache_menus(scene)
	var next := "other"
	if world != null and world.transitioning:
		next = "travel"
	else:
		for pair in _menus:
			var menu = pair[0].get_ref()
			if is_instance_valid(menu) and menu.is_open():
				next = pair[1]
				break
		if next == "other" and not get_tree().paused and is_instance_valid(runtime) and not runtime.debug_controller.is_open():
			if runtime.game_mode.is_fishing():
				var phases: Dictionary = runtime.get_script().get_script_constant_map().Phase
				if runtime.phase == phases.IN_WATER:
					next = "waiting_in_water"
				elif runtime.phase == phases.FIGHT:
					next = "fish_fight"
				else:
					next = "active_fishing"
			elif runtime.player is CharacterBody3D and Vector2(runtime.player.velocity.x, runtime.player.velocity.z).length() > 0.01:
				next = "world_movement"
	recorder.set_activity(next, _population(runtime) if is_instance_valid(runtime) and next in Recorder.FISHING_CATEGORIES else [])

func _cache_menus(node: Node) -> void:
	var script = node.get_script()
	if script != null:
		var path: String = script.resource_path
		var categories := {"res://scripts/fishing_economy_menu.gd": "shop_trade_ui", "res://scripts/beach_crafting_menu.gd": "crafting", "res://scripts/economy/fishing_card_maker_menu.gd": "shop_trade_ui", "res://scripts/triple_triad/triple_triad_game.gd": "triple_triad"}
		if categories.has(path):
			_menus.append([weakref(node), categories[path]])
	for child in node.get_children():
		_cache_menus(child)
