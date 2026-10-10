extends RefCounted
class_name SessionTestFixture
## Disposable composition wrapper. Free only the scene/session this fixture creates.
var tree: SceneTree
var scene: Node
var session: Node
var owns_session := false

func mount(target: SceneTree, mobile: bool = false, development: bool = false) -> Node:
	tree = target
	var previous := tree.root.get_node_or_null("FishingSessionServices")
	if previous == null and tree.root.has_meta("pending_fishing_session_services"):
		previous = tree.root.get_meta("pending_fishing_session_services").get_ref()
	var path := "res://actors/mobile/MobilePortraitHarness.tscn" if mobile else "res://actors/FishingTestScene_V2.tscn"
	scene = load(path).instantiate()
	if mobile:
		scene.isolated_playtest_save = false
	else:
		scene.development_tools_enabled = development
		var cards := scene.get_node("UI/TripleTriadGame")
		var menu := cards.get_node_or_null("TripleTriadDebugMenu")
		if not development and menu != null: menu.free()
	tree.root.add_child(scene)
	if mobile: preload("res://scripts/qa/mobile_qa_canvas.gd").prepare(tree)
	tree.current_scene = scene
	session = SessionComposition.acquire(tree)
	owns_session = previous == null
	return scene

func release() -> void:
	if is_instance_valid(scene):
		if tree.current_scene == scene: tree.current_scene = null
		scene.queue_free()
	if owns_session and is_instance_valid(session): session.queue_free()
	scene = null
	session = null
