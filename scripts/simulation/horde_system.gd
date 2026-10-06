class_name HordeSystem
extends RefCounted
## First-class hordes: aggregate population, not 100k nodes.

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
	var active: bool = true


var hordes: Array[Horde] = []
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	hordes.clear()
	_next_id = 1


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
	faction: int = 0
) -> int:
	## Creates aggregate field cells under one horde — never 100k agent objects.
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
	horde.active = true
	var cell_ids := fields.spawn_population_blob(pop, center, horde.extent * 0.7, faction)
	for ci in cell_ids:
		var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
		cell.horde_id = horde.id
		cell.destination = center
		cell.alertness = horde.alertness
		horde.cell_indices.append(ci)
	hordes.append(horde)
	return horde.id


func get_horde(id: int) -> Horde:
	for h in hordes:
		if h.id == id and h.active:
			return h
	return null


func update(delta: float, fields: PopulationFieldSystem, player_pos: Vector3, attract: bool) -> void:
	for horde in hordes:
		if not horde.active:
			continue
		_refresh_from_cells(horde, fields)
		if horde.population <= 0:
			horde.active = false
			continue
		if attract:
			horde.destination = player_pos
			horde.alertness = minf(horde.alertness + delta, 1.0)
			var to_p := player_pos - horde.center
			to_p.y = 0.0
			if to_p.length_squared() > 0.01:
				horde.velocity = horde.velocity.lerp(to_p.normalized() * SimConfig.HORDE_MAX_SPEED, 0.2)
		# Push destination/velocity onto member cells (aggregate steering)
		for ci in horde.cell_indices:
			if ci < 0 or ci >= fields.cells.size():
				continue
			var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
			if not cell.active:
				continue
			cell.destination = horde.destination
			cell.horde_id = horde.id
			# Cohesion pull toward horde center
			var to_c := horde.center - cell.position
			to_c.y = 0.0
			cell.velocity += to_c * horde.cohesion * delta * 0.5
			cell.alertness = maxf(cell.alertness, horde.alertness)


func _refresh_from_cells(horde: Horde, fields: PopulationFieldSystem) -> void:
	var pop := 0
	var center := Vector3.ZERO
	var vel := Vector3.ZERO
	var alive_cells := PackedInt32Array()
	for ci in horde.cell_indices:
		if ci < 0 or ci >= fields.cells.size():
			continue
		var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
		if not cell.active or cell.population <= 0 or cell.horde_id != horde.id:
			continue
		alive_cells.append(ci)
		pop += cell.population
		center += cell.position * float(cell.population)
		vel += cell.velocity * float(cell.population)
	horde.cell_indices = alive_cells
	horde.population = pop
	if pop > 0:
		var fp := float(pop)
		horde.center = center / fp
		horde.velocity = vel / fp
		horde.extent = clampf(sqrt(fp) * 0.15, 8.0, 140.0)
		horde.density = fp / maxf(horde.extent * horde.extent * PI, 1.0)


func split_horde(fields: PopulationFieldSystem, horde_id: int) -> int:
	var horde := get_horde(horde_id)
	if horde == null or horde.cell_indices.size() < 2:
		# Force field split then reassign
		if horde == null:
			return -1
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
	hordes.append(new_h)
	return new_h.id


func merge_hordes(fields: PopulationFieldSystem, id_a: int, id_b: int) -> int:
	var a := get_horde(id_a)
	var b := get_horde(id_b)
	if a == null or b == null or a.id == b.id:
		return -1
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
			var d: float = living[i].center.distance_to(living[j].center)
			if d < best_d:
				best_d = d
				best_i = i
				best_j = j
	return merge_hordes(fields, living[best_i].id, living[best_j].id)


func first_active_id() -> int:
	for h in hordes:
		if h.active and h.population > 0:
			return h.id
	return -1
