extends RefCounted
class_name BeachCraftingQA

const BeachGatheringInventoryScript = preload(
	"res://scripts/beach_gathering_inventory.gd"
)
const BeachGatheringCircuitScene = preload(
	"res://actors/BeachGatheringCircuit.tscn"
)


static func run(
	catalog: BeachCraftingCatalog,
	service: BeachCraftingService,
	tackle_catalog: FishingTackleCatalog
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
		"warnings": PackedStringArray(),
		"matrix_combination_count": 0,
		"recipe_metrics": {},
	}

	_test_integrity(report, catalog, tackle_catalog)
	_test_full_recipe_matrix(report, catalog, service)
	_test_material_identity(report, service)
	_test_duplicate_material_cost(report, service)
	_test_inventory_atomicity(report)
	_test_beach_circuit_economy(report)
	_test_ab_lure_separation(report, service)
	_test_readable_property_labels(report, service)
	_test_buoyancy_isolation(report, service)
	_test_handling_isolation(report, service)
	_test_attraction_isolation(report, service)
	_test_crafted_record_roundtrip(report, service)

	report["valid"] = (
		int(report["passed_count"]) == int(report["test_count"])
		and (report["failures"] as PackedStringArray).is_empty()
	)
	return report


static func _test_integrity(
	report: Dictionary,
	catalog: BeachCraftingCatalog,
	tackle_catalog: FishingTackleCatalog
) -> void:
	var audit: Dictionary = BeachCraftingIntegrity.audit(
		catalog,
		tackle_catalog
	)
	_record(
		report,
		"Catalog integrity",
		bool(audit.get("valid", false)),
		str(audit.get("errors", PackedStringArray()))
	)
	for warning in audit.get("warnings", PackedStringArray()):
		(report["warnings"] as PackedStringArray).append(str(warning))


static func _test_full_recipe_matrix(
	report: Dictionary,
	catalog: BeachCraftingCatalog,
	service: BeachCraftingService
) -> void:
	if catalog == null or service == null:
		_record(report, "Recipe matrix", false, "Crafting service/catalog unavailable.")
		return

	var every_preview_valid: bool = true
	var no_dead_choices: bool = true
	var physical_bounds_valid: bool = true
	var failure_details := PackedStringArray()
	var total_combinations: int = 0

	for recipe in catalog.recipes:
		if recipe == null:
			continue
		var signatures: Dictionary = {}
		var recipe_count: int = 0
		var min_depth: float = INF
		var max_depth: float = -INF
		var min_steer: float = INF
		var max_steer: float = -INF
		var min_attraction: float = INF
		var max_attraction: float = -INF

		var accents: Array = []
		if recipe.accent_optional:
			accents.append(&"")
		for raw_accent in recipe.accent_material_ids:
			accents.append(StringName(str(raw_accent)))

		for raw_body in recipe.body_material_ids:
			var body_id := StringName(str(raw_body))
			for raw_core in recipe.core_material_ids:
				var core_id := StringName(str(raw_core))
				for raw_accent in accents:
					var accent_id := StringName(str(raw_accent))
					var preview: Dictionary = service.preview_craft(
						recipe.recipe_id,
						body_id,
						core_id,
						accent_id
					)
					total_combinations += 1
					recipe_count += 1

					if not bool(preview.get("success", false)):
						every_preview_valid = false
						failure_details.append(
							"%s failed %s/%s/%s: %s"
							% [
								String(recipe.recipe_id),
								String(body_id),
								String(core_id),
								String(accent_id),
								str(preview.get("reason", "unknown")),
							]
						)
						continue

					var signature: String = "%d|%d|%d" % [
						int(preview.get("buoyancy", 0)),
						int(preview.get("handling", 0)),
						int(preview.get("attraction", 0)),
					]
					if signatures.has(signature):
						no_dead_choices = false
						failure_details.append(
							"%s has duplicate outcome %s for %s/%s/%s and %s"
							% [
								String(recipe.recipe_id),
								signature,
								String(body_id),
								String(core_id),
								String(accent_id),
								str(signatures[signature]),
							]
						)
					else:
						signatures[signature] = "%s/%s/%s" % [
							String(body_id),
							String(core_id),
							String(accent_id),
						]

					var depth: float = float(preview.get("sink_depth", -1.0))
					var steer: float = float(preview.get("reel_steer_strength", -1.0))
					var attraction: float = float(
						preview.get("attraction_multiplier", -1.0)
					)
					if (
						depth < 0.02
						or depth > 0.95
						or steer < 0.35
						or steer > 1.35
						or attraction < 0.72
						or attraction > 1.28
					):
						physical_bounds_valid = false
						failure_details.append(
							"%s physical output out of bounds for %s/%s/%s"
							% [
								String(recipe.recipe_id),
								String(body_id),
								String(core_id),
								String(accent_id),
							]
						)

					min_depth = minf(min_depth, depth)
					max_depth = maxf(max_depth, depth)
					min_steer = minf(min_steer, steer)
					max_steer = maxf(max_steer, steer)
					min_attraction = minf(min_attraction, attraction)
					max_attraction = maxf(max_attraction, attraction)

		var meaningful_spread: bool = (
			max_depth - min_depth >= 0.10
			or max_steer - min_steer >= 0.08
			or max_attraction - min_attraction >= 0.08
		)
		if not meaningful_spread:
			no_dead_choices = false
			failure_details.append(
				"%s material matrix has too little physical spread."
				% String(recipe.recipe_id)
			)

		report["recipe_metrics"][String(recipe.recipe_id)] = {
			"combination_count": recipe_count,
			"unique_score_outcomes": signatures.size(),
			"sink_depth_min": min_depth,
			"sink_depth_max": max_depth,
			"steer_min": min_steer,
			"steer_max": max_steer,
			"attraction_multiplier_min": min_attraction,
			"attraction_multiplier_max": max_attraction,
		}

	report["matrix_combination_count"] = total_combinations
	_record(
		report,
		"All legal recipe combinations preview",
		every_preview_valid,
		"\n".join(failure_details)
	)
	_record(
		report,
		"Every material choice has a distinct result",
		no_dead_choices,
		"\n".join(failure_details)
	)
	_record(
		report,
		"Crafted physical outputs stay in supported bounds",
		physical_bounds_valid,
		"\n".join(failure_details)
	)


