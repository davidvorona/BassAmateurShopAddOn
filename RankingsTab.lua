local _, ns = ...

local ROW_HEIGHT = 18
local COMPARE_HEIGHT = 74
local FILTER_HEIGHT = 24
local SELF_KEY = "__self"
local FRIENDS_KEY = "showFriends"
local GUILD_KEY = "showGuild"

local function timeAgo(t)
    local seconds = math.max(0, time() - (t or 0))
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
    return math.floor(seconds / 86400) .. "d ago"
end

local function bestCatchName(summary)
    if summary.bestItemId == 0 then return "-" end
    local name = C_Item.GetItemInfo(summary.bestItemId)
    -- Remove "Raw -" prefix from best catch name
    if name then
        name = name:gsub("Raw ", "", 1)
    end
    return (name or ("Item " .. summary.bestItemId)) .. " (" .. summary.bestPoints .. ")"
end

local function diffText(mine, theirs)
    local d = mine - theirs
    if d > 0 then return "|cff40ff40+" .. d .. "|r" end
    if d < 0 then return "|cffff4040" .. d .. "|r" end
    return "|cffaaaaaa0|r"
end

local page = CreateFrame("Frame", nil, ns.content)
page:SetAllPoints(ns.content)

local RankingsTab = {}
ns.RankingsTab = RankingsTab

-- Filters are saved with the character; both sources default to shown.
local function filterEnabled(key)
    return BassAmateurShopAddOnDB[key] ~= false
end

local function setFilter(key, value)
    if (key == nil) then return end
    if (key == GUILD_KEY) then
        BassAmateurShopAddOnDB[GUILD_KEY] = value and true or false
    elseif (key == FRIENDS_KEY) then
        BassAmateurShopAddOnDB[FRIENDS_KEY] = value and true or false
    end
end


local function makeFilter(label, key, x)
    local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("TOPLEFT", page, "TOPLEFT", x, 0)
    check.text:SetText(label)
    check:SetScript("OnClick", function(self)
        setFilter(key, self:GetChecked())
        RankingsTab.Refresh()
    end)
    return check
end
local guildCheck = makeFilter("Guildmates", GUILD_KEY, 0)
local friendsCheck = makeFilter("Friends", FRIENDS_KEY, 110)

local function makeHeader(text, x, justify, width)
    local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", x, -FILTER_HEIGHT)
    fs:SetWidth(width)
    fs:SetJustifyH(justify)
    fs:SetText(text)
    return fs
end
makeHeader("#", 4, "LEFT", 24)
makeHeader("Name", 30, "LEFT", 120)
makeHeader("Points", 155, "RIGHT", 60)
makeHeader("Catches", 220, "RIGHT", 55)
makeHeader("Best catch", 285, "LEFT", 130)

local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(FILTER_HEIGHT + 16))
scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, COMPARE_HEIGHT + 4)
local list = CreateFrame("Frame", nil, scroll)
list:SetSize(420, 1)
scroll:SetScrollChild(list)

local statusText = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
statusText:SetPoint("TOP", scroll, "TOP", 0, -30)

local compareText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
compareText:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, 0)
compareText:SetPoint("TOPRIGHT", page, "BOTTOMRIGHT", -4, COMPARE_HEIGHT)
compareText:SetJustifyH("LEFT")
compareText:SetJustifyV("TOP")
compareText:SetSpacing(3)

local compareDivider = page:CreateTexture(nil, "ARTWORK")
compareDivider:SetColorTexture(1, 1, 1, 0.15)
compareDivider:SetHeight(1)
compareDivider:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, COMPARE_HEIGHT + 2)
compareDivider:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, COMPARE_HEIGHT + 2)

local rows, entries, selectedKey = {}, {}, nil

