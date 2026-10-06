class_name PopulationFieldSystem
extends RefCounted
## Level 0 — extremely cheap collective representation.
## Empty regions have essentially zero simulation cost.

class PopulationCell:
	var population: int = 0
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var density: float = 0.0
	var destination: Vector3 = Vector3.ZERO
	var faction: int = 0
	var alertness: float = 0.0
	var cohesion: float = 0.5
	var floor_id: int = 0
	var radius: float = 8.0
	var pressure: float = 0.0
	var horde_id: int = -1
	var active: bool = true


var cells: Array[PopulationCell] = []
var _free: PackedInt32Array = PackedInt32Array()
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	cells.clear()
	_free.clear()


func living_count() -> int:
	var n := 0
	for c in cells:
		if c.active and c.population > 0:
			n += 1
	return n


func total_population() -> int:
	var n := 0
	for c in cells:
		if c.active:
			n += c.population
	return n


func create_cell(
	pop: int,
	pos: Vector3,
	faction: int = 0,
	radius: float = 8.0,
	floor_id: int = 0,
	horde_id: int = -1
) -> int:
	var cell: PopulationCell
	var idx: int
	if _free.size() > 0:
		idx = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
		cell = cells[idx]
	else:
		cell = PopulationCell.new()
		idx = cells.size()
		cells.append(cell)
	cell.population = pop
	cell.position = pos
	cell.velocity = Vector3.ZERO
	cell.density = clampf(float(pop) / maxf(radius * radius * PI, 1.0), 0.0, 10.0)
	cell.destination = pos
	cell.faction = faction
	cell.alertness = 0.0
	cell.cohesion = SimConfig.HORDE_COHESION
	cell.floor_id = floor_id
	cell.radius = radius
	cell.pressure = maxf(0.0, cell.density - 1.0)
	cell.horde_id = horde_id
	cell.active = true
	return idx


func destroy_cell(idx: int) -> void:
	if idx < 0 or idx >= cells.size():
		return
	var cell: PopulationCell = cells[idx]
	if not cell.active:
		return
	cell.active = false
	cell.population = 0
	_free.append(idx)


func spawn_population_blob(pop: int, center: Vector3, extent: float, faction: int = 0) -> PackedInt32Array:
	## Split a large population into sparse cells rather than one mega-allocation of agents.
	var created := PackedInt32Array()
	if pop <= 0:
		return created
	var cell_pop_target := 2500
	var remaining := pop
	while remaining > 0:
		var chunk := mini(remaining, cell_pop_target + _rng.randi_range(-400, 400))
		chunk = maxi(chunk, 1)
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * extent
		var pos := Vector3(center.x + cos(a) * r, center.y, center.z + sin(a) * r)
		var radius := clampf(sqrt(float(chunk) / PI) * 0.35, 4.0, 40.0)
		var idx := create_cell(chunk, pos, faction, radius)
		created.append(idx)
		remaining -= chunk
	return created


func update(delta: float, player_pos: Vector3, attract: bool, half_extent: float) -> void:
	var max_speed := SimConfig.HORDE_MAX_SPEED
	var attract_str := SimConfig.HORDE_ATTRACT_STRENGTH
	for cell in cells:
		if not cell.active or cell.population <= 0:
			continue
		var v := cell.velocity
		if attract:
			var to_player := player_pos - cell.position
			to_player.y = 0.0
			if to_player.length_squared() > 0.01:
				v += to_player.normalized() * attract_str * delta
			cell.alertness = minf(cell.alertness + delta * 2.0, 1.0)
			cell.destination = player_pos
		else:
			# Drift toward destination + mild noise
			var to_dest := cell.destination - cell.position
			to_dest.y = 0.0
			if to_dest.length_squared() > 1.0:
				v += to_dest.normalized() * 2.0 * delta
			v += Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)) * delta
			cell.alertness = maxf(cell.alertness - delta * 0.2, 0.0)
		# Density/pressure soft expansion
		if cell.pressure > 0.2:
			cell.radius = minf(cell.radius + cell.pressure * delta * 2.0, 60.0)
			cell.density = float(cell.population) / maxf(cell.radius * cell.radius * PI, 1.0)
			cell.pressure = maxf(0.0, cell.density - 1.0)
		# Clamp speed
		var spd := Vector3(v.x, 0.0, v.z).length()
		if spd > max_speed:
			v = v * (max_speed / spd)
		cell.velocity = v
		cell.position += Vector3(v.x, 0.0, v.z) * delta
		cell.position.y = float(cell.floor_id) * SimConfig.FLOOR_HEIGHT + 0.5
		# Bounds
		cell.position.x = clampf(cell.position.x, -half_extent, half_extent)
		cell.position.z = clampf(cell.position.z, -half_extent, half_extent)


