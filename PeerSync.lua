local _, ns = ...

-- Wire format (fields separated by "|", under the 255-byte addon message limit):
--   version|type|points|catchCount|c1,c2,...|bestPoints|bestItemId|sentTime
-- Types: HELLO (asks guildmates and friends to reply), UPDATE (sent after catches),
-- REPLY (whispered answer to a HELLO; never answered itself).
-- Guild cache exchange uses 2|SYNC and 2|RELAY|subject|points|...|sentTime.
-- A relay retains the original sender's timestamp, not the time it was forwarded.
local PREFIX = "BASHOP"
local VERSION = "1"
local CACHE_VERSION = "2"
local MAX_MESSAGE_LENGTH = 255
local SEND_INTERVAL = 1.0
local UPDATE_DEBOUNCE = 30
local MIN_RECEIVE_INTERVAL = 2
local REPLY_COOLDOWN = 300
local PRUNE_INTERVAL = 60

local sync = {}
ns.PeerSync = sync

local function db()
    return BassAmateurShopAddOnDB
end

local function isSharing()
    return db() and db().shareEnabled ~= false
end

-- Outgoing queue: one message per SEND_INTERVAL so a busy guild can't trip server throttling.
local queue, pumping = {}, false
local buildRelay

local function pump()
    local item = table.remove(queue, 1)
    if not item then
        pumping = false
        return
    end
    if isSharing() then
        local text = item.subject and buildRelay(item.subject, item.target) or item.text
        if text then
            local ok, err = pcall(function()
                if item.channel == "WHISPER" then
                    C_ChatInfo.SendAddonMessage(PREFIX, text, "WHISPER", item.target)
                elseif IsInGuild() then
                    C_ChatInfo.SendAddonMessage(PREFIX, text, "GUILD")
                end
            end)
            if not ok then print("Bass Amateur Shop: failed to send leaderboard data: " .. tostring(err)) end
        end
    end
    C_Timer.After(SEND_INTERVAL, pump)
end

