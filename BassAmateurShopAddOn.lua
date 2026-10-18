if not BassAmateurShopAddOnDB then
    BassAmateurShopAddOnDB = { catches = {}, points = 0 }
end

-- TODO:
-- Add sync/leaderboard functionality with friends list
-- Broadcast to guild and Discord webhook on certain events

local mainFrame = CreateFrame("Frame", "BassAmateurShopAddOnMainFrame", UIParent, "BasicFrameTemplateWithInset")
mainFrame:SetSize(500, 350)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
mainFrame.TitleBg:SetHeight(30)
mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mainFrame.title:SetPoint("TOPLEFT", mainFrame.TitleBg, "TOPLEFT", 5, -3)
mainFrame.title:SetText("Bass Amateur Shop")

mainFrame:Hide()
mainFrame:EnableMouse(true)
mainFrame:SetMovable(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", function(self)
	self:StartMoving()
end)
mainFrame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
end)

mainFrame:SetScript("OnShow", function()
    PlaySound(808)
end)

mainFrame:SetScript("OnHide", function()
    PlaySound(808)
end)

mainFrame.playerName = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
mainFrame.playerName:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, -30)
mainFrame.playerName:SetText(UnitName("player") .. " (Level " .. UnitLevel("player") .. ")")

mainFrame.guildText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mainFrame.guildText:SetPoint("TOPLEFT", mainFrame.playerName, "BOTTOMLEFT", 0, -2)

local _, ns = ...
-- Rarities that trigger the level-up style banner.
local BANNER_RARITIES = { Epic = true, Legendary = true, Artifact = true }

-- Big points readout: counts up to the new total and flashes white on gain.
local pointsLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
pointsLabel:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -20, -30)
pointsLabel:SetText("|cffaaaaaaTOTAL POINTS|r")

local pointsText = mainFrame:CreateFontString(nil, "OVERLAY")
pointsText:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE")
pointsText:SetPoint("TOPRIGHT", pointsLabel, "BOTTOMRIGHT", 0, -2)
pointsText:SetShadowOffset(2, -2)
pointsText:SetTextColor(1, 0.82, 0)

local displayedPoints, targetPoints, flash = 0, 0, 0
local pointsAnimator = CreateFrame("Frame", nil, mainFrame)
pointsAnimator:SetScript("OnUpdate", function(self, elapsed)
    if displayedPoints < targetPoints then
        local step = math.max(1, math.ceil((targetPoints - displayedPoints) * math.min(1, elapsed * 8)))
        displayedPoints = math.min(targetPoints, displayedPoints + step)
    elseif displayedPoints > targetPoints then
        displayedPoints = targetPoints
    end
    pointsText:SetText(tostring(displayedPoints))
    if flash > 0 then
        flash = math.max(0, flash - elapsed * 1.5)
        pointsText:SetTextColor(1, 0.82 + 0.18 * flash, 0.4 * flash)
    end
end)

local function SetPointsDisplay(total, animate)
    targetPoints = total
    if animate then
        flash = 1
    else
        displayedPoints = total
        pointsText:SetText(tostring(total))
    end
end
SetPointsDisplay(0)

SLASH_BASSAMATEURSHOPADDON1 = "/bas"
SlashCmdList["BASSAMATEURSHOPADDON"] = function(msg)
    local shareArg = msg and msg:lower():match("^%s*share%s+(%a+)%s*$")
    if shareArg == "on" or shareArg == "off" then
        ns.GuildSync.SetSharing(shareArg == "on")
        print("Bass Amateur Shop: guild sharing " .. shareArg .. ".")
        return
    end
    if msg and msg:lower():match("^%s*reset%s*$") then
        wipe(BassAmateurShopAddOnDB.catches)
        ns.CatchLog.Clear()
        BassAmateurShopAddOnDB.points = 0
        SetPointsDisplay(0)
        ns.GuildTab.Refresh()
        ns.GuildSync.NotifyChange()
        print("Bass Amateur Shop: catch history cleared.")
        return
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

table.insert(UISpecialFrames, "BassAmateurShopAddOnMainFrame")
    
-- Weights are percentages and sum to 100.
local RARITY_CHANCES = {
    { name = "Common",    chance = 60,  color = "ffffffff" },
    { name = "Uncommon",  chance = 25,  color = "ff1eff00" },
    { name = "Rare",      chance = 10,  color = "ff0070dd" },
    { name = "Epic",      chance = 3.5, color = "ffa335ee" },
    { name = "Legendary", chance = 1,   color = "ffff8000" },
    { name = "Artifact",  chance = 0.5, color = "ffe6cc80" },
}

ns.RARITY_CHANCES = RARITY_CHANCES

local RARITY_COLORS = {}
local RARITY_MULTIPLIERS = {}
for _, entry in ipairs(RARITY_CHANCES) do
    RARITY_COLORS[entry.name] = entry.color
    RARITY_MULTIPLIERS[entry.name] = 100 / entry.chance
end

local function ColorRarity(rarity)
    return "|c" .. RARITY_COLORS[rarity] .. rarity .. "|r"
