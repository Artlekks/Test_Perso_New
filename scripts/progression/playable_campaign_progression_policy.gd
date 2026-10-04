extends RefCounted
class_name PlayableCampaignProgressionPolicy

## Pure campaign-state evaluator. Runtime collection stays in the Director; this
## policy converts already-normalized facts into milestones and guidance.

const HARBOR_LOCKBOX_EVENT_ID := "beach_demo_harbor_lockbox_01"
const HARBOR_REQUEST_EVENT_ID := "beach_demo_harbor_errand_01"


static func build_snapshot_from_state(
	plan: Dictionary,
	runtime: Dictionary
) -> Dictionary:
	var card_state: Dictionary = {}
	var raw_card_state = runtime.get("card_state", {})
	if raw_card_state is Dictionary:
		card_state = raw_card_state

	var cards_owned: int = maxi(
		0,
		int(card_state.get("cards_owned_unique", 0))
	)
	var species_discovered: int = maxi(
		0,
		int(runtime.get("species_discovered", 0))
	)
	var rods_owned: int = maxi(0, int(runtime.get("rods_owned", 0)))
	var lures_owned: int = maxi(0, int(runtime.get("lures_owned", 0)))
	var total_catches: int = maxi(0, int(runtime.get("total_catches", 0)))
	var unlocked: bool = bool(card_state.get("card_game_unlocked", false))
	var starter_case_discovered: bool = bool(
		card_state.get("starter_case_discovered", false)
	)

	var milestone_statuses: Array = []
	var completed_ids := PackedStringArray()
	var current_milestone: Dictionary = {}
	var milestone_index: int = 0
	for raw_milestone in plan.get("milestones", []):
		if not (raw_milestone is Dictionary):
			continue
		var milestone: Dictionary = raw_milestone
		var status: Dictionary = _evaluate_milestone(
			milestone,
			cards_owned,
			species_discovered,
			rods_owned,
			lures_owned,
			unlocked,
			starter_case_discovered,
			runtime,
			card_state
		)
		status["index"] = milestone_index
		milestone_index += 1
		milestone_statuses.append(status)
		if bool(status.get("complete", false)):
			completed_ids.append(str(status.get("milestone_id", "")))
		elif current_milestone.is_empty():
			current_milestone = status

	var phase_id: String = "campaign_foundation_complete"
	if not current_milestone.is_empty():
		phase_id = str(current_milestone.get("milestone_id", ""))
		if phase_id == "first_fishing_trip" and not unlocked:
			phase_id = (
				"fresh_start"
				if total_catches <= 0
				else "starter_case_search"
			)

	var systems: Dictionary = _build_system_snapshot(runtime, card_state)
	var blockers: Array = _build_blockers(card_state)
	var next_objective: Dictionary = _build_next_objective(
		phase_id,
		current_milestone,
		runtime,
		card_state
	)

	return {
		"schema_version": 1,
		"plan_id": str(plan.get("plan_id", "playable_campaign_loop_v1")),
		"phase_id": phase_id,
		"target_milestone_id": str(
			current_milestone.get("milestone_id", "")
		),
		"target_milestone": current_milestone.duplicate(true),
		"completed_milestone_ids": completed_ids,
		"milestones": milestone_statuses,
		"next_objective": next_objective,
		"systems": systems,
		"blockers": blockers,
		"facts": {
			"card_backend_available": bool(
				card_state.get("backend_available", false)
			),
			"zenny": maxi(0, int(runtime.get("zenny", 0))),
			"total_catches": total_catches,
			"species_discovered": species_discovered,
			"cards_owned_unique": cards_owned,
			"rods_owned": rods_owned,
			"lures_owned": lures_owned,
			"duel_rank": maxi(1, int(card_state.get("duel_rank", 1))),
			"duel_points": maxi(0, int(card_state.get("duel_points", 0))),
			"card_game_unlocked": unlocked,
			"starter_case_discovered": starter_case_discovered,
			"prepared_bait_owned": _prepared_bait_owned(runtime),
			"card_maker_ready_recipe_count": _ready_card_maker_recipe_count(runtime),
		},
	}


