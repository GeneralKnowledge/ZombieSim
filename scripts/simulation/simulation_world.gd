class_name SimulationWorld
extends RefCounted
## Owns all mass-population state. Rendering must not own this.
## Godot Nodes are not created for mass agents.

signal population_changed(total: int)

var agents: AgentStore = AgentStore.new()
var fields: PopulationFieldSystem = PopulationFieldSystem.new()
var hordes: HordeSystem = HordeSystem.new()
var spatial: SpatialHash = SpatialHash.new()
var relevance: RelevanceSystem = RelevanceSystem.new()

var player_position: Vector3 = Vector3.ZERO
var half_extent: float = 512.0
var _rng := RandomNumberGenerator.new()
var _rebuild_spatial_timer: float = 0.0
var _merge_timer: float = 0.0

# Per-tick counters
var last_materialised: int = 0
var last_dematerialised: int = 0
var last_agents_updated: int = 0


func _init() -> void:
	_rng.randomize()
	spatial.configure(SimConfig.CELL_SIZE)
	half_extent = SimConfig.WORLD_HALF_EXTENT


func clear() -> void:
	agents.clear()
	fields.clear()
	hordes.clear()
	spatial.clear()
	population_changed.emit(total_population())


func total_population() -> int:
	return agents.living_count() + fields.total_population()


func bootstrap(initial_pop: int) -> void:
	clear()
	if initial_pop <= 0:
		return
	# Large populations prefer field representation to keep agent arrays manageable.
	if initial_pop >= SimConfig.spawn_as_fields_above:
		var individual := mini(20000, initial_pop / 10)
		var field_pop := initial_pop - individual
		_spawn_agents(individual, Vector3.ZERO, half_extent * 0.8)
		fields.spawn_population_blob(field_pop, Vector3(80, 0, -40), half_extent * 0.6)
	else:
		_spawn_agents(initial_pop, Vector3.ZERO, half_extent * 0.75)
	spatial.rebuild_from_agents(agents)
	population_changed.emit(total_population())


func _spawn_agents(amount: int, center: Vector3, radius: float) -> void:
	agents.spawn_batch(amount, center, radius, SimConfig.LEVEL_LIGHTWEIGHT, SimConfig.FACTION_ZOMBIE, _rng)


func add_zombies(amount: int, as_horde: bool = false) -> void:
	if amount <= 0:
		return
	var center := player_position + Vector3(_rng.randf_range(-40, 40), 0, _rng.randf_range(-40, 40))
	if as_horde or amount >= 10000:
		# Aggregate path — do NOT create amount agent records if huge
		if amount >= 5000:
			hordes.create_horde(fields, amount, center, SimConfig.FACTION_ZOMBIE)
		else:
			_spawn_agents(amount, center, 30.0)
	else:
		_spawn_agents(amount, center, 25.0)
	population_changed.emit(total_population())


func create_horde(amount: int) -> int:
	var center := player_position + Vector3(30, 0, 30)
	var id := hordes.create_horde(fields, amount, center, SimConfig.FACTION_ZOMBIE)
	population_changed.emit(total_population())
	return id


func split_horde() -> void:
	var id := hordes.first_active_id()
	if id >= 0:
		hordes.split_horde(fields, id)


func merge_hordes() -> void:
	hordes.merge_nearest(fields)


func extreme_density_building(amount: int = 100000) -> void:
	## Represent extreme density as one constrained field — no 100k physics bodies.
	var door_pos := Vector3(0, 0, 0)
	var idx := fields.create_cell(amount, door_pos, SimConfig.FACTION_ZOMBIE, 6.0, 0, -1)
	var cell: PopulationFieldSystem.PopulationCell = fields.cells[idx]
	cell.density = 20.0
	cell.pressure = 15.0
	cell.alertness = 1.0
	cell.destination = door_pos + Vector3(0, 0, 40)
	population_changed.emit(total_population())


func tick(delta: float) -> void:
	last_materialised = 0
	last_dematerialised = 0
	last_agents_updated = 0
	if SimConfig.simulation_paused:
		return

	var attract := SimConfig.attract_active
	var t0: int
	var t_section: int

	t0 = Time.get_ticks_usec()
	# Population fields (Level 0)
	fields.update(delta, player_position, attract, half_extent)
	Telemetry.population_update_ms = float(Time.get_ticks_usec() - t0) / 1000.0

	t_section = Time.get_ticks_usec()
	hordes.update(delta, fields, player_position, attract)
	Telemetry.horde_update_ms = float(Time.get_ticks_usec() - t_section) / 1000.0

	t_section = Time.get_ticks_usec()
	var budget := SimConfig.MAX_AGENT_UPDATES_PER_FRAME
	# Prefer updating active/detailed first by temporarily higher budget when few agents
	last_agents_updated = agents.update_motion(delta, player_position, attract, budget, half_extent)
	Telemetry.agent_update_ms = float(Time.get_ticks_usec() - t_section) / 1000.0

	t_section = Time.get_ticks_usec()
	# Materialise gradually near player — never dump entire horde
	last_materialised = fields.materialise_near(
		agents,
		player_position,
		SimConfig.RADIUS_LIGHTWEIGHT,
		SimConfig.MAX_MATERIALISATIONS_PER_FRAME
	)
	# Dematerialise only under heavy individual load — small benches stay as dots.
	# Far lightweight agents collapse into Level 0 fields beyond a wide keep radius.
	if agents.living_count() > SimConfig.MAX_VISIBLE_AGENTS * 2:
		last_dematerialised = fields.absorb_agents(
			agents,
			player_position,
			SimConfig.RADIUS_VISIBLE * 1.5,
			SimConfig.MAX_MATERIALISATIONS_PER_FRAME
		)
	var level_changes := relevance.apply_levels(
		agents,
		player_position,
		SimConfig.MAX_MATERIALISATIONS_PER_FRAME,
		SimConfig.MAX_MATERIALISATIONS_PER_FRAME
	)
	last_materialised += level_changes.x
	last_dematerialised += level_changes.y
	Telemetry.materialisation_ms = float(Time.get_ticks_usec() - t_section) / 1000.0

	_merge_timer += delta
	if _merge_timer >= 0.5:
		_merge_timer = 0.0
		fields.try_merge(SimConfig.FIELD_MERGE_DISTANCE)
		fields.try_split_overdense()

	_rebuild_spatial_timer += delta
	if _rebuild_spatial_timer >= 0.2:
		_rebuild_spatial_timer = 0.0
		spatial.rebuild_from_agents(agents)

	_publish_telemetry()


func _publish_telemetry() -> void:
	Telemetry.population = total_population()
	Telemetry.lightweight_agents = agents.count_by_level(SimConfig.LEVEL_LIGHTWEIGHT)
	Telemetry.active_agents = agents.count_by_level(SimConfig.LEVEL_ACTIVE)
	Telemetry.detailed_agents = agents.count_by_level(SimConfig.LEVEL_DETAILED)
	Telemetry.population_fields = fields.living_count()
	Telemetry.horde_count = hordes.living_count()
	Telemetry.materialisations_this_frame = last_materialised
	Telemetry.dematerialisations_this_frame = last_dematerialised
