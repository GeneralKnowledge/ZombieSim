extends Node3D
## Fast path: one uncolored MultiMesh for mass dots + tiny colored Multimesh for LOD.
## Bulk buffer upload. No sort. No SphereMesh.

var _sim_node: Node = null
var _mmi: MultiMeshInstance3D
var _lod_mmi: MultiMeshInstance3D
var _field_mmi: MultiMeshInstance3D
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _lod_buffer: PackedFloat32Array = PackedFloat32Array()
var _field_buffer: PackedFloat32Array = PackedFloat32Array()
var _scan_cursor: int = 0
var _frame_i: int = 0
var upload_interval: int = 1

const MASS_STRIDE := 12
const LOD_STRIDE := 16
const FIELD_STRIDE := 12
const LOD_CAP := 1536


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Software renderers cannot sustain full-rate MultiMesh uploads — throttle.
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	if "llvmpipe" in gpu or "softpipe" in gpu or "swrast" in gpu:
		upload_interval = 3
		# Level-colored LOD MultiMesh is a second upload; skip on software GL.
		SimConfig.show_simulation_levels = false
	_mmi = _make_mmi(_make_point_mesh(), _make_point_mat(Color(0.55, 0.78, 0.25)), false, SimConfig.MAX_VISIBLE_AGENTS)
	add_child(_mmi)
	_lod_mmi = _make_mmi(_make_point_mesh(), _make_point_mat(Color.WHITE), true, LOD_CAP)
	add_child(_lod_mmi)
	_field_mmi = _make_mmi(_make_field_mesh(), _make_mat(Color(0.35, 0.65, 0.95, 0.45), true), false, 256)
	add_child(_field_mmi)
	_buffer.resize(SimConfig.MAX_VISIBLE_AGENTS * MASS_STRIDE)
	_lod_buffer.resize(LOD_CAP * LOD_STRIDE)
	_field_buffer.resize(256 * FIELD_STRIDE)
	_mmi.multimesh.buffer = _buffer
	_lod_mmi.multimesh.buffer = _lod_buffer
	_field_mmi.multimesh.buffer = _field_buffer
	print("AgentRenderer ready mass=%d lod=%d upload_interval=%d gpu=%s" % [
		_mmi.multimesh.instance_count, LOD_CAP, upload_interval, RenderingServer.get_video_adapter_name()
	])


func bind_simulation(node: Node) -> void:
	_sim_node = node


func _make_mat(color: Color, transparent: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _make_point_mat(color: Color) -> StandardMaterial3D:
	var mat := _make_mat(color, false)
	mat.use_point_size = true
	mat.point_size = 3.0
	return mat


func _make_point_mesh() -> PointMesh:
	return PointMesh.new()


func _make_field_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.2
	var s := 1.0
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(-s, y, -s))
	st.add_vertex(Vector3(s, y, -s))
	st.add_vertex(Vector3(s, y, s))
	st.add_vertex(Vector3(-s, y, -s))
	st.add_vertex(Vector3(s, y, s))
	st.add_vertex(Vector3(-s, y, s))
	return st.commit()


