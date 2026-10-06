extends Node3D
## Minimal 3D props. Keep draw calls tiny — this is a simulation benchmark.

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_build_ground()
	_build_roads()
	# Multi-floor shell + split wall — few meshes only.
	_build_simple_building()
	_box(Vector3(40, 2, 0), Vector3(4, 4, 80), Color(0.35, 0.33, 0.3))


func _build_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(SimConfig.WORLD_HALF_EXTENT * 2.0, SimConfig.WORLD_HALF_EXTENT * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.26, 0.18)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)


func _build_roads() -> void:
	_box(Vector3(0, 0.02, 0), Vector3(24, 0.04, SimConfig.WORLD_HALF_EXTENT * 2.0), Color(0.28, 0.28, 0.26))
	_box(Vector3(0, 0.02, 0), Vector3(SimConfig.WORLD_HALF_EXTENT * 2.0, 0.04, 24), Color(0.28, 0.28, 0.26))


func _build_simple_building() -> void:
	## One 3-floor volume + doorway notch (visual only). Not 12 wall pieces per floor.
	var origin := Vector3(-60, 0, -60)
	var h := SimConfig.FLOOR_HEIGHT * 3.0
	_box(origin + Vector3(0, h * 0.5, 0), Vector3(28, h, 28), Color(0.42, 0.4, 0.36))
	# Stair volume marker
	_box(origin + Vector3(10, h * 0.5, -8), Vector3(4, h, 6), Color(0.55, 0.48, 0.32))


func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)
