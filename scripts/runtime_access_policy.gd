extends RefCounted
class_name RuntimeAccessPolicy
## Optional runtime access provider. Absence means normal authored access.
static func current() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var binding = tree.root.get_meta("runtime_access_provider") if tree != null and tree.root.has_meta("runtime_access_provider") else null
	return binding.get_ref() if binding is WeakRef else null

static func bind(provider: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null: tree.root.set_meta("runtime_access_provider", weakref(provider))

static func unbind(provider: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and current() == provider: tree.root.remove_meta("runtime_access_provider")

static func allows(key: StringName) -> bool:
	var provider := current()
	return provider != null and bool(provider.call("allows_access", key))

static func card_test_deck(catalog: Resource, owned: Array, policy: Resource, rank: int, budget: int) -> Array:
	var provider := current()
	return provider.call("build_practice_deck", catalog, owned, policy, rank, budget) if provider != null else []