static func _test_material_identity(
	report: Dictionary,
	service: BeachCraftingService
) -> void:
	if service == null:
		_record(report, "Material identity", false, "Crafting service unavailable.")
		return

	var driftwood: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"shell",
		&""
	)
	var shell: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"shell",
		&"shell",
		&""
	)
	var iron: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"shell",
		&"iron_scrap",
		&""
	)
	var glass: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"iron_scrap",
		&"sea_glass"
	)
	var fibre: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"iron_scrap",
		&"seaweed_fibre"
	)
	var neutral: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"iron_scrap",
		&""
	)

	var valid: bool = (
		bool(driftwood.get("success", false))
		and bool(shell.get("success", false))
		and bool(iron.get("success", false))
		and bool(glass.get("success", false))
		and bool(fibre.get("success", false))
		and bool(neutral.get("success", false))
		and int(driftwood.get("buoyancy", 0)) > int(shell.get("buoyancy", 0))
		and int(iron.get("buoyancy", 0)) < int(shell.get("buoyancy", 0))
		and int(glass.get("attraction", 0)) > int(neutral.get("attraction", 0))
		and int(fibre.get("handling", 0)) > int(neutral.get("handling", 0))
	)
	_record(
		report,
		"Material identities affect intended lure properties",
		valid,
		"Driftwood should float, iron should dive, glass should attract, fibre should handle."
	)


static func _test_duplicate_material_cost(
	report: Dictionary,
	service: BeachCraftingService
) -> void:
	var preview: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"shell",
		&"shell",
		&""
	)
	var costs: Dictionary = preview.get("costs", {})
	_record(
		report,
		"Repeated material slots consume repeated quantity",
		bool(preview.get("success", false))
		and int(costs.get("shell", 0)) == 2,
		"Shell body + shell core must cost 2 Shell."
	)


