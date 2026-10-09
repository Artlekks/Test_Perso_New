extends SceneTree
const Validator = preload("res://scripts/content/content_registration_validator.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func has_code(validator, code: String) -> bool:
	return validator.issues.any(func(issue): return issue.code == code)
func run() -> void:
	var orphan_before := Node.get_orphan_node_ids()
	var validator := Validator.new()
	var report := validator.validate()
	checks += report.checks
	for issue in report.issues:
		failures.append(JSON.stringify(issue))
		push_error(JSON.stringify(issue))
	var repeat := validator.validate()
	check(report == repeat, "deterministic validation and provider contract output")
	validator.issues.clear()
	validator.index("test", [Validator.Shops.offers[0], Validator.Shops.offers[0]], "offer_id")
	check(has_code(validator, "empty_or_duplicate_id"), "duplicate ID rejected")
	validator.issues.clear()
	validator.ref("fish", "missing_test_fish", "fixture")
	check(has_code(validator, "invalid_fish_reference"), "invalid reference rejected")
	var fish_before: Dictionary = validator.indexes.fish.duplicate()
	validator.indexes.fish.erase(fish_before.keys()[0])
	validator.issues.clear()
	validator.validate_unregistered_resources()
	check(has_code(validator, "unregistered_authored_resource"), "authored leaf omitted from registry rejected")
	validator.indexes.fish = fish_before
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(Validator.BINDINGS)).providers
	var broken: Array = rows.duplicate(true)
	broken[0].path = "World/MissingProvider"
	validator.issues.clear()
	validator.validate_providers(broken)
	check(has_code(validator, "missing_provider_node"), "broken node binding rejected")
	broken = rows.duplicate(true)
	broken.remove_at(0)
	validator.issues.clear()
	validator.validate_providers(broken)
	check(has_code(validator, "missing_required_provider_metadata"), "scene provider absent from metadata rejected")
	broken = rows.duplicate(true)
	broken.append(rows[0].duplicate(true))
	validator.issues.clear()
	validator.validate_providers(broken)
	check(has_code(validator, "duplicate_or_empty_provider_id"), "duplicate provider ID rejected")
	broken = rows.duplicate(true)
	broken[0].catalogs = ["res://data/missing_validation_fixture.tres"]
	validator.issues.clear()
	validator.validate_providers(broken)
	check(has_code(validator, "missing_provider_catalog"), "missing provider resource rejected")
	var original_mastery: Dictionary = validator.indexes.mastery.duplicate()
	var cyclic = Validator.Masters.techniques[0].duplicate(true)
	cyclic.prerequisite_ids = PackedStringArray([String(cyclic.technique_id)])
	validator.indexes.mastery[String(cyclic.technique_id)] = cyclic
	validator.issues.clear()
	validator.validate_dependency_graph("mastery", "prerequisite_ids")
	check(has_code(validator, "cyclic_or_missing_mastery_prerequisite"), "circular technique dependency rejected")
	validator.indexes.mastery = original_mastery
	var targets: Array = Validator.Route.new().targets()
	targets[0].source_id = "missing_test_source"
	validator.issues.clear()
	validator.validate_acquisition(targets)
	check(has_code(validator, "unreachable_required_acquisition"), "missing/circular unlock acquisition source rejected")
	targets = Validator.Route.new().targets()
	# Replace the initial Beach acquisition with an actual, valid locked-Lake
	# source. Nothing can seed Baby Frog, so the downstream chain deadlocks.
	targets[0].source_id = "lyp_popper"
	targets[0].item_id = "popper"
	validator.issues.clear()
	validator.validate_acquisition(targets)
	check(has_code(validator, "unreachable_required_acquisition"), "valid acquisition source behind an unseeded unlock chain rejected")
	check(Node.get_orphan_node_ids() == orphan_before, "off-tree inspection releases every scene")
	for exception in report.exceptions: print("ENCODED EXCEPTION: ", exception)
	print("CONTENT REGISTRATION QA: ", checks - failures.size(), "/", checks, "; providers=", report.providers.size(), "; failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)
