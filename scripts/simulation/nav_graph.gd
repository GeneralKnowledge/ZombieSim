class_name NavGraph
extends RefCounted
## Hierarchical navigation for mass populations — NOT per-zombie NavigationAgent3D.
## Regions + capacity-limited connections drive aggregate flow.

const KIND_STREET: int = 0
const KIND_PLAZA: int = 1
const KIND_ROOM: int = 2
const KIND_CORRIDOR: int = 3
const KIND_STAIRS: int = 4
const KIND_DOOR: int = 5
const KIND_OPEN: int = 6

class NavRegion:
	var id: int = -1
	var name: String = ""
	var kind: int = KIND_STREET
	var center: Vector3 = Vector3.ZERO
	var half_extents: Vector3 = Vector3(8, 2, 8)
	var floor_id: int = 0
	## Soft max population before pressure rises.
	var capacity: int = 5000
	var connection_ids: PackedInt32Array = PackedInt32Array()
	var active: bool = true


class NavConnection:
	var id: int = -1
	var from_region: int = -1
	var to_region: int = -1
	var position: Vector3 = Vector3.ZERO
	var kind: int = KIND_DOOR
	## Population transferable per second through this link.
	var capacity_per_sec: float = 50.0
	var blocked: bool = false
	var bidirectional: bool = true
	var active: bool = true
	## Accumulator leftover between ticks (fractional transfers).
	var transfer_accum: float = 0.0


var regions: Array[NavRegion] = []
var connections: Array[NavConnection] = []
var _free_regions: PackedInt32Array = PackedInt32Array()
var _free_connections: PackedInt32Array = PackedInt32Array()

## BFS parent / next-hop toward destination region (rebuilt when stimulus changes).
var flow_parent: PackedInt32Array = PackedInt32Array()
var flow_next_conn: PackedInt32Array = PackedInt32Array()
var flow_dest_region: int = -1
var last_flow_rebuilds: int = 0
var last_path_queries: int = 0


func clear() -> void:
	regions.clear()
	connections.clear()
	_free_regions.clear()
	_free_connections.clear()
	flow_parent.clear()
	flow_next_conn.clear()
	flow_dest_region = -1
	last_flow_rebuilds = 0
	last_path_queries = 0


func region_count() -> int:
	var n := 0
	for r in regions:
		if r.active:
			n += 1
	return n


func connection_count() -> int:
	var n := 0
	for c in connections:
		if c.active:
			n += 1
	return n


func add_region(
	name: String,
	kind: int,
	center: Vector3,
	half_extents: Vector3,
	capacity: int = 5000,
	floor_id: int = 0
) -> int:
	var region: NavRegion
	var idx: int
	if _free_regions.size() > 0:
		idx = _free_regions[_free_regions.size() - 1]
		_free_regions.resize(_free_regions.size() - 1)
		region = regions[idx]
	else:
		region = NavRegion.new()
		idx = regions.size()
		regions.append(region)
	region.id = idx
	region.name = name
	region.kind = kind
	region.center = center
	region.half_extents = half_extents
	region.floor_id = floor_id
	region.capacity = capacity
	region.connection_ids = PackedInt32Array()
	region.active = true
	return idx


func add_connection(
	from_id: int,
	to_id: int,
	position: Vector3,
	kind: int,
	capacity_per_sec: float,
	bidirectional: bool = true
) -> int:
	if from_id < 0 or to_id < 0 or from_id >= regions.size() or to_id >= regions.size():
		return -1
	var conn: NavConnection
	var idx: int
	if _free_connections.size() > 0:
		idx = _free_connections[_free_connections.size() - 1]
		_free_connections.resize(_free_connections.size() - 1)
		conn = connections[idx]
	else:
		conn = NavConnection.new()
		idx = connections.size()
		connections.append(conn)
	conn.id = idx
	conn.from_region = from_id
	conn.to_region = to_id
	conn.position = position
	conn.kind = kind
	conn.capacity_per_sec = capacity_per_sec
	conn.blocked = false
	conn.bidirectional = bidirectional
	conn.active = true
	conn.transfer_accum = 0.0
	regions[from_id].connection_ids.append(idx)
	if bidirectional:
		regions[to_id].connection_ids.append(idx)
	return idx


