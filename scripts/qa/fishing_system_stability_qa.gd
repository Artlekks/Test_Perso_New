extends RefCounted
class_name FishingSystemStabilityQA

## Cross-system freeze gate for the current fishing vertical slice.
##
## This intentionally checks integration/ownership only. It does not mutate saves,
## grant rewards, learn mastery techniques, catch fish, or alter runtime balance.

static func run(session: Node) -> Dictionary:
	var failures := PackedStringArray()
	var passed := 0
	var tests := 0

	tests += 1
	if session != null:
		passed += 1
	else:
		failures.append("session services node is null")
		return _report(passed, tests, failures)

	tests += 1
	if session.has_method("is_ready") and bool(session.call("is_ready")):
		passed += 1
	else:
		failures.append("session services did not reach ready state")

	tests += 1
	if _all_present(session, ["progress", "inventory", "catch_repository"]):
		passed += 1
	else:
		failures.append("core fishing progress/inventory/catch stack is incomplete")

	tests += 1
	if _all_present(
		session,
		["item_catalog", "player_item_inventory", "item_inventory_facade", "item_transaction_service"]
	):
		passed += 1
	else:
		failures.append("unified item backend is incomplete")

	tests += 1
	if _all_present(session, ["beach_gathering_inventory", "beach_crafting_service"]):
		passed += 1
	else:
		failures.append("beach gathering/crafting stack is incomplete")

	tests += 1
	if _all_present(
		session,
		["economy_service", "economy_access", "trade_service", "manillo_ledger"]
	):
		passed += 1
	else:
		failures.append("economy/trade stack is incomplete")

	tests += 1
	if _all_present(session, ["cooking_service", "prepared_bait_service"]):
		passed += 1
	else:
		failures.append("prepared-bait/cooking stack is incomplete")

	tests += 1
	if session.get("card_maker_service") != null:
		passed += 1
	else:
		failures.append("card maker service is unavailable")

	tests += 1
	if _all_present(
		session,
		["mastery_service", "current_service", "tide_service", "environment_service"]
	):
		passed += 1
	else:
		failures.append("mastery/current/tide/environment stack is incomplete")

	tests += 1
	if _all_present(
		session,
		["unlock_state", "reward_service", "journal_service", "save_integrity_service"]
	):
		passed += 1
	else:
		failures.append("unlock/reward/journal/save stack is incomplete")

	tests += 1
	if _all_present(
		session,
		["campaign_progression_director", "campaign_presentation_controller"]
	):
		passed += 1
	else:
		failures.append("campaign director/presentation stack is incomplete")

	tests += 1
	if _all_present(session, ["dialogue_service", "dialogue_controller"]):
		passed += 1
	else:
		failures.append("dialogue service/controller stack is incomplete")

	tests += 1
	if _report_has_no_errors(session.get("progression_integrity_report")):
		passed += 1
	else:
		failures.append("progression integrity report contains errors")

	tests += 1
	if _report_has_no_errors(session.get("economy_integrity_report")):
		passed += 1
	else:
		failures.append("economy integrity report contains errors")

	tests += 1
	if _report_has_no_errors(session.get("fish_effect_integrity_report")):
		passed += 1
	else:
		failures.append("fish-effect integrity report contains errors")

	tests += 1
	if _report_has_no_errors(session.get("environment_integrity_report")):
		passed += 1
	else:
		failures.append("environment integrity report contains errors")

	tests += 1
	if _report_has_no_errors(session.get("beach_crafting_integrity_report")):
		passed += 1
	else:
		failures.append("beach crafting integrity report contains errors")

	tests += 1
	if _report_has_no_errors(session.get("save_integrity_report")):
		passed += 1
	else:
		failures.append("save integrity report contains errors")

	tests += 1
	if _qa_report_passed(session.get("mastery_qa_report")):
		passed += 1
	else:
		failures.append("mastery QA did not report a clean pass")

	tests += 1
	if _qa_report_passed(session.get("fight_combat_qa_report")):
		passed += 1
	else:
		failures.append("fishing fight QA did not report a clean pass")

	tests += 1
	if _qa_report_passed(session.get("presentation_qa_report")):
		passed += 1
	else:
		failures.append("fishing presentation QA did not report a clean pass")

	tests += 1
	if _qa_report_passed(session.get("cephalopod_shadow_qa_report")):
		passed += 1
	else:
		failures.append("cephalopod shadow QA did not report a clean pass")

	tests += 1
	if _qa_report_passed(session.get("master_gyosil_qa_report")):
		passed += 1
	else:
		failures.append("Master Gyosil QA did not report a clean pass")

	tests += 1
	if _qa_report_passed(session.get("dialogue_qa_report")):
		passed += 1
	else:
		failures.append("dialogue QA did not report a clean pass")

	tests += 1
	if _qa_report_passed(session.get("master_drift_angler_qa_report")):
		passed += 1
	else:
		failures.append("Drift Angler QA did not report a clean pass")

	tests += 1
	var qa_health: Dictionary = {}
	if session.has_method("get_debug_qa_dependency_health"):
		qa_health = session.call("get_debug_qa_dependency_health")
	if bool(qa_health.get("ready", false)) and int(qa_health.get("failure_count", 1)) == 0:
		passed += 1
	else:
		failures.append("debug QA dependency isolation did not load cleanly")

	tests += 1
	if _unique_service_child_names(session):
		passed += 1
	else:
		failures.append("session contains duplicate named service children")

	return _report(passed, tests, failures)


static func _all_present(session: Node, property_names: Array) -> bool:
	for property_name in property_names:
		if session.get(property_name) == null:
			return false
	return true


static func _report_has_no_errors(value) -> bool:
	if not (value is Dictionary):
		return false
	var report: Dictionary = value
	var errors = report.get("errors", PackedStringArray())
	return errors != null and errors.size() == 0


static func _qa_report_passed(value) -> bool:
	if not (value is Dictionary):
		return false
	var report: Dictionary = value
	var test_count := int(report.get("test_count", 0))
	var passed_count := int(report.get("passed_count", -1))
	var failures = report.get("failures", PackedStringArray())
	if test_count <= 0 or passed_count != test_count:
		return false
	return failures != null and failures.size() == 0


static func _unique_service_child_names(session: Node) -> bool:
	var seen: Dictionary = {}
	for child in session.get_children():
		var key := str(child.name)
		if seen.has(key):
			return false
		seen[key] = true
	return true


static func _report(
	passed: int,
	tests: int,
	failures: PackedStringArray
) -> Dictionary:
	return {
		"passed_count": passed,
		"test_count": tests,
		"failures": failures,
	}
