extends Node
## Global simulation budgets and tunables.
## Simulation cost should track relevance, not raw population count.

# --- Hard caps (prevent performance cliffs) ---
var MAX_DETAILED_AGENTS: int = 128
var MAX_ACTIVE_AGENTS: int = 1024
var MAX_VISIBLE_AGENTS: int = 12000
var MAX_PATHFINDING_REQUESTS_PER_FRAME: int = 32
var MAX_MATERIALISATIONS_PER_FRAME: int = 32
var MAX_AI_DECISIONS_PER_FRAME: int = 128
## Per sim tick (sim runs ~20 Hz), not per rendered frame.
var MAX_AGENT_UPDATES_PER_FRAME: int = 10000

# --- Spatial ---
var CELL_SIZE: float = 16.0
var WORLD_HALF_EXTENT: float = 512.0
var FLOOR_HEIGHT: float = 4.0

# --- Materialisation radii (metres) ---
var RADIUS_DETAILED: float = 12.0
var RADIUS_ACTIVE: float = 40.0
var RADIUS_LIGHTWEIGHT: float = 120.0
var RADIUS_VISIBLE: float = 200.0

# --- Population field ---
var FIELD_MERGE_DISTANCE: float = 24.0
var FIELD_SPLIT_DENSITY: float = 0.85
var FIELD_ABSORB_MIN_POP: int = 50
## Agents denser than this may be represented as population fields.
var FIELD_THRESHOLD_POP: int = 200

# --- Hordes ---
var HORDE_ATTRACT_STRENGTH: float = 18.0
var HORDE_COHESION: float = 0.35
var HORDE_MAX_SPEED: float = 6.0

# --- Agent motion ---
var AGENT_MAX_SPEED: float = 4.5
var AGENT_WANDER_STRENGTH: float = 1.2

# --- Combat ring (shootable individuals) ---
var COMBAT_RING_RADIUS: float = 28.0
var SHOOT_RANGE: float = 45.0
var SHOOT_HIT_RADIUS: float = 1.2
var SHOOT_DAMAGE: float = 55.0
var SHOOT_FIELD_POP_DAMAGE: int = 12
var COMBAT_PROMOTIONS_PER_TICK: int = 48

# --- Fire / Molotov (area events) ---
var MOLOTOV_THROW_RANGE: float = 22.0
var MOLOTOV_RADIUS: float = 9.0
var MOLOTOV_INTENSITY: float = 1.0
var MOLOTOV_LIFETIME: float = 14.0
var FIRE_AGENT_DPS: float = 40.0
var FIRE_FIELD_KILL_RATE: float = 0.35
var MAX_FIRE_AGENT_CHECKS_PER_TICK: int = 2048
var MAX_FIRE_VOLUMES: int = 32

# --- Rendering ---
var MULTIMESH_BATCH_SIZE: int = 16384
var DOT_SCALE_LIGHTWEIGHT: float = 0.35
var DOT_SCALE_ACTIVE: float = 0.55
var DOT_SCALE_DETAILED: float = 0.85
var FIELD_MARKER_SCALE: float = 2.5
var show_combat_ring: bool = true
var show_fire_volumes: bool = true
var isometric_mode: bool = true

# --- Simulation levels (bit-friendly ints) ---
const LEVEL_FIELD: int = 0
const LEVEL_LIGHTWEIGHT: int = 1
const LEVEL_ACTIVE: int = 2
const LEVEL_DETAILED: int = 3

# --- Factions ---
const FACTION_ZOMBIE: int = 0
const FACTION_SURVIVOR: int = 1

# --- Debug toggles ---
var show_population_fields: bool = true
var show_flow_fields: bool = false
var show_spatial_grid: bool = false
var show_navigation: bool = false
var show_simulation_levels: bool = true
var simulation_paused: bool = false
var attract_active: bool = false

# --- Startup / benchmark ---
var initial_population: int = 10000
var spawn_as_fields_above: int = 50000
