# Architecture — Million Dot

## Separation of concerns

```
SIMULATION (RefCounted data)
  ├── AgentStore (SoA packed arrays)
  ├── PopulationFieldSystem
  ├── HordeSystem
  ├── SpatialHash
  ├── RelevanceSystem
  └── budgets / tick orchestration
          │
          ▼
     RENDER DATA (read-only pull)
          │
          ▼
   MultiMeshInstance3D batches
```

`SimulationWorld` is not a Node. The main scene holds a single orchestrator Node that ticks the world and exposes it to the renderer.

## Why not nodes?

Creating 100k `CharacterBody3D` / `NavigationAgent3D` / `AnimationPlayer` instances:

- inflates SceneTree walk cost
- multiplies physics pairs
- destroys cache locality
- couples rendering lifetime to simulation lifetime

Mass agents are rows in packed arrays. Godot Nodes represent player, camera, world props, debug UI, and (later) a tiny cap of detailed NPCs.

## Simulation levels

| Level | Representation | Cost driver |
|-------|----------------|-------------|
| 0 Field | `PopulationCell` aggregates | Active cells |
| 1 Lightweight | SoA floats/bytes | Update budget + visibility |
| 2 Active | Same SoA, richer steering | Cap `MAX_ACTIVE_AGENTS` |
| 3 Detailed | SoA now; scene NPC later | Cap `MAX_DETAILED_AGENTS` |

Transitions are **budgeted per frame**. Walking into a 100k horde must not materialise 100k individuals.

## Hordes

A horde is an aggregate:

- population, center, extent, density, velocity, destination
- cohesion / alertness / faction
- list of **population field** indices

Split/merge operate on field membership and weighted centers — not per-zombie iteration of 100k identities.

## Crowd motion (v1)

- No per-agent A*.
- Fields and agents steer with potential-style attraction (player stimulus) + wander + cohesion.
- M6 will add navigation surfaces / flow fields for multi-floor routing.
- Door flow for extreme density is pressure → destination transfer on fields.

## Rendering

- Simple sphere meshes, unshaded materials.
- Visual language: small green = lightweight, orange = active, red = detailed, translucent blue = population field.
- Frustum/distance gate + `MAX_VISIBLE_AGENTS`.
- Multiple MultiMesh batches (`MULTIMESH_BATCH_SIZE`) for GPU instancing.

## Threading policy

Architecture keeps systems separable (fields / agents / relevance). **Do not parallelise until profiles show a bottleneck.** Prefer correctness and budgets first.

## Rust escape hatch

Only after:

1. Godot implementation
2. profile
3. architecture optimisation
4. profile again
5. identified CPU-bound hot loop

Then isolate behind a narrow API (e.g. positions/densities in/out). Do not design v1 around GDExtension.

## File map

```
scripts/
  autoload/sim_config.gd      budgets & toggles
  autoload/telemetry.gd       first-class profiling
  simulation/*.gd             mass population systems
  rendering/agent_renderer.gd MultiMesh sync
  player/fly_camera.gd        free fly + attract
  world/world_setup.gd        primitive 3D world
  ui/debug_ui.gd              stress controls
  benchmarks/benchmark_runner.gd
scenes/main.tscn
scenes/benchmarks/benchmark_{a-f}.tscn
```
