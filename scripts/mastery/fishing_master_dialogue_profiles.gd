extends RefCounted
class_name FishingMasterDialogueProfiles

const NPCDialogueRouterScript = preload("res://scripts/dialogue/npc_dialogue_router.gd")

## Presentation-only dialogue flavor for fishing masters.
##
## The lesson scripts remain the owners of progression, requirements, timers,
## rewards and success conditions. This table only supplies a second line that
## reflects where the player is in that lesson's relationship with the master.

const STATE_INTRO: StringName = &"intro"
const STATE_ACTIVE: StringName = &"active"
const STATE_LEARNED: StringName = &"learned"
const STATE_REVISIT: StringName = &"revisit"
const STATE_UNAVAILABLE: StringName = &"unavailable"

const PROFILES: Dictionary = {
	&"master_still_water": {
		"speaker_name": "Still Water",
		"intro": "Before you learn to catch fish, learn how not to announce yourself to them.",
		"active": "The bank is part of the cast. Disturb it, and the water remembers.",
		"learned": "Good. Quiet is a technique now, not an accident.",
		"revisit": "Stillness isn't waiting. It's choosing not to waste movement.",
	},
	&"master_current_reader": {
		"speaker_name": "Current Reader",
		"intro": "The water is carrying your lure before your hand ever touches the reel.",
		"active": "Don't correct every drift. First find out what the current is telling you.",
		"learned": "Good. Now you can see the river inside the sea.",
		"revisit": "Read the pull before you decide where the lure belongs.",
	},
	&"master_depth_reader": {
		"speaker_name": "Depth Reader",
		"intro": "Fish don't live on a flat map. Read the water from surface to bottom.",
		"active": "One cast tells you a layer. The lesson is learning the whole column.",
		"learned": "Good. Depth is no longer invisible to you.",
		"revisit": "Surface, middle, bottom. Choose the layer before the lure.",
	},
	&"master_structure_hunter": {
		"speaker_name": "Structure Hunter",
		"intro": "Useful water hides along edges, shade and cover, not only in open space.",
		"active": "Trace the shape. Fish use structure long before you notice the fish.",
		"learned": "Good. The shoreline has more geometry now.",
		"revisit": "Look for the place a fish can use, not just the place you can cast.",
	},
	&"master_line_fighter": {
		"speaker_name": "Line Fighter",
		"intro": "The line speaks before it breaks. Learn the difference between pull, hold and yield.",
		"active": "Stop watching only the gauge. Feel what the fish is asking from the line.",
		"learned": "Good. You listened instead of forcing it.",
		"revisit": "A strong line is not a rigid line. Give when giving keeps control.",
	},
	&"master_deepwater_veteran": {
		"speaker_name": "Deep-Water Veteran",
		"intro": "Deep fish win by making you panic when they dive. Follow first, lift second.",
		"active": "When it goes down, don't answer too early. Read the load.",
		"learned": "Good. The deep won't surprise your hands so easily now.",
		"revisit": "A dive is information. Follow it until the moment to lift is real.",
	},
	&"master_surface_angler": {
		"speaker_name": "Surface Angler",
		"intro": "A fish near the surface can turn one bad lift into a lost hook.",
		"active": "Keep the fight under the water. Don't invite the fish into the air.",
		"learned": "Good. You controlled the surface instead of fighting it.",
		"revisit": "Hot fish need direction more than force.",
	},
	&"master_landing_guide": {
		"speaker_name": "Landing Guide",
		"intro": "Most fish are lost when the angler thinks the fight is already over.",
		"active": "Watch the last meters. Lead the fish; don't drag it.",
		"learned": "Good. You finished the fight instead of merely surviving it.",
		"revisit": "The landing begins before the fish reaches your feet.",
	},
	&"master_weather_watcher": {
		"speaker_name": "Weather Watcher",
		"intro": "Weather isn't scenery. Light, wind and pressure change how the water behaves.",
		"active": "Watch what the sky does to the water, then what the fish do in return.",
		"learned": "Good. The sky is part of your tackle now.",
		"revisit": "Read the weather before you blame the lure.",
	},
	&"master_tide_reader": {
		"speaker_name": "Tide Reader",
		"intro": "The coast never stands still. Water is arriving, leaving or turning.",
		"active": "Don't memorize a spot. Read what the tide is doing to it now.",
		"learned": "Good. You stopped treating the shoreline like a fixed map.",
		"revisit": "The same place can be different water an hour later.",
	},
	&"master_sign_reader": {
		"speaker_name": "Sign Reader",
		"intro": "You won't always see the fish. Learn to see what the fish disturb.",
		"active": "Ripples, flashes, birds, movement. Let the signs add up before you decide.",
		"learned": "Good. Absence has clues now.",
		"revisit": "Stop searching for the fish itself. Search for what it changed.",
	},
	&"master_nature_guide": {
		"speaker_name": "Nature Guide",
		"intro": "Technique matters, but forcing the bank to obey you only makes you louder.",
		"active": "Settle into the place. Let your cast belong there.",
		"learned": "Good. You stopped standing outside the water and started fishing with it.",
		"revisit": "The best presentation looks like it was always going to happen.",
	},
	&"master_drift_angler": {
		"speaker_name": "Drift Angler",
		"intro": "Don't cast only at where the fish is. Cast for where the water will carry the lure.",
		"active": "Think one drift ahead. Placement is only the beginning.",
		"learned": "Good. Now the current is part of your aim.",
		"revisit": "A good drift starts before the lure touches the water.",
	},
}


