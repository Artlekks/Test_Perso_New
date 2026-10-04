extends RefCounted
class_name PlayableCampaignPresentationPolicy

## Pure player-facing campaign presentation rules.
##
## The campaign Director remains the authority for what state the save is in.
## This policy only decides which prototype world interactions should currently
## advertise themselves and which rare state transitions deserve a short banner.

const FEATURE_BEACH_TRADER := "beach_trader"
const FEATURE_CARD_MAKER := "card_maker"
const FEATURE_HARBOR_REQUEST := "harbor_request"
const FEATURE_HARBOR_LOCKBOX := "harbor_lockbox"
const FEATURE_REGIONAL_CHAMPIONSHIP := "regional_championship"

# Temporary development/UI-authoring override. This only keeps the world
# interaction/menu available; Card Maker backend rules remain authoritative.
const DEV_ALWAYS_SHOW_CARD_MAKER := true


static func feature_states(snapshot: Dictionary) -> Dictionary:
	var phase_id: String = str(snapshot.get("phase_id", "fresh_start"))
	var facts: Dictionary = _dict(snapshot.get("facts", {}))
	var systems: Dictionary = _dict(snapshot.get("systems", {}))
	var unlocked: bool = bool(facts.get("card_game_unlocked", false))

	var connected: bool = phase_id in [
		"connected_systems",
		"specialization",
		"campaign_foundation_complete",
	]
	var specialized: bool = phase_id in [
		"specialization",
		"campaign_foundation_complete",
	]

	var regional: Dictionary = _dict(
		systems.get("regional_championship", {})
	)
	var regional_override: bool = (
		bool(regional.get("active", false))
		or bool(regional.get("available", false))
	)

	return {
		FEATURE_BEACH_TRADER: unlocked,
		FEATURE_CARD_MAKER: (
			DEV_ALWAYS_SHOW_CARD_MAKER or (unlocked and connected)
		),
		FEATURE_HARBOR_REQUEST: unlocked and connected,
		FEATURE_HARBOR_LOCKBOX: unlocked and connected,
		FEATURE_REGIONAL_CHAMPIONSHIP: (
			unlocked and (specialized or regional_override)
		),
	}


static func transition_message(
	previous_snapshot: Dictionary,
	current_snapshot: Dictionary
) -> Dictionary:
	if previous_snapshot.is_empty() or current_snapshot.is_empty():
		return {}

	var previous_phase: String = str(
		previous_snapshot.get("phase_id", "")
	)
	var current_phase: String = str(
		current_snapshot.get("phase_id", "")
	)
	if current_phase != previous_phase:
		match current_phase:
			"learn_loop":
				return _message(
					"Saltworn Card Case recovered. Card duels are now available.",
					3.4,
					1
				)
			"connected_systems":
				return _message(
					"New harbor options are opening up: requests, lockboxes and the Card Maker.",
					3.8,
					1
				)
			"specialization":
				return _message(
					"Your fishing and card collection are ready for deeper specialization.",
					3.4,
					1
				)
			"campaign_foundation_complete":
				return _message(
					"The current campaign foundation is complete. Choose your own next goal.",
					3.6,
					1
				)

	var previous_objective: String = _objective_code(previous_snapshot)
	var current_objective: String = _objective_code(current_snapshot)
	if current_objective == previous_objective:
		return {}

	match current_objective:
		"turn_in_harbor_request":
			return _message(
				"Harbor request complete. Return to the request board.",
				3.0,
				1
			)
		"use_card_maker":
			return _message(
				"A Card Maker recipe is ready.",
				2.6,
				0
			)
		"continue_active_competition":
			return _message(
				"Your card tournament is still active.",
				2.8,
				1
			)

	return {}


static func _objective_code(snapshot: Dictionary) -> String:
	var objective: Dictionary = _dict(snapshot.get("next_objective", {}))
	return str(objective.get("code", ""))


static func _message(text: String, duration: float, priority: int) -> Dictionary:
	return {
		"text": text,
		"duration": duration,
		"priority": priority,
	}


static func _dict(value) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}
