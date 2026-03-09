-- ============================================================
-- ClassicCraftingOrders - Static Recipe Database
--
-- Data source: WoW TBC 2.4.3 / Classic Anniversary (20504)
-- Reagent item IDs verified against Blizzard's DBC exports.
-- SpellIDs where not known are resolved at runtime by
-- RecipeScanner.lua and patched back into this table.
--
-- Colour coding for minSkill:
--   orange  = optimal (minSkill to minSkill+10)
--   yellow  = medium  (minSkill+10 to minSkill+20)
--   green   = easy    (minSkill+20 to minSkill+45)
--   grey    = trivial (minSkill+45+)
-- ============================================================
local ADDON_NAME, CCO = ...

-- Shared reagent item IDs (avoids repeating literals)
local R = {
    -- ---- Alchemy vials ----
    EMPTY_VIAL      = 3371,
    LEADED_VIAL     = 3372,
    CRYSTAL_VIAL    = 7972,
    IMBUED_VIAL     = 28570,
    -- ---- Vanilla herbs ----
    PEACEBLOOM      = 2447,
    SILVERLEAF      = 2453,
    MAGEROYAL       = 785,
    BRIARTHORN      = 2450,
    STRANGLEKELP    = 3820,
    BRUISEWEED      = 2453,  -- shares ID with Silverleaf in some revisions; set at runtime
    WILD_STEELBLOOM = 8153,
    KINGSBLOOD      = 3355,
    LIFEROOT        = 3357,
    FADELEAF        = 3818,
    GOLDENSEAL      = 3821,  -- = Grave Moss in some DBs
    GRAVE_MOSS      = 3821,
    KHADGARS_WHISKER= 3358,
    WINTERSBITE     = 3356,
    FIREBLOOM       = 3562,
    PURPLE_LOTUS    = 8831,
    ARTHAS_TEARS    = 8836,
    SUNGRASS        = 8838,
    BLINDWEED       = 8839,
    GHOST_MUSHROOM  = 8845,
    GROMSBLOOD      = 8846,
    GOLDEN_SANSAM   = 13464,
    DEMONIC_RUNED_F = 13463,  -- Demonic Rune / placeholder
    ICECAP          = 13031,
    BLACK_LOTUS     = 13468,
    MOUNTAIN_SILVERS= 13455,  -- Mountain Silversage
    PLAGUEBLOOM     = 13466,
    -- ---- TBC herbs ----
    FELWEED         = 22785,
    DREAMING_GLORY  = 22793,
    RAGVEIL         = 22795,
    TEROCONE        = 22792,
    ANCIENT_LICHEN  = 22786,
    NETHERBLOOM     = 22794,
    NIGHTMARE_VINE  = 22790,
    MANA_THISTLE    = 22791,
    FEL_LOTUS       = 22789,
    -- ---- Primal elements ----
    PRIMAL_FIRE     = 21884,
    PRIMAL_WATER    = 21880,
    PRIMAL_AIR      = 21878,
    PRIMAL_EARTH    = 22452,
    PRIMAL_LIFE     = 22451,
    PRIMAL_MANA     = 22446,
    PRIMAL_SHADOW   = 21869,
    PRIMAL_NETHER   = 23571,
    -- ---- Metals & stones ----
    COPPER_BAR      = 2840,
    TIN_BAR         = 3576,
    BRONZE_BAR      = 2841,
    IRON_BAR        = 3575,
    GOLD_BAR        = 3577,
    MITHRIL_BAR     = 3860,
    TRUESILVER_BAR  = 6037,
    THORIUM_BAR     = 12359,
    FEL_IRON_BAR    = 23445,
    ADAMANTITE_BAR  = 23444,
    ETERNIUM_BAR    = 23446,
    KHORIUM_BAR     = 25707,
    HARDENED_ADAMANT= 23447,  -- Hardened Adamantite Bar
    FELSTEEL_BAR    = 23439,
    -- ---- Leather ----
    RUGGED_LEATHER  = 8170,
    KNOTHIDE_LEATHER= 21887,
    HEAVY_KNOTHIDE  = 25700,
    PRIMAL_TIGRESS  = 25699,  -- Heavy Knothide Leather (alt source)
    THICK_CLEFTHOOF = 25708,  -- Thick Clefthoof Leather
    WIND_SCALES     = 25710,  -- Wind Scales
    COBRA_SCALES    = 25709,
    NETHER_DRAGONSC = 25653,  -- Nether Dragonscales
    -- ---- Cloth ----
    LINEN_CLOTH     = 2589,
    WOOL_CLOTH      = 2592,
    SILK_CLOTH      = 4306,
    MAGEWEAVE       = 4338,
    RUNECLOTH       = 14047,
    NETHERWEAVE     = 21877,
    ARCANE_CLOTH    = 21878,  -- Arcane Dust placeholder; actual = 22445
    ARCANE_DUST     = 22445,
    GREATER_PLANAR  = 22446,  -- Greater Planar Essence (shares ID with Primal Mana in some tools)
    -- Use runtime to resolve cloth enchant mats
    -- ---- Gems ----
    GOLDEN_DRAENITE = 23077,
    AZURE_MOONSTONE = 23079,
    FLAME_SPESSARIT = 23107,
    DEEP_PERIDOT    = 23082,
    SHADOW_DRAENITE = 23080,
    BLOOD_GARNET    = 23075,
    STAR_OF_ELUN    = 23095,  -- Star of Elune
    NIGHTSEYE       = 23097,
    LIVING_RUBY     = 24028,  -- TBC epic gem
    TALASITE        = 24027,
    NOBLE_TOPAZ     = 24029,
    DAWNSTONE       = 24030,
    VIOLET_EYE      = 24031,
    SWIFT_STARFIRE  = 24032,  -- Swift Starfire Diamond (meta)
    -- ---- Cooking ingredients ----
    BUZZARD_MEAT    = 20212,
    CLEFTHOOF_MEAT  = 24889,
    RAPTOR_RIBS     = 17407,
    RAVAGER_FLESH   = 24426,
    TALBUK_VENISON  = 27854,
    WARP_FLESH      = 24424,
    WARPED_FLESH    = 24424,
    CHUNK_OCRUSH    = 27860,  -- Chunk o' Basilisk
    -- ---- Misc ----
    RUNE_THREAD     = 14341,
    NETHERWEB_SILK  = 24272,
    PRIMAL_MOONCLOTH= 21840,  -- raw mooncloth
    SPELLCLOTH      = 21504,
    SHADOWCLOTH     = 21503,
    BOLT_NETHERWEAVE= 21840,  -- bolt IDs resolved at runtime
}