static func _evaluate_milestone(
	milestone: Dictionary,
	cards_owned: int,
	species_discovered: int,
	rods_owned: int,
	lures_owned: int,
	card_game_unlocked: bool,
	starter_case_discovered: bool,
	runtime: Dictionary,
	card_state: Dictionary
) -> Dictionary:
	var card_min: int = maxi(0, int(milestone.get("card_owned_min", 0)))
	var species_min: int = maxi(
		0,
		int(milestone.get("species_discovered_min", 0))
	)
	var rod_min: int = maxi(0, int(milestone.get("rod_owned_min", 0)))
	var lure_min: int = maxi(0, int(milestone.get("lure_owned_min", 0)))
	var missing_flags := PackedStringArray()
	for raw_flag in milestone.get("required_flags", []):
		var flag_id: String = str(raw_flag)
		var satisfied: bool = true
		match flag_id:
			"card_game_unlocked":
				satisfied = card_game_unlocked
			"starter_case_discovered":
				satisfied = starter_case_discovered
			_:
				satisfied = false
		if not satisfied:
			missing_flags.append(flag_id)

	var deficits: Array = []
	if cards_owned < card_min:
		deficits.append({
			"field": "cards_owned_unique",
			"current": cards_owned,
			"target": card_min,
			"missing": card_min - cards_owned,
		})
	if species_discovered < species_min:
		deficits.append({
			"field": "species_discovered",
			"current": species_discovered,
			"target": species_min,
			"missing": species_min - species_discovered,
		})
	if rods_owned < rod_min:
		deficits.append({
			"field": "rods_owned",
			"current": rods_owned,
			"target": rod_min,
			"missing": rod_min - rods_owned,
		})
	if lures_owned < lure_min:
		deficits.append({
			"field": "lures_owned",
			"current": lures_owned,
			"target": lure_min,
			"missing": lure_min - lures_owned,
		})
	for flag_id in missing_flags:
		deficits.append({
			"field": "flag",
			"flag_id": str(flag_id),
			"missing": 1,
		})

	var activity_evaluation: Dictionary = _evaluate_activity_requirements(
		milestone,
		runtime,
		card_state
	)
	for raw_activity_deficit in activity_evaluation.get("deficits", []):
		if raw_activity_deficit is Dictionary:
			deficits.append((raw_activity_deficit as Dictionary).duplicate(true))

	var score_parts := [
		_ratio(cards_owned, card_min),
		_ratio(species_discovered, species_min),
		_ratio(rods_owned, rod_min),
		_ratio(lures_owned, lure_min),
	]
	var flags_ratio: float = (
		1.0
		if missing_flags.is_empty()
		else 0.0
	)
	score_parts.append(flags_ratio)
	if int(activity_evaluation.get("component_count", 0)) > 0:
		score_parts.append(
			float(activity_evaluation.get("progress_ratio", 0.0))
		)
	var progress_total: float = 0.0
	for raw_score in score_parts:
		progress_total += float(raw_score)
	var progress_ratio: float = (
		progress_total / float(maxi(1, score_parts.size()))
	)

	return {
		"milestone_id": str(milestone.get("milestone_id", "")),
		"checkpoint_hour": float(milestone.get("checkpoint_hour", 0.0)),
		"headline": str(milestone.get("headline", "")),
		"player_goal": str(milestone.get("player_goal", "")),
		"complete": deficits.is_empty(),
		"progress_ratio": clampf(progress_ratio, 0.0, 1.0),
		"deficits": deficits,
		"systems_introduced": milestone.get("systems_introduced", []),
		"required_sources": milestone.get("required_sources", []),
		"activity_requirements": activity_evaluation.get("requirements", []),
		"activity_choice_groups": activity_evaluation.get("choice_groups", []),
		"activity_progress_ratio": float(
			activity_evaluation.get("progress_ratio", 1.0)
		),
		"target": {
			"cards_owned_min": card_min,
			"species_discovered_min": species_min,
			"rods_owned_min": rod_min,
			"lures_owned_min": lure_min,
		},
	}


