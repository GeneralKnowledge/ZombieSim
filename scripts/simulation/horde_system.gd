class_name HordeSystem
extends RefCounted
## First-class hordes: aggregate population, not 100k nodes.
## Large hordes move via nav flow / field membership — never per-zombie A*.

const NAV_IDLE: int = 0
const NAV_SEEKING: int = 1
const NAV_BOTTLENECK: int = 2
const NAV_SPLITTING: int = 3
const NAV_JOURNEY: int = 4

class Horde:
	var id: int = -1
	var population: int = 0
	var center: Vector3 = Vector3.ZERO
	var extent: float = 20.0
	var density: float = 0.0
	var velocity: Vector3 = Vector3.ZERO
	var destination: Vector3 = Vector3.ZERO
	var cohesion: float = 0.5
	var alertness: float = 0.0
	var faction: int = 0
	var floor_id: int = 0
	var cell_indices: PackedInt32Array = PackedInt32Array()
	var region_id: int = -1
	var flow_target_conn: int = -1
	var pressure: float = 0.0
	var navigation_state: int = NAV_IDLE
	var active: bool = true


var hordes: Array[Horde] = []
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()
var last_splits: int = 0
var last_merges: int = 0


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	hordes.clear()
	_next_id = 1
	last_splits = 0
	last_merges = 0


func living_count() -> int:
	var n := 0
	for h in hordes:
		if h.active and h.population > 0:
			n += 1
	return n


func create_horde(
	fields: PopulationFieldSystem,
	pop: int,
	center: Vector3,
	faction: int = 0,
	nav: NavGraph = null
) -> int:
	## Creates aggregate field cells under one horde — never 100k agent objects.
	var before_fields := fields.total_population()
	var horde := Horde.new()
	horde.id = _next_id
	_next_id += 1
	horde.population = pop
	horde.center = center
	horde.extent = clampf(sqrt(float(pop)) * 0.15, 12.0, 120.0)
	horde.density = float(pop) / maxf(horde.extent * horde.extent * PI, 1.0)
	horde.velocity = Vector3.ZERO
	horde.destination = center
	horde.cohesion = SimConfig.HORDE_COHESION
	horde.alertness = 0.8
	horde.faction = faction
	horde.floor_id = 0
	horde.pressure = 0.0
	horde.navigation_state = NAV_IDLE
	horde.active = true
	if nav != null and nav.region_count() > 0:
		horde.region_id = nav.find_region_at(center)
	var cell_ids := fields.spawn_population_blob(pop, center, horde.extent * 0.7, faction)
	for ci in cell_ids:
		var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
		cell.horde_id = horde.id
		cell.destination = center
		cell.alertness = horde.alertness
		if horde.region_id >= 0:
			cell.region_id = horde.region_id
		horde.cell_indices.append(ci)
	hordes.append(horde)
	if fields.total_population() != before_fields + pop:
		push_warning("Horde create conservation mismatch")
	return horde.id


func get_horde(id: int) -> Horde:
	for h in hordes:
		if h.id == id and h.active:
			return h
	return null


func update(
	delta: float,
	fields: PopulationFieldSystem,
	player_pos: Vector3,
	attract: bool,
	nav: NavGraph = null
) -> void:
	last_splits = 0
	for horde in hordes:
		if not horde.active:
			continue
		_refresh_from_cells(horde, fields)
		if horde.population <= 0:
			horde.active = false
			continue
		if nav != null and nav.region_count() > 0:
			horde.region_id = nav.find_region_at(horde.center)
			horde.flow_target_conn = nav.next_connection_from(horde.region_id)
		if attract:
			horde.destination = player_pos
			horde.alertness = minf(horde.alertness + delta, 1.0)
			horde.navigation_state = NAV_SEEKING
			var to_p := player_pos - horde.center
			to_p.y = 0.0
			if to_p.length_squared() > 0.01:
				horde.velocity = horde.velocity.lerp(to_p.normalized() * SimConfig.HORDE_MAX_SPEED, 0.2)
			# Bottleneck detection: high pressure + active flow target nearby.
			if horde.pressure > 3.0 and horde.flow_target_conn >= 0:
				horde.navigation_state = NAV_BOTTLENECK
				# Natural split toward alternate routes when blocked.
				if horde.population >= 2000 and nav != null:
					_try_nav_split(horde, fields, nav)
		else:
			if horde.navigation_state == NAV_SEEKING:
				horde.navigation_state = NAV_IDLE
		# Push destination/velocity onto member cells (aggregate steering)
		for ci in horde.cell_indices:
			if ci < 0 or ci >= fields.cells.size():
				continue
			var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
			if not cell.active:
				continue
			cell.destination = horde.destination
			cell.horde_id = horde.id
			if horde.flow_target_conn >= 0:
				cell.flow_target_conn = horde.flow_target_conn
			var to_c := horde.center - cell.position
			to_c.y = 0.0
			cell.velocity += to_c * horde.cohesion * delta * 0.5
			cell.alertness = maxf(cell.alertness, horde.alertness)