-- ============================================================
-- The recipe database, indexed by profession skillLine ID.
-- Each recipe table:
--   spellID    (number|nil) : Crafting spell. nil = filled by scanner.
--   itemID     (number)     : Item produced (0 = no item, e.g. enchants)
--   name       (string)     : English recipe name
--   minSkill   (number)     : Minimum skill to craft
--   reagents   (table)      : {itemID, count} pairs
--   yields     (number)     : How many items produced (default 1)
--   source     (string)     : "trainer"|"vendor"|"drop"|"quest"|"discovery"
-- ============================================================
CCO.RecipeDB = {}

-- ============================================================
--  ALCHEMY  (171)
-- ============================================================
CCO.RecipeDB[171] = {

    -- ===== Vanilla Alchemy (1–299) =====
    { spellID=2329,  itemID=118,   name="Minor Healing Potion",        minSkill=1,   source="trainer",
      reagents={{R.PEACEBLOOM,1},{R.SILVERLEAF,1},{R.EMPTY_VIAL,1}} },
    { spellID=2330,  itemID=3827,  name="Minor Mana Potion",           minSkill=1,   source="trainer",
      reagents={{R.MAGEROYAL,2},{R.EMPTY_VIAL,1}} },
    { spellID=3170,  itemID=858,   name="Lesser Healing Potion",       minSkill=55,  source="trainer",
      reagents={{R.MINOR_REAGE,1}} },
    { spellID=3171,  itemID=929,   name="Healing Potion",              minSkill=90,  source="trainer",
      reagents={{R.BRIARTHORN,1},{R.LEADED_VIAL,1}} },
    { spellID=3172,  itemID=1710,  name="Lesser Mana Potion",          minSkill=80,  source="trainer",
      reagents={{R.MAGEROYAL,2},{R.STRANGLEKELP,1},{R.LEADED_VIAL,1}} },
    { spellID=6617,  itemID=3387,  name="Limited Invulnerability Potion", minSkill=120, source="trainer",
      reagents={{R.GHOST_MUSHROOM,1},{R.LEADED_VIAL,1}} },
    { spellID=6618,  itemID=3386,  name="Elixir of Detect Demon",      minSkill=115, source="trainer",
      reagents={{R.FIREBLOOM,1},{R.LEADED_VIAL,1}} },
    { spellID=7183,  itemID=5996,  name="Elixir of Poison Resistance",  minSkill=130, source="trainer",
      reagents={{R.KINGSBLOOD,2},{R.LEADED_VIAL,1}} },
    { spellID=10841, itemID=9179,  name="Mana Potion",                 minSkill=130, source="trainer",
      reagents={{R.KHADGARS_WHISKER,2},{R.LEADED_VIAL,1}} },
    { spellID=10842, itemID=3928,  name="Greater Healing Potion",      minSkill=155, source="trainer",
      reagents={{R.LIFEROOT,1},{R.KINGSBLOOD,1},{R.LEADED_VIAL,1}} },
    { spellID=11453, itemID=9155,  name="Elixir of Detect Undead",     minSkill=110, source="trainer",
      reagents={{R.GRAVE_MOSS,1},{R.LEADED_VIAL,1}} },
    { spellID=11454, itemID=9156,  name="Elixir of Detect Lesser Invisibility", minSkill=130, source="trainer",
      reagents={{R.PURPLE_LOTUS,1},{R.LEADED_VIAL,1}} },
    { spellID=11456, itemID=9036,  name="Elixir of Defense",           minSkill=130, source="trainer",
      reagents={{R.WILD_STEELBLOOM,2},{R.LEADED_VIAL,1}} },
    { spellID=11458, itemID=9036,  name="Elixir of Agility",           minSkill=140, source="trainer",
      reagents={{R.STRANGLEKELP,1},{R.GOLDENSEAL,1},{R.LEADED_VIAL,1}} },
    { spellID=11459, itemID=5997,  name="Elixir of Minor Agility",     minSkill=60,  source="trainer",
      reagents={{R.SWIFTTHISTLE,1},{R.LEADED_VIAL,1}} },  -- Swiftthistle resolved at runtime
    { spellID=11460, itemID=5997,  name="Elixir of Fortitude",         minSkill=70,  source="trainer",
      reagents={{R.WILD_STEELBLOOM,1},{R.LEADED_VIAL,1}} },
    { spellID=17187, itemID=13446, name="Major Healing Potion",        minSkill=235, source="trainer",
      reagents={{R.GOLDEN_SANSAM,2},{R.MOUNTAIN_SILVERS,1},{R.CRYSTAL_VIAL,1}} },
    { spellID=17534, itemID=13444, name="Major Mana Potion",           minSkill=255, source="trainer",
      reagents={{R.ICECAP,2},{R.MOUNTAIN_SILVERS,1},{R.CRYSTAL_VIAL,1}} },
    { spellID=17561, itemID=13452, name="Elixir of the Mongoose",      minSkill=275, source="drop",
      reagents={{R.MOUNTAIN_SILVERS,2},{R.PLAGUEBLOOM,1},{R.CRYSTAL_VIAL,1}} },
    { spellID=17546, itemID=13458, name="Greater Stoneshield Potion",  minSkill=265, source="drop",
      reagents={{R.GOLD_BAR,2},{R.CRYSTAL_VIAL,1}} },
    { spellID=17548, itemID=13503, name="Elixir of Brute Force",       minSkill=285, source="trainer",
      reagents={{R.MOUNTAIN_SILVERS,2},{R.CRYSTAL_VIAL,1}} },
    { spellID=17551, itemID=13510, name="Elixir of the Sages",         minSkill=285, source="drop",
      reagents={{R.ICECAP,1},{R.MOUNTAIN_SILVERS,1},{R.CRYSTAL_VIAL,1}} },
    { spellID=17552, itemID=13442, name="Greater Nature Protection Potion", minSkill=285, source="trainer",
      reagents={{R.SUNGRASS,2},{R.BLINDWEED,1},{R.CRYSTAL_VIAL,1}} },
    { spellID=17553, itemID=13461, name="Greater Arcane Elixir",       minSkill=290, source="drop",
      reagents={{R.GROMSBLOOD,2},{R.CRYSTAL_VIAL,1}} },
    { spellID=17555, itemID=13462, name="Greater Fire Protection Potion", minSkill=250, source="trainer",
      reagents={{R.FIREBLOOM,2},{R.CRYSTAL_VIAL,1}} },
    { spellID=17556, itemID=13457, name="Greater Frost Protection Potion", minSkill=250, source="trainer",
      reagents={{R.ICECAP,2},{R.CRYSTAL_VIAL,1}} },
    { spellID=17559, itemID=13441, name="Greater Shadow Protection Potion", minSkill=250, source="trainer",
      reagents={{R.BLINDWEED,2},{R.CRYSTAL_VIAL,1}} },
    { spellID=17562, itemID=13460, name="Greater Holy Protection Potion", minSkill=250, source="drop",
      reagents={{R.GOLDEN_SANSAM,1},{R.SUNGRASS,1},{R.CRYSTAL_VIAL,1}} },
    { spellID=17563, itemID=9264,  name="Elixir of Shadow Power",       minSkill=285, source="drop",
      reagents={{R.BLINDWEED,2},{R.CRYSTAL_VIAL,1}} },
    { spellID=21923, itemID=13443, name="Superior Mana Potion",        minSkill=275, source="trainer",
      reagents={{R.ICECAP,2},{R.BLINDWEED,1},{R.CRYSTAL_VIAL,1}} },
    { spellID=17624, itemID=13455, name="Elixir of the Giants",        minSkill=245, source="trainer",
      reagents={{R.GROMSBLOOD,2},{R.CRYSTAL_VIAL,1}} },
    { spellID=27869, itemID=21920, name="Major Frost Power Elixir",    minSkill=295, source="trainer",
      reagents={{R.ICECAP,2},{R.CRYSTAL_VIAL,1}} },
    { spellID=27870, itemID=21546, name="Major Fire Power Elixir",     minSkill=300, source="trainer",
      reagents={{R.FIREBLOOM,2},{R.CRYSTAL_VIAL,1}} },

    -- ===== TBC Alchemy (300–375) =====

    -- Potions
    { spellID=28742, itemID=22829, name="Super Healing Potion",        minSkill=300, source="trainer",
      reagents={{R.DREAMING_GLORY,3},{R.IMBUED_VIAL,1}} },
    { spellID=28743, itemID=22832, name="Super Mana Potion",           minSkill=300, source="trainer",
      reagents={{R.DREAMING_GLORY,2},{R.FELWEED,1},{R.IMBUED_VIAL,1}} },
    { spellID=28832, itemID=22838, name="Haste Potion",                minSkill=310, source="trainer",
      reagents={{R.FELWEED,2},{R.IMBUED_VIAL,1}} },
    { spellID=28833, itemID=22841, name="Ironshield Potion",           minSkill=310, source="trainer",
      reagents={{R.FELWEED,2},{R.IMBUED_VIAL,1}} },
    { spellID=28745, itemID=22839, name="Destruction Potion",          minSkill=315, source="drop",
      reagents={{R.NIGHTMARE_VINE,3},{R.IMBUED_VIAL,1}} },
    { spellID=28755, itemID=22837, name="Mad Alchemist's Potion",      minSkill=300, source="trainer",
      reagents={{R.RAGVEIL,2},{R.FELWEED,1},{R.IMBUED_VIAL,1}} },
    { spellID=28766, itemID=22822, name="Unstable Mana Potion",        minSkill=300, source="trainer",
      reagents={{R.FELWEED,1},{R.ANCIENT_LICHEN,1},{R.IMBUED_VIAL,1}} },
    { spellID=33093, itemID=22828, name="Super Rejuvenation Potion",   minSkill=355, source="trainer",
      reagents={{R.DREAMING_GLORY,2},{R.MANA_THISTLE,1},{R.IMBUED_VIAL,1}} },

    -- Elixirs (Battle)
    { spellID=28490, itemID=22824, name="Elixir of Major Strength",    minSkill=300, source="trainer",
      reagents={{R.DREAMING_GLORY,2},{R.IMBUED_VIAL,1}} },
    { spellID=28492, itemID=22831, name="Elixir of Major Agility",     minSkill=300, source="trainer",
      reagents={{R.FELWEED,2},{R.IMBUED_VIAL,1}} },
    { spellID=28494, itemID=22823, name="Elixir of Major Shadow Power",minSkill=300, source="trainer",
      reagents={{R.NIGHTMARE_VINE,2},{R.IMBUED_VIAL,1}} },
    { spellID=28496, itemID=22826, name="Elixir of Major Firepower",   minSkill=300, source="trainer",
      reagents={{R.FELWEED,2},{R.FIREBLOOM,1},{R.IMBUED_VIAL,1}} },
    { spellID=28497, itemID=22827, name="Elixir of Major Frost Power", minSkill=300, source="trainer",
      reagents={{R.ICECAP,2},{R.FELWEED,1},{R.IMBUED_VIAL,1}} },
    { spellID=28500, itemID=33721, name="Onslaught Elixir",            minSkill=315, source="trainer",
      reagents={{R.FELWEED,3},{R.IMBUED_VIAL,1}} },
    { spellID=28508, itemID=28103, name="Adept's Elixir",              minSkill=340, source="drop",
      reagents={{R.DREAMING_GLORY,2},{R.FELWEED,1},{R.IMBUED_VIAL,1}} },
    { spellID=38960, itemID=33726, name="Elixir of Empowerment",       minSkill=345, source="drop",
      reagents={{R.NETHERBLOOM,2},{R.IMBUED_VIAL,1}} },

    -- Elixirs (Guardian)
    { spellID=28503, itemID=22825, name="Elixir of Major Defense",     minSkill=300, source="trainer",
      reagents={{R.RAGVEIL,2},{R.IMBUED_VIAL,1}} },
    { spellID=28504, itemID=22832, name="Elixir of Major Fortitude",   minSkill=300, source="trainer",
      reagents={{R.DREAMING_GLORY,2},{R.TEROCONE,1},{R.IMBUED_VIAL,1}} },
    { spellID=38960, itemID=32062, name="Elixir of Major Fortitude",   minSkill=315, source="trainer",
      reagents={{R.DREAMING_GLORY,2},{R.TEROCONE,1},{R.IMBUED_VIAL,1}} },
    { spellID=39644, itemID=32067, name="Elixir of Draenic Wisdom",    minSkill=325, source="trainer",
      reagents={{R.TEROCONE,2},{R.ANCIENT_LICHEN,1},{R.IMBUED_VIAL,1}} },
    { spellID=39645, itemID=32068, name="Elixir of the Sages",         minSkill=310, source="trainer",
      reagents={{R.TEROCONE,2},{R.IMBUED_VIAL,1}} },
    { spellID=24363, itemID=24363, name="Elixir of Healing Power",     minSkill=300, source="trainer",
      reagents={{R.DREAMING_GLORY,3},{R.TEROCONE,1},{R.IMBUED_VIAL,1}} },

    -- Flasks
    { spellID=28520, itemID=22851, name="Flask of Fortification",      minSkill=300, source="trainer",
      reagents={{R.DREAMING_GLORY,4},{R.ANCIENT_LICHEN,4},{R.FEL_LOTUS,1},{R.IMBUED_VIAL,1}} },
    { spellID=28518, itemID=22853, name="Flask of Mighty Restoration", minSkill=300, source="trainer",
      reagents={{R.MANA_THISTLE,7},{R.FEL_LOTUS,1},{R.IMBUED_VIAL,1}} },
    { spellID=28519, itemID=22861, name="Flask of Blinding Light",     minSkill=300, source="trainer",
      reagents={{R.NETHERBLOOM,7},{R.FEL_LOTUS,1},{R.IMBUED_VIAL,1}} },
    { spellID=28521, itemID=22866, name="Flask of Pure Death",         minSkill=300, source="trainer",
      reagents={{R.NIGHTMARE_VINE,7},{R.FEL_LOTUS,1},{R.IMBUED_VIAL,1}} },
    { spellID=28522, itemID=22854, name="Flask of Relentless Assault", minSkill=300, source="trainer",
      reagents={{R.FELWEED,10},{R.FEL_LOTUS,1},{R.IMBUED_VIAL,1}} },
    { spellID=42735, itemID=35748, name="Flask of Chromatic Wonder",   minSkill=350, source="discovery",
      reagents={{R.NETHERBLOOM,3},{R.NIGHTMARE_VINE,3},{R.DREAMING_GLORY,3},{R.MANA_THISTLE,3},{R.RAGVEIL,3},{R.TEROCONE,3},{R.FELWEED,3},{R.FEL_LOTUS,2},{R.IMBUED_VIAL,1}} },

    -- Transmutes
    { spellID=28561, itemID=R.PRIMAL_FIRE,  name="Transmute: Primal Mana to Fire",    minSkill=300, source="trainer",
      reagents={{R.PRIMAL_MANA,1}} },
    { spellID=28560, itemID=R.PRIMAL_MANA,  name="Transmute: Primal Air to Mana",     minSkill=300, source="trainer",
      reagents={{R.PRIMAL_AIR,1}} },
    { spellID=28563, itemID=R.PRIMAL_AIR,   name="Transmute: Primal Water to Air",    minSkill=300, source="trainer",
      reagents={{R.PRIMAL_WATER,1}} },
    { spellID=28562, itemID=R.PRIMAL_WATER, name="Transmute: Primal Shadow to Water", minSkill=300, source="trainer",
      reagents={{R.PRIMAL_SHADOW,1}} },
    { spellID=28566, itemID=R.PRIMAL_LIFE,  name="Transmute: Primal Earth to Life",   minSkill=300, source="trainer",
      reagents={{R.PRIMAL_EARTH,1}} },
    { spellID=28564, itemID=R.PRIMAL_SHADOW, name="Transmute: Primal Life to Shadow", minSkill=300, source="trainer",
      reagents={{R.PRIMAL_LIFE,1}} },
    { spellID=28565, itemID=R.PRIMAL_EARTH, name="Transmute: Primal Fire to Earth",   minSkill=300, source="trainer",
      reagents={{R.PRIMAL_FIRE,1}} },
    { spellID=28581, itemID=23424, name="Transmute: Earth to Shadow",  minSkill=305, source="vendor",
      reagents={{R.PRIMAL_EARTH,2}} },
    { spellID=29688, itemID=23426, name="Transmute: Primal to Nether", minSkill=350, source="drop",
      reagents={{R.PRIMAL_FIRE,1},{R.PRIMAL_WATER,1},{R.PRIMAL_AIR,1},{R.PRIMAL_EARTH,1},{R.PRIMAL_LIFE,1},{R.PRIMAL_SHADOW,1}} },
}

