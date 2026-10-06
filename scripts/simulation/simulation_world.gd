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
var fire: FireSystem = FireSystem.new()
var combat: CombatRing = CombatRing.new()
var nav: NavGraph = NavGraph.new()
var journeys: JourneySystem = JourneySystem.new()

var player_position: Vector3 = Vector3.ZERO
var player_aim: Vector3 = Vector3(0, 0, -1)
var half_extent: float = 512.0
var city_meta: Dictionary = {}
var world_seed: int = 42
var _rng := RandomNumberGenerator.new()
var _rebuild_spatial_timer: float = 0.0
var _merge_timer: float = 0.0
var _flow_rebuild_timer: float = 0.0
var _auto_merge_timer: float = 0.0
var _last_attract: bool = false

# Per-tick counters
var last_materialised: int = 0
var last_dematerialised: int = 0
var last_agents_updated: int = 0
var last_population_transfers: int = 0
var last_nav_flow_rebuilds: int = 0
var last_path_queries: int = 0
var last_horde_splits: int = 0
var last_horde_merges: int = 0
var last_journey_arrivals: int = 0


func _init() -> void:
	_rng.randomize()
	spatial.configure(SimConfig.CELL_SIZE)
	half_extent = SimConfig.WORLD_HALF_EXTENT
	world_seed = SimConfig.WORLD_SEED


func clear() -> void:
	agents.clear()
	fields.clear()
	hordes.clear()
	spatial.clear()
	fire.clear()
	combat.clear_stats()
	journeys.clear()
	# Keep nav graph — city topology is world geometry.
	population_changed.emit(total_population())


func total_population() -> int:
	return agents.living_count() + fields.total_population() + journeys.total_population()


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
	_assign_regions_to_fields()
	spatial.rebuild_from_agents(agents)
	population_changed.emit(total_population())


## M9 city distribution: population across buildings/streets as fields + sparse agents.
func bootstrap_city(initial_pop: int, seed: int = -1) -> void:
	clear()
	if seed >= 0:
		world_seed = seed
		_rng.seed = seed
	else:
		_rng.seed = world_seed
	if initial_pop <= 0:
		population_changed.emit(0)
		return
	var points: Array = city_meta.get("spawn_points", [])
	if points.is_empty():
		# Fallback if city not built yet.
		bootstrap(initial_pop)
		return
	var remaining := initial_pop
	var n_sites := points.size()
	# Keep a small individual ring near plaza for combat demos.
	var individual := mini(1500, initial_pop / 50)
	remaining -= individual
	var plaza: Vector3 = Vector3.ZERO
	if city_meta.has("plaza_region") and int(city_meta["plaza_region"]) >= 0:
		var pr: int = int(city_meta["plaza_region"])
		if pr < nav.regions.size():
			plaza = nav.regions[pr].center
	_spawn_agents(individual, plaza, 25.0)

	# Distribute remaining across spawn sites as field blobs / hordes.
	var per := remaining / maxi(n_sites, 1)
	var leftover := remaining - per * n_sites
	for i in n_sites:
		var center: Vector3 = points[i]
		var amount := per + (leftover if i == 0 else 0)
		if amount <= 0:
			continue
		if amount >= 5000:
			hordes.create_horde(fields, amount, center, SimConfig.FACTION_ZOMBIE, nav)
		else:
			fields.spawn_population_blob(amount, center, 20.0, SimConfig.FACTION_ZOMBIE)
	_assign_regions_to_fields()
	spatial.rebuild_from_agents(agents)
	if not (total_population() == initial_pop): push_warning("Conservation check failed: total_population() == initial_pop")
	population_changed.emit(total_population())


## Benchmark I / extreme density: pack pop into The Building as fields.
func bootstrap_bottleneck(amount: int = 100000) -> void:
	clear()
	extreme_density_building(amount)


func bind_city_meta(meta: Dictionary) -> void:
	city_meta = meta


func _assign_regions_to_fields() -> void:
	if nav.region_count() == 0:
		return
	for cell in fields.cells:
		if cell.active:
			cell.region_id = nav.find_region_at(cell.position)


