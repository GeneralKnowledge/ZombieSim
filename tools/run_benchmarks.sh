#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
OUT="$ROOT/benchmarks/results"
mkdir -p "$OUT"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/bench_${STAMP}.log"

echo "Using: $($GODOT --version 2>/dev/null || echo godot)"
echo "Logging to $LOG"

for key in a b c d e f; do
  scene="res://scenes/benchmarks/benchmark_${key}.tscn"
  echo "=== Running $scene ===" | tee -a "$LOG"
  "$GODOT" --headless --path "$ROOT" "$scene" 2>&1 | tee -a "$LOG" || true
done

echo "Done. Results in $LOG"
