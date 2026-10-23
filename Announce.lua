local _, ns = ...

-- Opt-in guild chat announcements. Both gates must pass: the player enabled announcing, and the
-- guild's Info text contains GUILD_TAG, which officers control.
local GUILD_TAG = "[BAS]"
local COOLDOWN = 10
local MAX_QUEUE = 3
local DEFAULT_MIN_RARITY = 4 -- Epic
local MILESTONES = { 100, 500, 1000, 5000 }
local STV_CONTEST_QUEST_ID = 8193 -- Master Angler

function ns.GetAnnounceMinRarity()
    return BassAmateurShopAddOnDB.announceMinRarity or DEFAULT_MIN_RARITY
end

local function GuildAllows()
    if not IsInGuild() then return false end
    local text = GetGuildInfoText and GetGuildInfoText()
    return text ~= nil and text:find(GUILD_TAG, 1, true) ~= nil
end

function ns.AnnouncingEnabled()
    return BassAmateurShopAddOnDB.announceGuild == true and GuildAllows()
end

local queue, sinceLast = {}, COOLDOWN
local pump = CreateFrame("Frame")
pump:SetScript("OnUpdate", function(_, elapsed)
    sinceLast = sinceLast + elapsed
    if sinceLast < COOLDOWN or #queue == 0 then return end
    local message = table.remove(queue, 1)
    -- Re-check at send time in case the setting or guild tag changed while queued.
    if ns.AnnouncingEnabled() then
        C_ChatInfo.SendChatMessage(message, "GUILD")
        sinceLast = 0
    else
        wipe(queue)
    end
end)

local function Enqueue(message)
    if #queue >= MAX_QUEUE then return end
    queue[#queue + 1] = message
end

-- Guild info text only arrives after a roster request.
local function RequestGuildInfo()
    if not IsInGuild() then return end
    C_GuildInfo.GuildRoster()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_TURNED_IN")
events:SetScript("OnEvent", function(_, event, questID)
    if event == "PLAYER_ENTERING_WORLD" then
        RequestGuildInfo()
    elseif event == "QUEST_TURNED_IN" and questID == STV_CONTEST_QUEST_ID and ns.AnnouncingEnabled() then
        Enqueue("[BAS] " .. ns.PlayerFullName() .. " won the Stranglethorn Vale Fishing Contest!")
    end
end)

-- Called after every catch. Each achievement fires once per character and is recorded even when
-- announcing is off, so enabling it later doesn't replay old milestones.
function ns.EvaluateAchievements(catch, totalCatches)
    local db = BassAmateurShopAddOnDB
    db.achievements = db.achievements or {}
    local fired = {}

    local rarityIndex
    for i, entry in ipairs(ns.RARITY_CHANCES) do
        if entry.name == catch.rarity then rarityIndex = i end
    end
    if rarityIndex and rarityIndex >= ns.GetAnnounceMinRarity() then
        fired[#fired + 1] = string.format("caught a %s %s (%d points)!",
            catch.rarity, catch.link or catch.name or "fish", catch.points)
    end

    for _, n in ipairs(MILESTONES) do
        local id = "catches" .. n
        if totalCatches >= n and not db.achievements[id] then
            db.achievements[id] = time()
            fired[#fired + 1] = "just reached " .. n .. " catches!"
        end
    end

    if #fired > 0 and ns.AnnouncingEnabled() then
        for _, text in ipairs(fired) do
            Enqueue("[BAS] " .. ns.PlayerFullName() .. " " .. text)
        end
    end
end