static func _evaluate_activity_requirements(
	milestone: Dictionary,
	runtime: Dictionary,
	card_state: Dictionary
) -> Dictionary:
	var requirement_statuses: Array = []
	var choice_group_statuses: Array = []
	var deficits: Array = []
	var component_count: int = 0
	var progress_total: float = 0.0

	var raw_requirements = milestone.get("activity_requirements", [])
	if raw_requirements is Array:
		for raw_requirement in raw_requirements:
			if not (raw_requirement is Dictionary):
				continue
			var requirement: Dictionary = (
				raw_requirement as Dictionary
			).duplicate(true)
			var complete: bool = _activity_is_satisfied(
				requirement,
				runtime,
				card_state
			)
			requirement["complete"] = complete
			requirement_statuses.append(requirement)
			component_count += 1
			if complete:
				progress_total += 1.0
			else:
				deficits.append({
					"field": "activity",
					"activity_id": str(requirement.get("activity_id", "")),
					"label": str(requirement.get("label", "")),
					"missing": 1,
				})

	var raw_groups = milestone.get("activity_choice_groups", [])
	if raw_groups is Array:
		for raw_group in raw_groups:
			if not (raw_group is Dictionary):
				continue
			var group: Dictionary = (raw_group as Dictionary).duplicate(true)
			var option_statuses: Array = []
			var complete_count: int = 0
			var raw_options = group.get("options", [])
			if raw_options is Array:
				for raw_option in raw_options:
					if not (raw_option is Dictionary):
						continue
					var option: Dictionary = (
						raw_option as Dictionary
					).duplicate(true)
					var option_complete: bool = _activity_is_satisfied(
						option,
						runtime,
						card_state
					)
					option["complete"] = option_complete
					option_statuses.append(option)
					if option_complete:
						complete_count += 1

			var minimum_complete: int = clampi(
				int(group.get("minimum_complete", 1)),
				0,
				option_statuses.size()
			)
			var group_complete: bool = complete_count >= minimum_complete
			group["options"] = option_statuses
			group["complete_count"] = complete_count
			group["minimum_complete"] = minimum_complete
			group["complete"] = group_complete
			choice_group_statuses.append(group)
			component_count += 1
			if minimum_complete <= 0:
				progress_total += 1.0
			else:
				progress_total += clampf(
					float(complete_count) / float(minimum_complete),
					0.0,
					1.0
				)
			if not group_complete:
				deficits.append({
					"field": "activity_group",
					"group_id": str(group.get("group_id", "")),
					"label": str(group.get("label", "")),
					"current": complete_count,
					"target": minimum_complete,
					"missing": maxi(0, minimum_complete - complete_count),
				})

	return {
		"requirements": requirement_statuses,
		"choice_groups": choice_group_statuses,
		"deficits": deficits,
		"component_count": component_count,
		"progress_ratio": (
			progress_total / float(component_count)
			if component_count > 0
			else 1.0
		),
	}


static func _activity_is_satisfied(
	activity: Dictionary,
	runtime: Dictionary,
	card_state: Dictionary
) -> bool:
	var kind: String = str(activity.get("kind", ""))
	match kind:
		"opponent_beaten":
			var opponent_id: String = str(activity.get("opponent_id", ""))
			var raw_opponents = card_state.get("opponents", {})
			if raw_opponents is Dictionary:
				var raw_opponent = (raw_opponents as Dictionary).get(
					opponent_id,
					{}
				)
				if raw_opponent is Dictionary:
					return bool(
						(raw_opponent as Dictionary).get(
							"beaten_before",
							false
						)
					)
			return _list_has_string(
				card_state.get("beaten_opponent_ids", []),
				opponent_id
			)
		"source_acquired":
			var source_key: String = "%s:%s" % [
				str(activity.get("source_type", "")),
				str(activity.get("source_id", "")),
			]
			return _source_acquisition_count(
				card_state,
				source_key
			) >= maxi(1, int(activity.get("minimum_count", 1)))
		"source_type_acquired":
			var wildcard_key: String = "%s:*" % str(
				activity.get("source_type", "")
			)
			return _source_acquisition_count(
				card_state,
				wildcard_key
			) >= maxi(1, int(activity.get("minimum_count", 1)))
		"world_event_claimed":
			return _list_has_string(
				card_state.get("claimed_world_event_ids", []),
				str(activity.get("event_id", ""))
			)
		"duel_rank_at_least":
			return maxi(1, int(card_state.get("duel_rank", 1))) >= maxi(
				1,
				int(activity.get("minimum_rank", 1))
			)
		"prepared_bait_owned":
			return _prepared_bait_owned(runtime) >= maxi(
				1,
				int(activity.get("minimum_count", 1))
			)
		"total_catches_at_least":
			return maxi(0, int(runtime.get("total_catches", 0))) >= maxi(
				1,
				int(activity.get("minimum_count", 1))
			)
		_:
			return false