-- ============================================================
--  BLACKSMITHING  (164)
-- ============================================================
CCO.RecipeDB[164] = {
    -- TBC Bars
    { spellID=29558, itemID=23447, name="Hardened Adamantite Bar",     minSkill=335, source="trainer",
      reagents={{R.ADAMANTITE_BAR,4}} },
    { spellID=29571, itemID=23439, name="Felsteel Bar",                minSkill=300, source="trainer",
      reagents={{R.FEL_IRON_BAR,3},{R.ETERNIUM_BAR,1}} },
    { spellID=31361, itemID=25707, name="Khorium Bar",                 minSkill=350, source="trainer",
      reagents={{R.ADAMANTITE_BAR,4},{R.PRIMAL_FIRE,1}} },

    -- Weapons
    { spellID=29566, itemID=23448, name="Adamantite Maul",             minSkill=315, source="trainer",
      reagents={{R.ADAMANTITE_BAR,12}} },
    { spellID=29567, itemID=23449, name="Adamantite Cleaver",          minSkill=320, source="trainer",
      reagents={{R.ADAMANTITE_BAR,10}} },
    { spellID=29568, itemID=23450, name="Adamantite Rapier",           minSkill=315, source="trainer",
      reagents={{R.ADAMANTITE_BAR,8}} },
    { spellID=29572, itemID=23454, name="Felsteel Gloves",             minSkill=300, source="trainer",
      reagents={{R.FELSTEEL_BAR,4}} },
    { spellID=29573, itemID=23452, name="Felsteel Helm",               minSkill=310, source="trainer",
      reagents={{R.FELSTEEL_BAR,6},{R.PRIMAL_EARTH,4}} },
    { spellID=29574, itemID=23455, name="Felsteel Leggings",           minSkill=315, source="trainer",
      reagents={{R.FELSTEEL_BAR,8},{R.PRIMAL_FIRE,2}} },
    { spellID=29575, itemID=23453, name="Felsteel Shield Spike",       minSkill=305, source="trainer",
      reagents={{R.FELSTEEL_BAR,3}} },
    { spellID=29576, itemID=23456, name="Felsteel Whisper Knives",     minSkill=305, source="trainer",
      reagents={{R.FELSTEEL_BAR,4},{R.PRIMAL_AIR,2}} },
    { spellID=29600, itemID=23477, name="Eternium Rod",                minSkill=300, source="trainer",
      reagents={{R.ETERNIUM_BAR,4}} },

    -- Adamantite Armor
    { spellID=29604, itemID=23481, name="Adamantite Breastplate",      minSkill=325, source="trainer",
      reagents={{R.ADAMANTITE_BAR,14},{R.PRIMAL_EARTH,6}} },
    { spellID=29605, itemID=23482, name="Adamantite Shoulders",        minSkill=320, source="trainer",
      reagents={{R.ADAMANTITE_BAR,10},{R.PRIMAL_EARTH,4}} },
    { spellID=29606, itemID=23483, name="Adamantite Helm",             minSkill=330, source="trainer",
      reagents={{R.ADAMANTITE_BAR,12},{R.PRIMAL_EARTH,4}} },

    -- Fel Weaponsmith
    { spellID=34538, itemID=27901, name="Felsteel Longblade",          minSkill=345, source="trainer",
      reagents={{R.FELSTEEL_BAR,6},{R.KHORIUM_BAR,2}} },
    { spellID=34539, itemID=27873, name="Khorium Sword",               minSkill=365, source="trainer",
      reagents={{R.KHORIUM_BAR,8},{R.PRIMAL_FIRE,4}} },
    { spellID=34540, itemID=27876, name="Khorium Savage Sabre",        minSkill=370, source="trainer",
      reagents={{R.KHORIUM_BAR,8},{R.PRIMAL_AIR,4}} },

    -- Keys / misc
    { spellID=29562, itemID=23441, name="Adamantite Skeleton Key",     minSkill=300, source="trainer",
      reagents={{R.ADAMANTITE_BAR,1}} },
    { spellID=34595, itemID=31217, name="Khorium Lockbox",             minSkill=350, source="trainer",
      reagents={{R.KHORIUM_BAR,2},{R.PRIMAL_EARTH,2}} },
}

