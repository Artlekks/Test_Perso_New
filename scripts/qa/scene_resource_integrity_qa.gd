extends SceneTree
## Off-tree serialization checks for all actor families. Companion real-editor
## QA exercises actual Ctrl+S-equivalent EditorInterface saves and hot reload.
const OUTPUT := "res://build/mobile-web/scene-authoring-integrity"
var checks := 0
var failures: Array[String] = []
var audited := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func scenes(directory: String) -> Array[String]:
	var result: Array[String] = []
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".tscn"): result.append(directory + "/" + file)
	for child in DirAccess.get_directories_at(directory): result.append_array(scenes(directory + "/" + child))
	result.sort()
	return result
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var before_orphans := Node.get_orphan_node_ids()
	for path in scenes("res://actors"):
		var source: PackedScene = load(path)
		check(source != null, "scene loads " + path)
		if source == null: continue
		var actor: Node = source.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
		var presentation: Node = actor.get_node_or_null("GroundPresentation")
		var sprite: Node
		var anchor: Node = actor.get_node_or_null("GroundPresentation/VisualAnchor")
		if anchor != null:
			for child in anchor.get_children():
				if child is SpriteBase3D and not child is Label3D: sprite = child
		if presentation == null or sprite == null:
			actor.free()
			continue
		audited += 1
		var sprite_path := actor.get_path_to(sprite)
		var root_transform: Transform3D = actor.transform
		var profile_path: String = presentation.profile.resource_path
		var family_path: String = presentation.profile.resolved_shadow_family().resource_path
		var file_before := FileAccess.get_file_as_bytes(path)
		var uid_before := ResourceLoader.get_resource_uid(path)
		check(actor.is_editable_instance(presentation), "nested actor-owned art has serialization declaration " + path)
		check(sprite.owner != null, "sprite has scene owner " + path)
		var packed := PackedScene.new()
		check(packed.pack(actor) == OK, "pack editor-state actor " + path)
		var output := OUTPUT.path_join(path.trim_prefix("res://").replace("/", "_"))
		check(ResourceSaver.save(packed, output) == OK, "save actor copy " + path)
		var saved: PackedScene = ResourceLoader.load(output, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var restored: Node = saved.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
		check(restored.has_node(sprite_path), "saved actor retains sprite " + path)
		check(restored.transform.is_equal_approx(root_transform), "save preserves root transform " + path)
		var restored_presentation: Node = restored.get_node("GroundPresentation")
		check(restored_presentation.profile.resource_path == profile_path, "save preserves canonical profile " + path)
		check(restored_presentation.profile.resolved_shadow_family().resource_path == family_path, "save preserves shared shadow family " + path)
		check(restored_presentation.has_node("ShadowAnchor/WorldBlobShadow"), "save preserves one shared shadow " + path)
		check(FileAccess.get_file_as_bytes(path) == file_before and ResourceLoader.get_resource_uid(path) == uid_before, "fixture cannot rewrite source or UID " + path)
		restored.free()
		# Negative control recreates the diagnosed defect in memory only.
		if path in ["res://actors/ExplorationPlayer_V2.tscn", "res://actors/FishingCardMakerNPC.tscn", "res://actors/FishingMasterStillWaterNPC.tscn", "res://actors/BeachGatheringNode3D.tscn"]:
			actor.set_editable_instance(presentation, false)
			var broken := PackedScene.new()
			check(broken.pack(actor) == OK, "negative fixture packs " + path)
			var lost: Node = broken.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
			check(not lost.has_node(sprite_path), "missing declaration reproduces sprite omission " + path)
			check(lost is Node3D and lost.transform.is_equal_approx(root_transform), "negative control retains physical actor root " + path)
			lost.free()
		actor.free()
	check(Node.get_orphan_node_ids() == before_orphans, "serialization fixture releases every node")
	print("SCENE RESOURCE INTEGRITY QA: ", checks - failures.size(), "/", checks, "; actor families/scenes=", audited)
	quit(0 if failures.is_empty() else 1)