static func _source_acquisition_count(
	card_state: Dictionary,
	source_key: String
) -> int:
	var raw_counts = card_state.get("source_acquisition_counts", {})
	if not (raw_counts is Dictionary):
		return 0
	return maxi(0, int((raw_counts as Dictionary).get(source_key, 0)))


static func _build_system_snapshot(
	runtime: Dictionary,
	card_state: Dictionary
) -> Dictionary:
	var unlocked: bool = bool(card_state.get("card_game_unlocked", false))
	var claimed_events = card_state.get("claimed_world_event_ids", [])
	var opponents: Dictionary = {}
	var raw_opponents = card_state.get("opponents", {})
	if raw_opponents is Dictionary:
		opponents = raw_opponents
	var beach_trader: Dictionary = {}
	var raw_trader = opponents.get("beach_trader", {})
	if raw_trader is Dictionary:
		beach_trader = raw_trader
	var regional: Dictionary = {}
	var raw_regional = card_state.get("regional_championship", {})
	if raw_regional is Dictionary:
		regional = raw_regional

	return {
		"fishing": {
			"available": true,
			"engaged": int(runtime.get("total_catches", 0)) > 0,
		},
		"catch_records": {
			"available": true,
			"engaged": int(runtime.get("species_discovered", 0)) > 0,
		},
		"triple_triad": {
			"available": unlocked,
			"engaged": int(card_state.get("matches", 0)) > 0,
		},
		"prepared_bait": {
			"available": not runtime.get("prepared_bait", {}).is_empty(),
			"engaged": _prepared_bait_owned(runtime) > 0,
		},
		"card_maker": {
			"available": unlocked and not runtime.get(
				"card_maker_recipe_statuses",
				[]
			).is_empty(),
			"ready_recipe_count": _ready_card_maker_recipe_count(runtime),
		},
		"harbor_request": {
			"available": unlocked,
			"objective_complete": bool(beach_trader.get("beaten_before", false)),
			"reward_claimed": _list_has_string(
				claimed_events,
				HARBOR_REQUEST_EVENT_ID
			),
		},
		"harbor_lockbox": {
			"available": unlocked,
			"reward_claimed": _list_has_string(
				claimed_events,
				HARBOR_LOCKBOX_EVENT_ID
			),
		},
		"regional_championship": {
			"available": bool(regional.get("available", false)),
			"active": bool(regional.get("active", false)),
			"clears": maxi(0, int(regional.get("clears", 0))),
			"reason": str(regional.get("reason", "")),
		},
	}


static func _build_blockers(card_state: Dictionary) -> Array:
	var result: Array = []
	if (
		bool(card_state.get("starter_case_discovered", false))
		and not bool(card_state.get("card_game_unlocked", false))
	):
		result.append({
			"code": "starter_case_unlock_mismatch",
			"severity": "error",
			"detail": "Starter case is claimed but the card game is still locked.",
		})
	if int(card_state.get("pending_world_reward_count", 0)) > 0:
		result.append({
			"code": "world_reward_recovery_pending",
			"severity": "warning",
			"detail": "%d world reward deliveries are pending recovery."
			% int(card_state.get("pending_world_reward_count", 0)),
		})
	if (
		bool(card_state.get("card_game_unlocked", false))
		and not bool(card_state.get("backend_available", false))
	):
		result.append({
			"code": "triple_triad_backend_unavailable",
			"severity": "error",
			"detail": "Card progression is unlocked but its runtime provider is unavailable.",
		})
	return result