func _try_nav_split(horde: Horde, fields: PopulationFieldSystem, nav: NavGraph) -> void:
	if horde.region_id < 0 or horde.region_id >= nav.regions.size():
		return
	var region: NavGraph.NavRegion = nav.regions[horde.region_id]
	var primary := horde.flow_target_conn
	var alts: PackedInt32Array = PackedInt32Array()
	for ci in region.connection_ids:
		if ci == primary:
			continue
		var conn: NavGraph.NavConnection = nav.connections[ci]
		if conn.active and not conn.blocked:
			alts.append(ci)
	if alts.is_empty():
		return
	# Pick alternate deterministically from horde id.
	var alt: int = alts[horde.id % alts.size()]
	# Find largest cell to peel population from.
	var best_cell := -1
	var best_pop := 0
	for ci in horde.cell_indices:
		if ci < 0 or ci >= fields.cells.size():
			continue
		var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
		if cell.active and cell.population > best_pop:
			best_pop = cell.population
			best_cell = ci
	if best_cell < 0 or best_pop < 800:
		return
	var peel := best_pop / 3
	var new_cell := fields.split_toward_alternate(nav, best_cell, alt, peel)
	if new_cell < 0:
		return
	# Create sibling horde with peeled population (identity not preserved per zombie).
	var before := horde.population
	var new_h := Horde.new()
	new_h.id = _next_id
	_next_id += 1
	new_h.faction = horde.faction
	new_h.cohesion = horde.cohesion
	new_h.alertness = horde.alertness
	new_h.destination = horde.destination
	new_h.navigation_state = NAV_SPLITTING
	new_h.flow_target_conn = alt
	new_h.region_id = horde.region_id
	new_h.active = true
	fields.cells[new_cell].horde_id = new_h.id
	new_h.cell_indices.append(new_cell)
	_refresh_from_cells(horde, fields)
	_refresh_from_cells(new_h, fields)
	if horde.population + new_h.population != before:
		push_warning("Nav split conservation mismatch %d+%d != %d" % [
			horde.population, new_h.population, before
		])
	hordes.append(new_h)
	horde.navigation_state = NAV_SPLITTING
	last_splits += 1


func _refresh_from_cells(horde: Horde, fields: PopulationFieldSystem) -> void:
	var pop := 0
	var center := Vector3.ZERO
	var vel := Vector3.ZERO
	var pressure := 0.0
	var alive_cells := PackedInt32Array()
	# Scan all fields so split orphans with this horde_id are reclaimed.
	for ci in fields.cells.size():
		var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
		if not cell.active or cell.population <= 0 or cell.horde_id != horde.id:
			continue
		alive_cells.append(ci)
		pop += cell.population
		center += cell.position * float(cell.population)
		vel += cell.velocity * float(cell.population)
		pressure = maxf(pressure, cell.pressure)
	horde.cell_indices = alive_cells
	horde.population = pop
	horde.pressure = pressure
	if pop > 0:
		var fp := float(pop)
		horde.center = center / fp
		horde.velocity = vel / fp
		horde.extent = clampf(sqrt(fp) * 0.15, 8.0, 140.0)
		horde.density = fp / maxf(horde.extent * horde.extent * PI, 1.0)


