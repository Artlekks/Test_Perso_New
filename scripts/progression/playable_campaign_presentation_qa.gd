extends RefCounted
class_name PlayableCampaignPresentationQA

const PolicyScript = preload(
	"res://scripts/progression/playable_campaign_presentation_policy.gd"
)


static func run() -> Dictionary:
	var failures := PackedStringArray()
	var passed: int = 0

	passed += _check(
		_enabled_ids(_snapshot("fresh_start", false)) == [],
		"Fresh save exposes no card-system interaction prompts.",
		failures
	)
	passed += _check(
		_enabled_ids(_snapshot("starter_case_search", false)) == [],
		"Starter-case search remains fishing-first.",
		failures
	)
	passed += _check(
		_enabled_ids(_snapshot("learn_loop", true)) == ["beach_trader"],
		"Learn Loop introduces the first card opponent without dumping later systems.",
		failures
	)
	passed += _check(
		_enabled_ids(_snapshot("connected_systems", true)) == [
			"beach_trader",
			"card_maker",
			"harbor_lockbox",
			"harbor_request",
		],
		"Connected Systems introduces Card Maker plus the two harbor rewards.",
		failures
	)
	passed += _check(
		_enabled_ids(_snapshot("specialization", true)) == [
			"beach_trader",
			"card_maker",
			"harbor_lockbox",
			"harbor_request",
			"regional_championship",
		],
		"Specialization exposes the full authored beach interaction set.",
		failures
	)
	passed += _check(
		bool(PolicyScript.feature_states(
			_snapshot("connected_systems", true, true, false)
		).get("regional_championship", false)),
		"An available Regional Championship is never hidden by campaign staging.",
		failures
	)
	passed += _check(
		bool(PolicyScript.feature_states(
			_snapshot("learn_loop", true, false, true)
		).get("regional_championship", false)),
		"An active tournament is never stranded by an earlier campaign phase.",
		failures
	)
	passed += _check(
		str(PolicyScript.transition_message(
			_snapshot("starter_case_search", false),
			_snapshot("learn_loop", true)
		).get("text", "")).contains("Saltworn Card Case"),
		"Starter-case discovery has one concise player-facing banner.",
		failures
	)
	var request_before := _snapshot("connected_systems", true)
	request_before["next_objective"] = {"code": "grow_card_collection"}
	var request_after := _snapshot("connected_systems", true)
	request_after["next_objective"] = {"code": "turn_in_harbor_request"}
	passed += _check(
		str(PolicyScript.transition_message(
			request_before,
			request_after
		).get("text", "")).contains("request complete"),
		"A newly-ready Harbor request produces actionable feedback.",
		failures
	)

	return {
		"passed_count": passed,
		"test_count": 9,
		"failures": failures,
	}


static func _snapshot(
	phase_id: String,
	card_game_unlocked: bool,
	regional_available: bool = false,
	regional_active: bool = false
) -> Dictionary:
	return {
		"phase_id": phase_id,
		"facts": {
			"card_game_unlocked": card_game_unlocked,
		},
		"systems": {
			"regional_championship": {
				"available": regional_available,
				"active": regional_active,
			},
		},
		"next_objective": {"code": ""},
	}


static func _enabled_ids(snapshot: Dictionary) -> Array:
	var states: Dictionary = PolicyScript.feature_states(snapshot)
	var result: Array = []
	for raw_id in states.keys():
		if bool(states[raw_id]):
			result.append(str(raw_id))
	result.sort()
	return result


static func _check(
	ok: bool,
	label: String,
	failures: PackedStringArray
) -> int:
	if ok:
		return 1
	failures.append(label)
	return 0