static func _test_inventory_atomicity(report: Dictionary) -> void:
	var inventory = BeachGatheringInventoryScript.new()
	inventory.reset_all(false)
	inventory.grant(&"driftwood", 1, false)

	var failed: Dictionary = inventory.consume_costs(
		{
			"driftwood": 2,
			"shell": 1,
		},
		false
	)
	var failure_preserved: bool = (
		not bool(failed.get("success", false))
		and inventory.get_count(&"driftwood") == 1
		and inventory.get_count(&"shell") == 0
	)

	inventory.grant(&"driftwood", 1, false)
	inventory.grant(&"shell", 1, false)
	var success: Dictionary = inventory.consume_costs(
		{
			"driftwood": 2,
			"shell": 1,
		},
		false
	)
	var success_consumed: bool = (
		bool(success.get("success", false))
		and inventory.get_count(&"driftwood") == 0
		and inventory.get_count(&"shell") == 0
	)

	_record(
		report,
		"Material spending is atomic",
		failure_preserved and success_consumed,
		"Failed costs must consume nothing; successful costs must consume exactly once."
	)
	inventory.free()


static func _test_beach_circuit_economy(
	report: Dictionary
) -> void:
	var circuit = BeachGatheringCircuitScene.instantiate()
	if circuit == null or not circuit.has_method("get_yield_snapshot"):
		_record(
			report,
			"Beach circuit supports three starter crafts",
			false,
			"Gathering circuit could not be instantiated."
		)
		return

	# The circuit script populates its cache on _ready(), which is not called
	# for an unattached QA instance, so inspect the authored gather children
	# directly here.
	var yields: Dictionary = {}
	var required := {
		"driftwood": 2,
		"shell": 2,
		"seaweed_fibre": 2,
		"iron_scrap": 2,
		"sea_glass": 1,
	}
	var descendants := circuit.find_children(
		"*",
		"",
		true,
		false
	)
	var starter_crafting_node_count: int = 0
	for raw_node in descendants:
		if not (raw_node is BeachGatheringNode3D):
			continue
		var node := raw_node as BeachGatheringNode3D
		var key: String = String(node.material_id)
		yields[key] = int(yields.get(key, 0)) + maxi(1, node.amount)
		if required.has(key):
			starter_crafting_node_count += 1

	# The beach circuit is allowed to grow with gathering resources that do
	# not belong to the original lure-crafting slice (for example herbs).
	# Keep this regression focused on the ten authored starter crafting nodes.
	var enough: bool = starter_crafting_node_count == 10
	for material_id in required.keys():
		enough = (
			enough
			and int(yields.get(material_id, 0))
			>= int(required[material_id])
		)

	_record(
		report,
		"Beach circuit supports three starter crafts",
		enough,
		"Expected 10 deterministic starter lure-material nodes and enough resources for Surface + Sinker + Minnow test crafts; unrelated gathering nodes must not invalidate this test."
	)
	circuit.free()


static func _test_ab_lure_separation(
	report: Dictionary,
	service: BeachCraftingService
) -> void:
	var a: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"shell",
		&"seaweed_fibre"
	)
	var b: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"shell",
		&"iron_scrap",
		&"sea_glass"
	)

	var separated: bool = (
		bool(a.get("success", false))
		and bool(b.get("success", false))
		and float(a.get("sink_depth", 1.0))
			< float(b.get("sink_depth", 0.0))
		and float(a.get("reel_steer_strength", 0.0))
			> float(b.get("reel_steer_strength", 0.0))
		and float(a.get("attraction_reference", 0.0))
			< float(b.get("attraction_reference", 0.0))
	)
	_record(
		report,
		"QA A/B Minnows separate depth, handling and attraction",
		separated,
		"A should be shallower/more controllable; B should dive deeper and attract more."
	)


static func _test_readable_property_labels(
	report: Dictionary,
	service: BeachCraftingService
) -> void:
	var preview: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"iron_scrap",
		&"sea_glass"
	)
	var valid: bool = (
		bool(preview.get("success", false))
		and not str(preview.get("buoyancy_label", "")).is_empty()
		and not str(preview.get("handling_label", "")).is_empty()
		and not str(preview.get("attraction_label", "")).is_empty()
	)
	_record(
		report,
		"Craft preview exposes readable property labels",
		valid,
		"Every valid craft preview should explain the three scores in words."
	)


