extends RefCounted
class_name GameConfig

# ============================================================================
# NIGHT SETTINGS
# ============================================================================

# Night duration configuration (for easy debugging)
const HOURS_PER_NIGHT := 8  # Service runs from 5pm (hour 1) to 1am (hour 8)
const STARTING_HOUR := 17  # 5pm in 24-hour format
const NUM_TABLES := 6  # Number of table slots available in the tavern

# Client generation pattern (hour -> number of clients generated)
const CLIENTS_PER_HOUR := {
	1: 2,
	2: 3,
	3: 4,
	4: 5,
	5: 4,
	6: 3,
	7: 2,
	8: 1,
}

# Table leaving chance configuration
const LEAVE_CHANCE_BASE := 0.2  # 20% chance after first hour
const LEAVE_CHANCE_INCREMENT := 0.2  # +20% per consecutive hour


# ============================================================================
# ROWDINESS & EVENTS
# ============================================================================

# Rowdiness thresholds
const ROWDINESS_DANGEROUS := 10  # Threshold for dangerous rowdiness alerts
const ROWDINESS_FISTFIGHT := 15  # Threshold for fistfight trigger

# Event chance calculation
const EVENT_CHANCE_DIVISOR := 30.0  # event_chance = rowdiness / EVENT_CHANCE_DIVISOR
const UNSERVED_EVENT_CHANCE_MULTIPLIER := 1.3  # Multiplier for unserved tables

# Rowdiness description thresholds
const ROWDINESS_CALM := 2
const ROWDINESS_MODERATE := 5
const ROWDINESS_ROWDY := 7

# Rowdiness modifiers
const GROUP_SIZE_ROWDINESS_MODIFIER := 0.3  # Per person per hour
const DRUNKENNESS_ROWDINESS_MODIFIER := 0.2  # Per pint consumed


# ============================================================================
# SATISFACTION & TIPS
# ============================================================================

# Tips calculation
const SATISFACTION_TIPS_DIVISOR := 10.0  # tips = consumption * price * (1 + satisfaction / SATISFACTION_TIPS_DIVISOR)

# Satisfaction/rowdiness penalties
const OUT_OF_STOCK_SATISFACTION_PENALTY := -2
const OUT_OF_STOCK_ROWDINESS_PENALTY := 1
const COMPLETELY_OUT_OF_STOCK_SATISFACTION_PENALTY := -3
const COMPLETELY_OUT_OF_STOCK_ROWDINESS_PENALTY := 2
const UNSERVED_SATISFACTION_PENALTY := -1  # Per hour
const UNSERVED_ROWDINESS_PENALTY := 1  # Per hour

# Intervention effects
const FREE_ROUND_SATISFACTION_BONUS := 2
const FREE_ROUND_ROWDINESS_REDUCTION := -3
const BOUNCER_SATISFACTION_PENALTY := -1
const BOUNCER_ROWDINESS_REDUCTION := -2

# Event satisfaction effects
const EVENT_SUCCESS_BASE_SATISFACTION := 2
const EVENT_FAIL_SATISFACTION_PENALTY := -2
const EVENT_FAIL_ROWDINESS_PENALTY := 1
const ROWDY_NOISE_ROWDINESS_PENALTY := 1


# ============================================================================
# STAMINA & WENCH MECHANICS
# ============================================================================

# Base stamina drain
const BASE_STAMINA_DRAIN := 1  # Per hour
const OVERWORK_STAMINA_DRAIN_PER_TABLE := 1  # Additional drain per extra table

# Stamina thresholds for mood (as percentages)
const STAMINA_EXHAUSTED := 0.0
const STAMINA_WEARY := 0.2
const STAMINA_TIRED := 0.4
const STAMINA_FOCUSED := 0.6
const STAMINA_CHEERFUL := 0.8

# Service efficiency
const SERVICE_EFFICIENCY_PENALTY_PER_TABLE := 0.1  # -10% per extra table
const OVERWORK_DIFFICULTY_PER_TABLE := 1  # +1 difficulty per extra table


# ============================================================================
# EVENT SYSTEM
# ============================================================================

# Default event weights
const DEFAULT_EVENT_WEIGHTS := [
	{"id": "request_refill", "weight": 6},
	{"id": "flirt_minor", "weight": 4},
	{"id": "spill_drink", "weight": 2},
	{"id": "rowdy_noise", "weight": 3},
]

# Group-specific event weights
const GROUP_EVENT_WEIGHTS := {
	"Dwarven miners": [
		{"id": "request_refill", "weight": 5},
		{"id": "flirt_minor", "weight": 2},
		{"id": "spill_drink", "weight": 3},
		{"id": "rowdy_noise", "weight": 5},
	],
	"Noble couple": [
		{"id": "request_refill", "weight": 4},
		{"id": "flirt_minor", "weight": 6},
		{"id": "spill_drink", "weight": 1},
		{"id": "rowdy_noise", "weight": 1},
	],
	"Mercenary band": [
		{"id": "request_refill", "weight": 4},
		{"id": "flirt_minor", "weight": 3},
		{"id": "spill_drink", "weight": 2},
		{"id": "rowdy_noise", "weight": 3},
	],
}