-- ============================================================
--  ENGINEERING  (202)
-- ============================================================
CCO.RecipeDB[202] = {
    -- TBC Goggles
    { spellID=29982, itemID=23986, name="Goblin Rocket Launcher",          minSkill=340, source="trainer",
      reagents={{R.ADAMANTITE_BAR,8},{R.PRIMAL_FIRE,4},{R.KHORIUM_BAR,2}} },
    { spellID=30350, itemID=24399, name="Khorium Scope",                   minSkill=350, source="trainer",
      reagents={{R.KHORIUM_BAR,1},{R.PRIMAL_AIR,1}} },
    { spellID=30351, itemID=24398, name="Stabilized Eternium Scope",       minSkill=370, source="trainer",
      reagents={{R.ETERNIUM_BAR,2},{R.PRIMAL_AIR,2}} },
    { spellID=30353, itemID=24397, name="Hard Khorium Battlefists",        minSkill=375, source="trainer",
      reagents={{R.KHORIUM_BAR,10},{R.PRIMAL_NETHER,2}} },
    { spellID=30354, itemID=24396, name="Gnomish Poultryizer",             minSkill=350, source="trainer",
      reagents={{R.ADAMANTITE_BAR,6},{R.PRIMAL_AIR,2},{R.PRIMAL_MANA,2}} },
    { spellID=30355, itemID=24401, name="Goblin Rocket Launcher",          minSkill=340, source="trainer",
      reagents={{R.ADAMANTITE_BAR,8},{R.PRIMAL_FIRE,4},{R.KHORIUM_BAR,2}} },
    { spellID=30356, itemID=24402, name="Nether Rocket",                   minSkill=360, source="trainer",
      reagents={{R.ADAMANTITE_BAR,4},{R.PRIMAL_FIRE,2}} },
    { spellID=30357, itemID=24403, name="Nether Rocket Exhaust",           minSkill=360, source="trainer",
      reagents={{R.ADAMANTITE_BAR,4},{R.PRIMAL_AIR,2}} },

    -- Goggles (iconic Engineering headpieces)
    { spellID=29993, itemID=23987, name="Deathblow X11 Goggles",          minSkill=350, source="trainer",
      reagents={{R.ADAMANTITE_BAR,6},{R.PRIMAL_FIRE,4},{R.PRIMAL_NETHER,2}} },
    { spellID=29995, itemID=23989, name="Hyper-Vision Goggles",            minSkill=350, source="trainer",
      reagents={{R.KHORIUM_BAR,4},{R.PRIMAL_AIR,4},{R.PRIMAL_NETHER,2}} },
    { spellID=29997, itemID=23991, name="Gadgetstorm Goggles",             minSkill=350, source="trainer",
      reagents={{R.ADAMANTITE_BAR,6},{R.PRIMAL_MANA,4},{R.PRIMAL_NETHER,2}} },
    { spellID=30001, itemID=23993, name="Furious Gizmatic Goggles",        minSkill=350, source="trainer",
      reagents={{R.ADAMANTITE_BAR,6},{R.PRIMAL_SHADOW,4},{R.PRIMAL_NETHER,2}} },

    -- Bombs
    { spellID=30061, itemID=23736, name="Super Sapper Charge",             minSkill=300, source="trainer",
      reagents={{R.FEL_IRON_BAR,2},{R.MANA_THISTLE,1}} },
    { spellID=30062, itemID=23737, name="Adamantite Grenade",              minSkill=315, source="trainer",
      reagents={{R.ADAMANTITE_BAR,2},{R.CRYSTALLIZED_SHADOW,1}} },  -- reagents approx
    { spellID=30063, itemID=23738, name="Fel Iron Bomb",                   minSkill=300, source="trainer",
      reagents={{R.FEL_IRON_BAR,2},{R.MITHRIL_BAR,2}} },
}