static func _build_next_objective(
	phase_id: String,
	current_milestone: Dictionary,
	runtime: Dictionary,
	card_state: Dictionary
) -> Dictionary:
	var active_competition: Dictionary = {}
	var raw_active = card_state.get("active_competition", {})
	if raw_active is Dictionary:
		active_competition = raw_active
	if bool(active_competition.get("active", false)):
		return _objective(
			"continue_active_competition",
			"Continue the active card tournament.",
			str(active_competition.get("display_name", "Tournament")),
			"triple_triad"
		)

	match phase_id:
		"fresh_start":
			return _objective(
				"catch_first_fish",
				"Go fishing at the coast.",
				"Land your first fish and begin building catch records.",
				"fishing"
			)
		"starter_case_search":
			return _starter_case_search_objective(card_state)
		"first_fishing_trip":
			return _objective_from_deficits(
				current_milestone,
				"Complete the first fishing-trip milestone."
			)
		"learn_loop":
			return _learn_loop_objective(current_milestone, card_state)
		"connected_systems":
			return _connected_systems_objective(
				current_milestone,
				runtime,
				card_state
			)
		"specialization":
			return _specialization_objective(
				current_milestone,
				card_state
			)
		"campaign_foundation_complete":
			return _objective(
				"choose_free_play_goal",
				"Choose your next specialization goal.",
				"The current 0-12h campaign foundation targets are satisfied.",
				"free_play"
			)
		_:
			return _objective(
				"review_campaign_state",
				"Review the current campaign state.",
				"The director could not map this state to a known milestone.",
				"qa"
			)


static func _starter_case_search_objective(
	card_state: Dictionary
) -> Dictionary:
	var onboarding: Dictionary = {}
	var raw_onboarding = card_state.get("onboarding", {})
	if raw_onboarding is Dictionary:
		onboarding = raw_onboarding as Dictionary
	var bridge: Dictionary = {}
	var raw_bridge = onboarding.get("fishing_salvage_bridge", {})
	if raw_bridge is Dictionary:
		bridge = raw_bridge as Dictionary

	if bool(bridge.get("starter_salvage_armed", false)):
		return _objective(
			"land_starter_salvage",
			"Finish this catch and reel the glint back in.",
			"Your cast landed on the unusual shine in the water.",
			"fishing"
		)
	if bool(bridge.get("starter_sparkle_active", false)):
		return _objective(
			"cast_at_starter_glint",
			"Cast directly at the glint in the water.",
			"Something unusual has surfaced after your first few catches.",
			"fishing"
		)

	var current: int = maxi(
		0,
		int(bridge.get("starter_search_count", 0))
	)
	var threshold: int = maxi(
		3,
		int(bridge.get("starter_spawn_threshold", 5))
	)
	return _objective(
		"discover_starter_glint",
		"Keep fishing the coastal shallows.",
		"After a few catches, watch the water for an unusual glint. (%d/%d)"
		% [mini(current, threshold), threshold],
		"fishing"
	)


static func _learn_loop_objective(
	milestone: Dictionary,
	_card_state: Dictionary
) -> Dictionary:
	# Card discovery is meant to create an immediate "what is this?" payoff.
	# Point the player at the first card opponent before asking for more journal
	# breadth, otherwise the introduction can feel artificially delayed.
	if not _activity_complete(milestone, "beat_beach_trader"):
		return _objective(
			"challenge_beach_trader",
			"Show the recovered cards to the Beach Trader.",
			"The first card player introduces the C challenge control; win once to learn the duel loop.",
			"triple_triad"
		)
	if not _activity_complete(
		milestone,
		"recover_coast_shallows_salvage"
	):
		return _objective(
			"recover_coast_shallows_salvage",
			"Keep fishing the coast after finding the card case.",
			"Post-starter coastal catches eventually recover another card from the shallows.",
			"fishing"
		)
	if _deficit_value(milestone, "species_discovered") > 0:
		return _objective(
			"discover_more_fish",
			"Catch a few different fish species.",
			"Now that the card loop is introduced, broaden the catch journal naturally while fishing.",
			"fishing"
		)
	if _deficit_value(milestone, "cards_owned_unique") > 0:
		return _objective(
			"grow_early_card_collection",
			"Grow the early card collection.",
			"Use card duels or coastal salvage to reach the next collection target.",
			"triple_triad"
		)
	return _objective_from_deficits(
		milestone,
		"Keep learning the fishing and card loops."
	)


