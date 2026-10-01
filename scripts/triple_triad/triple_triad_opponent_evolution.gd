extends RefCounted
class_name TripleTriadOpponentEvolution


func build_snapshot(
	profile: Resource,
	encounter_snapshot: Dictionary
) -> Dictionary:
	if profile == null or not bool(profile.get("rematch_evolution_enabled")):
		return _baseline_snapshot(profile, encounter_snapshot)

	var wins: int = maxi(0, int(encounter_snapshot.get("wins", 0)))
	var thresholds: PackedInt32Array = profile.get("rematch_win_thresholds")
	var stage: int = 0
	for threshold in thresholds:
		if wins >= int(threshold):
			stage += 1

	var bonuses: PackedInt32Array = profile.get("rematch_budget_bonuses")
	var budget_bonus: int = 0
	if not bonuses.is_empty():
		budget_bonus = int(bonuses[mini(stage, bonuses.size() - 1)])

	var promoted_source: PackedStringArray = profile.get(
		"rematch_promoted_card_ids"
	)
	var promoted := PackedStringArray()
	for index in range(mini(stage, promoted_source.size())):
		promoted.append(promoted_source[index])

	var signature_ids := PackedStringArray()
	var signature_stage: int = int(profile.get("signature_card_stage"))
	if stage >= signature_stage and stage > 0:
		var raw_signature: PackedStringArray = profile.get("signature_card_ids")
		for raw_id in raw_signature:
			if not signature_ids.has(raw_id):
				signature_ids.append(raw_id)

	var forced := PackedStringArray()
	for raw_id in promoted:
		if not forced.has(raw_id):
			forced.append(raw_id)
	for raw_id in signature_ids:
		if not forced.has(raw_id):
			forced.append(raw_id)

	var style_id: StringName = profile.get("adaptive_style_id")
	if String(style_id).is_empty():
		style_id = profile.get("archetype_id")

	return {
		"enabled": true,
		"opponent_id": String(profile.get("opponent_id")),
		"wins_against_opponent": wins,
		"stage": stage,
		"stage_label": _stage_label(stage),
		"budget_bonus": maxi(0, budget_bonus),
		"promoted_card_ids": promoted,
		"signature_card_ids": signature_ids,
		"forced_card_ids": forced,
		"adaptive_style_id": String(style_id),
	}


func build_adapted_ai(
	base_ai: Resource,
	evolution_snapshot: Dictionary
) -> Resource:
	if base_ai == null:
		return null
	var stage: int = maxi(0, int(evolution_snapshot.get("stage", 0)))
	if stage <= 0:
		return base_ai

	var adapted: Resource = base_ai.duplicate(true)
	var style: String = str(
		evolution_snapshot.get("adaptive_style_id", "balanced")
	).to_lower()

	# Everyone becomes less erratic after repeatedly facing the player.
	adapted.set(
		"randomness",
		maxf(
			0.15,
			float(adapted.get("randomness")) * maxf(0.45, 1.0 - 0.12 * stage)
		)
	)

	match style:
		"aggressive":
			_add(adapted, &"capture_weight", 6.0 * stage)
			_add(adapted, &"card_strength_weight", 0.018 * stage)
			_add(adapted, &"vulnerability_weight", 0.35 * stage)
		"defensive", "construct_defensive", "beast_defensive":
			_add(adapted, &"vulnerability_weight", 1.0 * stage)
			_add(adapted, &"positional_weight", 0.25 * stage)
			_add(adapted, &"future_setup_weight", 1.0 * stage)
		"influence_control", "control":
			_add(adapted, &"influence_weight", 2.0 * stage)
			_add(adapted, &"future_setup_weight", 2.0 * stage)
			_add(adapted, &"influence_source_capture_weight", 2.5 * stage)
			_add(adapted, &"plus_trigger_weight", 3.0 * stage)
		"plus_trickster", "trickster":
			_add(adapted, &"plus_trigger_weight", 7.0 * stage)
			_add(adapted, &"same_trigger_weight", 3.0 * stage)
			_add(adapted, &"future_setup_weight", 2.0 * stage)
			_add(adapted, &"influence_weight", 1.5 * stage)
		"same_combo_specialist", "same_combo":
			_add(adapted, &"same_trigger_weight", 8.0 * stage)
			_add(adapted, &"future_setup_weight", 2.0 * stage)
			_add(adapted, &"vulnerability_weight", 0.5 * stage)
		"champion":
			_add(adapted, &"capture_weight", 4.0 * stage)
			_add(adapted, &"same_trigger_weight", 4.0 * stage)
			_add(adapted, &"plus_trigger_weight", 4.0 * stage)
			_add(adapted, &"vulnerability_weight", 1.0 * stage)
		_:
			_add(adapted, &"positional_weight", 0.18 * stage)
			_add(adapted, &"vulnerability_weight", 0.6 * stage)
			_add(adapted, &"capture_weight", 2.0 * stage)

	var signature_ids: PackedStringArray = evolution_snapshot.get(
		"signature_card_ids",
		PackedStringArray()
	)
	adapted.set("signature_card_ids", signature_ids)
	if not signature_ids.is_empty():
		adapted.set("signature_early_play_penalty", 6.0 + 3.0 * stage)
		adapted.set("signature_late_play_bonus", 4.0 + 2.0 * stage)
		adapted.set("signature_late_empty_cell_threshold", 4)

	return adapted


func _baseline_snapshot(
	profile: Resource,
	encounter_snapshot: Dictionary
) -> Dictionary:
	return {
		"enabled": false,
		"opponent_id": (
			String(profile.get("opponent_id"))
			if profile != null
			else ""
		),
		"wins_against_opponent": maxi(
			0,
			int(encounter_snapshot.get("wins", 0))
		),
		"stage": 0,
		"stage_label": "Baseline",
		"budget_bonus": 0,
		"promoted_card_ids": PackedStringArray(),
		"signature_card_ids": PackedStringArray(),
		"forced_card_ids": PackedStringArray(),
		"adaptive_style_id": "",
	}


func _stage_label(stage: int) -> String:
	match stage:
		1:
			return "Rematch I"
		2:
			return "Rematch II"
		3:
			return "Veteran Rematch"
		_:
			return "Baseline"


func _add(resource: Resource, property_name: StringName, amount: float) -> void:
	resource.set(
		property_name,
		float(resource.get(property_name)) + amount
	)