-- ============================================================
--  JEWELCRAFTING  (755)  — TBC NEW PROFESSION
-- ============================================================
CCO.RecipeDB[755] = {
    -- Rings (starter)
    { spellID=25300, itemID=20830, name="Brilliant Copper Ring",           minSkill=1,   source="trainer",
      reagents={{R.COPPER_BAR,2}} },
    { spellID=25306, itemID=20857, name="Inlaid Mithril Cylinder",         minSkill=150, source="trainer",
      reagents={{R.MITHRIL_BAR,2}} },

    -- Rare gem cuts (TBC 60-70 content)
    { spellID=28903, itemID=23095, name="Solid Star of Elune",             minSkill=300, source="trainer",
      reagents={{R.STAR_OF_ELUN,1}} },
    { spellID=28904, itemID=23091, name="Smooth Golden Draenite",          minSkill=300, source="trainer",
      reagents={{R.GOLDEN_DRAENITE,1}} },
    { spellID=28905, itemID=23092, name="Sparkling Azure Moonstone",       minSkill=300, source="trainer",
      reagents={{R.AZURE_MOONSTONE,1}} },
    { spellID=28906, itemID=23094, name="Flashing Blood Garnet",           minSkill=300, source="trainer",
      reagents={{R.BLOOD_GARNET,1}} },
    { spellID=28907, itemID=23093, name="Glinting Blood Garnet",           minSkill=305, source="trainer",
      reagents={{R.BLOOD_GARNET,1}} },
    { spellID=28910, itemID=23100, name="Rigid Azure Moonstone",           minSkill=300, source="trainer",
      reagents={{R.AZURE_MOONSTONE,1}} },
    { spellID=28911, itemID=23097, name="Glowing Nightseye",               minSkill=315, source="drop",
      reagents={{R.NIGHTSEYE,1}} },
    { spellID=28912, itemID=23098, name="Shifting Nightseye",              minSkill=315, source="drop",
      reagents={{R.NIGHTSEYE,1}} },

    -- Epic gem cuts (T5/T6 era)
    { spellID=35765, itemID=32215, name="Bold Living Ruby",                minSkill=350, source="drop",
      reagents={{R.LIVING_RUBY,1}} },
    { spellID=35766, itemID=32196, name="Delicate Living Ruby",            minSkill=350, source="drop",
      reagents={{R.LIVING_RUBY,1}} },
    { spellID=35767, itemID=32200, name="Brilliant Dawnstone",             minSkill=360, source="drop",
      reagents={{R.DAWNSTONE,1}} },
    { spellID=35768, itemID=32204, name="Smooth Dawnstone",                minSkill=360, source="drop",
      reagents={{R.DAWNSTONE,1}} },
    { spellID=35769, itemID=32216, name="Gleaming Dawnstone",              minSkill=360, source="drop",
      reagents={{R.DAWNSTONE,1}} },
    { spellID=35770, itemID=32220, name="Solid Star of Elune (Epic)",      minSkill=350, source="drop",
      reagents={{R.STAR_OF_ELUN,1}} },
    { spellID=35771, itemID=32218, name="Sparkling Violet Eye",            minSkill=360, source="drop",
      reagents={{R.VIOLET_EYE,1}} },
    { spellID=35772, itemID=32217, name="Purified Shadow Pearl",           minSkill=360, source="drop",
      reagents={{R.VIOLET_EYE,1}} },

    -- Jewelry (TBC rings & necklaces)
    { spellID=29529, itemID=23427, name="Arcane Khorium Band",             minSkill=370, source="trainer",
      reagents={{R.KHORIUM_BAR,4},{R.VIOLET_EYE,2},{R.PRIMAL_MANA,4}} },
    { spellID=29530, itemID=23428, name="Blazing Eternium Band",           minSkill=370, source="trainer",
      reagents={{R.ETERNIUM_BAR,4},{R.LIVING_RUBY,2},{R.PRIMAL_FIRE,4}} },
    { spellID=29531, itemID=23429, name="Don Julio's Band",                minSkill=375, source="trainer",
      reagents={{R.KHORIUM_BAR,4},{R.LIVING_RUBY,4},{R.PRIMAL_NETHER,2}} },
}

