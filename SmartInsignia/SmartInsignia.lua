------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------

-- Cooldown threshold (seconds): equip insignia when CD is this or less
local CD_THRESHOLD = 40

-- Auto-use insignia when CC detected (true/false)
local AUTO_USE_ON_CC = false

------------------------------------------------------
-- STATE (Saved Variables)
------------------------------------------------------

SmartInsigniaDB = SmartInsigniaDB or {}

local autoMode = false  -- toggled by /insignia on/off
local updateFrame = nil


------------------------------------------------------
-- INTERNAL UTILITY FUNCTIONS
------------------------------------------------------

local TRINKET_SLOT = 14

local function FindItemInBags(name)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link and string.find(string.lower(link), string.lower(name), 1, true) then
                return bag, slot
            end
        end
    end
    return nil
end

local function IsEquipped(name)
    if not name then return false end
    local link = GetInventoryItemLink("player", TRINKET_SLOT)
    return link and string.find(string.lower(link), string.lower(name), 1, true)
end

local function GetInsigniaName()
    -- Try to find which insignia is in bags/equipped
    if FindItemInBags("Insignia of the Alliance") or IsEquipped("insignia of the alliance") then
        return "insignia of the alliance"
    elseif FindItemInBags("Insignia of the Horde") or IsEquipped("insignia of the horde") then
        return "insignia of the horde"
    end
    return nil
end

local function GetNormalTrinketName()
    return SmartInsigniaDB.normal or nil
end

local function InsigniaCooldown()
    local insigniaName = GetInsigniaName()
    if not insigniaName then return 999999 end

    -- First: if equipped in slot
    if IsEquipped(insigniaName) then
        local start, duration = GetInventoryItemCooldown("player", TRINKET_SLOT)
        if start == 0 or duration == 0 then
            return 0
        end
        local remaining = start + duration - GetTime()
        return max(remaining, 0)
    end

    -- If in bags
    local bag, slot = FindItemInBags(insigniaName)
    if bag then
        local start, duration = GetContainerItemCooldown(bag, slot)
        if start == 0 or duration == 0 then
            return 0
        end
        local remaining = start + duration - GetTime()
        return max(remaining, 0)
    end

    return 999999 -- not found
end

local function PlayerHasCC()
    return not HasFullControl()
end

local function EquipTrinket(name)
    if not name or UnitAffectingCombat("player") then return end

    local bag, slot = FindItemInBags(name)
    if bag then
        PickupContainerItem(bag, slot)
        EquipCursorItem(TRINKET_SLOT)
    end
end


------------------------------------------------------
-- MAIN LOGIC
------------------------------------------------------

-- Auto-equip logic (runs continuously when auto mode ON)
local function AutoEquipUpdate()
    if not autoMode then return end

    local insigniaName = GetInsigniaName()
    local normalName = GetNormalTrinketName()

    if not normalName then return end  -- Need normal trinket configured

    local cd = InsigniaCooldown()
    local inCombat = UnitAffectingCombat("player")
    local insigniaEquipped = IsEquipped(insigniaName)

    -- Only swap equipment out of combat
    if inCombat then return end

    -- Equip insignia when CD is low (ready or almost ready)
    if cd <= CD_THRESHOLD then
        if not insigniaEquipped then
            EquipTrinket(insigniaName)
        end
    else
        -- Equip normal trinket when insignia on long CD
        if insigniaEquipped then
            EquipTrinket(normalName)
        end
    end
end

-- Auto-use logic (runs continuously if AUTO_USE_ON_CC enabled)
local function AutoUseUpdate()
    if not AUTO_USE_ON_CC then return end

    local insigniaName = GetInsigniaName()
    if not insigniaName then return end

    local cd = InsigniaCooldown()
    local insigniaEquipped = IsEquipped(insigniaName)

    -- Auto-use if equipped, off CD, and CC'd
    if insigniaEquipped and cd == 0 and PlayerHasCC() then
        UseInventoryItem(TRINKET_SLOT)
    end
end