local function enqueue(item)
    queue[#queue + 1] = item
    if not pumping then
        pumping = true
        pump()
    end
end

local function buildSummary()
    local data = db()
    local counts = {}
    for i = 1, #ns.RARITY_CHANCES do counts[i] = 0 end
    local indexByName = {}
    for i, entry in ipairs(ns.RARITY_CHANCES) do indexByName[entry.name] = i end

    local bestPoints, bestItemId = 0, 0
    for _, catch in ipairs(data.catches) do
        local i = indexByName[catch.rarity]
        if i then counts[i] = counts[i] + 1 end
        if (catch.points or 0) > bestPoints then
            bestPoints = catch.points
            bestItemId = tonumber(catch.link and catch.link:match("item:(%d+)")) or 0
        end
    end
    return {
        points = data.points or 0,
        catches = #data.catches,
        rarities = counts,
        bestPoints = bestPoints,
        bestItemId = bestItemId,
    }
end

local function encode(messageType)
    local s = buildSummary()
    return table.concat({
        VERSION, messageType, s.points, s.catches,
        table.concat(s.rarities, ","), s.bestPoints, s.bestItemId, time(),
    }, "|")
end

local function toCount(text, max)
    local n = tonumber(text)
    if not n or n < 0 or n > max or n ~= math.floor(n) then return nil end
    return n
end

-- Returns messageType, summary or nil when the message is malformed or from an unknown version.
local function decode(message)
    if type(message) ~= "string" or #message > MAX_MESSAGE_LENGTH then return nil end
    local _version, messageType, _points, _catches, rarityList, _bestPoints, _bestItemId, _sentTime =
        strsplit("|", message)
    if _version ~= VERSION then return nil end
    if messageType ~= "HELLO" and messageType ~= "UPDATE" and messageType ~= "REPLY" then return nil end

    local points = toCount(_points, 1e9)
    local catches = toCount(_catches, 1e7)
    local bestPoints = toCount(_bestPoints, 1e9)
    local bestItemId = toCount(_bestItemId, 1e8)
    local sentTime = toCount(_sentTime, 1e11)
    if not (points and catches and bestPoints and bestItemId and sentTime and rarityList) then return nil end

    local rarities = {}
    for value in rarityList:gmatch("[^,]+") do
        local n = toCount(value, 1e7)
        if not n or #rarities >= 12 then return nil end
        rarities[#rarities + 1] = n
    end
    if #rarities == 0 then return nil end

    return messageType, {
        points = points, catches = catches, rarities = rarities,
        bestPoints = bestPoints, bestItemId = bestItemId, sentTime = sentTime,
    }
end

local function guildRosterNames()
    local names = {}
    for i = 1, (GetNumGuildMembers() or 0) do
        local name = GetGuildRosterInfo(i)
        if name then names[Ambiguate(name, "guild")] = true end
    end
    return names
end

local function friendRoster()
    local friends = {}
    -- Regular in-game friends
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name then
            local name = Ambiguate(info.name, "guild")
            friends[name] = { name = info.name, connected = info.connected }
        end
    end
    -- Battle.net friends (if available)
    local numFriends = 0
    if BNGetNumFriends and type(BNGetNumFriends) == "function" then
        numFriends = BNGetNumFriends() or 0
    end
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo then
            local gameInfo = accountInfo.gameAccountInfo
            
            local isOnline = gameInfo and gameInfo.isOnline
            local client = gameInfo and gameInfo.clientProgram -- e.g., "WoW"

            if isOnline and client == "WoW" and gameInfo.realmID == GetRealmID() then
                local name = Ambiguate(gameInfo.characterName, "guild")
                friends[name] = { name = name, connected = isOnline }
            end
        end
    end
    return friends
end

local function isFriend(sender)
    return friendRoster()[Ambiguate(sender, "guild")] ~= nil
end

local function isSelf(name)
    return Ambiguate(name, "guild") == Ambiguate(ns.PlayerFullName(), "guild")
end

local function newestSummary(name)
    local newest
    for _, data in ipairs({ db().guildData, db().friendData }) do
        for key, summary in pairs(data) do
            if Ambiguate(key, "guild") == name and
                (not newest or (summary.sentTime or 0) > (newest.sentTime or 0)) then
                newest = summary
            end
        end
    end
    return newest
end

local function saveSummary(name, summary, guildMember, friend, direct)
    name = Ambiguate(name, "guild")
    local previous = newestSummary(name)
    if previous and ((previous.sentTime or 0) > summary.sentTime or
        ((previous.sentTime or 0) == summary.sentTime and not direct)) then
        local changed = false
        if guildMember and (not db().guildData[name] or
            (db().guildData[name].sentTime or 0) < (previous.sentTime or 0)) then
            db().guildData[name] = previous
            changed = true
        end
        if friend and (not db().friendData[name] or
            (db().friendData[name].sentTime or 0) < (previous.sentTime or 0)) then
            db().friendData[name] = previous
            changed = true
        end
        if changed and sync.onUpdate then sync.onUpdate() end
        return
    end

    -- Older versions may have stored the same character with and without a realm.
    for _, data in ipairs({ db().guildData, db().friendData }) do
        for key in pairs(data) do
            if Ambiguate(key, "guild") == name then data[key] = nil end
        end
    end
    summary.received = summary.sentTime
    if guildMember then db().guildData[name] = summary end
    if friend then db().friendData[name] = summary end
    if sync.onUpdate then sync.onUpdate() end
end

buildRelay = function(subject, target)
    if not IsInGuild() then return nil end
    local roster = guildRosterNames()
    if not roster[subject] or not roster[Ambiguate(target, "guild")] then return nil end
    local summary = db().guildData[subject]
    if not summary or not summary.sentTime then return nil end
    local text = table.concat({
        CACHE_VERSION, "RELAY", subject, summary.points, summary.catches,
        table.concat(summary.rarities, ","), summary.bestPoints, summary.bestItemId, summary.sentTime,
    }, "|")
    if #text > MAX_MESSAGE_LENGTH then
        print("Bass Amateur Shop: leaderboard data for " .. subject .. " is too long to relay.")
        return nil
    end
    return text
end

local lastReceived, lastReplied, lastHello, lastSyncReply = {}, {}, {}, {}
local worldEntered, requestedGuild = false, nil

local function requestGuildCache()
    if not worldEntered or not isSharing() or not IsInGuild() then return end
    local guild = GetGuildInfo("player")
    if not guild or guild == requestedGuild or not next(guildRosterNames()) then return end
    requestedGuild = guild
    enqueue({ channel = "GUILD", text = CACHE_VERSION .. "|SYNC" })
end

local function sendReply(target)
    if not isSharing() then return end
    enqueue({ channel = "WHISPER", target = target, text = encode("REPLY") })
end

local function handleMessage(message, channel, sender)
    if not isSharing() then return end
    if isSelf(sender) then return end
    if channel ~= "GUILD" and channel ~= "WHISPER" then return end
    local roster = guildRosterNames()
    local senderName = Ambiguate(sender, "guild")
    local guildMember = IsInGuild() and (channel == "GUILD" or roster[senderName] ~= nil)
    local friend = isFriend(sender)
    -- Whispers can come from anyone, so only accept them from the guild or friend roster.
    if channel == "WHISPER" and not guildMember and not friend then return end

    local now = GetTime()
    if message == CACHE_VERSION .. "|SYNC" then
        if channel ~= "GUILD" or not guildMember or not roster[senderName] then return end
        if lastSyncReply[senderName] and now - lastSyncReply[senderName] < REPLY_COOLDOWN then return end
        lastSyncReply[senderName] = now
        C_Timer.After(1 + math.random() * 4, function()
            if not isSharing() or not IsInGuild() then return end
            local currentRoster = guildRosterNames()
            if not currentRoster[senderName] then return end
            local subjects = {}
            for key, summary in pairs(db().guildData) do
                local subject = Ambiguate(key, "guild")
                if currentRoster[subject] and not isSelf(subject) and subject ~= senderName and
                    summary.sentTime then
                    subjects[subject] = true
                end
            end
            for subject in pairs(subjects) do
                -- Normalize legacy keys before building the queued relay.
                local newest = newestSummary(subject)
                if newest then db().guildData[subject] = newest end
                enqueue({ channel = "WHISPER", target = sender, subject = subject })
            end
        end)
        return
    end

    if type(message) ~= "string" or #message > MAX_MESSAGE_LENGTH then return end
    local subject, fields = message:match("^2|RELAY|([^|]+)|(.+)$")
    if subject then
        subject = Ambiguate(subject, "guild")
        if channel ~= "WHISPER" or not guildMember or not roster[senderName] or
            not roster[subject] or isSelf(subject) then return end
        local _, summary = decode(VERSION .. "|REPLY|" .. fields)
        if not summary then return end
        saveSummary(subject, summary, true, isFriend(subject), false)
        return
    end

    local messageType, summary = decode(message)
    if not messageType then return end
    local receiveKey = senderName .. "|" .. messageType
    if lastReceived[receiveKey] and now - lastReceived[receiveKey] < MIN_RECEIVE_INTERVAL then return end
    lastReceived[receiveKey] = now

    saveSummary(senderName, summary, guildMember, friend, true)

    if messageType == "HELLO" and (not lastReplied[sender] or now - lastReplied[sender] > REPLY_COOLDOWN) then
        lastReplied[sender] = now
        -- Random delay spreads out the replies when a whole guild answers one login.
        C_Timer.After(1 + math.random() * 4, function() sendReply(sender) end)
    end
end

local updatePending = false

-- Called after any change to the local stats. Debounced so a run of catches sends one message.
function sync.NotifyChange()
    if updatePending or not isSharing() or (not IsInGuild() and next(friendRoster()) == nil) then return end
    updatePending = true
    C_Timer.After(UPDATE_DEBOUNCE, function()
        updatePending = false
        if not isSharing() then return end
        if IsInGuild() then
            enqueue({ channel = "GUILD", text = encode("UPDATE") })
        end
        for _, friend in pairs(friendRoster()) do
            if friend.connected then
                enqueue({ channel = "WHISPER", target = friend.name, text = encode("UPDATE") })
            end
        end
    end)
end

function sync.SetSharing(enabled)
    db().shareEnabled = enabled
    if enabled then
        sync.NotifyChange()
        requestGuildCache()
    else
        requestedGuild = nil
    end
end

-- Own stats in the same shape as received summaries, for comparisons.
function sync.GetOwnSummary()
    return buildSummary()
end

function sync.IsSharing()
    return isSharing()
end

-- Last summaries received from guildmates, keyed by sender name.
function sync.GetGuildData()
    return db().guildData
end

function sync.GetFriendData()
    return db().friendData
end

function sync.GetFriendCount()
    local count = C_FriendList.GetNumFriends()
    if BNGetNumFriends and type(BNGetNumFriends) == "function" then
        count = count + (BNGetNumFriends() or 0)
    end
    return count
end

local lastPrune = 0
local function pruneGuildData()
    local now = GetTime()
    if now - lastPrune < PRUNE_INTERVAL then return end
    lastPrune = now
    if not IsInGuild() then
        wipe(db().guildData)
        return
    end
    local roster = guildRosterNames()
    -- An empty roster usually means it hasn't loaded yet.
    if next(roster) == nil then return end
    for sender in pairs(db().guildData) do
        if not roster[Ambiguate(sender, "guild")] then
            db().guildData[sender] = nil
        end
    end
end

local function pruneFriendData()
    local roster = friendRoster()
    for sender in pairs(db().friendData) do
        if not roster[Ambiguate(sender, "guild")] then
            db().friendData[sender] = nil
        end
    end
end

local function announceFriends()
    if not isSharing() then return end
    local now = GetTime()
    for _, friend in pairs(friendRoster()) do
        if friend.connected and (not lastHello[friend.name] or now - lastHello[friend.name] >= 60) then
            lastHello[friend.name] = now
            enqueue({ channel = "WHISPER", target = friend.name, text = encode("HELLO") })
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("FRIENDLIST_UPDATE")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= "BassAmateurShopAddOn" then return end
        db().guildData = db().guildData or {}
        db().friendData = db().friendData or {}
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        worldEntered = true
        if IsInGuild() then
            C_GuildInfo.GuildRoster()
        end
        -- Only announce on the first world entry.
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(2 + math.random() * 6, function()
            if isSharing() then
                if IsInGuild() then
                    enqueue({ channel = "GUILD", text = encode("HELLO") })
                    requestGuildCache()
                end
                announceFriends()
            end
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == PREFIX then handleMessage(message, channel, sender) end
    elseif event == "GUILD_ROSTER_UPDATE" then
        pruneGuildData()
        requestGuildCache()
    elseif event == "FRIENDLIST_UPDATE" then
        pruneFriendData()
        if worldEntered then announceFriends() end
        if sync.onUpdate then sync.onUpdate() end
    end
end)