func find_region_at(pos: Vector3) -> int:
	## Prefer the smallest containing region (rooms over streets).
	var best := -1
	var best_vol := INF
	for i in regions.size():
		var r: NavRegion = regions[i]
		if not r.active:
			continue
		if _contains(r, pos):
			var vol := r.half_extents.x * r.half_extents.y * r.half_extents.z
			if vol < best_vol:
				best_vol = vol
				best = i
	if best >= 0:
		return best
	return nearest_region(pos)


func nearest_region(pos: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in regions.size():
		var r: NavRegion = regions[i]
		if not r.active:
			continue
		var d := r.center.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func _contains(r: NavRegion, pos: Vector3) -> bool:
	var d := pos - r.center
	return absf(d.x) <= r.half_extents.x and absf(d.y) <= r.half_extents.y + 0.5 and absf(d.z) <= r.half_extents.z


## Rebuild destination flow: for each region, next connection toward dest_region.
func rebuild_flow_to_region(dest_region: int) -> void:
	last_flow_rebuilds += 1
	flow_dest_region = dest_region
	var n := regions.size()
	flow_parent.resize(n)
	flow_next_conn.resize(n)
	for i in n:
		flow_parent[i] = -1
		flow_next_conn[i] = -1
	if dest_region < 0 or dest_region >= n or not regions[dest_region].active:
		return
	# BFS backward from destination over undirected graph.
	var queue: PackedInt32Array = PackedInt32Array()
	queue.append(dest_region)
	flow_parent[dest_region] = dest_region
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var region: NavRegion = regions[cur]
		for ci in region.connection_ids:
			if ci < 0 or ci >= connections.size():
				continue
			var conn: NavConnection = connections[ci]
			if not conn.active or conn.blocked:
				continue
			var other := conn.to_region if conn.from_region == cur else conn.from_region
			if other < 0 or other >= n:
				continue
			if not regions[other].active:
				continue
			if not conn.bidirectional and conn.from_region != cur:
				# Directed: can only leave via from→to, so reverse BFS needs to→from only if bi.
				continue
			if flow_parent[other] >= 0:
				continue
			flow_parent[other] = cur
			flow_next_conn[other] = ci
			queue.append(other)


func rebuild_flow_to_position(pos: Vector3) -> int:
	var dest := find_region_at(pos)
	rebuild_flow_to_region(dest)
	return dest


func next_connection_from(region_id: int) -> int:
	if region_id < 0 or region_id >= flow_next_conn.size():
		return -1
	return flow_next_conn[region_id]


func other_region(conn_id: int, from_region: int) -> int:
	if conn_id < 0 or conn_id >= connections.size():
		return -1
	var c: NavConnection = connections[conn_id]
	if c.from_region == from_region:
		return c.to_region
	if c.to_region == from_region:
		return c.from_region
	return -1


## Capacity-limited transfer budget for one connection this tick.
func available_transfer(conn_id: int, delta: float) -> int:
	if conn_id < 0 or conn_id >= connections.size():
		return 0
	var c: NavConnection = connections[conn_id]
	if not c.active or c.blocked:
		return 0
	c.transfer_accum += c.capacity_per_sec * delta
	var amount := int(c.transfer_accum)
	c.transfer_accum -= float(amount)
	return maxi(amount, 0)


func set_blocked(conn_id: int, blocked: bool) -> void:
	if conn_id < 0 or conn_id >= connections.size():
		return
	connections[conn_id].blocked = blocked


func route_region_ids(from_region: int, to_region: int) -> PackedInt32Array:
	## Single path query for journeys — not per-zombie A*.
	last_path_queries += 1
	var path := PackedInt32Array()
	if from_region < 0 or to_region < 0:
		return path
	rebuild_flow_to_region(to_region)
	var cur := from_region
	var guard := 0
	path.append(cur)
	while cur != to_region and guard < regions.size() + 2:
		guard += 1
		var next_c := next_connection_from(cur)
		if next_c < 0:
			break
		var nxt := other_region(next_c, cur)
		if nxt < 0:
			break
		path.append(nxt)
		cur = nxt
	return path


func reset_frame_counters() -> void:
	last_flow_rebuilds = 0
	last_path_queries = 0