-- Manual use command
function SmartInsignia_Use()
    local insigniaName = GetInsigniaName()
    if not insigniaName then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8888No insignia found!|r")
        return
    end

    local cd = InsigniaCooldown()
    local insigniaEquipped = IsEquipped(insigniaName)

    if cd > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8888Insignia on cooldown: " .. math.floor(cd) .. "s|r")
        return
    end

    if not PlayerHasCC() then
        -- Not CC'd - do nothing silently
        return
    end

    if not insigniaEquipped then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8888Insignia not equipped!|r")
        return
    end

    UseInventoryItem(TRINKET_SLOT)
end

-- Legacy function for backward compatibility
function SmartInsignia_Update()
    AutoEquipUpdate()
    AutoUseUpdate()
end


------------------------------------------------------
-- SLASH COMMAND
------------------------------------------------------

local function FindEquippedTrinketName()
    local link = GetInventoryItemLink("player", TRINKET_SLOT)
    if link then
        local _, _, itemName = string.find(link, "%[(.+)%]")
        return itemName
    end
    return nil
end

SLASH_INSIGNIA1 = "/insignia"
SlashCmdList["INSIGNIA"] = function(msg)
    msg = string.lower(msg or "")

    if msg == "on" then
        if not GetNormalTrinketName() then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff8888Set normal trinket first: /insignia set|r")
            return
        end
        if not GetInsigniaName() then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff8888No insignia found in bags!|r")
            return
        end
        autoMode = true
        if not updateFrame then
            updateFrame = CreateFrame("Frame")
            updateFrame:SetScript("OnUpdate", function()
                AutoEquipUpdate()
                AutoUseUpdate()
            end)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffSmartInsignia: AUTO mode ON|r")

    elseif msg == "off" then
        autoMode = false
        DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffSmartInsignia: AUTO mode OFF|r")

    elseif msg == "use" then
        SmartInsignia_Use()

    elseif msg == "set" then
        local trinketName = FindEquippedTrinketName()
        if trinketName then
            SmartInsigniaDB.normal = string.lower(trinketName)
            DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffNormal trinket set to: " .. trinketName .. "|r")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff8888No trinket equipped in slot 14|r")
        end

    elseif msg == "status" then
        local cd = InsigniaCooldown()
        local status = autoMode and "ON" or "OFF"
        local insigniaName = GetInsigniaName() or "Not found"
        local normalName = GetNormalTrinketName() or "Not set"
        DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffSmartInsignia Status:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Auto mode: " .. status)
        DEFAULT_CHAT_FRAME:AddMessage("  Insignia: " .. insigniaName)
        DEFAULT_CHAT_FRAME:AddMessage("  Normal: " .. normalName)
        DEFAULT_CHAT_FRAME:AddMessage("  Insignia CD: " .. math.floor(cd) .. "s")
        if insigniaName ~= "Not found" then
            DEFAULT_CHAT_FRAME:AddMessage("  Equipped: " .. (IsEquipped(insigniaName) and "Insignia" or "Normal"))
        end

    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffSmartInsignia Commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  /insignia set - Set equipped trinket as normal trinket")
        DEFAULT_CHAT_FRAME:AddMessage("  /insignia on  - Enable auto-equip")
        DEFAULT_CHAT_FRAME:AddMessage("  /insignia off - Disable auto-equip")
        DEFAULT_CHAT_FRAME:AddMessage("  /insignia use - Use insignia (when CC'd)")
        DEFAULT_CHAT_FRAME:AddMessage("  /insignia status - Show current status")
        DEFAULT_CHAT_FRAME:AddMessage(" ")
        DEFAULT_CHAT_FRAME:AddMessage("Note: Insignia auto-detected (Alliance/Horde)")
    end
end

-- Legacy command
SLASH_SMARTINSIGNIA1 = "/smartinsignia"
SlashCmdList["SMARTINSIGNIA"] = function()
    SlashCmdList["INSIGNIA"]("")
end

------------------------------------------------------
-- EVENT SETUP
------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffSmartInsignia Addon initialized.|r")
end)
