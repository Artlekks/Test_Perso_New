extends SceneTree
var output := "user://grounding_inventory.json"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")
func strip(node: Node) -> void:
	if node is GroundPresentation or node is WorldBlobShadow or node is BeachGatheringNode3D: return
	for child in node.get_children(): strip(child)
	node.set_script(null)
func vector(v: Vector3) -> Array: return [v.x, v.y, v.z]
func collision_bottom(shape: CollisionShape3D) -> float:
	var bounds := shape.shape.get_debug_mesh().get_aabb()
	var bottom := INF
	for corner in 8:
		bottom = minf(bottom, (shape.global_transform * bounds.get_endpoint(corner)).y)
	return bottom
func run() -> void:
	var scene = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	strip(scene)
	root.add_child(scene)
	for frame in 3: await process_frame
	var rows: Array = []
	var frames: Dictionary = {}
	for sprite in scene.find_children("*", "SpriteBase3D", true, false):
		if sprite is Label3D: continue
		var actor = sprite.get_parent()
		if actor.name == &"VisualAnchor": actor = actor.get_parent().get_parent()
		var row := {"path":str(sprite.get_path()), "root":str(actor.get_path()), "root_position":vector(actor.global_position), "sprite_position":vector(sprite.position), "offset":[sprite.offset.x,sprite.offset.y], "scale":vector(sprite.scale), "pixel_size":sprite.pixel_size,"billboard":sprite.billboard}
		if sprite is AnimatedSprite3D and sprite.sprite_frames != null:
			var resource: SpriteFrames = sprite.sprite_frames
			row["frames"] = resource.resource_path
			if not frames.has(resource.resource_path):
				var geometry: Array = []
				for animation in resource.get_animation_names():
					for i in resource.get_frame_count(animation):
						var texture = resource.get_frame_texture(animation,i)
						var image: Image
						if texture is AtlasTexture:
							image = Image.load_from_file(texture.atlas.resource_path).get_region(Rect2i(texture.region))
						else:
							image = Image.load_from_file(texture.resource_path)
						if image.is_compressed(): image.decompress()
						var rect = image.get_used_rect()
						geometry.append({"animation":animation,"frame":i,"size":[image.get_width(),image.get_height()],"alpha_rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"bottom_padding":image.get_height()-rect.end.y})
				frames[resource.resource_path] = geometry
		rows.append(row)
	var shapes: Array = []
	for shape in scene.find_children("*", "CollisionShape3D", true, false):
		shapes.append({"path":str(shape.get_path()),"position":vector(shape.global_position),"basis":str(shape.global_basis),"shape":str(shape.shape),"world_bottom":collision_bottom(shape),"disabled":shape.disabled,"layer":shape.get_parent().collision_layer,"mask":shape.get_parent().collision_mask})
	var f = FileAccess.open(output,FileAccess.WRITE)
	f.store_string(JSON.stringify({"sprites":rows,"frames":frames,"shapes":shapes,"ground":vector(scene.get_node("World/beach/Beach").global_position)},"\t"))
	f.close()
	scene.free()
	print("GROUNDING INVENTORY: ",output)
	quit()