static func _test_buoyancy_isolation(
	report: Dictionary,
	service: BeachCraftingService
) -> void:
	var floating: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"shell",
		&""
	)
	var sinking: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"shell",
		&"iron_scrap",
		&"seaweed_fibre"
	)

	var isolated: bool = (
		bool(floating.get("success", false))
		and bool(sinking.get("success", false))
		and int(floating.get("handling", 999))
			== int(sinking.get("handling", -999))
		and int(floating.get("attraction", 999))
			== int(sinking.get("attraction", -999))
		and int(floating.get("buoyancy", 0))
			> int(sinking.get("buoyancy", 0))
		and float(floating.get("sink_depth", 1.0))
			< float(sinking.get("sink_depth", 0.0))
	)
	_record(
		report,
		"Buoyancy QA pair isolates depth",
		isolated,
		"Float/Sink pair must keep Handling and Attraction equal while only Buoyancy/depth changes."
	)


static func _test_handling_isolation(
	report: Dictionary,
	service: BeachCraftingService
) -> void:
	var heavy: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"iron_scrap",
		&""
	)
	var responsive: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"iron_scrap",
		&"seaweed_fibre"
	)

	var isolated: bool = (
		bool(heavy.get("success", false))
		and bool(responsive.get("success", false))
		and int(heavy.get("buoyancy", 999))
			== int(responsive.get("buoyancy", -999))
		and int(heavy.get("attraction", 999))
			== int(responsive.get("attraction", -999))
		and int(heavy.get("handling", 0))
			< int(responsive.get("handling", 0))
		and float(heavy.get("reel_steer_strength", 99.0))
			< float(responsive.get("reel_steer_strength", -99.0))
	)
	_record(
		report,
		"Handling QA pair isolates steering",
		isolated,
		"Heavy/Responsive pair must keep Buoyancy and Attraction equal while only Handling/steering changes."
	)


static func _test_attraction_isolation(
	report: Dictionary,
	service: BeachCraftingService
) -> void:
	var subtle: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"iron_scrap",
		&""
	)
	var flash: Dictionary = service.preview_craft(
		&"beach_minnow",
		&"driftwood",
		&"iron_scrap",
		&"sea_glass"
	)

	var isolated: bool = (
		bool(subtle.get("success", false))
		and bool(flash.get("success", false))
		and int(subtle.get("buoyancy", 999))
			== int(flash.get("buoyancy", -999))
		and int(subtle.get("handling", 999))
			== int(flash.get("handling", -999))
		and int(subtle.get("attraction", 0))
			< int(flash.get("attraction", 0))
		and float(subtle.get("attraction_reference", 99.0))
			< float(flash.get("attraction_reference", -99.0))
	)
	_record(
		report,
		"Attraction QA pair isolates fish attraction",
		isolated,
		"Subtle/Flash pair must keep Buoyancy and Handling equal while only Attraction changes."
	)


static func _test_crafted_record_roundtrip(
	report: Dictionary,
	service: BeachCraftingService
) -> void:
	var result: Dictionary = service.qa_roundtrip_preview(
		&"beach_minnow",
		&"shell",
		&"iron_scrap",
		&"sea_glass"
	)
	var preserved: bool = (
		bool(result.get("success", false))
		and is_equal_approx(
			float(result.get("sink_depth", -1.0)),
			float(result.get("preview_sink_depth", -2.0))
		)
		and is_equal_approx(
			float(result.get("reel_steer_strength", -1.0)),
			float(result.get("preview_reel_steer_strength", -2.0))
		)
		and is_equal_approx(
			float(result.get("attraction_reference", -1.0)),
			float(result.get("preview_attraction_reference", -2.0))
		)
	)
	_record(
		report,
		"Crafted lure JSON record reconstructs exact fishing properties",
		preserved,
		"Serialized score records must rebuild the same depth, steering and attraction values used by preview."
	)


static func _record(
	report: Dictionary,
	test_name: String,
	passed: bool,
	detail: String = ""
) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get(
		"failures",
		PackedStringArray()
	)
	failures.append(
		"%s%s"
		% [
			test_name,
			" — %s" % detail if not detail.is_empty() else "",
		]
	)
	report["failures"] = failures
