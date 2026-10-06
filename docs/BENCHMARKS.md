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

### 2026-10-06 — headless Godot 4.3.stable (CI VM, no GPU render)

Hardware: cloud agent VM · Renderer: headless dummy (render_time_ms = 0) · VSync off · 5s runs

| Bench | Pop | Avg FPS | Min FPS | Avg frame ms | Max frame ms | Avg sim ms | Mem MB | Agents | Fields | Field pop | Notes |
|-------|-----|---------|---------|--------------|--------------|------------|--------|--------|--------|-----------|-------|
| A | 10k | 145 | 1* | 6.9 | 37.7 | 6.4 | 17.7 | 10000 | 0 | 0 | All SoA agents |
| C | 100k | 57 | 1* | 17.6 | 38.2 | 17.6 | 20.7 | ~27k | 326 | ~73k | Field-heavy spawn |
| F | 1M | 31 | 1* | 32.5 | 142 | 32.1 | 25.7 | ~23k | 3194 | ~977k | Aggregate million |

\* `min_fps` spikes on first frames during spawn; prefer avg metrics.

Architecture validation: `godot --headless --path . res://tools/validate_architecture.tscn`