end
ns.ColorRarity = ColorRarity

local function RollRarity()
    local roll = math.random() * 100
    local cumulative = 0
    for _, entry in ipairs(RARITY_CHANCES) do
        cumulative = cumulative + entry.chance
        if roll < cumulative then
            return entry.name
        end
    end
    return RARITY_CHANCES[1].name
end

-- Shared area below the header; each tab's page fills it.
local content = CreateFrame("Frame", nil, mainFrame)
content:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, -76)
content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -15, 15)
ns.content = content

-- Guild info isn't available at load time, so this runs again on guild/world events and when the frame opens.
local function UpdateHeader()
    mainFrame.playerName:SetText(UnitName("player") .. " (Level " .. UnitLevel("player") .. ")")
    local guildName, rankName = GetGuildInfo("player")
    mainFrame.guildText:Show()
    if guildName then
        mainFrame.guildText:SetText("|cff40ff40<" .. guildName .. ">|r" .. (rankName and (" - " .. rankName) or ""))
    else
        mainFrame.guildText:SetText("|cff888888Not in a guild|r")
    end
end
mainFrame:HookScript("OnShow", UpdateHeader)
UpdateHeader()

-- Side tabs on the right edge of the frame, like the Professions window.
-- Each tab file calls ns.RegisterTab({ name, icon, page, onSelect }); tabs appear in load order.
local tabs, tabButtons = {}, {}

local function SelectTab(index)
    for i, tab in ipairs(tabs) do
        tab.page:SetShown(i == index)
        tabButtons[i]:SetChecked(i == index)
    end
    if tabs[index].onSelect then tabs[index].onSelect() end
end

function ns.RegisterTab(tab)
    local i = #tabs + 1
    tabs[i] = tab
    local button = CreateFrame("CheckButton", nil, mainFrame)
    button:SetSize(36, 36)
    button:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 0, -60 - (i - 1) * 44)
    local backdrop = button:CreateTexture(nil, "BACKGROUND")
    backdrop:SetPoint("TOPLEFT", -3, 3)
    backdrop:SetPoint("BOTTOMRIGHT", 3, -3)
    backdrop:SetColorTexture(0.1, 0.1, 0.1, 0.9)
    button:SetNormalTexture(tab.icon)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local checked = button:GetCheckedTexture()
    checked:SetBlendMode("ADD")
    button:SetScript("OnClick", function() SelectTab(i) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tab.name, 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    tabButtons[i] = button
    tab.page:Hide()
end

local eventFrame = CreateFrame("Frame", "BassAmateurShopAddOnEventFrame", UIParent)

local function eventHandler(self, event, ...)
    if event == "PLAYER_GUILD_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        UpdateHeader()
    elseif event == "ADDON_LOADED" then
        if ... ~= "BassAmateurShopAddOn" then return end
        -- Every file has loaded by now, so all tabs are registered.
        ns.CatchLog.Load()
        SetPointsDisplay(BassAmateurShopAddOnDB.points or 0)
        SelectTab(1)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "LOOT_OPENED" then
        -- No dedicated fishing event exists, so we rely on the loot window to detect catches.
        if not IsFishingLoot() then return end
        for slot = 1, GetNumLootItems() do
            local link = GetLootSlotLink(slot)
            if link then
                local _, name, quantity = GetLootSlotInfo(slot)
                local rarity = RollRarity()
                local itemLevel = select(4, C_Item.GetItemInfo(link)) or 1
                if itemLevel < 1 then itemLevel = 1 end
                local points = math.ceil(itemLevel * RARITY_MULTIPLIERS[rarity])
                local isFirstCatch = not ns.CatchLog.HasFish(link)
                if isFirstCatch then
                    points = points * 2 -- Double points for first catchLog
                end
                local catch = {
                    rarity = rarity,
                    points = points,
                    time = time(),
                    link = link,
                    name = name,
                    quantity = quantity,
                    zone = GetZoneText(),
                }
                -- Update DB
                table.insert(BassAmateurShopAddOnDB.catches, catch)
                BassAmateurShopAddOnDB.points = (BassAmateurShopAddOnDB.points or 0) + catch.points
                -- Update UI
                ns.CatchLog.AddCatch(catch, #BassAmateurShopAddOnDB.catches)
                if isFirstCatch then
                    ns.ShowBanner("FIRST CATCH!", (name or "Unknown fish") .. "  -  " .. points .. " points", RARITY_COLORS[rarity]:sub(3))
                elseif BANNER_RARITIES[rarity] then
                    ns.ShowBanner(rarity:upper() .. " CATCH!", (name or "Unknown fish") .. "  -  " .. catch.points .. " points", RARITY_COLORS[rarity]:sub(3))
                end
                SetPointsDisplay(BassAmateurShopAddOnDB.points or 0, true)
                ns.GuildSync.NotifyChange()
                ns.GuildTab.Refresh()
            end
        end
    end
end

eventFrame:SetScript("OnEvent", eventHandler)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
