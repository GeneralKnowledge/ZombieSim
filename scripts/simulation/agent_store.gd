class_name AgentStore
extends RefCounted
## Structure-of-arrays storage for Level 1–3 agents.
## No Node3D per agent. Contiguous packed arrays, no per-NPC allocations in hot paths.

const INVALID: int = -1

var capacity: int = 0
var count: int = 0

var pos_x: PackedFloat32Array = PackedFloat32Array()
var pos_y: PackedFloat32Array = PackedFloat32Array()
var pos_z: PackedFloat32Array = PackedFloat32Array()
var vel_x: PackedFloat32Array = PackedFloat32Array()
var vel_y: PackedFloat32Array = PackedFloat32Array()
var vel_z: PackedFloat32Array = PackedFloat32Array()
var state: PackedByteArray = PackedByteArray()
var level: PackedByteArray = PackedByteArray()
var faction: PackedByteArray = PackedByteArray()
var health: PackedFloat32Array = PackedFloat32Array()
var target_x: PackedFloat32Array = PackedFloat32Array()
var target_y: PackedFloat32Array = PackedFloat32Array()
var target_z: PackedFloat32Array = PackedFloat32Array()
var floor_id: PackedByteArray = PackedByteArray()
var horde_id: PackedInt32Array = PackedInt32Array()
var alive: PackedByteArray = PackedByteArray()

## Free-list of recycled indices.
var _free: PackedInt32Array = PackedInt32Array()
var _cursor: int = 0


func ensure_capacity(n: int) -> void:
	if n <= capacity:
		return
	var new_cap := maxi(n, maxi(capacity * 2, 1024))
	_resize(new_cap)


func _resize(new_cap: int) -> void:
	pos_x.resize(new_cap)
	pos_y.resize(new_cap)
	pos_z.resize(new_cap)
	vel_x.resize(new_cap)
	vel_y.resize(new_cap)
	vel_z.resize(new_cap)
	state.resize(new_cap)
	level.resize(new_cap)
	faction.resize(new_cap)
	health.resize(new_cap)
	target_x.resize(new_cap)
	target_y.resize(new_cap)
	target_z.resize(new_cap)
	floor_id.resize(new_cap)
	horde_id.resize(new_cap)
	alive.resize(new_cap)
	capacity = new_cap


func clear() -> void:
	count = 0
	_cursor = 0
	_free.clear()
	_resize(0)
	capacity = 0


func spawn(
	p: Vector3,
	v: Vector3,
	agent_level: int,
	agent_faction: int,
	agent_floor: int = 0,
	agent_horde: int = INVALID
) -> int:
	var idx: int
	if _free.size() > 0:
		idx = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
	else:
		ensure_capacity(count + 1)
		idx = count
		count += 1
	pos_x[idx] = p.x
	pos_y[idx] = p.y
	pos_z[idx] = p.z
	vel_x[idx] = v.x
	vel_y[idx] = v.y
	vel_z[idx] = v.z
	state[idx] = 0
	level[idx] = agent_level
	faction[idx] = agent_faction
	health[idx] = 100.0
	target_x[idx] = p.x
	target_y[idx] = p.y
	target_z[idx] = p.z
	floor_id[idx] = agent_floor
	horde_id[idx] = agent_horde
	alive[idx] = 1
	return idx


func spawn_batch(
	amount: int,
	center: Vector3,
	radius: float,
	agent_level: int,
	agent_faction: int,
	rng: RandomNumberGenerator
) -> void:
	ensure_capacity(count + amount)
	for _i in amount:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := Vector3(center.x + cos(a) * r, center.y, center.z + sin(a) * r)
		var v := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		spawn(p, v, agent_level, agent_faction)


func kill(idx: int) -> void:
	if idx < 0 or idx >= count:
		return
	if alive[idx] == 0:
		return
	alive[idx] = 0
	_free.append(idx)


func get_position(idx: int) -> Vector3:
	return Vector3(pos_x[idx], pos_y[idx], pos_z[idx])


func set_position(idx: int, p: Vector3) -> void:
	pos_x[idx] = p.x
	pos_y[idx] = p.y
	pos_z[idx] = p.z


func get_velocity(idx: int) -> Vector3:
	return Vector3(vel_x[idx], vel_y[idx], vel_z[idx])


func set_velocity(idx: int, v: Vector3) -> void:
	vel_x[idx] = v.x
	vel_y[idx] = v.y
	vel_z[idx] = v.z


func get_target(idx: int) -> Vector3:
	return Vector3(target_x[idx], target_y[idx], target_z[idx])


func set_target(idx: int, t: Vector3) -> void:
	target_x[idx] = t.x
	target_y[idx] = t.y
	target_z[idx] = t.z


func living_count() -> int:
	return count - _free.size()


func count_by_level(lvl: int) -> int:
	var n := 0
	for i in count:
		if alive[i] != 0 and level[i] == lvl:
			n += 1
	return n


## Round-robin update of living agents with a per-frame budget.
func update_motion(delta: float, player_pos: Vector3, attract: bool, budget: int, half_extent: float) -> int:
	if count == 0 or budget <= 0:
		return 0
	var processed := 0
	var max_speed := SimConfig.AGENT_MAX_SPEED
	var wander := SimConfig.AGENT_WANDER_STRENGTH
	var attract_str := SimConfig.HORDE_ATTRACT_STRENGTH
	var start := _cursor
	var i := start
	var scanned := 0
	while processed < budget and scanned < count:
		if alive[i] != 0:
			var px := pos_x[i]
			var py := pos_y[i]
			var pz := pos_z[i]
			var vx := vel_x[i]
			var vz := vel_z[i]
			# Mild wander
			vx += (randf() - 0.5) * wander * delta
			vz += (randf() - 0.5) * wander * delta
			if attract:
				var dx := player_pos.x - px
				var dz := player_pos.z - pz
				var dist_sq := dx * dx + dz * dz
				if dist_sq > 0.0001:
					var inv := 1.0 / sqrt(dist_sq)
					vx += dx * inv * attract_str * delta
					vz += dz * inv * attract_str * delta
			else:
				# Soft pull toward personal target
				var tdx := target_x[i] - px
				var tdz := target_z[i] - pz
				vx += tdx * 0.15 * delta
				vz += tdz * 0.15 * delta
			# Clamp horizontal speed
			var spd := sqrt(vx * vx + vz * vz)
			if spd > max_speed:
				var s := max_speed / spd
				vx *= s
				vz *= s
			px += vx * delta
			pz += vz * delta
			# Soft world bounds
			if px > half_extent:
				px = half_extent
				vx = -absf(vx)
			elif px < -half_extent:
				px = -half_extent
				vx = absf(vx)
			if pz > half_extent:
				pz = half_extent
				vz = -absf(vz)
			elif pz < -half_extent:
				pz = -half_extent
				vz = absf(vz)
			pos_x[i] = px
			pos_z[i] = pz
			vel_x[i] = vx
			vel_z[i] = vz
			# Keep Y on floor plane for now (multi-floor later sets this)
			pos_y[i] = float(floor_id[i]) * SimConfig.FLOOR_HEIGHT + 0.4
			processed += 1
		i += 1
		if i >= count:
			i = 0
		scanned += 1
		if i == start and scanned > 0:
			break
	_cursor = i
	return processed