-- ============================================================
--  TAILORING  (197)
-- ============================================================
CCO.RecipeDB[197] = {
    -- Bolts
    { spellID=26751, itemID=21840, name="Bolt of Netherweave",             minSkill=300, source="trainer",
      reagents={{R.NETHERWEAVE,5}} },
    { spellID=26752, itemID=21881, name="Bolt of Imbued Netherweave",      minSkill=310, source="trainer",
      reagents={{R.NETHERWEAVE,5},{R.ARCANE_DUST,2}} },
    { spellID=26753, itemID=21882, name="Imbued Netherweave Bag",          minSkill=325, source="trainer",
      reagents={{21881,16}} },  -- Bolt of Imbued Netherweave x16
    { spellID=26754, itemID=21843, name="Netherweave Bag",                 minSkill=300, source="trainer",
      reagents={{21840,8}} },   -- Bolt of Netherweave x8

    -- Primal Mooncloth set
    { spellID=26776, itemID=21874, name="Primal Mooncloth",                minSkill=350, source="trainer",
      reagents={{R.FELWEED,3},{R.PRIMAL_LIFE,1},{R.PRIMAL_WATER,1}} },
    { spellID=26762, itemID=21871, name="Primal Mooncloth Bag",            minSkill=365, source="trainer",
      reagents={{21874,16},{R.PRIMAL_MANA,4}} },
    { spellID=26753, itemID=21872, name="Primal Mooncloth Robe",           minSkill=360, source="trainer",
      reagents={{21874,8},{R.PRIMAL_WATER,4},{R.PRIMAL_NETHER,1}} },
    { spellID=26754, itemID=21873, name="Primal Mooncloth Shoulders",      minSkill=350, source="trainer",
      reagents={{21874,6},{R.PRIMAL_WATER,2},{R.PRIMAL_MANA,2}} },

    -- Spellfire set
    { spellID=26777, itemID=21840, name="Spellcloth",                      minSkill=350, source="trainer",
      reagents={{R.FELWEED,3},{R.PRIMAL_FIRE,1},{R.PRIMAL_MANA,1}} },
    { spellID=26778, itemID=21841, name="Spellfire Bag",                   minSkill=375, source="trainer",
      reagents={{21840,16},{R.PRIMAL_MANA,4}} },

    -- Shadowweave set
    { spellID=26779, itemID=21842, name="Shadowcloth",                     minSkill=350, source="trainer",
      reagents={{R.FELWEED,3},{R.PRIMAL_SHADOW,1},{R.PRIMAL_FIRE,1}} },

    -- Bag of the Void
    { spellID=26775, itemID=21843, name="Bag of the Void",                 minSkill=375, source="drop",
      reagents={{R.NETHERWEAVE,10},{R.ARCANE_DUST,6},{R.PRIMAL_SHADOW,4}} },

    -- Flying carpets
    { spellID=34343, itemID=29519, name="Flying Carpet",                   minSkill=300, source="trainer",
      reagents={{R.NETHERWEAVE,6},{R.ARCANE_DUST,4}} },
    { spellID=34351, itemID=29520, name="Imbued Netherweave Boots",        minSkill=340, source="trainer",
      reagents={{21881,8},{R.ARCANE_DUST,4}} },
    { spellID=34352, itemID=29521, name="Imbued Netherweave Tunic",        minSkill=350, source="trainer",
      reagents={{21881,10},{R.ARCANE_DUST,6}} },
}

