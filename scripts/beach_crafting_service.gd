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

	return {
		"success": true,
		"recipe_id": String(recipe_id),
		"recipe_name": recipe.display_name,
		"body_id": String(body_id),
		"core_id": String(core_id),
		"accent_id": String(accent_id),
		"costs": costs,
		"can_afford": (
			_material_inventory != null
			and _material_inventory.can_afford(costs)
		),
		"buoyancy": int(scores["buoyancy"]),
		"handling": int(scores["handling"]),
		"attraction": int(scores["attraction"]),
		"sink_depth": float(physical["sink_depth"]),
		"sink_speed": float(physical["sink_speed"]),
		"reel_steer_strength": float(physical["reel_steer_strength"]),
		"reel_speed": float(physical["reel_speed"]),
		"attraction_multiplier": float(physical["attraction_multiplier"]),
		"property_text": _property_text(scores),
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
	if _material_inventory == null or _fishing_inventory == null:
		return _failure("inventory_unavailable")

	var consume_result: Dictionary = _material_inventory.consume_costs(
		preview.get("costs", {}),
		false
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
		# Roll the material spend back if the runtime lure could not be built.
		for raw_id in preview.get("costs", {}).keys():
			_material_inventory.grant(
				StringName(str(raw_id)),
				int(preview["costs"][raw_id]),
				false
			)
		_records.pop_back()
		_next_instance_number = maxi(1, _next_instance_number - 1)
		return _failure("runtime_lure_build_failed")

	_register_runtime_lure(lure)
	if not save_to_disk():
		push_warning("BeachCraftingService: crafted lure record could not be saved.")

	_material_inventory.save_to_disk()
	_fishing_inventory.grant_lure(lure, 1, true)

	var result: Dictionary = preview.duplicate(true)
	result["success"] = true
	result["reason"] = ""
	result["lure_id"] = String(lure_id)
	result["display_name"] = lure.display_name
	result["record"] = record.duplicate(true)
	crafted_lure_created.emit(lure, record.duplicate(true))
	return result


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
	lure.display_name = "%s #%03d" % [
		recipe.display_name,
		int(record.get("instance_number", 1)),
	]
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


func _failure(reason: String) -> Dictionary:
	return {
		"success": false,
		"reason": reason,
	}
