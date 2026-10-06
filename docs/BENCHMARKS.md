# Benchmark log

Record hardware + Godot version with every row. VSync should be **off** (`project.godot`).

## Template

| Bench | Pop | Mode | Avg FPS | Avg frame ms | Avg sim ms | Mem MB | Agents | Fields | Field pop | Hordes | Transfers | sim_cost/pop | expensive_frac | Notes |
|-------|-----|------|---------|--------------|------------|--------|--------|--------|-----------|--------|-----------|--------------|----------------|-------|
| A | 10k | open | | | | | | | | | | | | |
| B | 50k | open | | | | | | | | | | | | |
| C | 100k | open | | | | | | | | | | | | |
| D | 250k | open | | | | | | | | | | | | |
| E | 500k | open | | | | | | | | | | | | |
| F | 1M | open | | | | | | | | | | | | |
| G | 100k | city | | | | | | | | | | | | |
| H | 100k | convergence | | | | | | | | | | | | |
| I | 100k | bottleneck | | | | | | | | | | | | |
| J | 100k | combat | | | | | | | | | | | | |

## How to run

```bash
./tools/run_benchmarks.sh
# or single:
godot --headless --path . res://scenes/benchmarks/benchmark_g.tscn
```

Stdout includes `BENCH_RESULT {...}`.

## Horde / city stress checklist

1. Main or showcase → **100k City Spawn**
2. Confirm telemetry: `TOTAL POPULATION 100000`, agents ≪ 100000, fields/hordes > 0
3. Toggle Attract — fields flow via nav toward player; watch `Transfers`
4. Walk into a dense area — materialisation stays near budget; detailed/active capped
5. **100k Bottleneck** — crowd exits The Building through door capacity (no physics explosion)
6. Split / Merge — population conserved
7. Leave the area and return — population still exists (fields / journeys)

## Notes

### 2026-10-06 — M9 headless smoke (llvmpipe / software)

`VALIDATE_OK` — 40 nav regions, 43 connections; bottleneck agents=0 for 100k field pack.

| Bench | Pop | Mode | ~Avg FPS | ~Avg sim ms | Agents | Fields | Transfers | sim_cost/pop | expensive_frac |
|-------|-----|------|----------|-------------|--------|--------|-----------|--------------|----------------|
| C | 100k | open | ~62 | ~16 | ~21k | ~265 | 0 | ~1.8e-4 | ~0.0115 |
| G | 100k | city | ~60 | ~17 | ~17k | ~275 | ~27 | ~2.1e-4 | ~0.0115 |
| H | 100k | convergence | ~59 | ~17 | ~17k | ~285 | ~31 | ~2.1e-4 | ~0.0115 |
| I | 100k | bottleneck | ~63 | ~16 | ~17k | ~242 | ~90 | ~2.3e-4 | ~0.0115 |
| J | 100k | combat | ~53 | ~19 | ~15k | ~255 | ~41 | ~2.7e-4 | ~0.012 |

Active/detailed stayed at caps (1024 / 128). Population conserved except combat/fire kills in J.

### 2026-10-06 — performance pass (post-Million Dot)

**Root cause of the bad first build:** SphereMesh MultiMeshes + per-frame `sort_custom` + `set_instance_transform` loops + Forward+ + CharacterBody3D camera + full-array level counts every tick.

**Fixes:** PointMesh MultiMesh, bulk `buffer` upload, no sort, gl_compatibility, Node3D fly cam, 20 Hz fixed sim, O(1) level counters, skip empty field/horde systems, software-GL upload throttle.