func _spawn_agents(amount: int, center: Vector3, radius: float) -> void:
	var r := radius
	if amount <= 10000:
		r = minf(radius, 90.0)
	elif amount <= 50000:
		r = minf(radius, 160.0)
	agents.spawn_batch(amount, center, r, SimConfig.LEVEL_LIGHTWEIGHT, SimConfig.FACTION_ZOMBIE, _rng)


func add_zombies(amount: int, as_horde: bool = false) -> void:
	if amount <= 0:
		return
	var before := total_population()
	var center := player_position + Vector3(_rng.randf_range(-40, 40), 0, _rng.randf_range(-40, 40))
	if as_horde or amount >= 10000:
		if amount >= 5000:
			hordes.create_horde(fields, amount, center, SimConfig.FACTION_ZOMBIE, nav)
		else:
			_spawn_agents(amount, center, 30.0)
	else:
		_spawn_agents(amount, center, 25.0)
	_assign_regions_to_fields()
	if not (total_population() == before + amount): push_warning("Conservation check failed: total_population() == before + amount")
	population_changed.emit(total_population())


func create_horde(amount: int) -> int:
	var before := total_population()
	var center := player_position + Vector3(30, 0, 30)
	var id := hordes.create_horde(fields, amount, center, SimConfig.FACTION_ZOMBIE, nav)
	_assign_regions_to_fields()
	if not (total_population() == before + amount): push_warning("Conservation check failed: total_population() == before + amount")
	population_changed.emit(total_population())
	return id


func split_horde() -> void:
	var id := hordes.first_active_id()
	if id >= 0:
		var before := total_population()
		hordes.split_horde(fields, id)
		if not (total_population() == before): push_warning("Conservation check failed: total_population() == before")


func merge_hordes() -> void:
	var before := total_population()
	hordes.merge_nearest(fields)
	if not (total_population() == before): push_warning("Conservation check failed: total_population() == before")


func extreme_density_building(amount: int = 100000) -> void:
	## Represent extreme density as constrained fields inside The Building — no 100k physics bodies.
	var before := total_population()
	var hall_id: int = int(city_meta.get("extreme_building_region", -1))
	var center := Vector3(-90, 0, 86)
	if hall_id >= 0 and hall_id < nav.regions.size():
		center = nav.regions[hall_id].center
	# Multiple cells inside the hall to represent pressure without agent spawn.
	var chunks := maxi(1, amount / 8000)
	var remaining := amount
	var created_ids: PackedInt32Array = PackedInt32Array()
	for i in chunks:
		var chunk := remaining / (chunks - i)
		remaining -= chunk
		var offset := Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-6, 6))
		var idx := fields.create_cell(chunk, center + offset, SimConfig.FACTION_ZOMBIE, 10.0, 0, -1)
		var cell: PopulationFieldSystem.PopulationCell = fields.cells[idx]
		cell.density = 18.0
		cell.pressure = 12.0
		cell.alertness = 0.9
		cell.region_id = hall_id
		cell.destination = center + Vector3(0, 0, 40)
		created_ids.append(idx)
	# Wrap as one horde for collective behaviour.
	if created_ids.size() > 0:
		hordes.adopt_cells(fields, created_ids, center, SimConfig.FACTION_ZOMBIE, hall_id)
	if not (total_population() == before + amount): push_warning("Conservation check failed: total_population() == before + amount")
	population_changed.emit(total_population())


func throw_molotov() -> int:
	if fire.living_count() >= SimConfig.MAX_FIRE_VOLUMES:
		return -1
	return fire.throw_molotov(player_position, player_aim, 0)


func shoot() -> Dictionary:
	return combat.shoot(agents, fields, player_position, player_aim)


func reset_benchmark() -> void:
	Telemetry.reset_stats()
	combat.clear_stats()
	var pop := SimConfig.initial_population
	if city_meta.get("spawn_points", []).size() > 0:
		bootstrap_city(pop)
	else:
		bootstrap(pop)


