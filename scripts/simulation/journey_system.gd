class_name JourneySystem
extends RefCounted
## Extremely distant populations as lightweight journeys — not continuous agents.
## Reconstruct approximate state when relevance returns.

class Journey:
	var id: int = -1
	var origin: Vector3 = Vector3.ZERO
	var destination: Vector3 = Vector3.ZERO
	var departure_tick: int = 0
	var estimated_arrival_tick: int = 0
	var route: PackedInt32Array = PackedInt32Array()
	var population: int = 0
	var purpose: int = 0 ## 0=wander 1=attract 2=escape
	var state: int = 0 ## 0=travelling 1=arrived 2=cancelled
	var faction: int = 0
	var horde_id: int = -1
	var active: bool = true


var journeys: Array[Journey] = []
var _next_id: int = 1
var sim_tick: int = 0
var last_created: int = 0
var last_arrived: int = 0


func clear() -> void:
	journeys.clear()
	_next_id = 1
	sim_tick = 0
	last_created = 0
	last_arrived = 0


func living_count() -> int:
	var n := 0
	for j in journeys:
		if j.active and j.state == 0 and j.population > 0:
			n += 1
	return n


func total_population() -> int:
	var n := 0
	for j in journeys:
		if j.active and j.state == 0:
			n += j.population
	return n


func create_journey(
	pop: int,
	origin: Vector3,
	destination: Vector3,
	route: PackedInt32Array,
	ticks_to_arrive: int,
	purpose: int = 0,
	faction: int = 0,
	horde_id: int = -1
) -> int:
	if pop <= 0:
		return -1
	var j := Journey.new()
	j.id = _next_id
	_next_id += 1
	j.origin = origin
	j.destination = destination
	j.departure_tick = sim_tick
	j.estimated_arrival_tick = sim_tick + maxi(ticks_to_arrive, 1)
	j.route = route
	j.population = pop
	j.purpose = purpose
	j.state = 0
	j.faction = faction
	j.horde_id = horde_id
	j.active = true
	journeys.append(j)
	last_created += 1
	return j.id


func update(delta: float) -> Array[Journey]:
	## Advances clocks; returns journeys that arrived this tick.
	sim_tick += 1
	last_arrived = 0
	var arrived: Array[Journey] = []
	for j in journeys:
		if not j.active or j.state != 0:
			continue
		if sim_tick >= j.estimated_arrival_tick:
			j.state = 1
			j.active = false
			arrived.append(j)
			last_arrived += 1
	return arrived


func approximate_position(j: Journey) -> Vector3:
	## Deterministic lerp along route for save/load / visualisation.
	if j.route.is_empty():
		var t := 0.0
		var span := maxi(j.estimated_arrival_tick - j.departure_tick, 1)
		t = clampf(float(sim_tick - j.departure_tick) / float(span), 0.0, 1.0)
		return j.origin.lerp(j.destination, t)
	# Without region centers here, fall back to origin→destination.
	var span2 := maxi(j.estimated_arrival_tick - j.departure_tick, 1)
	var u := clampf(float(sim_tick - j.departure_tick) / float(span2), 0.0, 1.0)
	return j.origin.lerp(j.destination, u)


func cancel(id: int) -> int:
	for j in journeys:
		if j.id == id and j.active:
			var pop := j.population
			j.active = false
			j.state = 2
			j.population = 0
			return pop
	return 0
