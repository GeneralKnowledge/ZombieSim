extends Node3D
## Lightweight city-block stubs: cover, door, loot — enough of MVP #1 for the sandbox.

signal loot_taken(kind: String)
signal door_toggled(open: bool)

var door_open: bool = false
var _door_body: StaticBody3D
var _loot_nodes: Array[Area3D] = []
var _player: Node3D


func setup(player: Node3D) -> void:
	_player = player
	_build_cover()
	_build_door()
	_build_loot()


func _build_cover() -> void:
	var spots := [
		Vector3(8, 1, 6), Vector3(-10, 1, 12), Vector3(14, 1, -8),
		Vector3(-6, 1, -14), Vector3(22, 1, 18), Vector3(-18, 1, 4),
	]
	for p in spots:
		_static_box(p, Vector3(2.2, 2.0, 1.2), Color(0.38, 0.36, 0.32))


func _build_door() -> void:
	# Doorway gap in a short wall near spawn.
	_static_box(Vector3(0, 1.5, -22), Vector3(8, 3, 0.6), Color(0.4, 0.38, 0.34))
	_static_box(Vector3(10, 1.5, -22), Vector3(8, 3, 0.6), Color(0.4, 0.38, 0.34))
	_door_body = _static_box(Vector3(5, 1.5, -22), Vector3(2.2, 3, 0.5), Color(0.55, 0.35, 0.2))
	_door_body.name = "Door"


func _build_loot() -> void:
	_make_loot(Vector3(6, 0.5, -18), "ammo")
	_make_loot(Vector3(-8, 0.5, 8), "molotov")
	_make_loot(Vector3(16, 0.5, 4), "medkit")
	_make_loot(Vector3(-14, 0.5, -10), "ammo")


func _make_loot(pos: Vector3, kind: String) -> void:
	var area := Area3D.new()
	area.position = pos
	area.monitoring = true
	area.set_meta("loot_kind", kind)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	shape.shape = sphere
	area.add_child(shape)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.5, 0.8)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	match kind:
		"ammo":
			mat.albedo_color = Color(0.85, 0.75, 0.2)
		"molotov":
			mat.albedo_color = Color(0.95, 0.35, 0.1)
		"medkit":
			mat.albedo_color = Color(0.2, 0.85, 0.35)
		_:
			mat.albedo_color = Color(0.7, 0.7, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	area.add_child(mi)
	add_child(area)
	_loot_nodes.append(area)


func _static_box(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	return body


func _process(_delta: float) -> void:
	if _player == null:
		return
	if Input.is_action_just_pressed("interact"):
		_try_interact()


func _try_interact() -> void:
	var p := _player.global_position
	# Door
	if _door_body and p.distance_to(_door_body.global_position) < 3.5:
		door_open = not door_open
		_door_body.visible = not door_open
		_door_body.collision_layer = 0 if door_open else 1
		_door_body.collision_mask = 0 if door_open else 1
		door_toggled.emit(door_open)
		print("DOOR %s" % ("OPEN" if door_open else "CLOSED"))
		return
	# Loot
	for area in _loot_nodes:
		if not is_instance_valid(area):
			continue
		if p.distance_to(area.global_position) <= 2.0:
			var kind := str(area.get_meta("loot_kind"))
			loot_taken.emit(kind)
			area.queue_free()
			_loot_nodes.erase(area)
			print("LOOT %s" % kind)
			return
