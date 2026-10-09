@tool
extends EditorPlugin
## Runs only in the disposable project prepared by run_scene_authoring_qa.py.
## Uses the real EditorInterface save/reload path, never the designer's files.
const MAIN := "res://actors/FishingTestScene_V2.tscn"
const ACTORS := {
	"Player/CharacterBody3D": "res://actors/ExplorationPlayer_V2.tscn",
	"World/FishingMasterStillWaterNPC": "res://actors/FishingMasterStillWaterNPC.tscn",
	"World/FishingCardMakerNPC": "res://actors/FishingCardMakerNPC.tscn",
	"World/PopulationResident": "res://actors/npc/catalog/NPC_placeholder_cac2bbc2.tscn",
}
var checks := 0
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
func _enter_tree() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func settle() -> void:
	for frame in range(12): await get_tree().process_frame
func open_scene(path: String) -> Node:
	EditorInterface.open_scene_from_path(path)
	await settle()
	var edited := EditorInterface.get_edited_scene_root()
	check(edited != null and edited.scene_file_path == path, "editor opened " + path)
	return edited
func snapshot(parent: Node) -> Dictionary:
	var result := {}
	for path in ACTORS:
		var actor: Node3D = parent.get_node_or_null(path)
		check(actor != null, "parent retains instance " + path)
		if actor == null: continue
		var sprite: AnimatedSprite3D = actor.get_node_or_null("GroundPresentation/VisualAnchor/AnimatedSprite3D")
		check(sprite != null, "parent retains sprite " + path)
		check(actor.scene_file_path == ACTORS[path], "parent retains PackedScene binding " + path)
		var presentation: GroundPresentation = actor.get_node_or_null("GroundPresentation")
		var profile = presentation.profile if presentation != null else null
		result[path] = {"scene": actor.scene_file_path, "transform": var_to_str(actor.transform), "visible": actor.visible, "sprite": sprite != null, "profile": profile.resource_path if profile != null else "", "shadow_family": profile.resolved_shadow_family().resource_path if profile != null else "", "collider": actor.get_node_or_null("CollisionShape3D") != null or actor.get_node_or_null("BodyCollider/CollisionShape3D") != null}
	return result
