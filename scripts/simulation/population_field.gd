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
	var region_id: int = -1
	var flow_target_conn: int = -1
	var active: bool = true


var cells: Array[PopulationCell] = []
var _free: PackedInt32Array = PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var last_transfers: int = 0
var last_transfer_pop: int = 0
var last_merges: int = 0
var last_splits: int = 0


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	cells.clear()
	_free.clear()
	last_transfers = 0
	last_transfer_pop = 0
	last_merges = 0
	last_splits = 0


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
	cell.region_id = -1
	cell.flow_target_conn = -1
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


func update(delta: float, player_pos: Vector3, attract: bool, half_extent: float, nav: NavGraph = null) -> void:
	var max_speed := SimConfig.HORDE_MAX_SPEED
	var attract_str := SimConfig.HORDE_ATTRACT_STRENGTH
	for cell in cells:
		if not cell.active or cell.population <= 0:
			continue
		if nav != null and nav.region_count() > 0:
			cell.region_id = nav.find_region_at(cell.position)
			if cell.region_id >= 0 and cell.region_id < nav.regions.size():
				var region: NavGraph.NavRegion = nav.regions[cell.region_id]
				# Pressure from region capacity (aggregate crowd, not physics).
				var fill := float(cell.population) / maxf(float(region.capacity), 1.0)
				cell.pressure = maxf(cell.pressure, maxf(0.0, fill - 0.6) * 5.0)
				cell.floor_id = region.floor_id
		var v := cell.velocity
		if attract:
			cell.alertness = minf(cell.alertness + delta * 2.0, 1.0)
			cell.destination = player_pos
			# Prefer nav flow target when available — avoid per-zombie steering for fields.
			var steered := false
			if nav != null and cell.region_id >= 0:
				var next_c := nav.next_connection_from(cell.region_id)
				cell.flow_target_conn = next_c
				if next_c >= 0 and next_c < nav.connections.size():
					var conn: NavGraph.NavConnection = nav.connections[next_c]
					var to_door := conn.position - cell.position
					to_door.y = 0.0
					if to_door.length_squared() > 0.25:
						v += to_door.normalized() * attract_str * delta
						steered = true
					else:
						# At doorway — wait for capacity transfer (handled in apply_nav_transfers).
						v *= 0.5
						steered = true
			if not steered:
				var to_player := player_pos - cell.position
				to_player.y = 0.0
				if to_player.length_squared() > 0.01:
					v += to_player.normalized() * attract_str * delta
		else:
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
		var spd := Vector3(v.x, 0.0, v.z).length()
		if spd > max_speed:
			v = v * (max_speed / spd)
		cell.velocity = v
		cell.position += Vector3(v.x, 0.0, v.z) * delta
		cell.position.y = float(cell.floor_id) * SimConfig.FLOOR_HEIGHT + 0.5
		cell.position.x = clampf(cell.position.x, -half_extent, half_extent)
		cell.position.z = clampf(cell.position.z, -half_extent, half_extent)


## Capacity-limited population transfer through nav connections (bottleneck simulation).
func apply_nav_transfers(nav: NavGraph, delta: float) -> int:
	last_transfers = 0
	last_transfer_pop = 0
	if nav == null or nav.connection_count() == 0:
		return 0
	var moved_total := 0
	for cell_i in cells.size():
		var cell: PopulationCell = cells[cell_i]
		if not cell.active or cell.population <= 0:
			continue
		if cell.region_id < 0:
			cell.region_id = nav.find_region_at(cell.position)
		var conn_id := cell.flow_target_conn
		if conn_id < 0:
			conn_id = nav.next_connection_from(cell.region_id)
			cell.flow_target_conn = conn_id
		if conn_id < 0:
			continue
		var conn: NavGraph.NavConnection = nav.connections[conn_id]
		if not conn.active or conn.blocked:
			continue
		# Only transfer when near the doorway / connection point.
		if cell.position.distance_to(conn.position) > maxf(cell.radius, 10.0):
			continue
		var dest_region := nav.other_region(conn_id, cell.region_id)
		if dest_region < 0:
			continue
		var budget := nav.available_transfer(conn_id, delta)
		if budget <= 0:
			# Pressure builds when blocked by capacity.
			cell.pressure = minf(cell.pressure + delta * 2.0, 20.0)
			continue
		var take := mini(budget, cell.population)
		# Gradual: don't dump entire mega-field in one tick.
		take = mini(take, maxi(1, int(conn.capacity_per_sec)))
		if take <= 0:
			continue
		# Find or create a field in the destination region.
		var dest_idx := _find_or_create_region_cell(dest_region, nav, cell.faction, cell.horde_id)
		var transferred := transfer_population(cell_i, dest_idx, take)
		if transferred > 0:
			var dest_cell: PopulationCell = cells[dest_idx]
			dest_cell.region_id = dest_region
			dest_cell.destination = cell.destination
			dest_cell.alertness = maxf(dest_cell.alertness, cell.alertness)
			dest_cell.flow_target_conn = nav.next_connection_from(dest_region)
			moved_total += transferred
			last_transfers += 1
			last_transfer_pop += transferred
			# Source pressure drops slightly after release.
			if cell.active:
				cell.pressure = maxf(0.0, cell.pressure - float(transferred) * 0.01)
	return moved_total


