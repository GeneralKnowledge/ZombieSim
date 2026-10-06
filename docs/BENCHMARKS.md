# Benchmark log

Record hardware + Godot version with every row. VSync should be **off** (`project.godot`).

## Template

| Bench | Pop | Avg FPS | Min FPS | Avg frame ms | Max frame ms | Avg sim ms | Render ms | Mem MB | Agents | Fields | Field pop | Hordes | Visible | Notes |
|-------|-----|---------|---------|--------------|--------------|------------|-----------|--------|--------|--------|-----------|--------|---------|-------|
| A | 10k | | | | | | | | | | | | | |
| B | 50k | | | | | | | | | | | | | |
| C | 100k | | | | | | | | | | | | | |
| D | 250k | | | | | | | | | | | | | |
| E | 500k | | | | | | | | | | | | | |
| F | 1M | | | | | | | | | | | | | |

## How to run

```bash
./tools/run_benchmarks.sh
# or single:
godot --headless --path . res://scenes/benchmarks/benchmark_c.tscn
```

Stdout includes `BENCH_RESULT {...}`.

## Horde stress checklist

1. Main scene → **Create 100k Horde**
2. Confirm telemetry: `hordes ≥ 1`, `fields > 0`, agent count **≪ 100000**
3. Hold **Space** — fields drift toward player
4. Fly into horde — materialisation rate stays near budget; detailed/active stay capped
5. **Split Horde** / **Merge Hordes**
6. **Extreme Density 100k** — single high-pressure field

## Notes

### 2026-10-06 — performance pass (post-fix)

**Root cause of the bad first build:** SphereMesh MultiMeshes + per-frame `sort_custom` + `set_instance_transform` loops + Forward+ + CharacterBody3D camera + full-array level counts every tick.

**Fixes:** PointMesh MultiMesh, bulk `buffer` upload, no sort, gl_compatibility, Node3D fly cam, 20 Hz fixed sim, O(1) level counters, skip empty field/horde systems, software-GL upload throttle.

#### OpenGL windowed probe (llvmpipe software GL — this CI VM has no real GPU)

`tools/fps_probe.tscn` · VSync off · 1s warmup + 3s sample · all 10k dots visible

| Build | Pop | Visible | Avg FPS | Avg frame ms | Avg sim ms | Avg render CPU ms |
|-------|-----|---------|---------|--------------|------------|-------------------|
| Before | 10k | ~2.6k | ~27 | ~36 | ~6 | ~8 |
| After | 10k | 10k | ~82 | ~12 | ~1.2 | ~6.7 (every 3rd frame) |

Expect much higher FPS on a discrete/integrated GPU with `upload_interval = 1`.

#### Headless architecture check

`godot --headless --path . res://tools/validate_architecture.tscn` → `VALIDATE_OK`
