-- Run from the repository root with Lua 5.1 or later: lua tests\PeerSync.lua
local now, timers, clients, sent = 100000, {}, {}, {}
local roster = { "Alice", "Bob", "Charlie" }
local unpackValues = unpack or table.unpack

local function advance(seconds)
    local finish = now + seconds
    while true do
        local nextIndex
        for i, timer in ipairs(timers) do
            if timer.at <= finish and (not nextIndex or timer.at < timers[nextIndex].at) then
                nextIndex = i
            end
        end
        if not nextIndex then break end
        local timer = table.remove(timers, nextIndex)
        now = timer.at
        if timer.client.online then timer.callback() end
    end
    now = finish
end

local function client(name, saved)
    local c = { name = name, online = true, db = saved or { catches = {}, points = 0 } }
    local env = setmetatable({}, { __index = _G })
    env.BassAmateurShopAddOnDB = c.db
    env.UnitName = function()
        local first, last = name:match("^(%S+) (.+)$")
        return first or name, last
    end
    env.Ambiguate = function(value) return (value:gsub("%-Realm$", "")) end
    env.IsInGuild = function() return true end
    env.GetGuildInfo = function() return "Guild" end
    env.GetNumGuildMembers = function() return #roster end
    env.GetGuildRosterInfo = function(i) return roster[i] end
    env.GetRealmID = function() return 1 end
    env.GetTime = function() return now - 100000 end
    env.time = function() return math.floor(now) end
    env.wipe = function(t) for key in pairs(t) do t[key] = nil end end
    env.strsplit = function(separator, text)
        local result = {}
        for part in (text .. separator):gmatch("(.-)" .. separator) do
            result[#result + 1] = part
        end
        return unpackValues(result)
    end
    env.C_FriendList = {
        GetNumFriends = function() return 1 end,
        GetFriendInfoByIndex = function() return { name = "Friend", connected = false } end,
    }
    env.C_BattleNet = {}
    env.C_GuildInfo = { GuildRoster = function() end }
    env.C_Timer = { After = function(delay, callback)
        timers[#timers + 1] = { at = now + delay, callback = callback, client = c }
    end }
    env.CreateFrame = function()
        local frame = {}
        function frame:RegisterEvent() end
        function frame:UnregisterEvent() end
        function frame:SetScript(_, handler) c.handler = handler end
        c.frame = frame
        return frame
    end
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() end,
        SendAddonMessage = function(prefix, text, channel, target)
            sent[#sent + 1] = { from = name, text = text, channel = channel, target = target }
            for otherName, other in pairs(clients) do
                if other.online and (channel == "GUILD" or otherName == target) then
                    other.handler(other.frame, "CHAT_MSG_ADDON", prefix, text, channel, name)
                end
            end
        end,
    }
    local ns = {
        RARITY_CHANCES = { { name = "Common" } },
        PlayerFullName = function()
            local first, last = env.UnitName("player")
            return last and (first .. " " .. last) or first
        end,
    }
    local chunk
    if setfenv then
        chunk = assert(loadfile("PeerSync.lua"))
        setfenv(chunk, env)
    else
        chunk = assert(loadfile("PeerSync.lua", "t", env))
    end
    chunk("BassAmateurShopAddOn", ns)
    c.sync = ns.PeerSync
    clients[name] = c
    c.handler(c.frame, "ADDON_LOADED", "BassAmateurShopAddOn")
    return c
end

local function event(c, eventName, ...)
    c.handler(c.frame, eventName, ...)
end

local function message(c, sender, channel, text)
    event(c, "CHAT_MSG_ADDON", "BASHOP", text, channel, sender)
end

local alice = client("Alice", {
    catches = { { rarity = "Common", points = 500, link = "item:42" } },
    points = 500,
})
local bob = client("Bob")
event(alice, "PLAYER_ENTERING_WORLD")
event(bob, "PLAYER_ENTERING_WORLD")
advance(30)
assert(bob.db.guildData.Alice.points == 500, "direct update was not saved")

alice.online = false
local charlie = client("Charlie")
event(charlie, "PLAYER_ENTERING_WORLD")
advance(30)
assert(charlie.db.guildData.Alice.points == 500, "offline guildmate was not relayed")
assert(charlie.db.guildData.Alice.sentTime == bob.db.guildData.Alice.sentTime, "relay changed timestamp")

local older = charlie.db.guildData.Alice.sentTime - 1
message(charlie, "Bob", "WHISPER", "2|RELAY|Alice|999|1|1|999|42|" .. older)
assert(charlie.db.guildData.Alice.points == 500, "stale relay overwrote newer data")
message(charlie, "Alice", "GUILD", "1|UPDATE|0|0|0|0|0|" .. math.floor(now))
assert(charlie.db.guildData.Alice.points == 0, "newer reset was rejected")
message(charlie, "Bob", "WHISPER", "2|RELAY|Alice|500|1|1|500|42|" .. older)
assert(charlie.db.guildData.Alice.points == 0, "stale relay undid reset")
message(charlie, "Alice", "GUILD", "1|REPLY|500|1|1|500|42|" .. older)
assert(charlie.db.guildData.Alice.points == 0, "stale direct message undid reset")

message(charlie, "Friend", "WHISPER", "2|RELAY|Alice|900|1|1|900|42|" .. math.floor(now + 1))
message(charlie, "Bob", "WHISPER", "2|RELAY|Friend|900|1|1|900|42|" .. math.floor(now + 1))
message(charlie, "Bob", "GUILD", "2|RELAY|Alice|900|1|1|900|42|" .. math.floor(now + 1))
message(charlie, "Bob", "WHISPER", "2|RELAY|Alice|invalid")
assert(charlie.db.guildData.Alice.points == 0 and not charlie.db.guildData.Friend,
    "untrusted or malformed relay was accepted")

local revision = math.floor(now + 1)
message(charlie, "Bob", "WHISPER", "2|RELAY|Alice|50|1|1|50|42|" .. revision)
message(charlie, "Bob", "WHISPER", "2|RELAY|Bob|20|1|1|20|42|" .. revision)
assert(charlie.db.guildData.Alice.points == 50 and charlie.db.guildData.Bob.points == 20,
    "consecutive relays were throttled")
message(charlie, "Alice", "GUILD", "1|HELLO|0|0|0|0|0|" .. revision)
assert(charlie.db.guildData.Alice.points == 0, "equal-timestamp direct update did not take precedence")

message(bob, "Friend", "WHISPER", "1|UPDATE|100|1|1|100|42|" .. math.floor(now))
assert(bob.db.friendData.Friend.points == 100, "direct friend update was rejected")
sent = {}
advance(301)
message(bob, "Charlie", "GUILD", "2|SYNC")
advance(30)
for _, item in ipairs(sent) do
    assert(not item.text:match("^2|RELAY|Friend|"), "friend-only data was relayed")
end

charlie.sync.SetSharing(false)
message(charlie, "Bob", "WHISPER", "2|RELAY|Alice|800|1|1|800|42|" .. math.floor(now))
assert(charlie.db.guildData.Alice.points == 0, "sharing off accepted a relay")
sent = {}
charlie.sync.SetSharing(true)
advance(3)
local requested = false
for _, item in ipairs(sent) do
    if item.from == "Charlie" and item.text == "2|SYNC" then requested = true end
end
assert(requested, "sharing on did not request the guild cache")

local saved = bob.db
bob.online = false
local reloaded = client("Bob", saved)
assert(reloaded.db.guildData.Alice.points == 500, "saved guild cache did not survive reload")

roster[#roster + 1] = "Dana Fisher"
roster[#roster + 1] = "Dana Sailor"
local dana = client("Dana Fisher")
local timestamp = math.floor(now)
message(dana, "Dana Fisher-Realm", "GUILD", "1|UPDATE|10|1|1|10|42|" .. timestamp)
assert(not dana.db.guildData["Dana Fisher"], "full-name self broadcast was saved as a peer")
message(dana, "Bob", "WHISPER", "2|RELAY|Dana Fisher|10|1|1|10|42|" .. timestamp)
assert(not dana.db.guildData["Dana Fisher"], "full-name self relay was saved as a peer")
message(dana, "Dana Sailor", "GUILD", "1|UPDATE|20|1|1|20|42|" .. timestamp)
assert(dana.db.guildData["Dana Sailor"].points == 20, "different surname was mistaken for self")

dana.db.guildData["Dana Fisher"] = {
    points = 10, catches = 1, rarities = { 1 }, bestPoints = 10, bestItemId = 42, sentTime = timestamp,
}
sent = {}
message(dana, "Bob", "GUILD", "2|SYNC")
advance(30)
local sentPeer = false
for _, item in ipairs(sent) do
    if item.from == "Dana Fisher" then
        assert(not item.text:match("^2|RELAY|Dana Fisher|"), "own cached summary was relayed")
        if item.text:match("^2|RELAY|Dana Sailor|") then sentPeer = true end
    end
end
assert(sentPeer, "different surname was excluded from relays")
print("PeerSync tests passed")
