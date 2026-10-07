extends RefCounted

## Measurement only. No inventory writes, RNG calls, or save-schema dependency.
const ACQUISITIONS := ["baby_frog", "bamboo_rod", "tail", "crab", "floater", "popper", "angling_rod", "silver_top", "hanger"]
const FISHING_CATEGORIES := ["active_fishing", "waiting_in_water", "fish_fight"]
var active := false
var events: Array = []
var attempts: Array = []
var ledger: Array = []
var acquisitions: Dictionary = {}
var species: Dictionary = {}
var activity_seconds: Dictionary = {}
var opening: Dictionary = {}
var ending: Dictionary = {}
var started_at := ""
var ended_at := ""
var started_usec := 0
var last_usec := 0
var category := "other"
var exposure_ids: Array = []
var current_attempt: Dictionary = {}
var encounter_open := false
var current_species := ""
var fight_start := -1.0
var fight_end := -1.0
var wallet := 0
var clock: Callable = func(): return Time.get_ticks_usec()

func elapsed() -> float:
	return maxf(0.0, float(clock.call() - started_usec) / 1000000.0)

func start(snapshot: Dictionary) -> bool:
	if active:
		return false
	events = []
	attempts = []
	ledger = []
	acquisitions = {}
	species = {}
	activity_seconds = {}
	current_attempt = {}
	encounter_open = false
	current_species = ""
	fight_start = -1.0
	fight_end = -1.0
	category = "other"
	exposure_ids = []
	opening = snapshot.duplicate(true)
	ending = {}
	wallet = int(snapshot.get("zenny", 0))
	started_usec = clock.call()
	last_usec = started_usec
	started_at = Time.get_datetime_string_from_system(true)
	ended_at = ""
	active = true
	for id in ACQUISITIONS:
		if snapshot.get("owned_items", []).has(id):
			acquisitions[id] = {"pre_existing": true, "elapsed_seconds": null, "source": "owned_at_start"}
	event("session_start", snapshot)
	return true

func event(kind: String, data: Dictionary = {}) -> void:
	if active:
		events.append({"sequence": events.size() + 1, "elapsed_seconds": elapsed(), "kind": kind, "data": data.duplicate(true)})

func account_time() -> void:
	if not active:
		return
	var now: int = clock.call()
	var seconds := maxf(0.0, float(now - last_usec) / 1000000.0)
	last_usec = now
	activity_seconds[category] = float(activity_seconds.get(category, 0.0)) + seconds
	if category in FISHING_CATEGORIES:
		for id in exposure_ids:
			var row := species_row(id)
			row.population_exposure_seconds += seconds
		if not current_species.is_empty():
			species_row(current_species).identified_target_seconds += seconds

func set_activity(next_category: String, population_ids: Array = []) -> void:
	if not active:
		return
	account_time()
	category = next_category
	exposure_ids = population_ids.duplicate()

func species_row(id: String) -> Dictionary:
	if not species.has(id):
		species[id] = {"species_id": id, "encounters": 0, "hooks": 0, "hooks_from_observed_encounters": 0, "landed": 0, "partial_fight_landings": 0, "lost": 0, "missed_bites": 0, "fight_seconds": 0.0, "resolved_fights": 0, "population_exposure_seconds": 0.0, "identified_target_seconds": 0.0, "landed_value": 0, "sell_income": 0, "rods": {}, "landing_milestones": []}
	return species[id]

func begin_attempt(context: Dictionary, partial := false) -> void:
	if not active or not current_attempt.is_empty():
		return
	current_attempt = context.duplicate(true)
	current_attempt.merge({"attempt_id": attempts.size() + 1, "started_seconds": elapsed(), "partial_start": partial, "encounters": [], "result": "pending"})
	event("cast", current_attempt)

func encounter(id: String) -> void:
	if not active or current_attempt.is_empty() or encounter_open or id.is_empty():
		return
	account_time()
	current_species = id
	encounter_open = true
	var row := species_row(id)
	row.encounters += 1
	current_attempt.encounters.append({"species_id": id, "elapsed_seconds": elapsed(), "result": "pending"})
	event("encounter", {"species_id": id, "attempt_id": current_attempt.attempt_id})

