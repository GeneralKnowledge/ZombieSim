class_name FireSystem
extends RefCounted
## Area-effect fire. Burns individuals in the combat ring and population fields
## aggregately — never one flame node / burn sim per zombie.

class FireVolume:
	var position: Vector3 = Vector3.ZERO
	var radius: float = 8.0
	var intensity: float = 1.0
	var lifetime: float = 12.0
	var age: float = 0.0
	var floor_id: int = 0
	var active: bool = true
	## Population killed via aggregate field burns (for telemetry).
	var field_kills: int = 0
	var agent_kills: int = 0


var volumes: Array[FireVolume] = []
var total_field_kills: int = 0
var total_agent_kills: int = 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	volumes.clear()
	total_field_kills = 0
	total_agent_kills = 0


func living_count() -> int:
	var n := 0
	for v in volumes:
		if v.active:
			n += 1
	return n


func throw_molotov(origin: Vector3, direction: Vector3, floor_id: int = 0) -> int:
	## Spawns a fire patch ahead of the thrower. No projectile physics yet.
	var dir := direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0, 0, -1)
	dir = dir.normalized()
	var impact := origin + dir * SimConfig.MOLOTOV_THROW_RANGE
	impact.y = float(floor_id) * SimConfig.FLOOR_HEIGHT + 0.3
	return spawn_fire(impact, SimConfig.MOLOTOV_RADIUS, SimConfig.MOLOTOV_INTENSITY, SimConfig.MOLOTOV_LIFETIME, floor_id)


func spawn_fire(pos: Vector3, radius: float, intensity: float, lifetime: float, floor_id: int = 0) -> int:
	var v := FireVolume.new()
	v.position = pos
	v.radius = radius
	v.intensity = intensity
	v.lifetime = lifetime
	v.floor_id = floor_id
	v.active = true
	volumes.append(v)
	return volumes.size() - 1


func update(delta: float, agents: AgentStore, fields: PopulationFieldSystem) -> void:
	for v in volumes:
		if not v.active:
			continue
		v.age += delta
		if v.age >= v.lifetime:
			v.active = false
			continue
		# Intensity falls off over life.
		var life_t := 1.0 - (v.age / v.lifetime)
		var effective := v.intensity * life_t
		_burn_agents(v, effective, delta, agents)
		_burn_fields(v, effective, delta, fields)
		# Mild expansion while hot.
		if life_t > 0.4:
			v.radius = minf(v.radius + delta * 0.6 * effective, SimConfig.MOLOTOV_RADIUS * 2.2)


func _burn_agents(v: FireVolume, intensity: float, delta: float, agents: AgentStore) -> void:
	var r2 := v.radius * v.radius
	var dmg := SimConfig.FIRE_AGENT_DPS * intensity * delta
	# Budget: scan a slice of agents; fire is rare and local.
	var budget := SimConfig.MAX_FIRE_AGENT_CHECKS_PER_TICK
	var checked := 0
	var start := _rng.randi() % maxi(agents.count, 1)
	var i := start
	while checked < agents.count and budget > 0:
		if agents.alive[i] != 0:
			budget -= 1
			if agents.floor_id[i] == v.floor_id:
				var dx := agents.pos_x[i] - v.position.x
				var dz := agents.pos_z[i] - v.position.z
				if dx * dx + dz * dz <= r2:
					agents.health[i] -= dmg
					agents.state[i] = 1 # burning flag
					# Panic: push away from fire center.
					var inv_len := 1.0 / maxf(sqrt(dx * dx + dz * dz), 0.2)
					agents.vel_x[i] += dx * inv_len * 10.0 * delta
					agents.vel_z[i] += dz * inv_len * 10.0 * delta
					if agents.health[i] <= 0.0:
						agents.kill(i)
						v.agent_kills += 1
						total_agent_kills += 1
		checked += 1
		i += 1
		if i >= agents.count:
			i = 0
		if i == start and checked > 0:
			break


func _burn_fields(v: FireVolume, intensity: float, delta: float, fields: PopulationFieldSystem) -> void:
	## Aggregate: kill population proportional to overlap * density * intensity.
	for cell in fields.cells:
		if not cell.active or cell.population <= 0:
			continue
		if cell.floor_id != v.floor_id:
			continue
		var dist := cell.position.distance_to(v.position)
		var reach := v.radius + cell.radius
		if dist > reach:
			continue
		var overlap := 1.0 - clampf(dist / maxf(reach, 0.1), 0.0, 1.0)
		var kill_f := float(cell.population) * overlap * intensity * SimConfig.FIRE_FIELD_KILL_RATE * delta
		var kills := int(kill_f)
		if kills <= 0 and overlap > 0.2 and _rng.randf() < intensity * delta:
			kills = 1
		if kills <= 0:
			continue
		kills = mini(kills, cell.population)
		cell.population -= kills
		v.field_kills += kills
		total_field_kills += kills
		cell.alertness = 1.0
		# Crowd flees the blaze.
		var away := cell.position - v.position
		away.y = 0.0
		if away.length_squared() > 0.01:
			cell.velocity += away.normalized() * (8.0 * intensity)
			cell.destination = cell.position + away.normalized() * 40.0
		cell.density = float(cell.population) / maxf(cell.radius * cell.radius * PI, 1.0)
		cell.pressure = maxf(0.0, cell.density - 1.0)
		if cell.population <= 0:
			cell.active = false
