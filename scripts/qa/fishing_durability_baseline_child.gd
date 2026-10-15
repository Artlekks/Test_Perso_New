extends SceneTree

const PATH := "user://durability_baseline/inventory.json"

func _initialize() -> void:
	# Exact FileAccess.WRITE operation used by the original inventory writer.
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	var marker := FileAccess.open(PATH + ".marker", FileAccess.WRITE)
	marker.store_string("opened")
	marker.close()
	OS.delay_msec(15000)
	file.close()
	quit(0)
