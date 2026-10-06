class_name CityBuilder
extends RefCounted
## Deterministic procedural test city for mass-population movement.
## Graphics are intentionally primitive — geometry exists to create bottlenecks.

const BLOCK: float = 48.0
const STREET_W: float = 14.0
const WALL_H: float = 4.0


static func build(parent: Node3D, nav: NavGraph, world_seed: int = 42) -> Dictionary:
	## Returns metadata: building_exit_conn, extreme_building_region, plaza_region, spawn_points.
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	nav.clear()

	var meta := {
		"seed": world_seed,
		"building_exit_conn": -1,
		"extreme_building_region": -1,
		"plaza_region": -1,
		"spawn_points": [],
		"choke_connections": [],
	}

	_ground(parent)
	_grid_streets(parent, nav, meta)
	_buildings(parent, nav, rng, meta)
	_extreme_building(parent, nav, meta)
	_multi_floor_block(parent, nav, meta)
	return meta


static func _ground(parent: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var half := SimConfig.WORLD_HALF_EXTENT
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(half * 2.0, half * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.23, 0.18)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	parent.add_child(mi)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(half * 2.0, 1.0, half * 2.0)
	col.shape = shape
	col.position = Vector3(0, -0.5, 0)
	body.add_child(col)
	parent.add_child(body)


static func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, collide: bool = true) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.position = pos
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		parent.add_child(body)


static func _grid_streets(parent: Node3D, nav: NavGraph, meta: Dictionary) -> void:
	## 3x3 block grid → street regions + plaza at center.
	var coords: Array[Vector2i] = []
	for gz in range(-1, 2):
		for gx in range(-1, 2):
			coords.append(Vector2i(gx, gz))

	var street_ids: Dictionary = {} # "x,z" -> region id
	for c in coords:
		var center := Vector3(float(c.x) * BLOCK, 0.0, float(c.y) * BLOCK)
		var is_plaza := c.x == 0 and c.y == 0
		var kind := NavGraph.KIND_PLAZA if is_plaza else NavGraph.KIND_STREET
		var he := Vector3(STREET_W * 0.5 + 6.0, 2.0, STREET_W * 0.5 + 6.0)
		if is_plaza:
			he = Vector3(22.0, 2.0, 22.0)
		var region_name := "plaza" if is_plaza else "street_%d_%d" % [c.x, c.y]
		var cap := 80000 if is_plaza else 25000
		var rid := nav.add_region(region_name, kind, center, he, cap, 0)
		street_ids["%d,%d" % [c.x, c.y]] = rid
		if is_plaza:
			meta["plaza_region"] = rid
		# Visual road strip
		_box(parent, center + Vector3(0, 0.02, 0), Vector3(STREET_W, 0.04, STREET_W), Color(0.28, 0.28, 0.26), false)

	# Connect adjacent streets (cardinal)
	for c in coords:
		var key := "%d,%d" % [c.x, c.y]
		var a: int = street_ids[key]
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
		for d in dirs:
			var neighbor: Vector2i = c + d
			var nkey := "%d,%d" % [neighbor.x, neighbor.y]
			if not street_ids.has(nkey):
				continue
			var b: int = street_ids[nkey]
			var mid := (nav.regions[a].center + nav.regions[b].center) * 0.5
			var cid := nav.add_connection(a, b, mid, NavGraph.KIND_STREET, 400.0, true)
			meta["choke_connections"].append(cid)
		(meta["spawn_points"] as Array).append(nav.regions[a].center)


static func _buildings(parent: Node3D, nav: NavGraph, rng: RandomNumberGenerator, meta: Dictionary) -> void:
	## Place buildings in each quadrant with rooms, corridors, and narrow doors onto streets.
	var sites: Array[Vector3] = [
		Vector3(-BLOCK * 0.55, 0, -BLOCK * 0.55),
		Vector3(BLOCK * 0.55, 0, -BLOCK * 0.55),
		Vector3(-BLOCK * 0.55, 0, BLOCK * 0.55),
		Vector3(BLOCK * 0.55, 0, BLOCK * 0.55),
		Vector3(-BLOCK * 1.1, 0, 0),
		Vector3(BLOCK * 1.1, 0, 0),
		Vector3(0, 0, -BLOCK * 1.1),
		Vector3(0, 0, BLOCK * 1.1),
	]
	var bi := 0
	for site in sites:
		bi += 1
		_simple_building(parent, nav, site, "bldg_%d" % bi, rng, meta)