func hook(id: String, specimen: Dictionary = {}) -> void:
	if not active or current_attempt.is_empty() or fight_start >= 0.0:
		return
	var observed_encounter := encounter_open
	if not encounter_open and not current_attempt.get("partial_start", false):
		encounter(id)
		observed_encounter = encounter_open
	account_time()
	current_species = id
	fight_start = elapsed()
	current_attempt["hooked_species"] = id
	current_attempt["specimen"] = specimen.duplicate(true)
	var row := species_row(id)
	row.hooks += 1
	row.hooks_from_observed_encounters += int(observed_encounter)
	var rod: String = str(current_attempt.get("rod", "unknown"))
	row.rods[rod] = int(row.rods.get(rod, 0)) + 1
	event("hook", {"species_id": id, "specimen": specimen})

func join_existing_fight(id: String, specimen: Dictionary) -> void:
	if not active or current_attempt.is_empty() or fight_start >= 0.0 or id.is_empty():
		return
	account_time()
	current_species = id
	fight_start = elapsed()
	current_attempt["fight_already_active_at_start"] = true
	current_attempt["hooked_species"] = id
	current_attempt["specimen"] = specimen.duplicate(true)
	species_row(id)
	event("joined_existing_fight", {"species_id": id, "specimen": specimen})

func miss_bite() -> void:
	if not active or not encounter_open or fight_start >= 0.0:
		return
	account_time()
	species_row(current_species).missed_bites += 1
	current_attempt.encounters.back().result = "missed_bite"
	event("missed_bite", {"species_id": current_species})
	encounter_open = false
	current_species = ""

func begin_landing() -> void:
	if active and fight_start >= 0.0 and fight_end < 0.0:
		fight_end = elapsed()

func finish_attempt(result: String, details: Dictionary = {}) -> void:
	if not active or current_attempt.is_empty():
		return
	account_time()
	current_attempt["result"] = result
	current_attempt["duration_seconds"] = elapsed() - float(current_attempt.started_seconds)
	current_attempt["fight_seconds"] = (fight_end if fight_end >= 0.0 else elapsed()) - fight_start if fight_start >= 0.0 else 0.0
	current_attempt["details"] = details.duplicate(true)
	if encounter_open:
		current_attempt.encounters.back().result = result
	if not current_species.is_empty() and fight_start >= 0.0 and result in ["landed", "escaped", "failed"]:
		var row := species_row(current_species)
		var partial_fight: bool = current_attempt.get("fight_already_active_at_start", false)
		if not partial_fight:
			row.fight_seconds += current_attempt.fight_seconds
			row.resolved_fights += 1
		if result == "landed":
			row.landed += 1
			row.partial_fight_landings += int(partial_fight)
			row.landed_value += int(details.get("canonical_sell_value", 0))
			row.landing_milestones.append({"number": row.landed, "elapsed_seconds": elapsed(), "session_attempt_number": current_attempt.attempt_id, "species_encounters": row.encounters, "species_hooks": row.hooks, "population_exposure_seconds": row.population_exposure_seconds})
		else:
			row.lost += 1
	attempts.append(current_attempt.duplicate(true))
	event("attempt_end", current_attempt)
	current_attempt = {}
	encounter_open = false
	current_species = ""
	fight_start = -1.0
	fight_end = -1.0

func wallet_changed(after: int, origin: Array = []) -> void:
	if not active or after == wallet:
		return
	var entry := {"elapsed_seconds": elapsed(), "source": "unclassified_wallet_change", "source_id": "", "amount": after - wallet, "wallet_before": wallet, "wallet_after": after}
	entry["origin_stack"] = origin.duplicate(true)
	ledger.append(entry)
	event("wallet_change", entry)
	wallet = after