func tick(delta: float) -> void:
	last_materialised = 0
	last_dematerialised = 0
	last_agents_updated = 0
	last_population_transfers = 0
	last_nav_flow_rebuilds = 0
	last_path_queries = 0
	last_horde_splits = 0
	last_horde_merges = 0
	last_journey_arrivals = 0
	nav.reset_frame_counters()
	if SimConfig.simulation_paused:
		return

	var attract := SimConfig.attract_active
	var t0: int
	var t_section: int
	var has_fields := fields.living_count() > 0
	var has_hordes := hordes.living_count() > 0
	var has_nav := nav.region_count() > 0

	# Rebuild destination flow when attraction toggles or periodically while attracting.
	if has_nav:
		_flow_rebuild_timer += delta
		var need_flow := attract and (attract != _last_attract or _flow_rebuild_timer >= SimConfig.FLOW_REBUILD_INTERVAL)
		if need_flow:
			_flow_rebuild_timer = 0.0
			nav.rebuild_flow_to_position(player_position)
		elif not attract and _last_attract:
			nav.flow_dest_region = -1
		last_nav_flow_rebuilds = nav.last_flow_rebuilds
	_last_attract = attract

	t0 = Time.get_ticks_usec()
	if has_fields:
		fields.update(delta, player_position, attract, half_extent, nav if has_nav else null)
		if has_nav and attract:
			last_population_transfers = fields.apply_nav_transfers(nav, delta)
	Telemetry.population_update_ms = float(Time.get_ticks_usec() - t0) / 1000.0

	t_section = Time.get_ticks_usec()
	if has_hordes:
		hordes.update(delta, fields, player_position, attract, nav if has_nav else null)
		last_horde_splits = hordes.last_splits
		last_horde_merges = hordes.last_merges
	Telemetry.horde_update_ms = float(Time.get_ticks_usec() - t_section) / 1000.0

	# Journey system — distant aggregate travel without continuous field updates.
	t_section = Time.get_ticks_usec()
	_update_journeys(delta, attract)
	Telemetry.journey_update_ms = float(Time.get_ticks_usec() - t_section) / 1000.0

	t_section = Time.get_ticks_usec()
	var budget := SimConfig.MAX_AGENT_UPDATES_PER_FRAME
	last_agents_updated = agents.update_motion(delta, player_position, attract, budget, half_extent)
	Telemetry.agent_update_ms = float(Time.get_ticks_usec() - t_section) / 1000.0

	t_section = Time.get_ticks_usec()
	if has_fields:
		last_materialised = fields.materialise_near(
			agents,
			player_position,
			SimConfig.RADIUS_LIGHTWEIGHT,
			SimConfig.MAX_MATERIALISATIONS_PER_FRAME
		)
	if agents.living > SimConfig.MAX_VISIBLE_AGENTS * 2:
		last_dematerialised = fields.absorb_agents(
			agents,
			player_position,
			SimConfig.RADIUS_VISIBLE * 1.5,
			SimConfig.MAX_MATERIALISATIONS_PER_FRAME
		)
	if agents.living > 0:
		last_materialised += combat.maintain_ring(
			agents, player_position, SimConfig.COMBAT_PROMOTIONS_PER_TICK
		)
	if agents.living > 0 and SimConfig.show_simulation_levels:
		var level_changes := relevance.apply_levels(
			agents,
			player_position,
			SimConfig.MAX_MATERIALISATIONS_PER_FRAME,
			SimConfig.MAX_MATERIALISATIONS_PER_FRAME
		)
		last_materialised += level_changes.x
		last_dematerialised += level_changes.y
	if fire.living_count() > 0:
		fire.update(delta, agents, fields)
	Telemetry.materialisation_ms = float(Time.get_ticks_usec() - t_section) / 1000.0

	if has_fields:
		_merge_timer += delta
		if _merge_timer >= 0.5:
			_merge_timer = 0.0
			fields.try_merge(SimConfig.FIELD_MERGE_DISTANCE)
			fields.try_split_overdense()

	# Auto-merge nearby hordes with shared destination (aggregate).
	if has_hordes:
		_auto_merge_timer += delta
		if _auto_merge_timer >= 1.0:
			_auto_merge_timer = 0.0
			var m := hordes.merge_nearest(fields)
			if m >= 0:
				last_horde_merges += 1

	_rebuild_spatial_timer += delta
	if _rebuild_spatial_timer >= 1.0 and agents.living > 0:
		_rebuild_spatial_timer = 0.0
		spatial.rebuild_from_agents(agents)

	last_path_queries = nav.last_path_queries
	_publish_telemetry()


