extends Node3D
## Simulation → positions → MultiMesh → GPU instancing.
## Does not own simulation state. Caps visible instances via MAX_VISIBLE_AGENTS.

@export var simulation_path: NodePath

var _sim_node: Node = null
var _batches_light: Array[MultiMeshInstance3D] = []
var _batches_active: Array[MultiMeshInstance3D] = []
var _batches_detailed: Array[MultiMeshInstance3D] = []
var _field_mmi: MultiMeshInstance3D
var _mesh_light: SphereMesh
var _mesh_active: SphereMesh
var _mesh_detailed: SphereMesh
var _mesh_field: SphereMesh
var _mat_light: StandardMaterial3D
var _mat_active: StandardMaterial3D
var _mat_detailed: StandardMaterial3D
var _mat_field: StandardMaterial3D

var _xform_cache: Array[Transform3D] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_build_materials()
	_field_mmi = _make_mmi(_mesh_field, _mat_field, 512)
	add_child(_field_mmi)


func bind_simulation(node: Node) -> void:
	_sim_node = node


func _build_materials() -> void:
	_mesh_light = SphereMesh.new()
	_mesh_light.radius = 0.2
	_mesh_light.height = 0.4
	_mesh_light.radial_segments = 4
	_mesh_light.rings = 2

	_mesh_active = SphereMesh.new()
	_mesh_active.radius = 0.32
	_mesh_active.height = 0.64
	_mesh_active.radial_segments = 6
	_mesh_active.rings = 3

	_mesh_detailed = SphereMesh.new()
	_mesh_detailed.radius = 0.45
	_mesh_detailed.height = 0.9
	_mesh_detailed.radial_segments = 8
	_mesh_detailed.rings = 4

	_mesh_field = SphereMesh.new()
	_mesh_field.radius = 1.0
	_mesh_field.height = 2.0
	_mesh_field.radial_segments = 8
	_mesh_field.rings = 4

	_mat_light = StandardMaterial3D.new()
	_mat_light.albedo_color = Color(0.55, 0.75, 0.25)
	_mat_light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_mat_active = StandardMaterial3D.new()
	_mat_active.albedo_color = Color(0.95, 0.55, 0.15)
	_mat_active.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_mat_detailed = StandardMaterial3D.new()
	_mat_detailed.albedo_color = Color(0.95, 0.2, 0.2)
	_mat_detailed.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_mat_field = StandardMaterial3D.new()
	_mat_field.albedo_color = Color(0.3, 0.55, 0.85, 0.55)
	_mat_field.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_field.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _make_mmi(mesh: Mesh, mat: Material, alloc: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = alloc
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _ensure_batches(pool: Array[MultiMeshInstance3D], mesh: Mesh, mat: Material, needed: int) -> void:
	var batch := SimConfig.MULTIMESH_BATCH_SIZE
	var batches_needed := int(ceili(float(needed) / float(batch)))
	while pool.size() < batches_needed:
		var mmi := _make_mmi(mesh, mat, batch)
		add_child(mmi)
		pool.append(mmi)
	for i in pool.size():
		pool[i].visible = i < batches_needed
		if i >= batches_needed:
			pool[i].multimesh.visible_instance_count = 0


func _process(_delta: float) -> void:
	if _sim_node == null or not _sim_node.has_method("get_simulation"):
		return
	# Headless/dummy renderer has no real mesh surfaces — skip GPU upload.
	if DisplayServer.get_name() == "headless":
		return
	var t0 := Time.get_ticks_usec()
	var world: SimulationWorld = _sim_node.get_simulation()
	_sync_agents(world)
	_sync_fields(world)
	Telemetry.render_time_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _sync_agents(world: SimulationWorld) -> void:
	var store: AgentStore = world.agents
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cam_pos: Vector3 = world.player_position
	if cam != null:
		cam_pos = cam.global_position
	var max_vis: int = SimConfig.MAX_VISIBLE_AGENTS
	var radius: float = SimConfig.RADIUS_VISIBLE
	var radius_sq: float = radius * radius

	# Collect candidates with cheap distance score; prefer nearer
	var light_idx := PackedInt32Array()
	var active_idx := PackedInt32Array()
	var detailed_idx := PackedInt32Array()
	var scored: Array[Vector2] = []

	for i in store.count:
		if store.alive[i] == 0:
			continue
		var dx: float = store.pos_x[i] - cam_pos.x
		var dy: float = store.pos_y[i] - cam_pos.y
		var dz: float = store.pos_z[i] - cam_pos.z
		var d2: float = dx * dx + dy * dy + dz * dz
		if d2 > radius_sq:
			continue
		scored.append(Vector2(d2, float(i)))

	scored.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var visible := 0
	for entry: Vector2 in scored:
		if visible >= max_vis:
			break
		var i: int = int(entry.y)
		match store.level[i]:
			SimConfig.LEVEL_DETAILED:
				detailed_idx.append(i)
			SimConfig.LEVEL_ACTIVE:
				active_idx.append(i)
			_:
				light_idx.append(i)
		visible += 1

	_upload(store, light_idx, _batches_light, _mesh_light, _mat_light, SimConfig.DOT_SCALE_LIGHTWEIGHT)
	_upload(store, active_idx, _batches_active, _mesh_active, _mat_active, SimConfig.DOT_SCALE_ACTIVE)
	_upload(store, detailed_idx, _batches_detailed, _mesh_detailed, _mat_detailed, SimConfig.DOT_SCALE_DETAILED)
	Telemetry.visible_dots = visible


func _upload(
	store: AgentStore,
	indices: PackedInt32Array,
	pool: Array[MultiMeshInstance3D],
	mesh: Mesh,
	mat: Material,
	scale: float
) -> void:
	_ensure_batches(pool, mesh, mat, maxi(indices.size(), 1))
	var batch := SimConfig.MULTIMESH_BATCH_SIZE
	var basis := Basis.IDENTITY.scaled(Vector3(scale, scale, scale))
	for b in pool.size():
		var mm: MultiMesh = pool[b].multimesh
		var start := b * batch
		if start >= indices.size():
			mm.visible_instance_count = 0
			continue
		var count := mini(batch, indices.size() - start)
		mm.visible_instance_count = count
		for k in count:
			var i: int = indices[start + k]
			var xf := Transform3D(basis, Vector3(store.pos_x[i], store.pos_y[i], store.pos_z[i]))
			mm.set_instance_transform(k, xf)


func _sync_fields(world: SimulationWorld) -> void:
	if not SimConfig.show_population_fields:
		_field_mmi.multimesh.visible_instance_count = 0
		return
	var cells: Array[PopulationFieldSystem.PopulationCell] = world.fields.cells
	var living: Array[PopulationFieldSystem.PopulationCell] = []
	for c in cells:
		if c.active and c.population > 0:
			living.append(c)
	var n: int = mini(living.size(), _field_mmi.multimesh.instance_count)
	_field_mmi.multimesh.visible_instance_count = n
	for i in n:
		var cell: PopulationFieldSystem.PopulationCell = living[i]
		var s: float = clampf(cell.radius * 0.35, 1.0, SimConfig.FIELD_MARKER_SCALE * 4.0)
		# Encode population loosely in scale
		s *= clampf(1.0 + log(float(cell.population) + 1.0) * 0.08, 1.0, 3.0)
		var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), cell.position)
		_field_mmi.multimesh.set_instance_transform(i, xf)
	# Field markers also contribute to visible count conceptually
	Telemetry.visible_dots += n
