extends Node
class_name BeachCraftingService

signal crafted_lure_created(lure: BaitData, record: Dictionary)
signal crafted_lures_reloaded(count: int)

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://beach_crafted_lures.json"

const SCORE_MIN: int = -4
const SCORE_MAX: int = 4

var _material_inventory: BeachGatheringInventory = null
var _fishing_inventory: FishingInventory = null
var _tackle_catalog: FishingTackleCatalog = null
var _catalog: BeachCraftingCatalog = null

var _records: Array[Dictionary] = []
var _runtime_lures: Dictionary = {}
var _next_instance_number: int = 1
var _configured: bool = false
var _active_loadout = null
var _item_catalog: GameItemCatalogService = null
var _player_item_inventory: PlayerItemInventory = null
var _item_transaction_service: GameItemTransactionService = null


func configure_item_backbone(
	item_catalog: GameItemCatalogService,
	player_item_inventory: PlayerItemInventory,
	transaction_service: GameItemTransactionService
) -> void:
	_item_catalog = item_catalog
	_player_item_inventory = player_item_inventory
	_item_transaction_service = transaction_service


func configure(
	material_inventory: BeachGatheringInventory,
	fishing_inventory: FishingInventory,
	tackle_catalog: FishingTackleCatalog,
	catalog: BeachCraftingCatalog
) -> void:
	_material_inventory = material_inventory
	_fishing_inventory = fishing_inventory
	_tackle_catalog = tackle_catalog
	_catalog = catalog
	_configured = true

	load_from_disk()
	_register_all_saved_lures()


func bind_loadout(loadout) -> void:
	_active_loadout = loadout


func get_active_loadout():
	return _active_loadout


func get_equipped_lure() -> BaitData:
	if _active_loadout == null:
		return null
	if not _active_loadout.has_method("get_selected_lure"):
		return null
	return _active_loadout.get_selected_lure() as BaitData


func get_property_labels(
	buoyancy: int,
	handling: int,
	attraction: int
) -> Dictionary:
	return {
		"buoyancy": _buoyancy_label(buoyancy),
		"handling": _handling_label(handling),
		"attraction": _attraction_label(attraction),
	}


func grant_qa_ab_pair() -> Dictionary:
	if not OS.is_debug_build():
		return _failure("debug_build_required")
	if _material_inventory == null:
		return _failure("inventory_unavailable")

	# A: float/control. B: deep/flash. Grant only what the pair consumes.
	var required := {
		"driftwood": 1,
		"shell": 2,
		"seaweed_fibre": 1,
		"iron_scrap": 1,
		"sea_glass": 1,
	}
	for raw_id in required.keys():
		_material_inventory.grant(
			StringName(str(raw_id)),
			int(required[raw_id]),
			false
		)
	_material_inventory.save_to_disk()

	var a: Dictionary = craft(
		&"beach_minnow",
		&"driftwood",
		&"shell",
		&"seaweed_fibre"
	)
	if not bool(a.get("success", false)):
		return {
			"success": false,
			"reason": "qa_a_failed",
			"detail": a,
		}

	var b: Dictionary = craft(
		&"beach_minnow",
		&"shell",
		&"iron_scrap",
		&"sea_glass"
	)
	if not bool(b.get("success", false)):
		return {
			"success": false,
			"reason": "qa_b_failed",
			"detail": b,
		}

	var a_id := StringName(str(a.get("lure_id", "")))
	var b_id := StringName(str(b.get("lure_id", "")))
	_set_display_name_override(
		a_id,
		"[QA A] Float / Control Minnow"
	)
	_set_display_name_override(
		b_id,
		"[QA B] Deep / Flash Minnow"
	)

	var a_lure: BaitData = get_runtime_lure(a_id)
	if (
		a_lure != null
		and _active_loadout != null
		and _active_loadout.has_method("equip_lure")
	):
		_active_loadout.call("equip_lure", a_lure)

	return {
		"success": true,
		"a_lure_id": String(a_id),
		"b_lure_id": String(b_id),
		"a_name": (
			a_lure.display_name
			if a_lure != null
			else "[QA A] Float / Control Minnow"
		),
		"b_name": (
			get_runtime_lure(b_id).display_name
			if get_runtime_lure(b_id) != null
			else "[QA B] Deep / Flash Minnow"
		),
		"a_equipped": a_lure != null and _active_loadout != null,
	}


func get_lure_attraction_reference(lure: BaitData) -> float:
	return _lure_attraction_reference(lure)