func _update_journeys(delta: float, attract: bool) -> void:
	# Promote very distant hordes to journeys when far from player.
	if SimConfig.JOURNEY_ENABLED and hordes.living_count() > 0:
		var journey_r2 := SimConfig.RADIUS_JOURNEY * SimConfig.RADIUS_JOURNEY
		for horde in hordes.hordes:
			if not horde.active or horde.population < SimConfig.JOURNEY_MIN_POP:
				continue
			var d2 := horde.center.distance_squared_to(player_position)
			if d2 < journey_r2:
				continue
			# Only journey when not near and has a clear destination.
			if not attract and horde.destination.distance_squared_to(horde.center) < 100.0:
				continue
			var dest := player_position if attract else horde.destination
			var route := PackedInt32Array()
			var ticks := 60
			if nav.region_count() > 0:
				var from_r := nav.find_region_at(horde.center)
				var to_r := nav.find_region_at(dest)
				route = nav.route_region_ids(from_r, to_r)
				ticks = maxi(40, route.size() * 25)
			var payload := hordes.extract_for_journey(fields, horde.id)
			if payload.is_empty():
				continue
			journeys.create_journey(
				int(payload["population"]),
				payload["origin"],
				dest,
				route,
				ticks,
				1 if attract else 0,
				int(payload["faction"]),
				int(payload["horde_id"])
			)

	var arrived := journeys.update(delta)
	last_journey_arrivals = arrived.size()
	for j in arrived:
		# Reconstruct as a field/horde at destination — population conserved.
		if j.population <= 0:
			continue
		hordes.create_horde(fields, j.population, j.destination, j.faction, nav)


func _publish_telemetry() -> void:
	Telemetry.population = total_population()
	Telemetry.lightweight_agents = agents.count_lightweight
	Telemetry.active_agents = agents.count_active
	Telemetry.detailed_agents = agents.count_detailed
	Telemetry.population_fields = fields.living_count()
	Telemetry.horde_count = hordes.living_count()
	Telemetry.materialisations_this_frame = last_materialised
	Telemetry.dematerialisations_this_frame = last_dematerialised
	Telemetry.fire_volumes = fire.living_count()
	Telemetry.combat_ring_agents = combat.ring_agent_count
	Telemetry.shots_fired = combat.shots_fired
	Telemetry.kills_individual = combat.individual_kills + fire.total_agent_kills
	Telemetry.kills_field = combat.field_kills + fire.total_field_kills
	Telemetry.agent_updates = last_agents_updated
	Telemetry.nav_regions = nav.region_count()
	Telemetry.nav_connections = nav.connection_count()
	Telemetry.nav_flow_rebuilds = last_nav_flow_rebuilds
	Telemetry.path_requests = last_path_queries
	Telemetry.population_transfers = last_population_transfers
	Telemetry.transfer_population = fields.last_transfer_pop
	Telemetry.horde_splits = last_horde_splits + fields.last_splits
	Telemetry.horde_merges = last_horde_merges + fields.last_merges
	Telemetry.journey_count = journeys.living_count()
	Telemetry.journey_population = journeys.total_population()
	Telemetry.journey_arrivals = last_journey_arrivals
	var indiv := agents.count_lightweight + agents.count_active + agents.count_detailed
	Telemetry.expensive_sim_agents = agents.count_active + agents.count_detailed
	if Telemetry.population > 0:
		Telemetry.sim_cost_per_pop = Telemetry.sim_time_ms / float(Telemetry.population)
		Telemetry.expensive_fraction = float(Telemetry.expensive_sim_agents) / float(Telemetry.population)
	else:
		Telemetry.sim_cost_per_pop = 0.0
		Telemetry.expensive_fraction = 0.0
	Telemetry.individual_agents = indiv
