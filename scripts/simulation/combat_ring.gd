class_name CombatRing
extends RefCounted
## Near-player ring where individuals become "real enough" to shoot.
## Beyond the ring, damage is applied to population fields aggregately.

var last_shot_target: Vector3 = Vector3.ZERO
var last_shot_hit: bool = false
var last_shot_was_field: bool = false
var shots_fired: int = 0
var individual_kills: int = 0
var field_kills: int = 0
var ring_agent_count: int = 0

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func clear_stats() -> void:
	shots_fired = 0
	individual_kills = 0
	field_kills = 0
	ring_agent_count = 0
	last_shot_hit = false


## Promote nearby lightweight agents into ACTIVE (budgeted) so the edge can be shot.
func maintain_ring(agents: AgentStore, player_pos: Vector3, budget: int) -> int:
	var promoted := 0
	var ring_r := SimConfig.COMBAT_RING_RADIUS
	var ring_r2 := ring_r * ring_r
	var detailed_r2 := SimConfig.RADIUS_DETAILED * SimConfig.RADIUS_DETAILED
	ring_agent_count = 0
	var active_cap := SimConfig.MAX_ACTIVE_AGENTS
	var detailed_cap := SimConfig.MAX_DETAILED_AGENTS
	for i in agents.count:
		if agents.alive[i] == 0:
			continue
		var dx := agents.pos_x[i] - player_pos.x
		var dy := agents.pos_y[i] - player_pos.y
		var dz := agents.pos_z[i] - player_pos.z
		var d2 := dx * dx + dy * dy + dz * dz
		if d2 <= ring_r2:
			ring_agent_count += 1
			var want := SimConfig.LEVEL_ACTIVE
			if d2 <= detailed_r2:
				want = SimConfig.LEVEL_DETAILED
			var cur: int = agents.level[i]
			if want > cur and promoted < budget:
				if want == SimConfig.LEVEL_DETAILED and agents.count_detailed >= detailed_cap:
					want = SimConfig.LEVEL_ACTIVE
				if want == SimConfig.LEVEL_ACTIVE and agents.count_active >= active_cap:
					continue
				if want > cur:
					agents.set_level(i, want)
					promoted += 1
		elif agents.level[i] >= SimConfig.LEVEL_ACTIVE and d2 > ring_r2 * 1.5:
			# Demote far combat agents back to lightweight.
			if promoted < budget:
				agents.set_level(i, SimConfig.LEVEL_LIGHTWEIGHT)
				promoted += 1
	return promoted


## Hitscan toward aim_dir. Prefers ACTIVE/DETAILED individuals; else damages a field.
func shoot(
	agents: AgentStore,
	fields: PopulationFieldSystem,
	origin: Vector3,
	aim_dir: Vector3,
	max_range: float = -1.0
) -> Dictionary:
	shots_fired += 1
	var rng := max_range if max_range > 0.0 else SimConfig.SHOOT_RANGE
	var dir := aim_dir
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0, 0, -1)
	dir = dir.normalized()

	var best_i := -1
	var best_t := rng
	# Only consider agents in/near combat ring (shootable individuals).
	var consider_r := SimConfig.COMBAT_RING_RADIUS * 1.25
	var consider_r2 := consider_r * consider_r
	for i in agents.count:
		if agents.alive[i] == 0:
			continue
		if agents.level[i] < SimConfig.LEVEL_ACTIVE:
			continue
		var dx := agents.pos_x[i] - origin.x
		var dz := agents.pos_z[i] - origin.z
		if dx * dx + dz * dz > consider_r2:
			continue
		# Project onto aim ray
		var t := dx * dir.x + dz * dir.z
		if t < 0.5 or t > best_t:
			continue
		var closest := Vector3(origin.x + dir.x * t, origin.y, origin.z + dir.z * t)
		var lateral := Vector2(agents.pos_x[i] - closest.x, agents.pos_z[i] - closest.z).length()
		if lateral <= SimConfig.SHOOT_HIT_RADIUS:
			best_t = t
			best_i = i

	if best_i >= 0:
		agents.health[best_i] -= SimConfig.SHOOT_DAMAGE
		last_shot_target = agents.get_position(best_i)
		last_shot_hit = true
		last_shot_was_field = false
		var killed := false
		if agents.health[best_i] <= 0.0:
			agents.kill(best_i)
			individual_kills += 1
			killed = true
		return {"hit": true, "field": false, "killed": killed, "agent": best_i, "pos": last_shot_target}

	# No individual — punch a hole in the nearest overlapping population field along the ray.
	var field_hit := _damage_field_along_ray(fields, origin, dir, rng)
	if field_hit.hit:
		last_shot_target = field_hit.pos
		last_shot_hit = true
		last_shot_was_field = true
		field_kills += int(field_hit.kills)
		return field_hit

	last_shot_hit = false
	last_shot_was_field = false
	last_shot_target = origin + dir * rng
	return {"hit": false, "field": false, "killed": false, "pos": last_shot_target}


func _damage_field_along_ray(
	fields: PopulationFieldSystem,
	origin: Vector3,
	dir: Vector3,
	max_range: float
) -> Dictionary:
	var best_idx := -1
	var best_t := max_range
	var best_pos := origin
	for ci in fields.cells.size():
		var cell: PopulationFieldSystem.PopulationCell = fields.cells[ci]
		if not cell.active or cell.population <= 0:
			continue
		var to := cell.position - origin
		to.y = 0.0
		var t := to.x * dir.x + to.z * dir.z
		if t < 1.0 or t > best_t:
			continue
		var closest := origin + dir * t
		var lat := Vector2(cell.position.x - closest.x, cell.position.z - closest.z).length()
		if lat <= cell.radius + SimConfig.SHOOT_HIT_RADIUS:
			best_t = t
			best_idx = ci
			best_pos = closest

	if best_idx < 0:
		return {"hit": false, "field": true, "kills": 0, "pos": origin + dir * max_range}

	var cell2: PopulationFieldSystem.PopulationCell = fields.cells[best_idx]
	var kills := mini(cell2.population, SimConfig.SHOOT_FIELD_POP_DAMAGE)
	cell2.population -= kills
	cell2.alertness = 1.0
	cell2.destination = cell2.position + dir * 20.0
	cell2.velocity += dir * 4.0
	if cell2.population <= 0:
		cell2.active = false
	else:
		cell2.density = float(cell2.population) / maxf(cell2.radius * cell2.radius * PI, 1.0)
	return {"hit": true, "field": true, "kills": kills, "killed": kills > 0, "pos": best_pos, "cell": best_idx}