func get_lure_craft_scores(lure: BaitData) -> Dictionary:
	if lure == null or not lure.has_meta("craft_record"):
		return {}
	var raw_record = lure.get_meta("craft_record")
	if not (raw_record is Dictionary):
		return {}
	var record: Dictionary = raw_record
	return {
		"buoyancy": int(record.get("buoyancy", 0)),
		"handling": int(record.get("handling", 0)),
		"attraction": int(record.get("attraction", 0)),
	}


func get_qa_feel_suite_snapshot() -> Dictionary:
	var role_to_id: Dictionary = {}
	for record in _records:
		var existing_role: String = str(
			record.get("qa_feel_role", "")
		)
		if existing_role.is_empty():
			continue
		role_to_id[existing_role] = str(
			record.get("lure_id", "")
		)

	var pairs := {
		"buoyancy": {
			"label": "FLOAT / SINK",
			"a_id": str(role_to_id.get("buoyancy_a", "")),
			"b_id": str(role_to_id.get("buoyancy_b", "")),
		},
		"handling": {
			"label": "HEAVY / RESPONSIVE",
			"a_id": str(role_to_id.get("handling_a", "")),
			"b_id": str(role_to_id.get("handling_b", "")),
		},
		"attraction": {
			"label": "SUBTLE / FLASH",
			"a_id": str(role_to_id.get("attraction_a", "")),
			"b_id": str(role_to_id.get("attraction_b", "")),
		},
	}

	var complete: bool = true
	for pair_id in pairs.keys():
		var pair: Dictionary = pairs[pair_id]
		complete = (
			complete
			and not str(pair.get("a_id", "")).is_empty()
			and not str(pair.get("b_id", "")).is_empty()
		)

	return {
		"complete": complete,
		"pairs": pairs,
	}


func grant_qa_feel_suite() -> Dictionary:
	if not OS.is_debug_build():
		return _failure("debug_build_required")
	if _material_inventory == null or _fishing_inventory == null:
		return _failure("inventory_unavailable")

	var existing: Dictionary = get_qa_feel_suite_snapshot()
	if bool(existing.get("complete", false)):
		_ensure_qa_suite_owned(existing)
		return {
			"success": true,
			"created": false,
			"suite": existing,
		}

	var specs: Array[Dictionary] = [
		{
			"role": "buoyancy_a",
			"name": "[QA BUOY+] Float Minnow",
			"body": &"driftwood",
			"core": &"shell",
			"accent": &"",
		},
		{
			"role": "buoyancy_b",
			"name": "[QA BUOY-] Sink Minnow",
			"body": &"shell",
			"core": &"iron_scrap",
			"accent": &"seaweed_fibre",
		},
		{
			"role": "handling_a",
			"name": "[QA HANDLE-] Heavy Minnow",
			"body": &"driftwood",
			"core": &"iron_scrap",
			"accent": &"",
		},
		{
			"role": "handling_b",
			"name": "[QA HANDLE+] Responsive Minnow",
			"body": &"driftwood",
			"core": &"iron_scrap",
			"accent": &"seaweed_fibre",
		},
		{
			"role": "attraction_a",
			"name": "[QA ATTR-] Subtle Minnow",
			"body": &"driftwood",
			"core": &"iron_scrap",
			"accent": &"",
		},
		{
			"role": "attraction_b",
			"name": "[QA ATTR+] Flash Minnow",
			"body": &"driftwood",
			"core": &"iron_scrap",
			"accent": &"sea_glass",
		},
	]

	var existing_roles: Dictionary = {}
	for record in _records:
		var existing_role: String = str(
			record.get("qa_feel_role", "")
		)
		if not existing_role.is_empty():
			existing_roles[existing_role] = true

	var created_ids := PackedStringArray()
	for spec in specs:
		var requested_role: String = str(spec.get("role", ""))
		if bool(existing_roles.get(requested_role, false)):
			continue

		var body_id := StringName(str(spec.get("body", "")))
		var core_id := StringName(str(spec.get("core", "")))
		var accent_id := StringName(str(spec.get("accent", "")))
		var preview: Dictionary = preview_craft(
			&"beach_minnow",
			body_id,
			core_id,
			accent_id
		)
		if not bool(preview.get("success", false)):
			return {
				"success": false,
				"reason": "qa_preview_failed",
				"role": requested_role,
			}

		var costs = preview.get("costs", {})
		if costs is Dictionary:
			for raw_id in costs.keys():
				_material_inventory.grant(
					StringName(str(raw_id)),
					int(costs[raw_id]),
					false
				)
		_material_inventory.save_to_disk()

		var result: Dictionary = craft(
			&"beach_minnow",
			body_id,
			core_id,
			accent_id
		)
		if not bool(result.get("success", false)):
			return {
				"success": false,
				"reason": "qa_craft_failed",
				"role": requested_role,
				"detail": result,
			}

		var lure_id := StringName(str(result.get("lure_id", "")))
		_set_record_fields(
			lure_id,
			{
				"display_name_override": str(spec.get("name", "")),
				"qa_feel_role": requested_role,
			}
		)
		created_ids.append(String(lure_id))

	save_to_disk()
	var suite: Dictionary = get_qa_feel_suite_snapshot()
	_ensure_qa_suite_owned(suite)

	return {
		"success": bool(suite.get("complete", false)),
		"created": true,
		"created_ids": created_ids,
		"suite": suite,
	}


