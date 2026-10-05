-- Lint config shared across the Voc family (see FAMILY.md). The WoW
-- client runs Lua 5.1; tests may use 5.4 features behind guards.
--
-- read_globals is the allowlist of WoW API verified against the build
-- in `## Interface:` (Blizzard_APIDocumentationGenerated for that
-- build, see FAMILY.md "Sources of truth"). Lint fails on any other
-- global on purpose: add a name here only after confirming it exists,
-- under that namespace, in the current build. Never from a wiki.
std = "lua51"
max_line_length = false
self = false
unused_args = false
exclude_files = { ".reference/**", "mock/**" }

-- Globals this addon owns: SavedVariables, slash registration, popups.
globals = {
  "VocWarbankDB",
  "SLASH_VOCWARBANK1", "SLASH_VOCWARBANK2",
  "SlashCmdList", "StaticPopupDialogs",
}

-- WoW API and UI globals read by the addon.
read_globals = {
  "_G",
  "C_AddOns", "C_Container", "C_EquipmentSet", "C_Item",
  "C_MountJournal", "C_PetJournal", "C_QuestLog", "C_Spell", "C_Timer", "C_ToyBox",
  "C_TransmogCollection", "Enum",
  "CreateFrame", "CreateObjectPool", "CreateSettingsListSectionHeaderInitializer",
  "GameTooltip", "GetCursorInfo", "DeleteCursorItem", "GetExpansionLevel",
  "GetProfessionInfo", "GetProfessions", "InCombatLockdown", "IsShiftKeyDown", "PlayerHasToy",
  "Mixin", "BackdropTemplateMixin", "FramePool_HideAndClearAnchors", "Pool_HideAndClearAnchors",
  "Settings", "SettingsPanel", "StaticPopup_Show", "UIParent", "UISpecialFrames",
  "ITEM_QUALITY_COLORS", "YES", "NO",
  "MerchantFrame", "MailFrame", "AuctionHouseFrame",
  "ClickSendMailItemButton", "SendMailMailButton", "SendMailNameEditBox", "SendMailSubjectEditBox",
  -- optional neighbors (presence-gated)
  "Auctionator", "OEMarketInfo", "Syndicator", "TSM_API",
}

-- Tests install stubs onto _G by design.
files["tests/**"] = {
  std = "+lua54",
  globals = { "print", "_G" },
  read_globals = { "unpack" },
}