func transaction(source: String, id: String, before: int, after: int, details: Dictionary = {}) -> void:
	if not active:
		return
	# Inventory emits committed wallet notifications before the service emits
	# completion. Enrich that entry instead of recording the cash delta twice.
	var matched := false
	for index in range(ledger.size() - 1, -1, -1):
		var entry: Dictionary = ledger[index]
		if entry.source == "unclassified_wallet_change" and entry.wallet_before == before and entry.wallet_after == after:
			entry.source = source
			entry.source_id = id
			entry["details"] = details.duplicate(true)
			matched = true
			break
	if not matched:
		ledger.append({"elapsed_seconds": elapsed(), "source": source, "source_id": id, "amount": after - before, "wallet_before": before, "wallet_after": after, "details": details.duplicate(true)})
	if source == "fish_sale":
		species_row(id).sell_income += after - before
	event("transaction", {"source": source, "source_id": id, "wallet_before": before, "wallet_after": after, "details": details})

func acquired(id: String, context: Dictionary) -> void:
	if not active or id not in ACQUISITIONS or acquisitions.has(id):
		return
	var row := context.duplicate(true)
	row.merge({"pre_existing": false, "elapsed_seconds": elapsed(), "wallet": wallet, "total_landed": total_landed()})
	acquisitions[id] = row
	event("acquisition", {"item_id": id, "context": row})

func annotate_acquisition(id: String, source: String) -> void:
	if acquisitions.has(id) and not acquisitions[id].pre_existing and acquisitions[id].get("source", "") == "inventory_commit":
		acquisitions[id].source = source
		event("acquisition_source", {"item_id": id, "source": source})

func total_landed() -> int:
	var count := 0
	for row in species.values():
		count += int(row.landed)
	return count

