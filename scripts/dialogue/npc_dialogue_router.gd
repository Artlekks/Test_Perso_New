extends RefCounted
class_name NPCDialogueRouter

## Shared presentation helper for direct NPC speech.
##
## Rule:
## - direct NPC conversation -> DialogueService / dialogue box
## - live gameplay coaching/system feedback -> the existing HUD/info channels
##
## This helper owns no gameplay action. NPC scripts still decide what happens
## after a conversation (open a shop, start a duel, begin a lesson, etc.).


static func start_spoken_line(
	bridge: Node,
	dialogue_id: StringName,
	action_id: StringName,
	speaker_id: StringName,
	fallback_speaker_name: String,
	source_text: String,
	animated_sprite: AnimatedSprite3D = null,
	allow_cancel: bool = true,
	metadata: Dictionary = {}
) -> bool:
	if bridge == null or not bridge.has_method("start_single_line"):
		return false
	var speech := split_speaker_prefix(source_text, fallback_speaker_name)
	var spoken_text := str(speech.get("text", "")).strip_edges()
	if spoken_text.is_empty():
		return false
	var payload := metadata.duplicate(true)
	payload["npc_dialogue"] = true
	var result = bridge.call(
		"start_single_line",
		dialogue_id,
		action_id,
		speaker_id,
		str(speech.get("speaker_name", fallback_speaker_name)),
		spoken_text,
		portrait_from_sprite(animated_sprite),
		allow_cancel,
		payload
	)
	return bool(result)


static func split_speaker_prefix(
	source_text: String,
	fallback_speaker_name: String
) -> Dictionary:
	var clean_text := source_text.strip_edges()
	var speaker_name := fallback_speaker_name.strip_edges()
	var separator := clean_text.find(":")
	if separator > 0 and separator <= 48:
		var candidate := clean_text.substr(0, separator).strip_edges()
		var remainder := clean_text.substr(separator + 1).strip_edges()
		if (
			not candidate.is_empty()
			and not remainder.is_empty()
			and not candidate.contains("\n")
		):
			speaker_name = candidate
			clean_text = remainder
	if speaker_name.is_empty():
		speaker_name = "NPC"
	return {
		"speaker_name": speaker_name,
		"text": clean_text,
	}


static func humanize_id(
	raw_id,
	prefix_to_remove: String = "",
	fallback: String = "NPC"
) -> String:
	var clean := str(raw_id).strip_edges()
	if not prefix_to_remove.is_empty() and clean.begins_with(prefix_to_remove):
		clean = clean.substr(prefix_to_remove.length())
	if clean.is_empty():
		return fallback
	var words := PackedStringArray()
	for raw_part in clean.split("_", false):
		var part := str(raw_part).strip_edges()
		if not part.is_empty():
			words.append(part.capitalize())
	if words.is_empty():
		return fallback
	return " ".join(words)


static func portrait_from_sprite(
	animated_sprite: AnimatedSprite3D
) -> Texture2D:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return null
	var animation := animated_sprite.animation
	var frames := animated_sprite.sprite_frames
	if not frames.has_animation(animation):
		return null
	var frame_count := frames.get_frame_count(animation)
	if frame_count <= 0:
		return null
	var frame_index := clampi(animated_sprite.frame, 0, frame_count - 1)
	return frames.get_frame_texture(animation, frame_index)