func run() -> void:
	check(FileAccess.file_exists("res://AUTHORING_QA_DISPOSABLE"), "refuse to edit a non-disposable project")
	if not FileAccess.file_exists("res://AUTHORING_QA_DISPOSABLE"): return
	check(Engine.is_editor_hint(), "real editor lifecycle")
	while EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
	await settle()
	var parent: Node = await open_scene(MAIN)
	var baseline := snapshot(parent)
	check(EditorInterface.save_scene() == OK, "editor saves parent before child edits")
	var parent_text := FileAccess.get_file_as_string(MAIN)
	# Save each actor through EditorInterface, including edits to authored marker
	# copy. Mutations occur only in the disposable project and retain root transforms.
	for path in ACTORS:
		var actor: Node = await open_scene(ACTORS[path])
		var prompt: Label3D = actor.get_node_or_null("PromptLabel3D")
		if prompt != null: prompt.text += " [authoring QA]"
		else:
			var profile = actor.get_node("GroundPresentation").profile
			profile.marker_height += 0.001
			check(ResourceSaver.save(profile) == OK, "save actor profile " + path)
		check(EditorInterface.save_scene() == OK, "editor saves child " + path)
		var saved: PackedScene = ResourceLoader.load(ACTORS[path], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var saved_child := saved.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
		check(saved_child.has_node("GroundPresentation/VisualAnchor/AnimatedSprite3D"), "child serialization keeps actor sprite " + path)
		saved_child.free()
		check(FileAccess.get_file_as_string(MAIN) == parent_text, "child save does not delete parent instance text " + path)
		EditorInterface.reload_scene_from_path(MAIN)
		parent = await open_scene(MAIN)
		var after := snapshot(parent)
		check(after == baseline, "live editor parent remains intact after child save " + path)
		if prompt != null:
			var updated_prompt: Label3D = parent.get_node(path + "/PromptLabel3D")
			check(updated_prompt.text.ends_with(" [authoring QA]"), "saved child marker change propagates to parent " + path)
		evidence.append({"edited": ACTORS[path], "parent_before": baseline, "parent_after": after})
		check(EditorInterface.save_scene() == OK, "save reloaded parent " + path)
		parent_text = FileAccess.get_file_as_string(MAIN)
	# Saving the base must also retain the sprite for every inherited catalogue actor.
	for component in ["res://actors/npc/NPCActor.tscn", "res://actors/WorldGroundPresentation.tscn", "res://actors/WorldBlobShadow.tscn", "res://actors/WorldRequestMarker.tscn"]:
		await open_scene(component)
		check(EditorInterface.save_scene() == OK, "save shared component " + component)
		EditorInterface.reload_scene_from_path(MAIN)
		parent = await open_scene(MAIN)
		check(snapshot(parent) == baseline, "shared save retains parent actors " + component)
	for path in ["res://data/presentation/shadows/player.tres", "res://data/presentation/shadows/humanoid_standard.tres", "res://data/presentation/shadows/humanoid_large.tres"]:
		var family: WorldShadowFamily = load(path)
		var before := [family.width, family.depth, family.opacity, family.ground_offset]
		family.width = before[0] + 0.01
		family.depth = before[1] + 0.01
		family.opacity = before[2] + 0.01
		family.ground_offset = before[3] + 0.001
		check(ResourceSaver.save(family) == OK, "save shared shadow family " + path)
		await settle()
		var applied := 0
		for actor_path in ACTORS:
			var actor: Node = parent.get_node_or_null(actor_path)
			if actor == null: continue
			var presentation: GroundPresentation = actor.get_node("GroundPresentation")
			if presentation.profile.resolved_shadow_family().resource_path != path: continue
			var shadow: WorldBlobShadow = presentation.get_node("ShadowAnchor/WorldBlobShadow")
			check(is_equal_approx(shadow.width, family.width * presentation.profile.shadow_scale_multiplier), "family edit propagates without editable child tuning " + actor_path)
			check(is_equal_approx(shadow.depth, family.depth * presentation.profile.shadow_scale_multiplier) and is_equal_approx(shadow.opacity, family.opacity) and is_equal_approx(shadow.ground_offset, family.ground_offset), "all shared shadow controls propagate " + actor_path)
			applied += 1
		if applied == 0 and family.family == &"humanoid_large":
			# This family is available but currently assigned to no production
			# profile. Verify the supported opt-in on a disposable preview only.
			var presentation: GroundPresentation = parent.get_node("World/FishingCardMakerNPC/GroundPresentation")
			var original_profile := presentation.profile
			var preview: WorldActorPresentationProfile = original_profile.duplicate()
			preview.shadow_family_resource = family
			presentation.profile = preview
			await settle()
			check(is_equal_approx(presentation.shadow.width, family.width * preview.shadow_scale_multiplier), "unused large family works through a profile override")
			check(is_equal_approx(presentation.shadow.depth, family.depth * preview.shadow_scale_multiplier) and is_equal_approx(presentation.shadow.opacity, family.opacity) and is_equal_approx(presentation.shadow.ground_offset, family.ground_offset), "unused large family controls propagate")
			presentation.profile = original_profile
			await settle()
			applied += 1
		check(applied > 0, "family exercised by an actor/profile " + path)
		check(snapshot(parent) == baseline, "family save preserves actor transforms/bindings " + path)
		family.width = before[0]
		family.depth = before[1]
		family.opacity = before[2]
		family.ground_offset = before[3]
		check(ResourceSaver.save(family) == OK, "restore disposable family " + path)
	# Cold reload verifies disk serialization, not just cached live editor nodes.
	var fresh: PackedScene = ResourceLoader.load(MAIN, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var reloaded := fresh.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	check(snapshot(reloaded) == baseline, "cold parent reload keeps all actors, transforms and resources")
	reloaded.free()
	var report := {"checks": checks, "failures": failures, "evidence": evidence}
	var file := FileAccess.open("res://authoring-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SCENE INSTANCE EDITOR AUTHORING QA: ", checks - failures.size(), "/", checks)
	get_tree().quit(1 if not failures.is_empty() else 0)
