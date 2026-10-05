extends FishingRewardClaimNPCBase
class_name FishingMasterGyosilNPC

const Policy = preload("res://scripts/progression/fishing_master_gyosil_policy.gd")
const SPEAKER_ID: StringName = &"master_gyosil"
const SPEAKER_NAME: String = "Master Gyosil"
const COMPLETE_DIALOGUE_ID: StringName = &"master_gyosil_complete"
const RUNTIME_DIALOGUE_ID: StringName = &"master_gyosil_runtime"
const PORTRAIT: Texture2D = preload("res://data/dialogue/portraits/master_gyosil.tres")


func _on_reward_interaction() -> void:
	if _reward_service == null:
		_speak("Come back when your fishing record is ready.", 3.0)
		return

	_reward_service.evaluate_rewards()
	var statuses: Array[Dictionary] = _reward_service.get_all_reward_statuses()
	var gyosil_statuses := Policy.filter_gyosil_statuses(statuses)
	if gyosil_statuses.is_empty():
		_speak("I have no reward record for you yet.", 3.0)
		return

	var claimable := Policy.get_claimable_keys(gyosil_statuses)
	if not claimable.is_empty():
		var claimed_names := PackedStringArray()
		for raw_key in claimable:
			var reward_key := StringName(raw_key)
			var before := _reward_service.get_reward_status(reward_key)
			var result := _reward_service.claim_reward(reward_key)
			if bool(result.get("claimed", false)):
				claimed_names.append(str(before.get("display_name", raw_key)))
		if not claimed_names.is_empty():
			_speak(
				"You've earned it. Take %s." % _join_reward_names(claimed_names),
				4.8
			)
			return

	var refreshed: Array[Dictionary] = _reward_service.get_all_reward_statuses()
	if Policy.are_all_rewards_claimed(refreshed):
		_play_animation(talk_animation)
		_start_authored_dialogue(
			COMPLETE_DIALOGUE_ID,
			SPEAKER_NAME,
			"You've claimed every point reward I can teach you toward. Keep fishing for the water, not the number.",
			4.8,
			PORTRAIT
		)
		return

	var next_status := Policy.get_next_unclaimed_status(refreshed)
	if next_status.is_empty():
		_speak("Keep fishing. Your next mark will come.", 3.2)
		return

	var display_name := str(next_status.get("display_name", "reward"))
	var progress_text := Policy.get_progress_text(next_status)
	_speak(
		"%s. Next reward: %s." % [progress_text, display_name],
		4.2
	)


func _speak(body: String, fallback_duration: float) -> void:
	_play_animation(talk_animation)
	_show_dialogue_line(
		SPEAKER_ID,
		SPEAKER_NAME,
		body,
		fallback_duration,
		RUNTIME_DIALOGUE_ID,
		PORTRAIT
	)


func _join_reward_names(names: PackedStringArray) -> String:
	if names.is_empty():
		return "your reward"
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return "%s and %s" % [names[0], names[1]]
	var prefix := ""
	for index in range(names.size() - 1):
		if not prefix.is_empty():
			prefix += ", "
		prefix += names[index]
	return "%s, and %s" % [prefix, names[names.size() - 1]]