static func classify_state(
	technique_known: bool,
	lesson_phase_value: int,
	completion_ack_pending: bool
) -> StringName:
	if technique_known:
		if completion_ack_pending:
			return STATE_LEARNED
		return STATE_REVISIT
	if lesson_phase_value <= 0:
		return STATE_INTRO
	return STATE_ACTIVE


static func has_profile(teacher_id: StringName) -> bool:
	return PROFILES.has(teacher_id)


static func get_profile_count() -> int:
	return PROFILES.size()


static func get_speaker_name(
	teacher_id: StringName,
	fallback: String = "Fishing Master"
) -> String:
	var profile = PROFILES.get(teacher_id, {})
	var speaker_name := str(profile.get("speaker_name", "")).strip_edges()
	if not speaker_name.is_empty():
		return speaker_name
	return NPCDialogueRouterScript.humanize_id(
		teacher_id,
		"master_",
		fallback
	)


static func get_state_line(
	teacher_id: StringName,
	state: StringName
) -> String:
	if state == STATE_UNAVAILABLE:
		return ""
	var profile = PROFILES.get(teacher_id, {})
	return str(profile.get(str(state), "")).strip_edges()


static func build_runtime_lines(
	teacher_id: StringName,
	state: StringName,
	source_text: String,
	animated_sprite: AnimatedSprite3D = null
) -> Array:
	var fallback_name := get_speaker_name(teacher_id)
	var speech: Dictionary = NPCDialogueRouterScript.split_speaker_prefix(
		source_text,
		fallback_name
	)
	var speaker_name := str(speech.get("speaker_name", fallback_name))
	var spoken_text := str(speech.get("text", "")).strip_edges()
	var portrait: Texture2D = NPCDialogueRouterScript.portrait_from_sprite(
		animated_sprite
	)
	var lines: Array = []

	# Preserve the original lesson instruction as the first page so cancelling a
	# conversation never hides information that the old one-line interaction gave.
	if not spoken_text.is_empty():
		lines.append({
			"speaker_id": teacher_id,
			"speaker_name": speaker_name,
			"portrait": portrait,
			"text": spoken_text,
		})

	var state_line := get_state_line(teacher_id, state)
	if not state_line.is_empty() and state_line != spoken_text:
		lines.append({
			"speaker_id": teacher_id,
			"speaker_name": fallback_name,
			"portrait": portrait,
			"text": state_line,
		})
	return lines