# Event difficulty values
const EVENT_DIFFICULTY_REQUEST_REFILL := 2
const EVENT_DIFFICULTY_FLIRT_MINOR := 3
const EVENT_DIFFICULTY_SPILL_DRINK := 4


# ============================================================================
# LIQUOR & PRICING
# ============================================================================

# Liquor prices (base price per unit)
const LIQUOR_PRICES := {
	"cheap ale": 1,
	"cheap wine": 3,
	"strong ale": 5,
	"mead": 7,
	"good wine": 10,
}

# Social status to liquor preference mapping
const SOCIAL_STATUS_LIQUOR := {
	"poor": "cheap ale",
	"merchant": "cheap wine",
	"noble": "mead",
	"adventurer": "strong ale",
	"priestly": "good wine",
}

# Starting stock (in pints)
const STARTING_STOCK := {
	"cheap_ale": 90,      # Most common, higher stock
	"cheap_wine": 50,
	"strong_ale": 40,
	"mead": 15,           # Noble preference, less common
	"good_wine": 12,      # Priestly preference, rarest
}


# ============================================================================
# SOCIAL STATUS & CONSUMPTION
# ============================================================================

# Base drain rates by social status (pints per person per hour)
const SOCIAL_STATUS_BASE_DRAIN := {
	"poor": 0.8,
	"merchant": 1.0,
	"noble": 1.5,
	"adventurer": 1.3,
	"priestly": 0.9,
}

# Group size modifier for resource drain (applied when group_size > 2)
const GROUP_SIZE_DRAIN_MODIFIER := 0.3  # size_modifier = 1.0 + (group_size - 2) * GROUP_SIZE_DRAIN_MODIFIER

# Social status weights for randomization
const SOCIAL_STATUS_WEIGHTS := {
	"poor": 3,
	"merchant": 4,
	"noble": 2,
	"adventurer": 3,
	"priestly": 1,
}


# ============================================================================
# RACE COMPATIBILITY & ROWDINESS
# ============================================================================

# Race compatibility modifiers: [wench_race][client_race] = modifier
const RACE_COMPATIBILITY := {
	"human": {
		"dwarf": 1,
		"human": 0,
		"elf": 0,
		"orc": -1,
		"tiefling": 0,
	},
	"elf": {
		"dwarf": 0,
		"human": 0,
		"elf": 2,
		"orc": -2,
		"tiefling": 0,
	},
	"tiefling": {
		"dwarf": 0,
		"human": -1,
		"elf": 0,
		"orc": 0,
		"tiefling": 1,
	},
	"dwarf": {
		"dwarf": 1,
		"human": 0,
		"elf": -1,
		"orc": 0,
		"tiefling": 0,
	},
	"orc": {
		"dwarf": 0,
		"human": 0,
		"elf": -2,
		"orc": 1,
		"tiefling": 0,
	},
}

# Race rowdiness modifiers (per hour increase rate)
const RACE_ROWDINESS_MODIFIER := {
	"orc": 0.4,      # Highest
	"dwarf": 0.3,    # Second highest
	"tiefling": 0.2,
	"human": 0.15,
	"elf": 0.1,      # Most calm
}

# Available races and social statuses for randomization
const AVAILABLE_RACES := ["human", "dwarf", "elf", "orc", "tiefling"]
const AVAILABLE_SOCIAL_STATUSES := ["poor", "merchant", "noble", "adventurer", "priestly"]


# ============================================================================
# GROUP GENERATION
# ============================================================================

# Group size distribution weights (cumulative probabilities)
const GROUP_SIZE_DISTRIBUTION := {
	1: 0.2,   # 20% chance
	2: 0.5,   # 30% chance (0.5 - 0.2)
	3: 0.75,  # 25% chance (0.75 - 0.5)
	4: 0.9,   # 15% chance (0.9 - 0.75)
	5: 0.97,  # 7% chance (0.97 - 0.9)
	6: 1.0,   # 3% chance (1.0 - 0.97)
}

# Group size description thresholds
const GROUP_SIZE_SINGLE := 1
const GROUP_SIZE_SMALL := 2
const GROUP_SIZE_MEDIUM := 4


# ============================================================================
# TABLE SETTINGS
# ============================================================================

const STARTING_PATIENCE := 5  # Initial patience value for tables

# Client entry chance
const CLIENT_ENTRY_CHANCE := 0.5  # 50% chance for each client to enter the tavern

