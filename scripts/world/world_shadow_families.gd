extends RefCounted

const FAMILIES := {
 "player": preload("res://data/presentation/shadows/player.tres"),
 "humanoid_standard": preload("res://data/presentation/shadows/humanoid_standard.tres"),
 "humanoid_large": preload("res://data/presentation/shadows/humanoid_large.tres"),
 "humanoid_small": preload("res://data/presentation/shadows/humanoid_small.tres"),
 "critter": preload("res://data/presentation/shadows/critter.tres"),
 "ground_prop": preload("res://data/presentation/shadows/ground_prop.tres"),
 "item": preload("res://data/presentation/shadows/item.tres"),
}

static func resolve(id: StringName) -> WorldShadowFamily:
	# Existing ingestion manifests remain compatible; newly written profiles use
	# the explicit category names. Both aliases resolve to the same Resource.
	if id == &"humanoid": id = &"humanoid_standard"
	if id == &"small_creature": id = &"critter"
	return FAMILIES.get(String(id), FAMILIES.humanoid_standard)
