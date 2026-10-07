extends SceneTree

const Simulator = preload("res://scripts/progression/economy_progression_simulator.gd")
const Campaign = preload("res://scripts/progression/playable_campaign_loop_qa.gd")
var checks := 0
var failures := PackedStringArray()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void:
	var report := Simulator.new().run_default_suite(false)
	var health := Simulator.classify_health(report)
	check(report.checks_passed == 22 and report.checks_total == 24, "guardrail truth remains 22/24")
	check(health.structural_passed and health.balance_alerts.size() == 2, "healthy structure with two separate provisional alerts")
	var ids := PackedStringArray()
	for alert in health.balance_alerts:
		ids.append(alert.check_id)
		check(not alert.passed and alert.category == "provisional_balance", "provisional alert remains a failed guardrail")
	check(ids.has("balanced_h12_cash_ceiling") and ids.has("sell_heavy_h12_cash_ceiling"), "only intended H12 checks are provisional")
	var campaign := {}
	Campaign._test_simulator_health(campaign, report)
	check(campaign.passed_count == campaign.test_count and campaign.balance_alerts.size() == 2, "campaign structural gate passes without falsifying balance alerts")
	for fault in ["route", "source", "deadlock", "incomplete_profile", "negative_cash", "nonfinite_cash", "fish_accounting", "cash_accounting", "missing_classification", "unknown_classification", "unknown_balance_id", "hard_guardrail"]:
		var broken := report.duplicate(true)
		match fault:
			"route": broken.runtime_route.issues.append({"reason": "missing_provider"})
			"source": broken.source_truth.ok = false
			"deadlock": broken.runtime_viability.passed = false
			"incomplete_profile": broken.profiles.SELL_HEAVY.final.purchases.clear()
			"negative_cash": broken.profiles.BALANCED.checkpoints.H1.zenny = -1
			"nonfinite_cash": broken.profiles.BALANCED.checkpoints.H1.zenny = NAN
			"fish_accounting": broken.profiles.BALANCED.checkpoints.H1.fish_accounting_error = 1.0
			"cash_accounting": broken.profiles.BALANCED.checkpoints.H1.cash_flow.cash_accounting_error = 1.0
			"missing_classification": broken.checks[0].erase("category")
			"unknown_classification": broken.checks[0].category = "ignored"
			"unknown_balance_id":
				broken.checks[0].category = "provisional_balance"
				broken.checks[0].check_id = "suppress_all_failures"
			"hard_guardrail": broken.checks[0].passed = false
		var failed := Simulator.classify_health(broken)
		check(not failed.structural_passed and not failed.structural_failures.is_empty(), "hard fault remains fatal: " + fault)
		var failed_campaign := {}
		Campaign._test_simulator_health(failed_campaign, broken)
		check(int(failed_campaign.get("passed_count", 0)) < failed_campaign.test_count and not failed_campaign.failures.is_empty(), "campaign propagates hard fault: " + fault)
	print("ECONOMY HEALTH CLASSIFICATION QA: %d/%d passed; guardrails %s" % [checks - failures.size(), checks, report.summary])
	quit(0 if failures.is_empty() else 1)
