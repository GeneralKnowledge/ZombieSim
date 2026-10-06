# Architecture — ZombieSim / Million Dot

## Separation of concerns

```
SIMULATION (RefCounted data)
  ├── AgentStore (SoA packed arrays)
  ├── PopulationFieldSystem
  ├── HordeSystem
  ├── NavGraph (regions + capacity connections)
  ├── JourneySystem (distant aggregate travel)
  ├── SpatialHash
  ├── RelevanceSystem
  ├── CombatRing / FireSystem
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

## M9 — City navigation & population flow

```
CityBuilder (deterministic seed)
        │
        ▼
   NavGraph regions + connections
        │  (doors / streets / stairs / corridors + capacity/sec)
        ▼
Population fields steer via flow field (BFS to player region)
        │
        ▼
Capacity-limited population_transfer across connections
        │
        ├── source field population decreases
        └── destination field population increases
```

- No `NavigationAgent3D` per zombie.
- Bottlenecks create **pressure**, not physics explosions.
- Hordes split toward alternate connections when blocked; merge when nearby with shared destination.
- Extremely distant hordes may become **journeys** (origin/destination/ETA) and reconstruct on arrival.

## Hordes

A horde is an aggregate:

- population, center, extent, density, velocity, destination
- cohesion / alertness / faction / pressure / navigation_state
- flow_target connection + region_id
- list of **population field** indices (reclaimed by horde_id scan)

Split/merge operate on field membership and weighted centers — not per-zombie iteration of 100k identities.

**Population conservation:** before = after + legitimate_deaths for split/merge/transfer/materialise/journey/combat/fire.

## Crowd motion

- No per-agent A* for the mass population.
- Fields use nav flow targets under attraction; individuals near the player use direct steering.
- Door flow: pressure → capacity-limited transfer.
- Path queries are reserved for journeys / rare aggregate routing (`MAX_PATHFINDING_REQUESTS_PER_FRAME`).

## Rendering

- PointMesh MultiMesh for mass dots; field markers for aggregates.
- Visual language: small green = lightweight, orange = active, red = detailed, translucent blue = population field.
- Frustum/distance gate + `MAX_VISIBLE_AGENTS`.
- Simulation does not depend on the renderer.

## Combat ring + fire

```
Player aim / shoot / molotov
        │
        ▼
 CombatRing (budgeted ACTIVE/DETAILED near player)
        │ hitscan individuals in ring
        │ else aggregate field damage
        ▼
 FireSystem volumes
        │ burn agents in radius (budgeted scan)
        │ burn overlapping fields aggregately
```

## Threading / Rust

Do not parallelise or add Rust until profiles show a bottleneck after architectural optimisation.