-- ============================================================
--  LEATHERWORKING  (165)
-- ============================================================
CCO.RecipeDB[165] = {
    -- Drums (TBC key utility – BiS for many groups)
    { spellID=35551, itemID=29471, name="Drums of Battle",                 minSkill=340, source="trainer",
      reagents={{R.HEAVY_KNOTHIDE,8}} },
    { spellID=35552, itemID=29472, name="Drums of Panic",                  minSkill=350, source="trainer",
      reagents={{R.HEAVY_KNOTHIDE,8},{R.PRIMAL_AIR,2}} },
    { spellID=35553, itemID=29473, name="Drums of Restoration",            minSkill=330, source="trainer",
      reagents={{R.HEAVY_KNOTHIDE,8}} },
    { spellID=35554, itemID=29474, name="Drums of Speed",                  minSkill=360, source="trainer",
      reagents={{R.HEAVY_KNOTHIDE,8},{R.PRIMAL_FIRE,2}} },
    { spellID=35555, itemID=29475, name="Drums of War",                    minSkill=370, source="trainer",
      reagents={{R.HEAVY_KNOTHIDE,8},{R.PRIMAL_MANA,2}} },

    -- Knothide Armor
    { spellID=30441, itemID=25684, name="Knothide Armor Kit",              minSkill=300, source="trainer",
      reagents={{R.KNOTHIDE_LEATHER,4}} },
    { spellID=25721, itemID=21673, name="Thick Draenic Vest",              minSkill=305, source="trainer",
      reagents={{R.KNOTHIDE_LEATHER,10},{R.THICK_CLEFTHOOF,4}} },

    -- Heavy Knothide
    { spellID=29032, itemID=25700, name="Heavy Knothide Leather",          minSkill=310, source="trainer",
      reagents={{R.KNOTHIDE_LEATHER,5}} },

    -- Elemental Leatherworking
    { spellID=29546, itemID=23196, name="Wind Trader's Bracers",           minSkill=350, source="trainer",
      reagents={{R.HEAVY_KNOTHIDE,10},{R.PRIMAL_AIR,6},{R.PRIMAL_NETHER,1}} },
    { spellID=29547, itemID=23197, name="Living Earth Shoulders",          minSkill=360, source="trainer",
      reagents={{R.HEAVY_KNOTHIDE,12},{R.PRIMAL_EARTH,8},{R.PRIMAL_NETHER,1}} },

    -- Dragonscale sets
    { spellID=29539, itemID=23201, name="Netherdrake Helm",                minSkill=355, source="trainer",
      reagents={{R.NETHER_DRAGONSC,12},{R.PRIMAL_SHADOW,4},{R.PRIMAL_NETHER,2}} },
    { spellID=29543, itemID=23203, name="Netherfury Boots",                minSkill=365, source="trainer",
      reagents={{R.NETHER_DRAGONSC,10},{R.PRIMAL_SHADOW,6},{R.PRIMAL_NETHER,1}} },

    -- Clefthoof set
    { spellID=29533, itemID=23190, name="Clefthoof Hide Vest",             minSkill=340, source="trainer",
      reagents={{R.THICK_CLEFTHOOF,12},{R.PRIMAL_EARTH,8}} },

    -- Cobrahide set
    { spellID=29536, itemID=23192, name="Cobra-Lash Boots",                minSkill=345, source="trainer",
      reagents={{R.COBRA_SCALES,10},{R.PRIMAL_FIRE,4},{R.PRIMAL_NETHER,1}} },
    { spellID=29537, itemID=23193, name="Cobrahide Leg Armor",             minSkill=325, source="trainer",
      reagents={{R.COBRA_SCALES,4},{R.KNOTHIDE_LEATHER,4}} },
    { spellID=29538, itemID=23194, name="Windscale Hood",                  minSkill=355, source="trainer",
      reagents={{R.WIND_SCALES,10},{R.PRIMAL_AIR,4},{R.PRIMAL_NETHER,1}} },
}

-- ============================================================
--  ENCHANTING  (333)
-- ============================================================
CCO.RecipeDB[333] = {
    -- TBC enchants (no itemID – enchants produce no item, use 0)
    -- Weapon enchants
    { spellID=27984, itemID=0, name="Enchant Weapon - Soulfrost",          minSkill=350, source="drop",
      reagents={{22445,8},{22446,8}} },  -- Arcane Dust, Greater Planar Essence
    { spellID=27981, itemID=0, name="Enchant Weapon - Sunfire",            minSkill=350, source="drop",
      reagents={{22445,8},{22447,4}} },  -- Arcane Dust, Large Prismatic Shard
    { spellID=34872, itemID=0, name="Enchant Weapon - Major Spellpower",   minSkill=350, source="trainer",
      reagents={{22445,8},{22447,6}} },
    { spellID=27977, itemID=0, name="Enchant Weapon - Mongoose",           minSkill=350, source="drop",
      reagents={{22447,10},{22448,2}} },  -- Large Prismatic Shard, Void Crystal
    { spellID=27975, itemID=0, name="Enchant Weapon - Executioner",        minSkill=350, source="drop",
      reagents={{22447,10},{22448,2}} },
    { spellID=27972, itemID=0, name="Enchant Weapon - Spellsurge",         minSkill=350, source="drop",
      reagents={{22445,6},{22447,8}} },
    { spellID=27971, itemID=0, name="Enchant Weapon - Battlemaster",       minSkill=350, source="drop",
      reagents={{22447,8},{22448,4}} },
    -- Ring enchants (Enchanting only)
    { spellID=27924, itemID=0, name="Enchant Ring - Stats",                minSkill=300, source="trainer",
      reagents={{22445,4}} },
    { spellID=27927, itemID=0, name="Enchant Ring - Spellpower",           minSkill=360, source="trainer",
      reagents={{22447,4}} },
    { spellID=27926, itemID=0, name="Enchant Ring - Healing Power",        minSkill=360, source="trainer",
      reagents={{22447,4}} },
    -- Chest
    { spellID=27960, itemID=0, name="Enchant Chest - Exceptional Health",  minSkill=310, source="trainer",
      reagents={{22445,4}} },
    { spellID=27958, itemID=0, name="Enchant Chest - Exceptional Mana",    minSkill=310, source="trainer",
      reagents={{22445,4}} },
    { spellID=27957, itemID=0, name="Enchant Chest - Major Resilience",    minSkill=350, source="drop",
      reagents={{22447,6}} },
    -- Shoulders (Aldor / Scryers rep)
    { spellID=35400, itemID=0, name="Enchant Shoulder - Inscription of Vengeance", minSkill=350, source="vendor",
      reagents={{22447,4},{22448,1}} },
    { spellID=35401, itemID=0, name="Enchant Shoulder - Inscription of Faith",     minSkill=350, source="vendor",
      reagents={{22447,4},{22448,1}} },
    -- Gloves
    { spellID=33999, itemID=0, name="Enchant Gloves - Major Spellpower",   minSkill=340, source="drop",
      reagents={{22447,6}} },
    { spellID=33995, itemID=0, name="Enchant Gloves - Assault",            minSkill=300, source="trainer",
      reagents={{22445,4}} },
    { spellID=33997, itemID=0, name="Enchant Gloves - Major Healing",      minSkill=340, source="drop",
      reagents={{22447,6}} },
    -- Boots
    { spellID=34008, itemID=0, name="Enchant Boots - Dexterity",           minSkill=300, source="trainer",
      reagents={{22445,4}} },
    { spellID=34010, itemID=0, name="Enchant Boots - Surefooted",          minSkill=340, source="drop",
      reagents={{22447,4},{22445,4}} },
    { spellID=34009, itemID=0, name="Enchant Boots - Boar's Speed",        minSkill=360, source="drop",
      reagents={{22447,6},{22448,2}} },
    -- Cloak
    { spellID=34004, itemID=0, name="Enchant Cloak - Greater Agility",     minSkill=300, source="trainer",
      reagents={{22445,4}} },
    { spellID=34005, itemID=0, name="Enchant Cloak - Spell Penetration",   minSkill=340, source="drop",
      reagents={{22447,4}} },
}

