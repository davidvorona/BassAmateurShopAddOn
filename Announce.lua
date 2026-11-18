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

function ns.MeetsAnnounceRarity(catch)
    for i, entry in ipairs(ns.RARITY_CHANCES) do
        if entry.name == catch.rarity then
            return i >= ns.GetAnnounceMinRarity()
        end
    end
    return false
end

local function CatchAnnouncement(catch)
    return string.format("[BAS] %s caught a %s %s (%d points)!",
        ns.PlayerFullName(), catch.rarity, catch.link or catch.name or "fish", catch.points)
end

-- This is an extremely defensive function designed to handle blocked guild chats gracefully.
-- This function is invoked on button press, which is shown when the automated guild chat fails.
-- If even the manual send fails, the last fallback is opening the chat input with the message pre-filled.
local sending, manualSendBlocked, lastManuallySharedCatch
function ns.AnnounceLatestCatch()
    if not ns.AnnouncingEnabled() then
        print("[BAS] Guild announcements must be enabled and your guild's Info must contain [BAS].")
        return
    end
    local catches = BassAmateurShopAddOnDB.catches
    local catch = catches and catches[#catches]
    if not catch then
        print("[BAS] There is no catch to share.")
        return
    end
    if not ns.MeetsAnnounceRarity(catch) then
        print("[BAS] The latest catch does not meet the announcement rarity threshold.")
        return
    end
    if catch == lastManuallySharedCatch then
        print("[BAS] The latest catch has already been shared or prepared for sharing.")
        return
    end
    local message = CatchAnnouncement(catch)
    manualSendBlocked = false
    sending = "manual"
    C_ChatInfo.SendChatMessage(message, "GUILD")
    sending = nil
    if not manualSendBlocked then
        lastManuallySharedCatch = catch
        ns.CatchLog.MarkLatestCatchShared()
        return
    end
    local editBox = ChatFrameUtil.ChooseBoxForSend(DEFAULT_CHAT_FRAME)
    if not editBox or editBox.disableActivate then
        print("[BAS] The chat input is unavailable.")
        return
    end
    if editBox:GetText() ~= "" then
        print("[BAS] Finish or clear your chat draft before sharing a catch.")
        return
    end
    ChatFrameUtil.OpenChat(SLASH_GUILD1 .. " " .. message, DEFAULT_CHAT_FRAME)
    lastManuallySharedCatch = catch
    ns.CatchLog.MarkLatestCatchShared()
    print("[BAS] Guild announcement was blocked. Press Enter to send the prepared message.")
end

local queue, sinceLast = {}, COOLDOWN
local pump = CreateFrame("Frame")
-- https://wowwiki-archive.fandom.com/wiki/Using_OnUpdate_correctly
pump:SetScript("OnUpdate", function(_, elapsed)
    sinceLast = sinceLast + elapsed
    if sinceLast < COOLDOWN or #queue == 0 then return end
    local message = table.remove(queue, 1)
    -- Re-check at send time in case the setting or guild tag changed while queued.
    if ns.AnnouncingEnabled() then
        -- This method fails for chatType "GUILD" due to tainted context for some clients only.
        -- The documentation claims that chatType "GUILD" does not require a hardware event:
        -- https://warcraft.wiki.gg/wiki/API:C_ChatInfo.SendChatMessage
        -- However, replacing the chatType "GUILD" with "PARTY" fixes the issue.
        -- Reported: https://us.forums.blizzard.com/en/wow/t/wow-forever-1601-delayed-guild-chat-messages-blocked-as-tainted/2414879
        sending = "automatic"
        C_ChatInfo.SendChatMessage(message, "GUILD")
        sending = nil
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
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_ENTERING_WORLD" then
        RequestGuildInfo()
    elseif event == "QUEST_TURNED_IN" and arg1 == STV_CONTEST_QUEST_ID and ns.AnnouncingEnabled() then
        Enqueue("[BAS] " .. ns.PlayerFullName() .. " won the Stranglethorn Vale Fishing Contest!")
    -- Workaround for clients that cannot send automated guild announcements due to tainted context
    elseif event == "ADDON_ACTION_BLOCKED" and sending and arg2 then
        if sending == "automatic" then
            if ns.CatchLog.ShowShareButton() then
                print("[BAS] Automatic guild announcement blocked. Use the Share button in the Catch Log.")
            end
        elseif sending == "manual" then
            manualSendBlocked = true
        end
    end
end)

-- Called after every catch. Each achievement fires once per character and is recorded even when
-- announcing is off, so enabling it later doesn't replay old milestones.
function ns.EvaluateAchievements(catch, totalCatches)
    local db = BassAmateurShopAddOnDB
    db.achievements = db.achievements or {}
    local fired = {}

    if ns.MeetsAnnounceRarity(catch) then
        fired[#fired + 1] = CatchAnnouncement(catch)
    end

    for _, n in ipairs(MILESTONES) do
        local id = "catches" .. n
        if totalCatches >= n and not db.achievements[id] then
            db.achievements[id] = time()
            fired[#fired + 1] = "[BAS] " .. ns.PlayerFullName() .. " just reached " .. n .. " catches!"
        end
    end

    if #fired > 0 and ns.AnnouncingEnabled() then
        for _, text in ipairs(fired) do
            Enqueue(text)
        end
    end
end