func toggle_qa_feel_pair(pair_id: StringName) -> Dictionary:
	if not OS.is_debug_build():
		return _failure("debug_build_required")
	if _active_loadout == null:
		return _failure("loadout_unavailable")

	var grant_result: Dictionary = grant_qa_feel_suite()
	if not bool(grant_result.get("success", false)):
		return grant_result

	var suite: Dictionary = get_qa_feel_suite_snapshot()
	var pairs = suite.get("pairs", {})
	if not (pairs is Dictionary):
		return _failure("qa_suite_invalid")

	var pair_key: String = String(pair_id)
	if not pairs.has(pair_key):
		return _failure("unknown_qa_pair")
	var pair: Dictionary = pairs[pair_key]

	var a_id := StringName(str(pair.get("a_id", "")))
	var b_id := StringName(str(pair.get("b_id", "")))
	var current: BaitData = get_equipped_lure()
	var current_id: StringName = &""
	if current != null:
		current_id = current.lure_id

	var next_id: StringName = (
		b_id
		if current_id == a_id
		else a_id
	)
	var lure: BaitData = get_runtime_lure(next_id)
	if lure == null:
		return _failure("qa_lure_missing")

	_active_loadout.call("equip_lure", lure)
	return {
		"success": true,
		"pair_id": pair_key,
		"pair_label": str(pair.get("label", pair_key)),
		"lure_id": String(next_id),
		"display_name": lure.display_name,
		"recast_required": true,
	}


func qa_roundtrip_preview(
	recipe_id: StringName,
	body_id: StringName,
	core_id: StringName,
	accent_id: StringName = &""
) -> Dictionary:
	if not OS.is_debug_build():
		return _failure("debug_build_required")

	var preview: Dictionary = preview_craft(
		recipe_id,
		body_id,
		core_id,
		accent_id
	)
	if not bool(preview.get("success", false)):
		return preview

	var record := {
		"lure_id": "qa_roundtrip_temp",
		"instance_number": 999999,
		"recipe_id": String(recipe_id),
		"body_id": String(body_id),
		"core_id": String(core_id),
		"accent_id": String(accent_id),
		"buoyancy": int(preview.get("buoyancy", 0)),
		"handling": int(preview.get("handling", 0)),
		"attraction": int(preview.get("attraction", 0)),
		"created_unix": 0,
	}

	var parsed = JSON.parse_string(JSON.stringify(record))
	if not (parsed is Dictionary):
		return _failure("qa_roundtrip_json_failed")

	var lure: BaitData = _build_runtime_lure(parsed as Dictionary)
	if lure == null:
		return _failure("qa_roundtrip_rebuild_failed")

	return {
		"success": true,
		"sink_depth": lure.sink_depth,
		"reel_steer_strength": lure.reel_steer_strength,
		"attraction_reference": _lure_attraction_reference(lure),
		"preview_sink_depth": float(preview.get("sink_depth", 0.0)),
		"preview_reel_steer_strength": float(
			preview.get("reel_steer_strength", 0.0)
		),
		"preview_attraction_reference": float(
			preview.get("attraction_reference", 0.0)
		),
	}


func get_catalog() -> BeachCraftingCatalog:
	return _catalog


func get_material_inventory() -> BeachGatheringInventory:
	return _material_inventory


func get_material_definition(
	material_id: StringName
) -> BeachMaterialDefinition:
	if _catalog == null:
		return null
	return _catalog.get_material(material_id)


func get_recipe(recipe_id: StringName) -> BeachCraftingRecipe:
	if _catalog == null:
		return null
	return _catalog.get_recipe(recipe_id)


func get_crafted_records() -> Array:
	var result: Array = []
	for record in _records:
		result.append(record.duplicate(true))
	return result


func get_runtime_lure(lure_id: StringName) -> BaitData:
	return _runtime_lures.get(String(lure_id), null)


