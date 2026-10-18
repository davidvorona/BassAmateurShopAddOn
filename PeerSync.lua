local _, ns = ...

-- Wire format (fields separated by "|", under the 255-byte addon message limit):
--   version|type|points|catchCount|c1,c2,...|bestPoints|bestItemId|sentTime
-- Types: HELLO (asks guildmates and friends to reply), UPDATE (sent after catches),
-- REPLY (whispered answer to a HELLO; never answered itself).
local PREFIX = "BASHOP"
local VERSION = "1"
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

local function pump()
    local item = table.remove(queue, 1)
    if not item then
        pumping = false
        return
    end
    if item.channel == "WHISPER" then
        C_ChatInfo.SendAddonMessage(PREFIX, item.text, "WHISPER", item.target)
    elseif IsInGuild() then
        C_ChatInfo.SendAddonMessage(PREFIX, item.text, "GUILD")
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
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name then
            local name = Ambiguate(info.name, "guild")
            friends[name] = { name = info.name, connected = info.connected }
        end
    end
    return friends
end

local function isFriend(sender)
    return friendRoster()[Ambiguate(sender, "guild")] ~= nil
end

local lastReceived, lastReplied, lastHello = {}, {}, {}

local function sendReply(target)
    enqueue({ channel = "WHISPER", target = target, text = encode("REPLY") })
end

local function handleMessage(message, channel, sender)
    if not isSharing() then return end
    if Ambiguate(sender, "short") == UnitName("player") then return end
    if channel ~= "GUILD" and channel ~= "WHISPER" then return end
    local guildMember = channel == "GUILD" or guildRosterNames()[Ambiguate(sender, "guild")] ~= nil
    local friend = isFriend(sender)
    -- Whispers can come from anyone, so only accept them from the guild or friend roster.
    if channel == "WHISPER" and not guildMember and not friend then return end

    local now = GetTime()
    if lastReceived[sender] and now - lastReceived[sender] < MIN_RECEIVE_INTERVAL then return end
    lastReceived[sender] = now

    local messageType, summary = decode(message)
    if not messageType then return end

    summary.received = time()
    if guildMember then db().guildData[sender] = summary end
    if friend then db().friendData[sender] = summary end
    if sync.onUpdate then sync.onUpdate() end

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
    if enabled then sync.NotifyChange() end
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
    return C_FriendList.GetNumFriends()
end

local lastPrune = 0
local worldEntered = false

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
                end
                announceFriends()
            end
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == PREFIX then handleMessage(message, channel, sender) end
    elseif event == "GUILD_ROSTER_UPDATE" then
        pruneGuildData()
    elseif event == "FRIENDLIST_UPDATE" then
        pruneFriendData()
        if worldEntered then announceFriends() end
        if sync.onUpdate then sync.onUpdate() end
    end
end)
