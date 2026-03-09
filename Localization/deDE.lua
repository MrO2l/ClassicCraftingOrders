-- ============================================================
-- ClassicCraftingOrders - German (deDE) Localization
-- ============================================================
local ADDON_NAME, CCO = ...

-- Only override if the client locale matches
if GetLocale() ~= "deDE" then return end

CCO.L = CCO.L or {}

local L = CCO.L

L["ADDON_LOADED_MSG"]       = "ClassicCraftingOrders geladen. Tippe /cco für Hilfe."
L["UNKNOWN_COMMAND"]        = "Unbekannter Befehl: '%s'. Tippe /cco help."
L["UI_RESET"]               = "UI-Positionen wurden zurückgesetzt."

L["HELP_HEADER"]            = "ClassicCraftingOrders Befehle"
L["HELP_SHOW"]              = "Haupt-Dashboard ein-/ausblenden"
L["HELP_ORDERS"]            = "Auftragstafel ein-/ausblenden"
L["HELP_RESET"]             = "Alle Fenster-Positionen zurücksetzen"
L["HELP_HELP"]              = "Diese Hilfe anzeigen"

L["DASHBOARD_TITLE"]        = "Handwerksaufträge"
L["BTN_NEW_ORDER"]          = "Neuer Auftrag"
L["BTN_ORDER_BOARD"]        = "Auftragstafel"
L["BTN_MY_ORDERS"]          = "Meine Aufträge"
L["BTN_SETTINGS"]           = "Einstellungen"

L["RECIPE_BROWSER_TITLE"]   = "Rezept-Browser"
L["SEARCH_PLACEHOLDER"]     = "Rezepte suchen…"
L["LABEL_PROFESSION"]       = "Beruf:"
L["LABEL_REAGENTS"]         = "Materialien:"
L["LABEL_COMMISSION"]       = "Trinkgeld (Gold):"
L["LABEL_MATS_PROVIDED"]    = "Ich stelle die Materialien bereit"
L["BTN_POST_ORDER"]         = "Auftrag aufgeben"
L["ORDER_POSTED"]           = "Auftrag für %s aufgegeben! Warte auf Handwerker…"
L["ORDER_MISSING_FIELDS"]   = "Bitte Rezept auswählen und Trinkgeld eingeben."

L["ORDER_BOARD_TITLE"]      = "Aktive Handwerksaufträge"
L["COL_ITEM"]               = "Gegenstand"
L["COL_REQUESTER"]          = "Auftraggeber"
L["COL_COMMISSION"]         = "Trinkgeld"
L["COL_MATS"]               = "Materialien"
L["COL_ACTION"]             = " "
L["MATS_PROVIDED"]          = "Bereitgestellt"
L["MATS_NEEDED"]            = "Mats mitbringen"
L["BTN_ACCEPT"]             = "Annehmen"
L["NO_ORDERS"]              = "Keine aktiven Aufträge in deiner Nähe."
L["CAN_CRAFT"]              = "Du kannst das herstellen!"
L["CANNOT_CRAFT"]           = "Du kannst das nicht herstellen."
L["ORDER_ACCEPTED_MSG"]     = "Du hast den Auftrag für %s angenommen. Flüstere %s…"
L["WHISPER_ACCEPT"]         = "Hey! Ich würde gerne %s für dich herstellen (Trinkgeld: %s). Bitte initiiere /handel mit mir!"

L["STATUS_SEARCHING"]       = "Suche nach Handwerker…"
L["STATUS_FOUND"]           = "Handwerker gefunden: %s"
L["STATUS_TRADE_READY"]     = "Starte /handel mit %s, um den Auftrag abzuschließen."
L["STATUS_COMPLETED"]       = "Auftrag abgeschlossen!"
L["STATUS_CANCELLED"]       = "Auftrag abgebrochen."

L["TRADE_HELPER_TITLE"]     = "Handelsassistent"
L["TRADE_AUTOFILL_BTN"]     = "Materialien automatisch einfügen"
L["TRADE_AUTOFILL_DONE"]    = "Materialien wurden ins Handelsfenster gelegt."
L["TRADE_AUTOFILL_FAIL"]    = "Einige Materialien konnten nicht in deinen Taschen gefunden werden."
L["TRADE_HIGHLIGHT_TIP"]    = "Markierte Gegenstände werden für diesen Auftrag benötigt."

L["COMM_BROADCAST_THROTTLE"]= "Bitte warte, bevor du einen weiteren Auftrag aufgibst."
L["COMM_PLAYER_ONLINE"]     = "%s nutzt jetzt ClassicCraftingOrders."

L["ERR_NO_PROFESSION"]      = "Du hast keine Handwerksberufe."
L["ERR_RECIPE_NOT_FOUND"]   = "Rezept nicht gefunden."
L["ERR_CHANNEL_JOIN_FAIL"]  = "Synchronisationskanal konnte nicht beigetreten werden."