func preview_craft(
	recipe_id: StringName,
	body_id: StringName,
	core_id: StringName,
	accent_id: StringName = &""
) -> Dictionary:
	if not _configured:
		return _failure("crafting_service_unconfigured")

	var recipe: BeachCraftingRecipe = get_recipe(recipe_id)
	if recipe == null:
		return _failure("unknown_recipe")

	var validation: Dictionary = _validate_selection(
		recipe,
		body_id,
		core_id,
		accent_id
	)
	if not bool(validation.get("valid", false)):
		return {
			"success": false,
			"reason": validation.get("reason", "invalid_selection"),
			"recipe_id": String(recipe_id),
		}

	var costs: Dictionary = _build_costs(
		body_id,
		core_id,
		accent_id
	)
	var scores: Dictionary = _compute_scores(
		recipe,
		body_id,
		core_id,
		accent_id
	)
	var physical: Dictionary = _compute_physical_preview(
		recipe,
		scores
	)

	var labels: Dictionary = get_property_labels(
		int(scores["buoyancy"]),
		int(scores["handling"]),
		int(scores["attraction"])
	)
	var actual_attraction: float = _preview_actual_attraction(
		recipe,
		physical
	)

	return {
		"success": true,
		"recipe_id": String(recipe_id),
		"recipe_name": recipe.display_name,
		"body_id": String(body_id),
		"core_id": String(core_id),
		"accent_id": String(accent_id),
		"costs": costs,
		"can_afford": _can_afford_material_costs(costs),
		"buoyancy": int(scores["buoyancy"]),
		"handling": int(scores["handling"]),
		"attraction": int(scores["attraction"]),
		"buoyancy_label": str(labels.get("buoyancy", "")),
		"handling_label": str(labels.get("handling", "")),
		"attraction_label": str(labels.get("attraction", "")),
		"sink_depth": float(physical["sink_depth"]),
		"sink_speed": float(physical["sink_speed"]),
		"reel_steer_strength": float(physical["reel_steer_strength"]),
		"reel_speed": float(physical["reel_speed"]),
		"attraction_multiplier": float(physical["attraction_multiplier"]),
		"attraction_reference": actual_attraction,
		"property_text": _property_text(scores),
		"equipped_comparison": _equipped_comparison(
			physical,
			actual_attraction
		),
	}


func craft(
	recipe_id: StringName,
	body_id: StringName,
	core_id: StringName,
	accent_id: StringName = &""
) -> Dictionary:
	var preview: Dictionary = preview_craft(
		recipe_id,
		body_id,
		core_id,
		accent_id
	)
	if not bool(preview.get("success", false)):
		return preview
	if not bool(preview.get("can_afford", false)):
		preview["success"] = false
		preview["reason"] = "missing_materials"
		return preview
	if (
		_player_item_inventory == null
		or _item_transaction_service == null
		or _fishing_inventory == null
	):
		return _failure("item_backend_unavailable")

	var canonical_costs: Dictionary = _canonical_material_costs(
		preview.get("costs", {})
	)
	if canonical_costs.is_empty():
		return _failure("material_cost_mapping_failed")

	var player_snapshot: Dictionary = (
		_player_item_inventory.create_transaction_snapshot()
	)
	var fishing_snapshot: Dictionary = (
		_fishing_inventory.create_transaction_snapshot()
	)
	var records_snapshot: Array[Dictionary] = []
	for existing_record in _records:
		records_snapshot.append(
			existing_record.duplicate(true)
		)
	var next_instance_snapshot: int = _next_instance_number

	var consume_result: Dictionary = (
		_item_transaction_service.consume_player_items(
			canonical_costs,
			false,
			&"beach_crafting"
		)
	)
	if not bool(consume_result.get("success", false)):
		return {
			"success": false,
			"reason": "material_consume_failed",
			"missing": consume_result.get("missing", {}),
		}

	var lure_id := StringName(
		"crafted_%s_%03d"
		% [String(recipe_id), _next_instance_number]
	)
	_next_instance_number += 1

	var record := {
		"lure_id": String(lure_id),
		"instance_number": _next_instance_number - 1,
		"recipe_id": String(recipe_id),
		"body_id": String(body_id),
		"core_id": String(core_id),
		"accent_id": String(accent_id),
		"buoyancy": int(preview["buoyancy"]),
		"handling": int(preview["handling"]),
		"attraction": int(preview["attraction"]),
		"created_unix": int(Time.get_unix_time_from_system()),
	}
	_records.append(record)

	var lure: BaitData = _build_runtime_lure(record)
	if lure == null:
		_restore_craft_transaction(
			player_snapshot,
			fishing_snapshot,
			records_snapshot,
			next_instance_snapshot,
			false
		)
		return _failure("runtime_lure_build_failed")

	var lure_count_after: int = _fishing_inventory.grant_lure(
		lure,
		1,
		false
	)
	if lure_count_after <= 0:
		_restore_craft_transaction(
			player_snapshot,
			fishing_snapshot,
			records_snapshot,
			next_instance_snapshot,
			false
		)
		return _failure("lure_grant_failed")

	if not save_to_disk():
		_restore_craft_transaction(
			player_snapshot,
			fishing_snapshot,
			records_snapshot,
			next_instance_snapshot,
			false
		)
		return _failure("crafted_record_save_failed")

	if not _player_item_inventory.commit_changes():
		_restore_craft_transaction(
			player_snapshot,
			fishing_snapshot,
			records_snapshot,
			next_instance_snapshot,
			true
		)
		return _failure("material_save_failed")

	if not _fishing_inventory.commit_changes():
		_restore_craft_transaction(
			player_snapshot,
			fishing_snapshot,
			records_snapshot,
			next_instance_snapshot,
			true
		)
		return _failure("fishing_inventory_save_failed")

	# Register presentation/runtime data only after all persistent stores agree.
	_register_runtime_lure(lure)

	var result: Dictionary = preview.duplicate(true)
	result["success"] = true
	result["reason"] = "completed"
	result["lure_id"] = String(lure_id)
	result["display_name"] = lure.display_name
	result["record"] = record.duplicate(true)
	result["lure_count_after"] = lure_count_after
	crafted_lure_created.emit(
		lure,
		record.duplicate(true)
	)
	return result