func _find_or_create_region_cell(region_id: int, nav: NavGraph, faction: int, horde_id: int) -> int:
	for i in cells.size():
		var c: PopulationCell = cells[i]
		if c.active and c.region_id == region_id and c.faction == faction:
			if horde_id < 0 or c.horde_id == horde_id or c.horde_id < 0:
				if c.horde_id < 0:
					c.horde_id = horde_id
				return i
	var region: NavGraph.NavRegion = nav.regions[region_id]
	var idx := create_cell(0, region.center, faction, 8.0, region.floor_id, horde_id)
	cells[idx].region_id = region_id
	return idx


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
			# Prefer same region when assigned.
			if a.region_id >= 0 and b.region_id >= 0 and a.region_id != b.region_id:
				continue
			if a.position.distance_to(b.position) > merge_distance:
				continue
			# Merge B into A (aggregate — no per-member iteration)
			var before := a.population + b.population
			var total := before
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
			if a.region_id < 0:
				a.region_id = b.region_id
			destroy_cell(j)
			if a.population != before:
				push_warning("Field merge conservation mismatch")
			merges += 1
			break
	last_merges = merges
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
		var before := cell.population
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
		neu.region_id = cell.region_id
		neu.flow_target_conn = cell.flow_target_conn
		cell.radius *= 0.75
		cell.density = float(cell.population) / maxf(cell.radius * cell.radius * PI, 1.0)
		cell.pressure = maxf(0.0, cell.density - 1.0)
		if cell.population + neu.population != before:
			push_warning("Field split conservation mismatch")
		splits += 1
	last_splits = splits
	return splits


## Split a cell toward an alternate connection when the primary route is blocked/saturated.
func split_toward_alternate(nav: NavGraph, cell_idx: int, alt_conn: int, amount: int) -> int:
	if cell_idx < 0 or cell_idx >= cells.size():
		return -1
	var cell: PopulationCell = cells[cell_idx]
	if not cell.active or amount <= 0 or amount >= cell.population:
		return -1
	if alt_conn < 0 or alt_conn >= nav.connections.size():
		return -1
	var before := cell.population
	cell.population -= amount
	var conn: NavGraph.NavConnection = nav.connections[alt_conn]
	var new_idx := create_cell(
		amount,
		cell.position + (conn.position - cell.position).normalized() * cell.radius * 0.5,
		cell.faction,
		cell.radius * 0.7,
		cell.floor_id,
		cell.horde_id
	)
	var neu: PopulationCell = cells[new_idx]
	neu.destination = cell.destination
	neu.alertness = cell.alertness
	neu.region_id = cell.region_id
	neu.flow_target_conn = alt_conn
	neu.velocity = (conn.position - cell.position).normalized() * SimConfig.HORDE_MAX_SPEED
	cell.density = float(cell.population) / maxf(cell.radius * cell.radius * PI, 1.0)
	if cell.population + neu.population != before:
		push_warning("Alternate split conservation mismatch")
	last_splits += 1
	return new_idx


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