func _make_mmi(mesh: Mesh, mat: Material, use_colors: bool, alloc: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_colors
	mm.mesh = mesh
	mm.instance_count = alloc
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _process(_delta: float) -> void:
	if _sim_node == null or _mmi == null:
		return
	if DisplayServer.get_name() == "headless":
		return
	_frame_i += 1
	if upload_interval > 1 and (_frame_i % upload_interval) != 0:
		return
	var t0 := Time.get_ticks_usec()
	var world: SimulationWorld = _sim_node.get_simulation()
	_sync_agents(world)
	_sync_fields(world)
	Telemetry.render_time_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _sync_agents(world: SimulationWorld) -> void:
	var store: AgentStore = world.agents
	var max_vis: int = SimConfig.MAX_VISIBLE_AGENTS
	var count: int = store.count
	if count == 0 or store.living == 0:
		_mmi.multimesh.visible_instance_count = 0
		_lod_mmi.multimesh.visible_instance_count = 0
		Telemetry.visible_dots = 0
		return

	var cam: Camera3D = get_viewport().get_camera_3d()
	var cx: float = world.player_position.x
	var cy: float = world.player_position.y
	var cz: float = world.player_position.z
	if cam != null:
		var cp := cam.global_position
		cx = cp.x
		cy = cp.y
		cz = cp.z

	var radius_sq: float = SimConfig.RADIUS_VISIBLE * SimConfig.RADIUS_VISIBLE
	var show_levels: bool = SimConfig.show_simulation_levels
	var mass_scale: float = SimConfig.DOT_SCALE_LIGHTWEIGHT
	var written := 0
	var lod_written := 0
	var scanned := 0
	var i: int = _scan_cursor
	var fits_all := store.living <= max_vis

	while scanned < count and written < max_vis:
		if store.alive[i] != 0:
			var px: float = store.pos_x[i]
			var py: float = store.pos_y[i]
			var pz: float = store.pos_z[i]
			var dx: float = px - cx
			var dy: float = py - cy
			var dz: float = pz - cz
			if dx * dx + dy * dy + dz * dz <= radius_sq:
				var lvl: int = store.level[i]
				if show_levels and lvl >= SimConfig.LEVEL_ACTIVE and lod_written < LOD_CAP:
					var scale: float = SimConfig.DOT_SCALE_ACTIVE if lvl == SimConfig.LEVEL_ACTIVE else SimConfig.DOT_SCALE_DETAILED
					var base: int = lod_written * LOD_STRIDE
					_lod_buffer[base + 0] = scale
					_lod_buffer[base + 1] = 0.0
					_lod_buffer[base + 2] = 0.0
					_lod_buffer[base + 3] = px
					_lod_buffer[base + 4] = 0.0
					_lod_buffer[base + 5] = scale
					_lod_buffer[base + 6] = 0.0
					_lod_buffer[base + 7] = py
					_lod_buffer[base + 8] = 0.0
					_lod_buffer[base + 9] = 0.0
					_lod_buffer[base + 10] = scale
					_lod_buffer[base + 11] = pz
					if lvl == SimConfig.LEVEL_ACTIVE:
						_lod_buffer[base + 12] = 0.95
						_lod_buffer[base + 13] = 0.55
						_lod_buffer[base + 14] = 0.15
					else:
						_lod_buffer[base + 12] = 0.95
						_lod_buffer[base + 13] = 0.2
						_lod_buffer[base + 14] = 0.2
					_lod_buffer[base + 15] = 1.0
					lod_written += 1
				else:
					var b: int = written * MASS_STRIDE
					_buffer[b + 0] = mass_scale
					_buffer[b + 1] = 0.0
					_buffer[b + 2] = 0.0
					_buffer[b + 3] = px
					_buffer[b + 4] = 0.0
					_buffer[b + 5] = mass_scale
					_buffer[b + 6] = 0.0
					_buffer[b + 7] = py
					_buffer[b + 8] = 0.0
					_buffer[b + 9] = 0.0
					_buffer[b + 10] = mass_scale
					_buffer[b + 11] = pz
					written += 1
		i += 1
		if i >= count:
			i = 0
		scanned += 1
		if fits_all and i == _scan_cursor and scanned > 0:
			break

	_scan_cursor = i
	_mmi.multimesh.visible_instance_count = written
	_lod_mmi.multimesh.visible_instance_count = lod_written
	if written > 0:
		_mmi.multimesh.buffer = _buffer
	if lod_written > 0:
		_lod_mmi.multimesh.buffer = _lod_buffer
	Telemetry.visible_dots = written + lod_written


func _sync_fields(world: SimulationWorld) -> void:
	if _field_mmi == null:
		return
	if not SimConfig.show_population_fields:
		_field_mmi.multimesh.visible_instance_count = 0
		return
	var cells: Array[PopulationFieldSystem.PopulationCell] = world.fields.cells
	var cap: int = _field_mmi.multimesh.instance_count
	var written := 0
	for cell in cells:
		if written >= cap:
			break
		if not cell.active or cell.population <= 0:
			continue
		var s: float = clampf(cell.radius * 0.25, 0.8, 8.0)
		s *= clampf(1.0 + log(float(cell.population) + 1.0) * 0.06, 1.0, 2.5)
		var base: int = written * FIELD_STRIDE
		_field_buffer[base + 0] = s
		_field_buffer[base + 1] = 0.0
		_field_buffer[base + 2] = 0.0
		_field_buffer[base + 3] = cell.position.x
		_field_buffer[base + 4] = 0.0
		_field_buffer[base + 5] = 0.15
		_field_buffer[base + 6] = 0.0
		_field_buffer[base + 7] = cell.position.y
		_field_buffer[base + 8] = 0.0
		_field_buffer[base + 9] = 0.0
		_field_buffer[base + 10] = s
		_field_buffer[base + 11] = cell.position.z
		written += 1
	_field_mmi.multimesh.visible_instance_count = written
	if written > 0:
		_field_mmi.multimesh.buffer = _field_buffer
