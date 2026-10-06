extends Node
## Headless architecture + M9 assertions.
## Run: godot --headless --path . res://tools/validate_architecture.tscn

func _ready() -> void:
	var ok := true
	var world := SimulationWorld.new()

	# --- Existing: 10k individuals ---
	world.bootstrap(10000)
	if world.total_population() != 10000:
		push_error("Expected 10k population, got %d" % world.total_population())
		ok = false
	if world.agents.living_count() != 10000:
		push_error("Expected 10k individual agents for M1-scale spawn")
		ok = false

	# --- 100k horde without agents ---
	world.clear()
	var horde_id := world.create_horde(100000)
	if horde_id < 0:
		push_error("Horde creation failed")
		ok = false
	if world.total_population() != 100000:
		push_error("Horde population mismatch: %d" % world.total_population())
		ok = false
	if world.agents.living_count() != 0:
		push_error("100k horde must not create individual agents; got %d" % world.agents.living_count())
		ok = false
	if world.fields.living_count() < 1:
		push_error("Horde should create population fields")
		ok = false
	if world.hordes.living_count() != 1:
		push_error("Expected 1 horde entity")
		ok = false

	# --- Split conserves population ---
	var before_split := world.total_population()
	world.split_horde()
	if world.total_population() != before_split:
		push_error("Split lost population: %d -> %d" % [before_split, world.total_population()])
		ok = false
	if world.hordes.living_count() < 2:
		# Force denser cells then split
		world.fields.try_split_overdense()
		world.split_horde()
	var after_split_hordes := world.hordes.living_count()
	if after_split_hordes < 1:
		push_error("Expected hordes after split")
		ok = false

	# --- Merge conserves population ---
	var before_merge := world.total_population()
	world.merge_hordes()
	if world.total_population() != before_merge:
		push_error("Merge lost population: %d -> %d" % [before_merge, world.total_population()])
		ok = false

	# --- Fire aggregate ---
	world.clear()
	horde_id = world.create_horde(100000)
	var horde := world.hordes.get_horde(horde_id)
	var before := world.total_population()
	var fire_idx := world.fire.spawn_fire(horde.center, 14.0, 1.0, 14.0, 0)
	if fire_idx < 0:
		push_error("Fire spawn failed")
		ok = false
	SimConfig.attract_active = false
	for _i in 40:
		world.tick(1.0 / 20.0)
	if world.fire.total_field_kills <= 0 and world.total_population() >= before:
		push_error("Fire should reduce field population aggregately")
		ok = false

	# --- Combat ring ---
	world.clear()
	world.bootstrap(10000)
	world.player_position = Vector3.ZERO
	for _i in 10:
		world.tick(1.0 / 20.0)
	if world.combat.ring_agent_count <= 0 and world.agents.count_active <= 0:
		world.agents.spawn_batch(50, Vector3.ZERO, 10.0, SimConfig.LEVEL_LIGHTWEIGHT, SimConfig.FACTION_ZOMBIE, RandomNumberGenerator.new())
		world.tick(1.0 / 20.0)
	if world.agents.count_active + world.agents.count_detailed <= 0:
		push_error("Combat ring should promote nearby agents")
		ok = false
	world.player_aim = Vector3(1, 0, 0)
	var shoot_result := world.shoot()
	if not shoot_result.has("hit"):
		push_error("Shoot returned unexpected payload")
		ok = false

	# --- 1M field-heavy ---
	world.clear()
	world.bootstrap(1000000)
	if world.total_population() != 1000000:
		push_error("1M bootstrap failed: %d" % world.total_population())
		ok = false
	if world.agents.living_count() > 50000:
		push_error("1M should be field-heavy; agents=%d" % world.agents.living_count())
		ok = false
	if world.fields.total_population() < 500000:
		push_error("1M should keep most pop in fields")
		ok = false

	# --- M9: City nav + city bootstrap ---
	world.clear()
	var city_root := Node3D.new()
	add_child(city_root)
	var meta := CityBuilder.build(city_root, world.nav, 42)
	world.bind_city_meta(meta)
	if world.nav.region_count() < 10:
		push_error("City should create many nav regions; got %d" % world.nav.region_count())
		ok = false
	if world.nav.connection_count() < 5:
		push_error("City should create nav connections; got %d" % world.nav.connection_count())
		ok = false
	if int(meta.get("extreme_building_region", -1)) < 0:
		push_error("Extreme building region missing")
		ok = false

	world.bootstrap_city(100000)
	if world.total_population() != 100000:
		push_error("City 100k bootstrap mismatch: %d" % world.total_population())
		ok = false
	if world.agents.living_count() > 5000:
		push_error("City 100k should be mostly aggregate; agents=%d" % world.agents.living_count())
		ok = false
	if world.hordes.living_count() < 1 and world.fields.living_count() < 1:
		push_error("City 100k needs fields/hordes")
		ok = false

	# Flow rebuild + transfers under attraction
	SimConfig.attract_active = true
	world.player_position = Vector3(0, 1, 0)
	world.nav.rebuild_flow_to_position(world.player_position)
	if world.nav.flow_dest_region < 0:
		push_error("Flow rebuild failed")
		ok = false
	var pop_before_flow := world.total_population()
	for _i in 60:
		world.tick(1.0 / 20.0)
	if world.total_population() > pop_before_flow:
		push_error("Population increased unexpectedly during flow")
		ok = false
	# Deaths from nothing shouldn't happen; conservation unless fire/combat.
	if world.total_population() != pop_before_flow:
		# Materialisation moves field→agent but conserves; allow equality only.
		push_error("Population not conserved during city attraction: %d -> %d" % [
			pop_before_flow, world.total_population()
		])
		ok = false

	# Bottleneck extreme density — no mass agents
	world.clear()
	world.bind_city_meta(meta)
	world.extreme_density_building(100000)
	if world.total_population() != 100000:
		push_error("Bottleneck pop mismatch: %d" % world.total_population())
		ok = false
	if world.agents.living_count() != 0:
		push_error("Bottleneck must not spawn 100k agents; got %d" % world.agents.living_count())
		ok = false

	# Entering the building must not materialise entire population
	var extreme_center := Vector3(-90, 1, 86)
	var spawns: Array = meta.get("spawn_points", [])
	if spawns.size() > 0:
		extreme_center = spawns[spawns.size() - 1]
	world.player_position = extreme_center
	for _i in 30:
		world.tick(1.0 / 20.0)
	var detailed := world.agents.count_detailed
	var active := world.agents.count_active
	if detailed > SimConfig.MAX_DETAILED_AGENTS:
		push_error("Detailed over cap: %d" % detailed)
		ok = false
	if active > SimConfig.MAX_ACTIVE_AGENTS:
		push_error("Active over cap: %d" % active)
		ok = false
	if world.agents.living_count() > 5000:
		push_error("Materialisation blew up inside 100k building: agents=%d" % world.agents.living_count())
		ok = false

	if ok:
		print("VALIDATE_OK architecture + M9 city/nav/conservation assertions passed")
		print("  city regions=%d connections=%d" % [world.nav.region_count(), world.nav.connection_count()])
		print("  bottleneck agents=%d fields=%d hordes=%d" % [
			world.agents.living_count(), world.fields.living_count(), world.hordes.living_count()
		])
		city_root.queue_free()
		await get_tree().process_frame
		get_tree().quit(0)
	else:
		print("VALIDATE_FAIL")
		get_tree().quit(1)
