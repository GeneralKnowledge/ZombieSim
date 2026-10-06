extends Node3D
## City test bed: procedural streets/buildings + nav graph for mass populations.

@onready var interactables: Node3D = $Interactables

var nav: NavGraph = NavGraph.new()
var city_meta: Dictionary = {}
var _nav_debug: MeshInstance3D = null
var _flow_debug: MeshInstance3D = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		# Still build nav graph headlessly for benchmarks/validation.
		city_meta = CityBuilder.build(self, nav, SimConfig.WORLD_SEED)
		return
	city_meta = CityBuilder.build(self, nav, SimConfig.WORLD_SEED)
	print("City built seed=%d regions=%d connections=%d" % [
		city_meta.get("seed", 0), nav.region_count(), nav.connection_count()
	])


func setup_interactables(player: Node3D) -> void:
	if interactables and interactables.has_method("setup"):
		interactables.setup(player)


func get_nav() -> NavGraph:
	return nav


func get_city_meta() -> Dictionary:
	return city_meta


func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if SimConfig.show_navigation:
		_ensure_nav_debug()
	elif _nav_debug:
		_nav_debug.visible = false
	if SimConfig.show_flow_fields:
		_ensure_flow_debug()
	elif _flow_debug:
		_flow_debug.visible = false


func _ensure_nav_debug() -> void:
	if _nav_debug == null:
		_nav_debug = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.9, 0.85, 0.35)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_nav_debug.material_override = mat
		add_child(_nav_debug)
		_rebuild_nav_mesh()
	_nav_debug.visible = true


func _rebuild_nav_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in nav.regions:
		if not r.active:
			continue
		var c := r.center
		var hx := r.half_extents.x * 0.9
		var hz := r.half_extents.z * 0.9
		var y := 0.15
		st.add_vertex(c + Vector3(-hx, y, -hz))
		st.add_vertex(c + Vector3(hx, y, -hz))
		st.add_vertex(c + Vector3(hx, y, hz))
		st.add_vertex(c + Vector3(-hx, y, -hz))
		st.add_vertex(c + Vector3(hx, y, hz))
		st.add_vertex(c + Vector3(-hx, y, hz))
	_nav_debug.mesh = st.commit()


func _ensure_flow_debug() -> void:
	if _flow_debug == null:
		_flow_debug = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.55, 0.1, 0.8)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flow_debug.material_override = mat
		add_child(_flow_debug)
	_rebuild_flow_mesh()
	_flow_debug.visible = true


func _rebuild_flow_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in nav.regions.size():
		var r: NavGraph.NavRegion = nav.regions[i]
		if not r.active:
			continue
		var cid := nav.next_connection_from(i)
		if cid < 0:
			continue
		var conn: NavGraph.NavConnection = nav.connections[cid]
		st.add_vertex(r.center + Vector3(0, 1.0, 0))
		st.add_vertex(conn.position + Vector3(0, 1.0, 0))
	_flow_debug.mesh = st.commit()
