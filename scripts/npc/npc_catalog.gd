extends Resource
class_name NPCCatalog
@export var entries: Array[NPCCatalogEntry] = []

func get_entry(id: StringName) -> NPCCatalogEntry:
	for entry in entries:
		if entry.id == id: return entry
	return null

