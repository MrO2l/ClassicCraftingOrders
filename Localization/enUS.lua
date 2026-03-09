-- ============================================================
-- ClassicCraftingOrders - English (enUS) Localization
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.L = {
    -- General
    ADDON_LOADED_MSG    = "ClassicCraftingOrders loaded. Type /cco for help.",
    UNKNOWN_COMMAND     = "Unknown command: '%s'. Type /cco help.",
    UI_RESET            = "UI positions have been reset.",

    -- Help
    HELP_HEADER         = "ClassicCraftingOrders Commands",
    HELP_SHOW           = "Toggle main dashboard",
    HELP_ORDERS         = "Toggle order board",
    HELP_RESET          = "Reset all window positions",
    HELP_HELP           = "Show this help",

    -- Dashboard
    DASHBOARD_TITLE     = "Crafting Orders",
    BTN_NEW_ORDER       = "New Order",
    BTN_ORDER_BOARD     = "Order Board",
    BTN_MY_ORDERS       = "My Orders",
    BTN_SETTINGS        = "Settings",

    -- Recipe Browser
    RECIPE_BROWSER_TITLE    = "Recipe Browser",
    SEARCH_PLACEHOLDER      = "Search recipes…",
    LABEL_PROFESSION        = "Profession:",
    LABEL_REAGENTS          = "Reagents:",
    LABEL_COMMISSION        = "Commission (gold):",
    LABEL_MATS_PROVIDED     = "I will provide materials",
    BTN_POST_ORDER          = "Post Order",
    ORDER_POSTED            = "Order posted for %s! Waiting for a crafter…",
    ORDER_MISSING_FIELDS    = "Please select a recipe and enter a commission.",

    -- Order Board
    ORDER_BOARD_TITLE       = "Active Crafting Orders",
    COL_ITEM                = "Item",
    COL_REQUESTER           = "Requester",
    COL_COMMISSION          = "Commission",
    COL_MATS                = "Materials",
    COL_ACTION              = " ",
    MATS_PROVIDED           = "Provided",
    MATS_NEEDED             = "Bring mats",
    BTN_ACCEPT              = "Accept",
    NO_ORDERS               = "No active orders in your area.",
    CAN_CRAFT               = "You can craft this!",
    CANNOT_CRAFT            = "You cannot craft this.",
    ORDER_ACCEPTED_MSG      = "You accepted the order for %s. Whispering %s…",
    WHISPER_ACCEPT          = "Hey! I'd like to craft %s for you (Commission: %s). Please /trade me when ready!",

    -- Status Monitor
    STATUS_SEARCHING        = "Searching for a crafter…",
    STATUS_FOUND            = "Crafter found: %s",
    STATUS_TRADE_READY      = "Initiate /trade with %s to complete the order.",
    STATUS_COMPLETED        = "Order completed!",
    STATUS_CANCELLED        = "Order cancelled.",

    -- Trade Assistant
    TRADE_HELPER_TITLE      = "Trade Assistant",
    TRADE_AUTOFILL_BTN      = "Auto-Fill Materials",
    TRADE_AUTOFILL_DONE     = "Materials placed in trade window.",
    TRADE_AUTOFILL_FAIL     = "Some materials could not be found in your bags.",
    TRADE_HIGHLIGHT_TIP     = "Highlighted items are required for this order.",

    -- Communication
    COMM_BROADCAST_THROTTLE = "Please wait before posting another order.",
    COMM_PLAYER_ONLINE      = "%s is now using ClassicCraftingOrders.",

    -- Errors
    ERR_NO_PROFESSION       = "You don't have any crafting professions.",
    ERR_RECIPE_NOT_FOUND    = "Recipe not found.",
    ERR_CHANNEL_JOIN_FAIL   = "Could not join the synchronisation channel. Orders may not propagate.",
}