static func _simple_building(
	parent: Node3D,
	nav: NavGraph,
	origin: Vector3,
	name: String,
	rng: RandomNumberGenerator,
	meta: Dictionary
) -> void:
	var w := 18.0 + rng.randf() * 8.0
	var d := 16.0 + rng.randf() * 8.0
	var h := WALL_H
	# Outer shell walls (leave a door gap on +Z face)
	var wall_c := Color(0.4, 0.38, 0.34)
	_box(parent, origin + Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, 0.6), wall_c)
	_box(parent, origin + Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.6, h, d), wall_c)
	_box(parent, origin + Vector3(w * 0.5, h * 0.5, 0), Vector3(0.6, h, d), wall_c)
	# Front wall with door gap
	var door_w := 2.4
	var left_len := (w - door_w) * 0.5
	_box(parent, origin + Vector3(-w * 0.25 - door_w * 0.25, h * 0.5, d * 0.5), Vector3(left_len, h, 0.6), wall_c)
	_box(parent, origin + Vector3(w * 0.25 + door_w * 0.25, h * 0.5, d * 0.5), Vector3(left_len, h, 0.6), wall_c)
	# Interior partition → corridor + two rooms
	_box(parent, origin + Vector3(0, h * 0.5, 0), Vector3(w * 0.7, h, 0.5), Color(0.45, 0.42, 0.38))

	var room_a := nav.add_region(
		name + "_room_a",
		NavGraph.KIND_ROOM,
		origin + Vector3(0, 0, -d * 0.25),
		Vector3(w * 0.4, 2.0, d * 0.2),
		8000,
		0
	)
	var room_b := nav.add_region(
		name + "_room_b",
		NavGraph.KIND_ROOM,
		origin + Vector3(-w * 0.2, 0, d * 0.15),
		Vector3(w * 0.25, 2.0, d * 0.15),
		4000,
		0
	)
	var corridor := nav.add_region(
		name + "_corr",
		NavGraph.KIND_CORRIDOR,
		origin + Vector3(w * 0.2, 0, d * 0.15),
		Vector3(w * 0.2, 2.0, d * 0.15),
		1500,
		0
	)
	# Internal connections (narrow)
	var c1 := nav.add_connection(
		room_a, corridor,
		origin + Vector3(w * 0.1, 0, 0),
		NavGraph.KIND_DOOR, 40.0, true
	)
	var c2 := nav.add_connection(
		room_b, corridor,
		origin + Vector3(0, 0, d * 0.15),
		NavGraph.KIND_DOOR, 35.0, true
	)
	meta["choke_connections"].append(c1)
	meta["choke_connections"].append(c2)

	# Door onto nearest street
	var door_pos := origin + Vector3(0, 0, d * 0.5 + 1.0)
	var street := nav.nearest_region(door_pos)
	var exit_c := nav.add_connection(
		corridor, street, door_pos, NavGraph.KIND_DOOR, 45.0, true
	)
	meta["choke_connections"].append(exit_c)
	(meta["spawn_points"] as Array).append(nav.regions[room_a].center)


static func _extreme_building(parent: Node3D, nav: NavGraph, meta: Dictionary) -> void:
	## "The Building" — large enclosed structure for 100k density test.
	var origin := Vector3(-90.0, 0.0, 90.0)
	var w := 40.0
	var d := 36.0
	var h := WALL_H * 1.2
	var wall_c := Color(0.5, 0.35, 0.28)
	# Walls
	_box(parent, origin + Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, 0.8), wall_c)
	_box(parent, origin + Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.8, h, d), wall_c)
	_box(parent, origin + Vector3(w * 0.5, h * 0.5, 0), Vector3(0.8, h, d), wall_c)
	# Front with single narrow exit
	var door_w := 2.0
	var side := (w - door_w) * 0.5
	_box(parent, origin + Vector3(-(door_w * 0.5 + side * 0.5), h * 0.5, d * 0.5), Vector3(side, h, 0.8), wall_c)
	_box(parent, origin + Vector3((door_w * 0.5 + side * 0.5), h * 0.5, d * 0.5), Vector3(side, h, 0.8), wall_c)
	# Interior rooms + choke corridor to exit
	_box(parent, origin + Vector3(-8, h * 0.5, 0), Vector3(0.6, h, d * 0.6), Color(0.55, 0.4, 0.32))
	_box(parent, origin + Vector3(8, h * 0.5, -4), Vector3(0.6, h, d * 0.4), Color(0.55, 0.4, 0.32))

	var hall := nav.add_region(
		"extreme_hall",
		NavGraph.KIND_ROOM,
		origin + Vector3(0, 0, -4),
		Vector3(16, 2.5, 12),
		120000,
		0
	)
	var ante := nav.add_region(
		"extreme_ante",
		NavGraph.KIND_CORRIDOR,
		origin + Vector3(0, 0, d * 0.25),
		Vector3(6, 2.0, 5),
		8000,
		0
	)
	var exit_corr := nav.add_region(
		"extreme_exit_corr",
		NavGraph.KIND_CORRIDOR,
		origin + Vector3(0, 0, d * 0.5 + 2.0),
		Vector3(2.5, 2.0, 4.0),
		2000,
		0
	)
	nav.add_connection(hall, ante, origin + Vector3(0, 0, 6), NavGraph.KIND_DOOR, 60.0, true)
	var choke := nav.add_connection(
		ante, exit_corr, origin + Vector3(0, 0, d * 0.4), NavGraph.KIND_DOOR, 40.0, true
	)
	var street := nav.nearest_region(origin + Vector3(0, 0, d * 0.5 + 8.0))
	var exit_c := nav.add_connection(
		exit_corr, street, origin + Vector3(0, 0, d * 0.5 + 4.0), NavGraph.KIND_DOOR, 50.0, true
	)
	meta["extreme_building_region"] = hall
	meta["building_exit_conn"] = exit_c
	meta["choke_connections"].append(choke)
	meta["choke_connections"].append(exit_c)
	(meta["spawn_points"] as Array).append(nav.regions[hall].center)

	# Dead-end alley next to building
	var alley := nav.add_region(
		"dead_end_alley",
		NavGraph.KIND_CORRIDOR,
		origin + Vector3(-w * 0.5 - 6.0, 0, 0),
		Vector3(4, 2, 10),
		1500,
		0
	)
	nav.add_connection(alley, street, origin + Vector3(-w * 0.5 - 2.0, 0, d * 0.3), NavGraph.KIND_CORRIDOR, 80.0, true)
	_box(parent, origin + Vector3(-w * 0.5 - 6.0, h * 0.4, -8), Vector3(8, h * 0.8, 0.5), Color(0.35, 0.35, 0.32))