func split_horde(fields: PopulationFieldSystem, horde_id: int) -> int:
	var horde := get_horde(horde_id)
	if horde == null:
		return -1
	var before := horde.population
	if horde.cell_indices.size() < 2:
		fields.try_split_overdense()
		_refresh_from_cells(horde, fields)
		if horde.cell_indices.size() < 2:
			return -1
	var mid := horde.cell_indices.size() / 2
	var new_h := Horde.new()
	new_h.id = _next_id
	_next_id += 1
	new_h.faction = horde.faction
	new_h.cohesion = horde.cohesion
	new_h.alertness = horde.alertness
	new_h.destination = horde.destination + Vector3(20.0, 0.0, 0.0)
	new_h.navigation_state = NAV_SPLITTING
	new_h.active = true
	var keep := PackedInt32Array()
	for i in horde.cell_indices.size():
		var ci: int = horde.cell_indices[i]
		if i < mid:
			keep.append(ci)
		else:
			new_h.cell_indices.append(ci)
			var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
			cell.horde_id = new_h.id
			cell.destination = new_h.destination
			cell.velocity += Vector3(4.0, 0.0, _rng.randf_range(-2.0, 2.0))
	horde.cell_indices = keep
	_refresh_from_cells(horde, fields)
	_refresh_from_cells(new_h, fields)
	if horde.population + new_h.population != before:
		push_warning("Horde split conservation mismatch")
	hordes.append(new_h)
	last_splits += 1
	return new_h.id


func merge_hordes(fields: PopulationFieldSystem, id_a: int, id_b: int) -> int:
	var a := get_horde(id_a)
	var b := get_horde(id_b)
	if a == null or b == null or a.id == b.id:
		return -1
	var before := a.population + b.population
	for ci in b.cell_indices:
		if ci < 0 or ci >= fields.cells.size():
			continue
		var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
		if cell.active:
			cell.horde_id = a.id
			a.cell_indices.append(ci)
	b.active = false
	b.population = 0
	b.cell_indices.clear()
	_refresh_from_cells(a, fields)
	if a.population != before:
		push_warning("Horde merge conservation mismatch")
	last_merges += 1
	return a.id


func merge_nearest(fields: PopulationFieldSystem) -> int:
	var living: Array[Horde] = []
	for h in hordes:
		if h.active and h.population > 0:
			living.append(h)
	if living.size() < 2:
		return -1
	var best_i := 0
	var best_j := 1
	var best_d := INF
	for i in living.size():
		for j in range(i + 1, living.size()):
			# Same destination affinity: prefer merging toward shared goals.
			var d: float = living[i].center.distance_to(living[j].center)
			var dest_bonus := living[i].destination.distance_to(living[j].destination)
			d += dest_bonus * 0.15
			if d < best_d:
				best_d = d
				best_i = i
				best_j = j
	# Only merge if reasonably close.
	if living[best_i].center.distance_to(living[best_j].center) > SimConfig.HORDE_MERGE_DISTANCE:
		return -1
	return merge_hordes(fields, living[best_i].id, living[best_j].id)


func first_active_id() -> int:
	for h in hordes:
		if h.active and h.population > 0:
			return h.id
	return -1


## Attach an existing set of field cells as a horde (population already in fields).
func adopt_cells(
	fields: PopulationFieldSystem,
	cell_indices: PackedInt32Array,
	center: Vector3,
	faction: int = 0,
	region_id: int = -1
) -> int:
	var horde := Horde.new()
	horde.id = _next_id
	_next_id += 1
	horde.center = center
	horde.faction = faction
	horde.region_id = region_id
	horde.alertness = 1.0
	horde.pressure = 12.0
	horde.navigation_state = NAV_BOTTLENECK
	horde.active = true
	for ci in cell_indices:
		if ci < 0 or ci >= fields.cells.size():
			continue
		var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
		if not cell.active:
			continue
		cell.horde_id = horde.id
		horde.cell_indices.append(ci)
	_refresh_from_cells(horde, fields)
	hordes.append(horde)
	return horde.id


## Convert a distant horde into a journey (returns journey payload dict).
func extract_for_journey(fields: PopulationFieldSystem, horde_id: int) -> Dictionary:
	var horde := get_horde(horde_id)
	if horde == null:
		return {}
	var pop := horde.population
	var center := horde.center
	var dest := horde.destination
	var faction := horde.faction
	# Destroy field cells — population moves to journey.
	for ci in horde.cell_indices:
		if ci >= 0 and ci < fields.cells.size():
			fields.destroy_cell(ci)
	horde.active = false
	horde.population = 0
	horde.cell_indices.clear()
	horde.navigation_state = NAV_JOURNEY
	return {
		"population": pop,
		"origin": center,
		"destination": dest,
		"faction": faction,
		"horde_id": horde_id,
	}
