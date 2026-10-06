extends Node3D
## Simple 3D terrain + multi-floor building for navigation demos.
## Deliberately primitive — this is a simulation benchmark.

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_build_ground()
	_build_roads()
	_build_multi_floor_building()
	_build_obstacle_wall()


func _build_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(SimConfig.WORLD_HALF_EXTENT * 2.0, SimConfig.WORLD_HALF_EXTENT * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.26, 0.18)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(0, 0, 0)
	add_child(mi)


func _build_roads() -> void:
	_box(Vector3(0, 0.02, 0), Vector3(24, 0.04, SimConfig.WORLD_HALF_EXTENT * 2.0), Color(0.28, 0.28, 0.26))
	_box(Vector3(0, 0.02, 0), Vector3(SimConfig.WORLD_HALF_EXTENT * 2.0, 0.04, 24), Color(0.28, 0.28, 0.26))


func _build_multi_floor_building() -> void:
	var origin := Vector3(-60, 0, -60)
	var floor_h := SimConfig.FLOOR_HEIGHT
	for f in 3:
		var y := float(f) * floor_h
		# Floor slab
		_box(origin + Vector3(0, y + 0.1, 0), Vector3(28, 0.2, 28), Color(0.4, 0.38, 0.34))
		# Walls with door gap on +Z
		_box(origin + Vector3(-14, y + floor_h * 0.5, 0), Vector3(0.4, floor_h, 28), Color(0.45, 0.42, 0.38))
		_box(origin + Vector3(14, y + floor_h * 0.5, 0), Vector3(0.4, floor_h, 28), Color(0.45, 0.42, 0.38))
		_box(origin + Vector3(0, y + floor_h * 0.5, -14), Vector3(28, floor_h, 0.4), Color(0.45, 0.42, 0.38))
		# Front wall split for doorway
		_box(origin + Vector3(-8, y + floor_h * 0.5, 14), Vector3(12, floor_h, 0.4), Color(0.45, 0.42, 0.38))
		_box(origin + Vector3(8, y + floor_h * 0.5, 14), Vector3(12, floor_h, 0.4), Color(0.45, 0.42, 0.38))
		# Stairs (visual volumes — crowd flow uses floor_id later)
		_box(origin + Vector3(10, y + floor_h * 0.5, -8), Vector3(4, floor_h, 6), Color(0.55, 0.48, 0.32))


func _build_obstacle_wall() -> void:
	# Wall that encourages horde splitting
	_box(Vector3(40, 2, 0), Vector3(4, 4, 80), Color(0.35, 0.33, 0.3))


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
