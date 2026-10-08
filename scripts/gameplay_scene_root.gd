extends RefCounted

## Scene hosting only. Desktop remains the ordinary SceneTree current_scene.
static func resolve(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene != null and scene.has_method("get_gameplay_scene"):
		return scene.get_gameplay_scene()
	return scene

static func change_scene_to_file(tree: SceneTree, path: String) -> Error:
	var host := tree.current_scene
	if host != null and host.has_method("load_gameplay_scene"):
		return host.load_gameplay_scene(path)
	return tree.change_scene_to_file(path)