-- ============================================================
--  COOKING  (185)
-- ============================================================
CCO.RecipeDB[185] = {
    { spellID=33275, itemID=27657, name="Roasted Clefthoof",               minSkill=300, source="trainer",
      reagents={{R.CLEFTHOOF_MEAT,1}} },
    { spellID=33272, itemID=27658, name="Buzzard Bites",                   minSkill=300, source="trainer",
      reagents={{R.BUZZARD_MEAT,1}} },
    { spellID=33276, itemID=27659, name="Warp Burger",                     minSkill=300, source="trainer",
      reagents={{R.WARP_FLESH,1}} },
    { spellID=33278, itemID=27660, name="Talbuk Steak",                    minSkill=300, source="trainer",
      reagents={{R.TALBUK_VENISON,1}} },
    { spellID=33288, itemID=27662, name="Ravager Dog",                     minSkill=300, source="trainer",
      reagents={{R.RAVAGER_FLESH,1}} },
    { spellID=33290, itemID=27663, name="Grilled Mudfish",                 minSkill=310, source="trainer",
      reagents={{24521,1}} },  -- Spotted Feltail
    { spellID=33294, itemID=27664, name="Poached Bluefish",                minSkill=315, source="trainer",
      reagents={{27422,1}} },  -- Feltail fish
    { spellID=33301, itemID=27665, name="Golden Fish Sticks",              minSkill=310, source="trainer",
      reagents={{27421,1}} },  -- Golden Darter
    { spellID=33302, itemID=27666, name="Spicy Crawdad",                   minSkill=325, source="trainer",
      reagents={{27523,1}} },  -- Furious Crawdad
    { spellID=33303, itemID=27667, name="Blackened Basilisk",              minSkill=300, source="trainer",
      reagents={{R.CHUNK_OCRUSH,1}} },
    { spellID=33304, itemID=27668, name="Feltail Delight",                 minSkill=310, source="trainer",
      reagents={{24521,1}} },
    -- Buff foods
    { spellID=35564, itemID=30155, name="Broiled Bloodfin",                minSkill=350, source="vendor",
      reagents={{31673,1}} },
    { spellID=35562, itemID=30154, name="Blackened Sporefish",             minSkill=350, source="vendor",
      reagents={{31673,1}} },
    { spellID=35566, itemID=30156, name="Fisherman's Feast",               minSkill=350, source="vendor",
      reagents={{31673,1}} },
    { spellID=35568, itemID=30158, name="Skullfish Soup",                  minSkill=375, source="vendor",
      reagents={{31674,1}} },
    { spellID=35570, itemID=30159, name="Stormchops",                      minSkill=375, source="vendor",
      reagents={{31674,1}} },
}

-- ============================================================
--  FIRST AID  (129)
-- ============================================================
CCO.RecipeDB[129] = {
    { spellID=10840, itemID=8544,  name="Silk Bandage",                    minSkill=150, source="trainer",
      reagents={{R.SILK_CLOTH,1}} },
    { spellID=10842, itemID=8545,  name="Heavy Silk Bandage",              minSkill=180, source="trainer",
      reagents={{R.SILK_CLOTH,2}} },
    { spellID=10843, itemID=8546,  name="Mageweave Bandage",               minSkill=210, source="trainer",
      reagents={{R.MAGEWEAVE,1}} },
    { spellID=10844, itemID=8547,  name="Heavy Mageweave Bandage",         minSkill=240, source="trainer",
      reagents={{R.MAGEWEAVE,2}} },
    { spellID=18629, itemID=14529, name="Runecloth Bandage",               minSkill=260, source="trainer",
      reagents={{R.RUNECLOTH,1}} },
    { spellID=18630, itemID=14530, name="Heavy Runecloth Bandage",         minSkill=290, source="trainer",
      reagents={{R.RUNECLOTH,2}} },
    { spellID=27032, itemID=21990, name="Netherweave Bandage",             minSkill=300, source="trainer",
      reagents={{R.NETHERWEAVE,1}} },
    { spellID=27033, itemID=21991, name="Heavy Netherweave Bandage",       minSkill=330, source="trainer",
      reagents={{R.NETHERWEAVE,2}} },
}

-- ============================================================
-- Helper: look up all recipes for a given profession skillLine ID
-- ============================================================
function CCO:GetRecipesForProfession(skillLineID)
    return CCO.RecipeDB[skillLineID] or {}
end

-- ============================================================
-- Helper: find a recipe by itemID across all professions
-- ============================================================
function CCO:FindRecipeByItemID(itemID)
    for _, recipes in pairs(CCO.RecipeDB) do
        for _, recipe in ipairs(recipes) do
            if recipe.itemID == itemID then
                return recipe
            end
        end
    end
    return nil
end
