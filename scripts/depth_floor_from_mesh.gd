extends StaticBody3D

## Builds the water-bottom collision from the visible Bottom MeshInstance3D.
## The collision therefore follows the current GLB geometry after reimport.
@export var source_mesh_path: NodePath

func _ready() -> void:
    rebuild_from_source()

func rebuild_from_source() -> void:
    var source := get_node_or_null(source_mesh_path) as MeshInstance3D
    if source == null:
        push_warning("DepthFloor: source MeshInstance3D was not found: %s" % source_mesh_path)
        return

    if source.mesh == null:
        push_warning("DepthFloor: source mesh is empty: %s" % source_mesh_path)
        return

    var source_faces := source.mesh.get_faces()
    if source_faces.is_empty():
        push_warning("DepthFloor: source mesh has no triangle faces: %s" % source_mesh_path)
        return

    # Bake the Bottom mesh transform into collision vertices relative to World.
    # This avoids running the physics body itself at the GLB's 0.2 scale.
    var parent_3d := get_parent() as Node3D
    var source_to_parent := Transform3D.IDENTITY
    if parent_3d != null:
        source_to_parent = parent_3d.global_transform.affine_inverse() * source.global_transform

    var baked_faces := PackedVector3Array()
    baked_faces.resize(source_faces.size())
    for i in range(source_faces.size()):
        baked_faces[i] = source_to_parent * source_faces[i]

    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(baked_faces)

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    collision.shape = shape
    add_child(collision)
    collision.add_to_group(&"depth_zone")