func _canonical_material_costs(costs: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if _item_catalog == null:
		return result

	for raw_id in costs.keys():
		var definition: GameItemDefinition = _item_catalog.get_by_domain(
			GameItemCatalogService.STORAGE_PLAYER,
			StringName(str(raw_id))
		)
		if (
			definition == null
			or definition.category
			!= GameItemCatalogService.CATEGORY_MATERIALS
		):
			return {}
		result[String(definition.item_id)] = maxi(
			0,
			int(costs[raw_id])
		)
	return result


func _can_afford_material_costs(costs: Dictionary) -> bool:
	if (
		_item_transaction_service != null
		and _player_item_inventory != null
	):
		var canonical: Dictionary = _canonical_material_costs(costs)
		if canonical.is_empty() and not costs.is_empty():
			return false
		var evaluation: Dictionary = (
			_item_transaction_service.evaluate_player_costs(
				canonical
			)
		)
		return bool(evaluation.get("can_afford", false))

	if _material_inventory == null:
		return false
	return _material_inventory.can_afford(costs)


func _restore_craft_transaction(
	player_snapshot: Dictionary,
	fishing_snapshot: Dictionary,
	records_snapshot: Array[Dictionary],
	next_instance_snapshot: int,
	rewrite_disk: bool
) -> void:
	_records.clear()
	for old_record in records_snapshot:
		_records.append(old_record.duplicate(true))
	_next_instance_number = maxi(
		1,
		next_instance_snapshot
	)

	_player_item_inventory.restore_transaction_snapshot(
		player_snapshot,
		false
	)
	_fishing_inventory.restore_transaction_snapshot(
		fishing_snapshot
	)

	if rewrite_disk:
		# One of the stores may already have committed before a later store
		# failed. Rewrite all restored snapshots so disk converges too.
		save_to_disk()
		_player_item_inventory.save_to_disk()
		_fishing_inventory.save_to_disk()


func grant_qa_material_bundle(amount: int = 10) -> Dictionary:
	var result := {
		"success": false,
		"granted_each": 0,
	}
	if not OS.is_debug_build():
		result["reason"] = "debug_build_required"
		return result
	if _catalog == null or _material_inventory == null:
		result["reason"] = "crafting_unavailable"
		return result

	var clean_amount: int = maxi(1, amount)
	for material in _catalog.materials:
		if material == null:
			continue
		_material_inventory.grant(
			material.material_id,
			clean_amount,
			false
		)
	_material_inventory.save_to_disk()
	result["success"] = true
	result["granted_each"] = clean_amount
	return result


func get_debug_snapshot() -> Dictionary:
	return {
		"configured": _configured,
		"crafted_count": _records.size(),
		"next_instance_number": _next_instance_number,
		"materials": (
			_material_inventory.get_snapshot()
			if _material_inventory != null
			else {}
		),
		"records": get_crafted_records(),
	}


func save_to_disk() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(
		JSON.stringify(
			{
				"version": SAVE_VERSION,
				"next_instance_number": _next_instance_number,
				"records": _records,
			},
			"\t"
		)
	)
	file.close()
	return true


func load_from_disk() -> bool:
	_records.clear()
	_runtime_lures.clear()
	_next_instance_number = 1

	if not FileAccess.file_exists(SAVE_PATH):
		return true

	var parsed = JSON.parse_string(
		FileAccess.get_file_as_string(SAVE_PATH)
	)
	if not (parsed is Dictionary):
		push_warning("BeachCraftingService: crafted-lure save is invalid.")
		return false

	var data: Dictionary = parsed
	_next_instance_number = maxi(
		1,
		int(data.get("next_instance_number", 1))
	)

	var raw_records = data.get("records", [])
	if raw_records is Array:
		for raw_record in raw_records:
			if not (raw_record is Dictionary):
				continue
			var record: Dictionary = (
				raw_record as Dictionary
			).duplicate(true)
			if str(record.get("lure_id", "")).is_empty():
				continue
			_records.append(record)
	return true


func _register_all_saved_lures() -> void:
	var registered: int = 0
	for record in _records:
		var lure: BaitData = _build_runtime_lure(record)
		if lure == null:
			continue
		_register_runtime_lure(lure)
		registered += 1
	crafted_lures_reloaded.emit(registered)


func _register_runtime_lure(lure: BaitData) -> void:
	if lure == null or _tackle_catalog == null:
		return
	if _tackle_catalog.lure_catalog == null:
		return

	_runtime_lures[String(lure.lure_id)] = lure
	if _item_catalog != null:
		_item_catalog.register_dynamic_lure(lure)

	for existing in _tackle_catalog.lure_catalog.lures:
		if existing != null and existing.lure_id == lure.lure_id:
			return
	_tackle_catalog.lure_catalog.lures.append(lure)


func _build_runtime_lure(record: Dictionary) -> BaitData:
	if _catalog == null or _tackle_catalog == null:
		return null

	var recipe := _catalog.get_recipe(
		StringName(str(record.get("recipe_id", "")))
	)
	if recipe == null:
		return null

	var template: BaitData = _tackle_catalog.get_lure_by_id(
		recipe.template_lure_id
	)
	if template == null:
		return null

	var lure := template.duplicate(true) as BaitData
	if lure == null:
		return null

	var lure_id := StringName(str(record.get("lure_id", "")))
	if lure_id == &"":
		return null

	var body_id := StringName(str(record.get("body_id", "")))
	var core_id := StringName(str(record.get("core_id", "")))
	var accent_id := StringName(str(record.get("accent_id", "")))

	var scores := {
		"buoyancy": clampi(
			int(record.get("buoyancy", recipe.base_buoyancy)),
			SCORE_MIN,
			SCORE_MAX
		),
		"handling": clampi(
			int(record.get("handling", recipe.base_handling)),
			SCORE_MIN,
			SCORE_MAX
		),
		"attraction": clampi(
			int(record.get("attraction", recipe.base_attraction)),
			SCORE_MIN,
			SCORE_MAX
		),
	}
	var physical: Dictionary = _compute_physical_preview(
		recipe,
		scores
	)

	lure.lure_id = lure_id
	var display_override: String = str(
		record.get("display_name_override", "")
	)
	if not display_override.is_empty():
		lure.display_name = display_override
	else:
		# Instance numbering belongs in the internal lure_id only.
		# The player-facing lure name stays clean even when several copies exist.
		lure.display_name = recipe.display_name
	lure.level = 1
	lure.description = _crafted_description(
		recipe,
		body_id,
		core_id,
		accent_id,
		scores
	)
	lure.sink_depth = float(physical["sink_depth"])
	lure.sink_speed = float(physical["sink_speed"])
	lure.reel_steer_strength = float(
		physical["reel_steer_strength"]
	)
	lure.reel_speed = float(physical["reel_speed"])

	if lure.action_profile != null:
		lure.action_profile = lure.action_profile.duplicate(true)
		var attraction_multiplier: float = float(
			physical["attraction_multiplier"]
		)
		lure.action_profile.idle_attraction_multiplier = clampf(
			lure.action_profile.idle_attraction_multiplier
			* attraction_multiplier,
			0.10,
			2.0
		)
		lure.action_profile.reel_attraction_multiplier = clampf(
			lure.action_profile.reel_attraction_multiplier
			* attraction_multiplier,
			0.10,
			2.0
		)

	var accent: BeachMaterialDefinition = get_material_definition(
		accent_id
	)
	if accent != null:
		lure.visual_tint = lure.visual_tint.lerp(
			accent.visual_tint,
			0.35
		)
	else:
		var body: BeachMaterialDefinition = get_material_definition(
			body_id
		)
		if body != null:
			lure.visual_tint = lure.visual_tint.lerp(
				body.visual_tint,
				0.20
			)

	lure.set_meta("crafted_lure", true)
	lure.set_meta("craft_record", record.duplicate(true))
	lure.set_meta("craft_property_text", _property_text(scores))
	return lure


func _compute_scores(
	recipe: BeachCraftingRecipe,
	body_id: StringName,
	core_id: StringName,
	accent_id: StringName
) -> Dictionary:
	var buoyancy: int = recipe.base_buoyancy
	var handling: int = recipe.base_handling
	var attraction: int = recipe.base_attraction

	for material_id in [body_id, core_id, accent_id]:
		if material_id == &"":
			continue
		var material: BeachMaterialDefinition = get_material_definition(
			material_id
		)
		if material == null:
			continue
		buoyancy += material.buoyancy_delta
		handling += material.handling_delta
		attraction += material.attraction_delta

	return {
		"buoyancy": clampi(buoyancy, SCORE_MIN, SCORE_MAX),
		"handling": clampi(handling, SCORE_MIN, SCORE_MAX),
		"attraction": clampi(attraction, SCORE_MIN, SCORE_MAX),
	}


func _compute_physical_preview(
	recipe: BeachCraftingRecipe,
	scores: Dictionary
) -> Dictionary:
	var template: BaitData = null
	if _tackle_catalog != null:
		template = _tackle_catalog.get_lure_by_id(
			recipe.template_lure_id
		)
	if template == null:
		return {
			"sink_depth": 0.5,
			"sink_speed": 0.2,
			"reel_steer_strength": 0.8,
			"reel_speed": 0.05,
			"attraction_multiplier": 1.0,
		}

	var buoyancy: int = int(scores.get("buoyancy", 0))
	var handling: int = int(scores.get("handling", 0))
	var attraction: int = int(scores.get("attraction", 0))

	var depth: float = clampf(
		template.sink_depth - float(buoyancy) * 0.07,
		0.02,
		0.95
	)
	var sink_speed_multiplier: float = clampf(
		1.0 - float(buoyancy) * 0.08,
		0.55,
		1.45
	)
	var handling_multiplier: float = clampf(
		1.0 + float(handling) * 0.07,
		0.72,
		1.28
	)
	var reel_speed_multiplier: float = clampf(
		1.0 + float(handling) * 0.025,
		0.88,
		1.12
	)
	var attraction_multiplier: float = clampf(
		1.0 + float(attraction) * 0.07,
		0.72,
		1.28
	)

	return {
		"sink_depth": depth,
		"sink_speed": clampf(
			template.sink_speed * sink_speed_multiplier,
			0.02,
			0.50
		),
		"reel_steer_strength": clampf(
			template.reel_steer_strength * handling_multiplier,
			0.35,
			1.35
		),
		"reel_speed": clampf(
			template.reel_speed * reel_speed_multiplier,
			0.02,
			0.09
		),
		"attraction_multiplier": attraction_multiplier,
	}


func _validate_selection(
	recipe: BeachCraftingRecipe,
	body_id: StringName,
	core_id: StringName,
	accent_id: StringName
) -> Dictionary:
	if body_id == &"" or not recipe.allows_material(
		&"body",
		body_id
	):
		return {"valid": false, "reason": "invalid_body"}
	if core_id == &"" or not recipe.allows_material(
		&"core",
		core_id
	):
		return {"valid": false, "reason": "invalid_core"}
	if not recipe.allows_material(&"accent", accent_id):
		return {"valid": false, "reason": "invalid_accent"}
	return {"valid": true}


func _build_costs(
	body_id: StringName,
	core_id: StringName,
	accent_id: StringName
) -> Dictionary:
	var costs: Dictionary = {}
	for material_id in [body_id, core_id, accent_id]:
		if material_id == &"":
			continue
		var key: String = String(material_id)
		costs[key] = int(costs.get(key, 0)) + 1
	return costs


func _crafted_description(
	recipe: BeachCraftingRecipe,
	body_id: StringName,
	core_id: StringName,
	accent_id: StringName,
	scores: Dictionary
) -> String:
	var body_name: String = _material_name(body_id)
	var core_name: String = _material_name(core_id)
	var accent_name: String = (
		_material_name(accent_id)
		if accent_id != &""
		else "None"
	)
	return (
		"%s\nBody: %s  Core: %s  Accent: %s\n%s"
		% [
			recipe.description,
			body_name,
			core_name,
			accent_name,
			_property_text(scores),
		]
	)


func _material_name(material_id: StringName) -> String:
	var material: BeachMaterialDefinition = get_material_definition(
		material_id
	)
	return (
		material.display_name
		if material != null
		else String(material_id)
	)


func _property_text(scores: Dictionary) -> String:
	return "Buoyancy %s   Handling %s   Attraction %s" % [
		_score_text(int(scores.get("buoyancy", 0))),
		_score_text(int(scores.get("handling", 0))),
		_score_text(int(scores.get("attraction", 0))),
	]


func _score_text(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return str(value)


func _set_record_fields(
	lure_id: StringName,
	fields: Dictionary
) -> void:
	var clean_id: String = String(lure_id)
	if clean_id.is_empty():
		return

	var updated_record: Dictionary = {}
	for index in range(_records.size()):
		if str(_records[index].get("lure_id", "")) != clean_id:
			continue
		for raw_key in fields.keys():
			_records[index][str(raw_key)] = fields[raw_key]
		updated_record = _records[index].duplicate(true)
		break

	var lure: BaitData = get_runtime_lure(lure_id)
	if lure != null:
		if fields.has("display_name_override"):
			lure.display_name = str(fields["display_name_override"])
		if not updated_record.is_empty():
			lure.set_meta(
				"craft_record",
				updated_record.duplicate(true)
			)


func _ensure_qa_suite_owned(suite: Dictionary) -> void:
	if _fishing_inventory == null:
		return
	var raw_pairs = suite.get("pairs", {})
	if not (raw_pairs is Dictionary):
		return

	for raw_pair in raw_pairs.values():
		if not (raw_pair is Dictionary):
			continue
		var pair: Dictionary = raw_pair
		for key in ["a_id", "b_id"]:
			var lure_id := StringName(str(pair.get(key, "")))
			if lure_id == &"":
				continue
			var lure: BaitData = get_runtime_lure(lure_id)
			if lure == null:
				continue
			if not _fishing_inventory.owns_lure(lure):
				_fishing_inventory.grant_lure(
					lure,
					1,
					true
				)


func _set_display_name_override(
	lure_id: StringName,
	display_name: String
) -> void:
	var clean_id: String = String(lure_id)
	if clean_id.is_empty():
		return
	for index in range(_records.size()):
		if str(_records[index].get("lure_id", "")) != clean_id:
			continue
		_records[index]["display_name_override"] = display_name
		break
	var lure: BaitData = get_runtime_lure(lure_id)
	if lure != null:
		lure.display_name = display_name
	save_to_disk()


func _equipped_comparison(
	physical: Dictionary,
	actual_attraction: float
) -> Dictionary:
	var lure: BaitData = get_equipped_lure()
	if lure == null:
		return {
			"available": false,
		}

	var current_attraction: float = _lure_attraction_reference(lure)
	return {
		"available": true,
		"lure_id": String(lure.lure_id),
		"display_name": lure.display_name,
		"current_depth": lure.sink_depth,
		"preview_depth": float(physical.get("sink_depth", lure.sink_depth)),
		"depth_delta": (
			float(physical.get("sink_depth", lure.sink_depth))
			- lure.sink_depth
		),
		"current_steer": lure.reel_steer_strength,
		"preview_steer": float(
			physical.get(
				"reel_steer_strength",
				lure.reel_steer_strength
			)
		),
		"steer_delta": (
			float(
				physical.get(
					"reel_steer_strength",
					lure.reel_steer_strength
				)
			)
			- lure.reel_steer_strength
		),
		"current_attraction": current_attraction,
		"preview_attraction": actual_attraction,
		"attraction_delta": actual_attraction - current_attraction,
	}


func _preview_actual_attraction(
	recipe: BeachCraftingRecipe,
	physical: Dictionary
) -> float:
	if _tackle_catalog == null:
		return float(physical.get("attraction_multiplier", 1.0))
	var template: BaitData = _tackle_catalog.get_lure_by_id(
		recipe.template_lure_id
	)
	if template == null:
		return float(physical.get("attraction_multiplier", 1.0))
	return (
		_lure_attraction_reference(template)
		* float(physical.get("attraction_multiplier", 1.0))
	)


func _lure_attraction_reference(lure: BaitData) -> float:
	if lure == null or lure.action_profile == null:
		return 1.0
	return (
		lure.action_profile.idle_attraction_multiplier
		+ lure.action_profile.reel_attraction_multiplier
	) * 0.5


func _buoyancy_label(value: int) -> String:
	if value <= -3:
		return "Deep sink"
	if value <= -1:
		return "Sinking"
	if value == 0:
		return "Neutral"
	if value <= 2:
		return "Buoyant"
	return "High float"


func _handling_label(value: int) -> String:
	if value <= -3:
		return "Heavy"
	if value <= -1:
		return "Slower control"
	if value == 0:
		return "Balanced"
	if value <= 2:
		return "Responsive"
	return "Very responsive"


func _attraction_label(value: int) -> String:
	if value <= -2:
		return "Subtle"
	if value <= 0:
		return "Normal"
	if value <= 2:
		return "Noticeable"
	return "High visibility"


func _failure(reason: String) -> Dictionary:
	return {
		"success": false,
		"reason": reason,
	}