local function updateCompare()
    local entry
    for _, e in ipairs(entries) do
        if e.key == selectedKey then entry = e end
    end
    if not entry then
        compareText:SetText("|cff888888Click an angler to compare your stats with theirs.|r")
        return
    end
    if entry.key == SELF_KEY then
        compareText:SetText("|cff888888That's you! Pick an angler to compare against.|r")
        return
    end
    local me = ns.PeerSync.GetOwnSummary()
    local them = entry.summary
    local lines = {
        "|cffffd100You vs " .. entry.name .. "|r  |cff888888(updated " .. timeAgo(them.received) .. ")|r",
        "Points: " .. me.points .. " vs " .. them.points .. "  " .. diffText(me.points, them.points) ..
            "     Catches: " .. me.catches .. " vs " .. them.catches .. "  " .. diffText(me.catches, them.catches),
    }
    local parts = {}
    for i, rarity in ipairs(ns.RARITY_CHANCES) do
        local mine, theirs = me.rarities[i] or 0, them.rarities[i] or 0
        parts[#parts + 1] = ns.ColorRarity(rarity.name) .. " " .. mine .. " vs " .. theirs
    end
    lines[#lines + 1] = table.concat(parts, "    ", 1, math.min(3, #parts))
    if #parts > 3 then lines[#lines + 1] = table.concat(parts, "    ", 4, #parts) end
    compareText:SetText(table.concat(lines, "\n"))
end

local function sourceText(entry)
    if entry.guild and entry.friend then return "Guild, Friend" end
    if entry.guild then return "Guild" end
    if entry.friend then return "Friend" end
end

local function getRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.18)
    row.selected:Hide()

    local function cell(x, width, justify)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", row, "LEFT", x, 0)
        fs:SetWidth(width)
        fs:SetJustifyH(justify)
        fs:SetWordWrap(false)
        return fs
    end
    row.rank = cell(4, 24, "LEFT")
    row.name = cell(30, 120, "LEFT")
    row.points = cell(155, 60, "RIGHT")
    row.catches = cell(220, 55, "RIGHT")
    row.best = cell(285, 130, "LEFT")

    row:SetScript("OnClick", function(self)
        selectedKey = self.key
        RankingsTab.Refresh()
    end)
    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then return end
        local summary = entry.summary
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(entry.name, 1, 0.82, 0)
        if entry.key ~= SELF_KEY then
            GameTooltip:AddLine(sourceText(entry) .. " - updated " .. timeAgo(summary.received), 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(" ")
        for j, rarity in ipairs(ns.RARITY_CHANCES) do
            GameTooltip:AddDoubleLine(ns.ColorRarity(rarity.name), tostring(summary.rarities[j] or 0), 1, 1, 1, 1, 1, 1)
        end
        if summary.bestItemId > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Best catch: " .. bestCatchName(summary), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

-- Someone who is both a guildmate and a friend appears once, keyed by their short name.
local function addPeers(byName, data, flag)
    for sender, summary in pairs(data) do
        local name = Ambiguate(sender, "guild")
        local entry = byName[name]
        if not entry then
            entry = { key = name, name = name, summary = summary }
            byName[name] = entry
        elseif summary.received > entry.summary.received then
            entry.summary = summary
        end
        entry[flag] = tostring(true)
    end
end

function RankingsTab.Refresh()
    if not page:IsShown() then return end
    local sync = ns.PeerSync
    local showGuild, showFriends = filterEnabled(GUILD_KEY), filterEnabled(FRIENDS_KEY)
    guildCheck:SetChecked(showGuild)
    friendsCheck:SetChecked(showFriends)

    local byName = {}
    local inGuild, hasFriends = IsInGuild(), sync.GetFriendCount() > 0
    if showGuild and inGuild then addPeers(byName, sync.GetGuildData(), "guild") end
    if showFriends and hasFriends then addPeers(byName, sync.GetFriendData(), "friend") end

    wipe(entries)
    local own = sync.GetOwnSummary()
    own.received = time()

    entries[1] = { key = SELF_KEY, name = ns.PlayerFullName(), summary = own }
    for _, entry in pairs(byName) do entries[#entries + 1] = entry end
    table.sort(entries, function(a, b)
        if a.summary.points ~= b.summary.points then return a.summary.points > b.summary.points end
        return a.name < b.name
    end)

    if not showGuild and not showFriends then
        statusText:SetText("|cff888888Select guildmates or friends to see other anglers.|r")
    elseif not (showGuild and inGuild) and not (showFriends and hasFriends) then
        statusText:SetText("|cff888888Join a guild or make a friend to compare your ranking with other anglers.|r")
    elseif not sync.IsSharing() then
        statusText:SetText("|cffffa040Sharing is off. Use /bas share on to exchange stats.|r")
    elseif #entries == 1 then
        statusText:SetText("|cff888888No anglers with the add-on seen yet.|r")
    else
        statusText:SetText("")
    end

    for i, entry in ipairs(entries) do
        local row = getRow(i)
        local isSelf = entry.key == SELF_KEY
        row.key, row.entry = entry.key, entry
        row.rank:SetText(tostring(i))
        row.name:SetText(isSelf and ("|cffffd100" .. entry.name .. " (you)|r") or entry.name)
        row.points:SetText(entry.summary.points)
        row.catches:SetText(entry.summary.catches)
        row.best:SetText(bestCatchName(entry.summary))
        row.selected:SetShown(entry.key == selectedKey)
        row:Show()
    end
    for i = #entries + 1, #rows do rows[i]:Hide() end
    list:SetHeight(math.max(1, #entries * ROW_HEIGHT))

    -- A selected angler may have been filtered out or pruned.
    local found = false
    for _, e in ipairs(entries) do
        if e.key == selectedKey then found = true end
    end
    if not found then selectedKey = nil end
    updateCompare()
end

ns.PeerSync.onUpdate = RankingsTab.Refresh

ns.RegisterTab({
    name = "Rankings",
    icon = "Interface\\Icons\\INV_Misc_Trophy_Argent",
    page = page,
    onSelect = RankingsTab.Refresh,
})
