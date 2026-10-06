# ZombieSim — Mass-NPC 3D Simulation (M9: 100,000 Zombie City)

Technical prototype proving Godot 4 can host extremely large NPC populations when the simulation is **data-oriented** from day one — not one `Node3D` / `CharacterBody3D` / `NavigationAgent3D` per agent.

## Guiding principle

> Do not ask “how do we update 100,000 NPCs faster?”  
> Ask “why does Godot need to update 100,000 NPCs individually?”

Simulation cost should track **relevance and complexity**, not raw population.

```
100,000 zombies
       │
       ▼
Population / Horde representation
       │
       ├── population fields
       ├── density / flow / pressure
       ├── nav regions + capacity connections
       └── collective state
              │
              ▼
      materialise only where useful
              │
       ┌──────┴──────┐
       ▼             ▼
 lightweight       active
       │             │
       └──────┬──────┘
              ▼
          detailed
```

## Requirements

- **Godot 4.3+**
- No Rust in M9 — Godot-first. Rust is an escape hatch only after profiling.

## Quick start — 100k city

1. Open this folder in Godot 4.3+.
2. Run `scenes/main.tscn` (or showcase `scenes/showcase/city_100k.tscn`).
3. **WASD** move, mouse aim, **LMB/C** shoot, **F** molotov, **Space** attract, **R** reload, **G** interact.
4. Use the debug panel: **100k City Spawn**, **100k Bottleneck**, Split/Merge, Toggle Nav/Flow.

```bash
godot --headless --path . res://tools/validate_architecture.tscn
godot --headless --path . res://scenes/benchmarks/benchmark_g.tscn
./tools/run_benchmarks.sh
```

## Architecture (short)

| Layer | Role | Node3D? |
|-------|------|---------|
| Level 0 Population field | Aggregate density / flow / faction | No |
| NavGraph | Regions + capacity-limited connections | No |
| Journey | Distant aggregate travel | No |
| Level 1 Lightweight | Packed SoA agent | No |
| Level 2 Active | Near player; more motion detail | No |
| Level 3 Detailed | Hard-capped | Rare |
| Horde | First-class aggregate over fields | No |
| MultiMesh renderer | GPU instancing of dots / field markers | Yes (batches) |

Core types live under `scripts/simulation/`. City geometry: `scripts/world/city_builder.gd`.

## Debug controls

| Action | Effect |
|--------|--------|
| +1k / +10k / +100k / +1M | Spawn zombies (large counts → fields/hordes) |
| Create 100k Horde | One horde, aggregate cells — not 100k nodes |
| Split / Merge Hordes | Population-conserving field manipulation |
| Toggle Attract | Stimulus propagates via nav flow → fields → hordes |
| Extreme Density / Bottleneck | 100k inside The Building; door capacity flow |
| 100k City Spawn | Distribute 100k across city spawn sites |
| Toggle Nav / Flow | Visualise regions and destination flow |
| Shoot / Molotov | Individual ring + aggregate field damage |
| Pause / Step | Deterministic inspection |

## Benchmarks

| Scene | Population | Mode |
|-------|------------|------|
| A–F | 10k … 1M | open field |
| G | 100k | city distribution |
| H | 100k | convergence (attract) |
| I | 100k | bottleneck building |
| J | 100k | combat + fire |

Each run prints `BENCH_RESULT {json}` including `sim_cost_per_pop` and `expensive_fraction`.

## Milestones

- **M1–M8** — Million Dot foundation (fields, hordes, combat, MultiMesh) — **implemented**
- **M9** — 100,000 Zombie City (nav, flow, bottlenecks, journeys, city benches) — **this branch**

## Success criteria

1. 100,000 zombies exist simultaneously; population is conserved.
2. 250k/500k/1M aggregate benches remain possible.
3. Hordes move through the city, split, merge, and pass bottlenecks without 100k physics bodies.
4. Materialisation stays budgeted; entering a massive horde does not materialise the entire horde.
5. Increasing population primarily increases cheap aggregate simulation (`sim_cost_per_pop`, `expensive_fraction`).