static func _connected_systems_objective(
	milestone: Dictionary,
	runtime: Dictionary,
	card_state: Dictionary
) -> Dictionary:
	var claimed_events = card_state.get("claimed_world_event_ids", [])
	var opponents: Dictionary = {}
	var raw_opponents = card_state.get("opponents", {})
	if raw_opponents is Dictionary:
		opponents = raw_opponents
	var raw_trader = opponents.get("beach_trader", {})
	var trader_beaten: bool = (
		raw_trader is Dictionary
		and bool((raw_trader as Dictionary).get("beaten_before", false))
	)
	if (
		trader_beaten
		and not _list_has_string(claimed_events, HARBOR_REQUEST_EVENT_ID)
	):
		return _objective(
			"turn_in_harbor_request",
			"Return to the Harbor Request Board.",
			"The Beach Trader request is ready to turn in.",
			"world_reward"
		)

	if not _activity_group_complete(
		milestone,
		"use_one_connected_card_route"
	):
		if (
			not _activity_complete(milestone, "use_card_maker")
			and _ready_card_maker_recipe_count(runtime) > 0
		):
			return _objective(
				"use_card_maker",
				"Turn a fish into a new card.",
				"A Card Maker recipe is currently affordable and ready.",
				"card_maker"
			)
		if not _activity_complete(milestone, "open_harbor_lockbox"):
			return _objective(
				"search_harbor_lockbox",
				"Search the Harbor Lockbox.",
				"Use one connected-system card route before treating the milestone as learned.",
				"world_reward"
			)
		return _objective(
			"use_connected_card_route",
			"Use one of the new connected card routes.",
			"Card Maker, Harbor Request or Harbor Lockbox can satisfy this pacing step.",
			"cross_system"
		)

	if _deficit_value(milestone, "rods_owned") > 0 or _deficit_value(
		milestone,
		"lures_owned"
	) > 0:
		return _objective(
			"improve_tackle",
			"Invest in a broader tackle set.",
			"Craft or buy the rod and lure options needed for the connected-systems target.",
			"economy"
		)
	if _deficit_value(milestone, "species_discovered") > 0:
		return _objective(
			"expand_fish_journal",
			"Fish for species you have not logged yet.",
			"The campaign target now expects a broader catch journal.",
			"fishing"
		)
	if _deficit_value(milestone, "cards_owned_unique") > 0:
		if _ready_card_maker_recipe_count(runtime) > 0:
			return _objective(
				"use_card_maker",
				"Turn a fish into a new card.",
				"A Card Maker recipe is currently affordable and ready.",
				"card_maker"
			)
		return _objective(
			"feed_card_collection",
			"Use fishing and opponents to grow the card collection.",
			"Card Maker recipes, opponent wins and world rewards all feed this target.",
			"cross_system"
		)
	return _objective_from_deficits(
		milestone,
		"Connect fishing, economy and card progression."
	)


static func _specialization_objective(
	milestone: Dictionary,
	card_state: Dictionary
) -> Dictionary:
	if not _activity_complete(milestone, "reach_duel_rank_2"):
		return _objective(
			"reach_duel_rank_2",
			"Push the card ladder to Duel Rank 2.",
			"Rank 2 is the bridge into deeper coastal salvage and the next opponent tier.",
			"triple_triad"
		)
	if not _activity_complete(
		milestone,
		"recover_deeper_coast_salvage"
	):
		return _objective(
			"recover_deeper_coast_salvage",
			"Push the coastal salvage loop into deeper rewards.",
			"After the shallow salvage pool is exhausted at Rank 2, keep fishing the coast for the deeper pool.",
			"fishing"
		)
	if _deficit_value(milestone, "rods_owned") > 0 or _deficit_value(
		milestone,
		"lures_owned"
	) > 0:
		return _objective(
			"specialize_tackle",
			"Build out the stronger tackle set.",
			"Use the economy and crafting loops to widen your fishing options.",
			"economy"
		)
	if _deficit_value(milestone, "species_discovered") > 0:
		return _objective(
			"push_deeper_fishing",
			"Push into less familiar fish and deeper salvage.",
			"The specialization target expects a substantially broader journal.",
			"fishing"
		)
	if _deficit_value(milestone, "cards_owned_unique") > 0:
		var world_progression: Dictionary = {}
		var raw_world = card_state.get("world_progression", {})
		if raw_world is Dictionary:
			world_progression = raw_world
		return _objective(
			"push_card_ladder",
			str(world_progression.get(
				"headline",
				"Push the Rank 2 card ladder and deeper acquisition sources."
			)),
			str(world_progression.get(
				"detail",
				"Opponent progression and deeper salvage feed the specialization target."
			)),
			"triple_triad"
		)
	return _objective_from_deficits(
		milestone,
		"Choose a specialization path."
	)