func stop(snapshot: Dictionary) -> Dictionary:
	if not active:
		return {}
	account_time()
	finish_attempt("partial", {"reason": "recording_stopped"})
	ending = snapshot.duplicate(true)
	ended_at = Time.get_datetime_string_from_system(true)
	var duration := elapsed()
	event("session_stop", snapshot)
	active = false
	var income := 0
	var spent := 0
	var delta := 0
	var unknown := 0
	for entry in ledger:
		delta += int(entry.amount)
		income += maxi(int(entry.amount), 0)
		spent += maxi(-int(entry.amount), 0)
		unknown += int(entry.source == "unclassified_wallet_change")
	var active_seconds := 0.0
	for key in FISHING_CATEGORIES:
		active_seconds += float(activity_seconds.get(key, 0.0))
	var rows: Array = []
	var value := 0
	var encounters := 0
	var hooks := 0
	var observed_encounter_hooks := 0
	var partial_landings := 0
	for raw in species.values():
		var row: Dictionary = raw.duplicate(true)
		row["hook_rate"] = float(row.hooks_from_observed_encounters) / row.encounters if row.encounters > 0 else null
		row["landing_rate"] = float(row.landed - row.partial_fight_landings) / row.hooks if row.hooks > 0 else null
		row["average_fight_seconds"] = row.fight_seconds / row.resolved_fights if row.resolved_fights > 0 else null
		row["active_fishing_minutes"] = row.population_exposure_seconds / 60.0
		row["actual_zenny_per_active_minute"] = row.sell_income * 60.0 / row.population_exposure_seconds if row.population_exposure_seconds > 0 else null
		value += int(row.landed_value)
		encounters += int(row.encounters)
		hooks += int(row.hooks)
		observed_encounter_hooks += int(row.hooks_from_observed_encounters)
		partial_landings += int(row.partial_fight_landings)
		rows.append(row)
	rows.sort_custom(func(a, b): return a.sell_income > b.sell_income)
	var completed := 0
	var failures := 0
	for attempt in attempts:
		completed += int(not attempt.partial_start and attempt.result != "partial")
		failures += int(attempt.result in ["failed", "escaped"])
	var summary := {"duration_seconds": duration, "active_fishing_seconds": active_seconds, "active_fishing_percent": active_seconds * 100.0 / duration if duration > 0 else 0.0, "activity_seconds": activity_seconds.duplicate(true), "completed_attempts": completed, "failed_or_escaped_attempts": failures, "landed": total_landed(), "encounters": encounters, "hooks": hooks, "hook_rate": float(hooks) / encounters if encounters > 0 else null, "landing_rate": float(total_landed()) / hooks if hooks > 0 else null, "attempts_per_hour": completed * 3600.0 / duration if duration > 0 else null, "landed_per_hour": total_landed() * 3600.0 / duration if duration > 0 else null, "gross_landed_value_per_hour": value * 3600.0 / duration if duration > 0 else null, "actual_zenny_income_per_hour": income * 3600.0 / duration if duration > 0 else null, "income": income, "spent": spent, "ending_wallet": int(snapshot.get("zenny", 0)), "wallet_reconciliation_error": int(opening.get("zenny", 0)) + delta - int(snapshot.get("zenny", 0)), "unclassified_wallet_events": unknown, "top_species_by_income": rows, "acquisitions": acquisitions.duplicate(true), "salmon": {}, "martian_squid": {}}
	for row in rows:
		if row.species_id in ["salmon", "martian_squid"]:
			summary[row.species_id] = row
	var top_income: Array = []
	summary["ledger_reconciled"] = summary.wallet_reconciliation_error == 0
	summary.hook_rate = float(observed_encounter_hooks) / encounters if encounters > 0 else null
	summary.landing_rate = float(total_landed() - partial_landings) / hooks if hooks > 0 else null
	summary["partial_fight_landings"] = partial_landings
	for row in rows:
		if row.sell_income > 0 and top_income.size() < 5:
			top_income.append({"species_id": row.species_id, "sell_income": row.sell_income, "landed": row.landed})
	summary.top_species_by_income = top_income
	summary["landed_per_active_fishing_hour"] = total_landed() * 3600.0 / active_seconds if active_seconds > 0 else null
	var squid: Dictionary = summary.martian_squid
	var squid_landings: Array = squid.get("landing_milestones", [])
	squid["time_to_first_seconds"] = squid_landings[0].elapsed_seconds if squid_landings.size() >= 1 else null
	squid["time_to_two_seconds"] = squid_landings[1].elapsed_seconds if squid_landings.size() >= 2 else null
	squid["active_seconds_to_two"] = squid_landings[1].population_exposure_seconds if squid_landings.size() >= 2 else null
	squid["session_attempts_to_two"] = squid_landings[1].session_attempt_number if squid_landings.size() >= 2 else null
	return {"schema": "economy_playtest_telemetry_v1", "started_at_utc": started_at, "ended_at_utc": ended_at, "opening": opening, "ending": ending, "summary": summary, "species_aggregates": rows, "attempts": attempts, "economy_ledger": ledger, "events": events, "measurement_notes": ["Monotonic wall time includes pauses/debug menus; these are other activity, not fishing.", "Species active minutes are population exposure: full fishing time while this species is available in the authored zone. Species denominators overlap and include waiting, not just fights.", "Identified-target seconds exclude waiting before an encounter selects a species.", "Sale income may include fish owned before recording. Raw sale details preserve consumed specimens.", "Missed bites are per-encounter outcomes; one cast can have multiple encounters. Partial attempts are not failures.", "No quality is invented: recorded specimen fields are size, size_band, king, points and score_tier when available."]}

static func save_report(report: Dictionary, directory := "user://playtest_telemetry") -> Dictionary:
	if report.is_empty() or not (directory == "user://playtest_telemetry" or directory.begins_with("user://playtest_telemetry/")) or ".." in directory:
		return {"ok": false, "reason": "invalid_report_directory"}
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "reason": "directory_unavailable"}
	# Timestamp and monotonic counter, never a gameplay random draw.
	var path := directory.path_join("session_%d_%d.json" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "report_open_failed"}
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return {"ok": false, "reason": "report_write_failed"}
	var summary_path := path.trim_suffix(".json") + "_summary.json"
	file = FileAccess.open(summary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "summary_open_failed", "raw_path": path}
	file.store_string(JSON.stringify(report.summary, "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	return {"ok": error == OK, "raw_path": path, "summary_path": summary_path}
