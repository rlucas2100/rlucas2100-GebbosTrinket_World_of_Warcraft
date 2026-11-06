local ADDON, ns = ...

ns.ITEM_ID    = 270164      -- Gebbo's Bottomless Bag
ns.PASSIVE_ID = 1292291     -- the trinket's equip effect
ns.MEDIA      = "Interface\\AddOns\\" .. ADDON .. "\\media\\"

-- Community values (Inven, 16 Aug 2026) were read at item level 334, before Blizzard's
-- 14 Aug 2026 hotfix cut secondary stat effects by 29%. They are only used as a fallback;
-- whenever the game lets the addon read the real buff, the real number wins and the
-- estimate self-calibrates for your item level.
ns.BASE_ILVL   = 334
ns.NERF        = 0.71
ns.ILVL_GROWTH = 1.0065    -- rough per-item-level growth, replaced by calibration

-- Spell IDs near the confirmed Salmon ID are scanned at login and matched by name,
-- so the other five pulls are found automatically on English clients.
ns.SCAN_RANGES = { { 1307940, 1308090 }, { 1292270, 1292330 } }

ns.SOUNDS = {
	jackpot = ns.MEDIA .. "jackpot.ogg",
	shimmer = ns.MEDIA .. "shimmer.ogg",
	womp    = ns.MEDIA .. "womp.ogg",
}

ns.STAT_ORDER = { "crit", "haste", "mastery", "vers" }
ns.STAT = {
	crit    = { label = "Crit",    long = "Critical Strike", r = 1.00, g = 0.40, b = 0.32, cr = CR_CRIT_SPELL or 11 },
	haste   = { label = "Haste",   long = "Haste",           r = 1.00, g = 0.81, b = 0.27, cr = CR_HASTE_SPELL or 20 },
	mastery = { label = "Mastery", long = "Mastery",         r = 0.74, g = 0.52, b = 1.00, cr = CR_MASTERY or 26 },
	vers    = { label = "Vers",    long = "Versatility",     r = 0.36, g = 0.95, b = 0.70, cr = CR_VERSATILITY_DAMAGE_DONE or 29 },
}

local ALL = { "crit", "haste", "mastery", "vers" }

-- mood drives glow, sound and flourish:  jackpot | good | mixed | bad
ns.ARTIFACTS = {
	salmon = {
		order = 1, name = "50-Lb Midnight Salmon", match = { "midnight salmon" }, ids = { 1308013 },
		stats = ALL, amount = 222, duration = 12, calibrate = true,
		mood = "jackpot", sound = "jackpot", tag = "Jackpot! Every secondary stat up",
		r = 1.00, g = 0.80, b = 0.30,
	},
	scroll = {
		order = 2, name = "Tattered Tortollan Scroll", match = { "tortollan scroll" },
		stats = { "mastery" }, amount = 710, decayPerSec = 50, duration = 12,
		mood = "good", sound = "shimmer", tag = "Big Mastery, fading every second",
		r = 0.74, g = 0.52, b = 1.00,
	},
	totem = {
		order = 3, name = "Brittle Torga Totem", match = { "torga totem" },
		stats = { "vers" }, amount = 710, decayPerCast = 51, softCap = 30,
		mood = "good", sound = "shimmer", tag = "Versatility that crumbles as you cast",
		r = 0.36, g = 0.95, b = 0.70,
	},
	gralstone = {
		order = 4, name = "Slick and Slimy Gralstone", match = { "gralstone" },
		stats = { "haste" }, amount = 350, duration = 12, calibrate = true,
		mood = "good", sound = "shimmer", tag = "Haste and movement speed",
		r = 1.00, g = 0.81, b = 0.27,
	},
	seashell = {
		order = 5, name = "Seriously Sharp Seashell", match = { "sharp seashell" },
		stats = { "crit" }, amount = 59, growPerSec = 59, duration = 12, stackScaled = true,
		mood = "mixed", sound = "shimmer", tag = "Crit climbs each second, but it cuts you",
		r = 1.00, g = 0.40, b = 0.32,
	},
	voidfin = {
		order = 6, name = "Rotting Voidfin", match = { "voidfin" },
		stats = ALL, amount = -44, duration = 12, calibrate = true,
		mood = "bad", sound = "womp", tag = "Ew. Every secondary stat down",
		r = 0.55, g = 0.85, b = 0.30,
	},
}

ns.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- top-to-bottom order when several pulls are up at once (same order in raids/M+)
ns.STACK_ORDER = { "salmon", "scroll", "totem", "gralstone", "seashell", "voidfin" }

-- Alert look per pull, in the Juggernaut Mode / Sunwell Infusion style.
-- bgA -> bgB is the panel's left-to-right gradient. Engine priority decides which
-- panel sits on top if two pulls are up at once inside M+ or raids.
ns.THEME = {
	salmon    = { title = "JACKPOT!",      bgA = { 0.40, 0.04, 0.70 }, bgB = { 1.00, 0.45, 0.00 }, rainbow = true, cameo = "badge",     prio = 6 },
	scroll    = { title = "MASTERY SURGE", bgA = { 0.12, 0.03, 0.38 }, bgB = { 0.52, 0.20, 0.92 }, cameo = "badge",     prio = 5 },
	totem     = { title = "VERSATILITY",   bgA = { 0.01, 0.20, 0.20 }, bgB = { 0.08, 0.66, 0.48 }, cameo = "badge",     prio = 4 },
	gralstone = { title = "HASTE RUSH",    bgA = { 0.36, 0.16, 0.00 }, bgB = { 0.92, 0.66, 0.06 }, cameo = "badge",     prio = 3 },
	seashell  = { title = "CRIT CLIMB",    bgA = { 0.36, 0.02, 0.04 }, bgB = { 0.92, 0.32, 0.18 }, cameo = "badge",     prio = 2 },
	voidfin   = { title = "EW. VOIDFIN",   bgA = { 0.06, 0.02, 0.12 }, bgB = { 0.20, 0.38, 0.05 }, danger = true, cameo = "voidfin", prio = 1 },
	idle      = { title = "GEBBO'S BAG",   bgA = { 0.02, 0.09, 0.14 }, bgB = { 0.06, 0.28, 0.33 }, cameo = "badge" },
}