static func _objective_from_deficits(
	milestone: Dictionary,
	fallback_title: String
) -> Dictionary:
	var deficits = milestone.get("deficits", [])
	if deficits is Array and not deficits.is_empty():
		var first = deficits[0]
		if first is Dictionary:
			var field: String = str((first as Dictionary).get("field", ""))
			match field:
				"cards_owned_unique":
					return _objective(
						"grow_card_collection",
						"Grow the card collection.",
						"Reach the current campaign collection target.",
						"triple_triad"
					)
				"species_discovered":
					return _objective(
						"discover_more_fish",
						"Catch new fish species.",
						"Reach the current catch-journal target.",
						"fishing"
					)
				"rods_owned", "lures_owned":
					return _objective(
						"improve_tackle",
						"Expand the tackle collection.",
						"Reach the current rod and lure target.",
						"economy"
					)
				"activity", "activity_group":
					return _objective(
						"complete_pacing_activity",
						str((first as Dictionary).get(
							"label",
							"Complete the current campaign activity."
						)),
						"Milestone totals are not enough until the intended activity has actually happened.",
						"campaign"
					)
	return _objective(
		"continue_campaign",
		fallback_title,
		str(milestone.get("player_goal", "")),
		"campaign"
	)


static func _objective(
	code: String,
	title: String,
	detail: String,
	category: String
) -> Dictionary:
	return {
		"code": code,
		"title": title,
		"detail": detail,
		"category": category,
	}


static func _activity_complete(
	milestone: Dictionary,
	activity_id: String
) -> bool:
	for raw_status in milestone.get("activity_requirements", []):
		if not (raw_status is Dictionary):
			continue
		var status: Dictionary = raw_status
		if str(status.get("activity_id", "")) == activity_id:
			return bool(status.get("complete", false))
	for raw_group in milestone.get("activity_choice_groups", []):
		if not (raw_group is Dictionary):
			continue
		for raw_option in (raw_group as Dictionary).get("options", []):
			if not (raw_option is Dictionary):
				continue
			var option: Dictionary = raw_option
			if str(option.get("activity_id", "")) == activity_id:
				return bool(option.get("complete", false))
	return false


static func _activity_group_complete(
	milestone: Dictionary,
	group_id: String
) -> bool:
	for raw_group in milestone.get("activity_choice_groups", []):
		if not (raw_group is Dictionary):
			continue
		var group: Dictionary = raw_group
		if str(group.get("group_id", "")) == group_id:
			return bool(group.get("complete", false))
	return false


static func _deficit_value(milestone: Dictionary, field: String) -> int:
	for raw_deficit in milestone.get("deficits", []):
		if not (raw_deficit is Dictionary):
			continue
		var deficit: Dictionary = raw_deficit
		if str(deficit.get("field", "")) == field:
			return maxi(0, int(deficit.get("missing", 0)))
	return 0


static func _prepared_bait_owned(runtime: Dictionary) -> int:
	var raw_bait = runtime.get("prepared_bait", {})
	if raw_bait is Dictionary:
		return maxi(0, int((raw_bait as Dictionary).get("owned_count", 0)))
	return 0


static func _ready_card_maker_recipe_count(runtime: Dictionary) -> int:
	var count: int = 0
	var raw_recipes = runtime.get("card_maker_recipe_statuses", [])
	if not (raw_recipes is Array):
		return count
	for raw_recipe in raw_recipes:
		if raw_recipe is Dictionary and bool(
			(raw_recipe as Dictionary).get("can_make", false)
		):
			count += 1
	return count


static func _ratio(value: int, minimum: int) -> float:
	if minimum <= 0:
		return 1.0
	return clampf(float(value) / float(minimum), 0.0, 1.0)


static func _list_has_string(raw_values, expected: String) -> bool:
	if not (raw_values is PackedStringArray or raw_values is Array):
		return false
	for raw_value in raw_values:
		if str(raw_value) == expected:
			return true
	return false