func try_merge(merge_distance: float) -> int:
	var merges := 0
	var n := cells.size()
	for i in n:
		var a: PopulationCell = cells[i]
		if not a.active or a.population <= 0:
			continue
		for j in range(i + 1, n):
			var b: PopulationCell = cells[j]
			if not b.active or b.population <= 0:
				continue
			if a.faction != b.faction or a.floor_id != b.floor_id:
				continue
			if a.position.distance_to(b.position) > merge_distance:
				continue
			# Merge B into A (aggregate — no per-member iteration)
			var total := a.population + b.population
			var w_a := float(a.population) / float(total)
			var w_b := float(b.population) / float(total)
			a.position = a.position * w_a + b.position * w_b
			a.velocity = a.velocity * w_a + b.velocity * w_b
			a.population = total
			a.radius = maxf(a.radius, b.radius) * 1.05
			a.density = float(a.population) / maxf(a.radius * a.radius * PI, 1.0)
			a.pressure = maxf(0.0, a.density - 1.0)
			a.alertness = maxf(a.alertness, b.alertness)
			if a.horde_id < 0:
				a.horde_id = b.horde_id
			destroy_cell(j)
			merges += 1
			break
	return merges


func try_split_overdense() -> int:
	var splits := 0
	var threshold := SimConfig.FIELD_SPLIT_DENSITY
	var n := cells.size()
	for i in n:
		var cell: PopulationCell = cells[i]
		if not cell.active or cell.population < 400:
			continue
		if cell.density < threshold and cell.pressure < 1.5:
			continue
		# Split into two aggregate cells (population-field manipulation)
		var half := cell.population / 2
		if half < 50:
			continue
		cell.population -= half
		var offset := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
		offset *= cell.radius * 0.8
		var new_idx := create_cell(
			half,
			cell.position + offset,
			cell.faction,
			cell.radius * 0.75,
			cell.floor_id,
			cell.horde_id
		)
		var neu: PopulationCell = cells[new_idx]
		neu.velocity = cell.velocity.rotated(Vector3.UP, 0.4)
		neu.destination = cell.destination
		neu.alertness = cell.alertness
		cell.radius *= 0.75
		cell.density = float(cell.population) / maxf(cell.radius * cell.radius * PI, 1.0)
		cell.pressure = maxf(0.0, cell.density - 1.0)
		splits += 1
	return splits


func transfer_population(from_idx: int, to_idx: int, amount: int) -> int:
	if from_idx < 0 or to_idx < 0 or from_idx >= cells.size() or to_idx >= cells.size():
		return 0
	var a: PopulationCell = cells[from_idx]
	var b: PopulationCell = cells[to_idx]
	if not a.active or not b.active:
		return 0
	var moved := mini(amount, a.population)
	a.population -= moved
	b.population += moved
	a.density = float(a.population) / maxf(a.radius * a.radius * PI, 1.0)
	b.density = float(b.population) / maxf(b.radius * b.radius * PI, 1.0)
	if a.population <= 0:
		destroy_cell(from_idx)
	return moved


## Materialise up to `budget` lightweight agents near a point from field population.
func materialise_near(
	store: AgentStore,
	center: Vector3,
	radius: float,
	budget: int
) -> int:
	var created := 0
	for cell in cells:
		if created >= budget:
			break
		if not cell.active or cell.population <= 0:
			continue
		if cell.position.distance_to(center) > radius + cell.radius:
			continue
		var take := mini(cell.population, budget - created)
		# Don't drain entire massive field in one frame — gradual
		take = mini(take, maxi(1, budget / 4))
		for _k in take:
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * cell.radius
			var p := cell.position + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var v := cell.velocity + Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
			store.spawn(p, v, SimConfig.LEVEL_LIGHTWEIGHT, cell.faction, cell.floor_id, cell.horde_id)
		cell.population -= take
		created += take
		if cell.population <= 0:
			cell.active = false
	for i in cells.size():
		var c: PopulationCell = cells[i]
		if c.active:
			continue
		var already := false
		for f in _free:
			if f == i:
				already = true
				break
		if not already:
			_free.append(i)
	return created


## Absorb distant lightweight agents back into nearby fields (or create new fields).
func absorb_agents(store: AgentStore, center: Vector3, keep_radius: float, budget: int) -> int:
	var absorbed := 0
	for i in store.count:
		if absorbed >= budget:
			break
		if store.alive[i] == 0:
			continue
		if store.level[i] != SimConfig.LEVEL_LIGHTWEIGHT:
			continue
		var p := store.get_position(i)
		if p.distance_to(center) <= keep_radius:
			continue
		# Find nearest field of same faction
		var best := -1
		var best_d := 40.0
		for ci in cells.size():
			var cell: PopulationCell = cells[ci]
			if not cell.active:
				continue
			if cell.faction != store.faction[i]:
				continue
			var d := cell.position.distance_to(p)
			if d < best_d:
				best_d = d
				best = ci
		if best >= 0:
			var cell: PopulationCell = cells[best]
			cell.population += 1
			# Running average position (cheap)
			var w := 1.0 / float(cell.population)
			cell.position = cell.position * (1.0 - w) + p * w
		else:
			create_cell(1, p, store.faction[i], 6.0, store.floor_id[i], store.horde_id[i])
		store.kill(i)
		absorbed += 1
	return absorbed
