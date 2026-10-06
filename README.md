# Million Dot — Godot Mass-NPC 3D Simulation

Technical prototype proving Godot 4 can host extremely large NPC populations when the simulation is **data-oriented** from day one — not one `Node3D` / `CharacterBody3D` / `NavigationAgent3D` per agent.

## Guiding principle

> Do not ask “how do we update 100,000 NPCs faster?”  
> Ask “why does Godot need to update 100,000 NPCs individually?”

Population stays persistent. Only the **amount of information** about each individual changes.

```
1,000,000 population
        ↓
population fields (Level 0)
        ↓
crowds / hordes
        ↓
GPU-visible dots (MultiMesh)
        ↓
nearby lightweight / active agents
        ↓
small capped set of detailed NPCs
```

## Requirements

- **Godot 4.3+** (Forward Plus)
- No Rust in v1 — Godot-first. Rust is an escape hatch only after profiling.

## Quick start — combat sandbox

1. Open this folder in Godot 4.3+.
2. Run `scenes/main.tscn`.
3. **WASD** move (iso), mouse aim, **LMB** shoot, **F** molotov, **R** reload, **G** door/loot.
4. Waves spawn growing hordes automatically; survive and score kills.
5. Debug panel still supports mass-population stress spawns.

```bash
# Optional CLI (headless smoke / benchmarks)
godot --path . --quit-after 3
godot --headless --path . res://tools/validate_architecture.tscn
godot --headless --path . res://scenes/benchmarks/benchmark_a.tscn
./tools/run_benchmarks.sh
```

## Architecture (short)

| Layer | Role | Node3D? |
|-------|------|---------|
| Level 0 Population field | Aggregate density / flow / faction | No |
| Level 1 Lightweight | Packed SoA agent | No |
| Level 2 Active | Near player; more motion detail | No |
| Level 3 Detailed | Hard-capped; may become scene NPCs later | Rare |
| Horde | First-class aggregate over fields | No |
| MultiMesh renderer | GPU instancing of dots / field markers | Yes (batches) |

Core types live under `scripts/simulation/`:

- `agent_store.gd` — packed arrays (`pos_x[]` …)
- `spatial_hash.gd` — sparse 3D hash
- `population_field.gd` — Level 0 cells, merge/split/transfer
- `horde_system.gd` — create / attract / split / merge
- `relevance_system.gd` — detail from relevance, not headcount
- `simulation_world.gd` — orchestration + budgets

Rendering (`scripts/rendering/agent_renderer.gd`) reads simulation data and uploads a **budgeted** visible set to MultiMesh batches. Simulation does not depend on the renderer.

## Debug controls

| Action | Effect |
|--------|--------|
| +1k / +10k / +100k / +1M | Spawn zombies (large counts → fields/hordes) |
| Create 100k Horde | One horde, aggregate cells — not 100k nodes |
| Split / Merge Hordes | Population-field manipulation |
| Space / Toggle Attract | Strong stimulus toward player |
| Extreme Density 100k | Constrained high-pressure field |
| Shoot (R) / click | Hitscan combat ring; else field damage |
| Molotov (F) | Area fire — individuals + aggregate fields |
| Toggle Isometric (I) | Orthographic iso camera |
| Pause / Step | Deterministic inspection |
| Toggle Population Fields | Show/hide Level 0 markers |

Budgets (see `scripts/autoload/sim_config.gd`):

- `MAX_DETAILED_AGENTS` (128)
- `MAX_ACTIVE_AGENTS` (1024)
- `MAX_VISIBLE_AGENTS` (8000)
- `MAX_MATERIALISATIONS_PER_FRAME` (64)
- `MAX_AGENT_UPDATES_PER_FRAME` (50000)

## Benchmarks

Scenes in `scenes/benchmarks/`:

| Scene | Population |
|-------|------------|
| A | 10,000 |
| B | 50,000 |
| C | 100,000 |
| D | 250,000 |
| E | 500,000 |
| F | 1,000,000 |

Each run prints `BENCH_RESULT {json}` with FPS, frame/sim time, memory, agent/field/horde counts. Record results in `docs/BENCHMARKS.md`.

## Milestones

- **M1** Dot world + telemetry + 10k — **implemented**
- **M2** 100k — **implemented** (spawn / benches)
- **M3** Million Dot Test — **implemented** (field-heavy path)
- **M4** Population fields — **implemented**
- **M5** Hordes — **implemented** (create/split/merge/attract)
- **M6** Multi-floor navigation / flow fields — scaffolding (building + `floor_id`)
- **M7** Materialisation budgets — **implemented** (progressive)
- **M8** Massive horde stress — use Create Horde + Space

See `docs/ARCHITECTURE.md` for deeper design notes.

## Success criteria (architectural)

1. Hundreds of thousands of NPCs exist as **simulation state**.
2. A million population can exist as **aggregate** simulation.
3. 100k+ zombies form **one horde** without 100k Godot nodes / physics bodies / nav agents.
4. Nearby agents materialise within budgets; detail stays capped.
5. Rendering uses **GPU instancing** (MultiMesh).
6. Cost tracks **relevance**, not raw population.
7. Godot remains primary; Rust only if profiling demands it.