static func _multi_floor_block(parent: Node3D, nav: NavGraph, meta: Dictionary) -> void:
	## Two-floor structure with stairs for vertical flow.
	var origin := Vector3(90.0, 0.0, -80.0)
	var w := 22.0
	var d := 20.0
	var h0 := WALL_H
	var h1 := WALL_H
	var c0 := Color(0.38, 0.42, 0.48)
	var c1 := Color(0.42, 0.46, 0.52)
	# Floor 0 shell
	_box(parent, origin + Vector3(0, h0 * 0.5, -d * 0.5), Vector3(w, h0, 0.5), c0)
	_box(parent, origin + Vector3(-w * 0.5, h0 * 0.5, 0), Vector3(0.5, h0, d), c0)
	_box(parent, origin + Vector3(w * 0.5, h0 * 0.5, 0), Vector3(0.5, h0, d), c0)
	_box(parent, origin + Vector3(-w * 0.2, h0 * 0.5, d * 0.5), Vector3(w * 0.5, h0, 0.5), c0)
	# Floor slab + F1 walls
	_box(parent, origin + Vector3(0, h0, 0), Vector3(w - 1.0, 0.4, d - 1.0), Color(0.32, 0.34, 0.36), false)
	_box(parent, origin + Vector3(0, h0 + h1 * 0.5, -d * 0.5), Vector3(w, h1, 0.5), c1)
	_box(parent, origin + Vector3(-w * 0.5, h0 + h1 * 0.5, 0), Vector3(0.5, h1, d), c1)
	_box(parent, origin + Vector3(w * 0.5, h0 + h1 * 0.5, 0), Vector3(0.5, h1, d), c1)
	# Stair volume (visual)
	_box(parent, origin + Vector3(w * 0.3, h0 * 0.5, d * 0.2), Vector3(3.0, h0, 4.0), Color(0.5, 0.48, 0.4), false)

	var f0 := nav.add_region(
		"tower_f0", NavGraph.KIND_ROOM, origin, Vector3(w * 0.4, 2.0, d * 0.4), 6000, 0
	)
	var f1 := nav.add_region(
		"tower_f1",
		NavGraph.KIND_ROOM,
		origin + Vector3(0, SimConfig.FLOOR_HEIGHT, 0),
		Vector3(w * 0.4, 2.0, d * 0.4),
		6000,
		1
	)
	var stairs := nav.add_region(
		"tower_stairs",
		NavGraph.KIND_STAIRS,
		origin + Vector3(w * 0.3, SimConfig.FLOOR_HEIGHT * 0.5, d * 0.2),
		Vector3(2.0, SimConfig.FLOOR_HEIGHT * 0.6, 2.5),
		800,
		0
	)
	nav.add_connection(f0, stairs, origin + Vector3(w * 0.25, 0, d * 0.2), NavGraph.KIND_STAIRS, 30.0, true)
	nav.add_connection(
		stairs, f1,
		origin + Vector3(w * 0.25, SimConfig.FLOOR_HEIGHT, d * 0.2),
		NavGraph.KIND_STAIRS, 30.0, true
	)
	var street := nav.nearest_region(origin + Vector3(0, 0, d * 0.5 + 4.0))
	var exit_c := nav.add_connection(
		f0, street, origin + Vector3(w * 0.2, 0, d * 0.5 + 1.0), NavGraph.KIND_DOOR, 40.0, true
	)
	meta["choke_connections"].append(exit_c)
	(meta["spawn_points"] as Array).append(nav.regions[f0].center)
	(meta["spawn_points"] as Array).append(nav.regions[f1].center)
