local _, ns = ...

local MAX_LOG_LINES = 500
local ColorRarity = ns.ColorRarity

local catchLog = CreateFrame("ScrollingMessageFrame", nil, ns.content)
catchLog:SetAllPoints(ns.content)
catchLog:SetFontObject(GameFontHighlight)
catchLog:SetJustifyH("LEFT")
catchLog:SetFading(false)
catchLog:SetMaxLines(MAX_LOG_LINES)
catchLog:EnableMouseWheel(true)
catchLog:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
end)

catchLog:SetHyperlinksEnabled(true)

-- Nested hyperlinks aren't allowed, so each entry gets a custom link that points at its saved catch.
catchLog:SetScript("OnHyperlinkEnter", function(self, linkData)
    local index = tonumber(linkData:match("^bascatch:(%d+)$"))
    local catch = index and BassAmateurShopAddOnDB.catches[index]
    if not catch then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(catch.link)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Catch Record", 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Rarity:", ColorRarity(catch.rarity))
    GameTooltip:AddDoubleLine("Points:", tostring(catch.points or 0), 1, 1, 1, 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Quantity:", tostring(catch.quantity or 1), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Zone:", catch.zone or "Unknown", 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Caught:", tostring(date("%Y-%m-%d %H:%M:%S", catch.time)), 1, 1, 1, 1, 1, 1)
    GameTooltip:Show()
end)
catchLog:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)

local CatchLog = {}
ns.CatchLog = CatchLog

function CatchLog.AddCatch(catch, index)
    local color = catch.link:match("|c(%x%x%x%x%x%x%x%x)") or "ffffffff"
    local name = catch.name or catch.link:match("%[(.-)%]") or "Unknown"
    local itemText = "|c" .. color .. "|Hbascatch:" .. index .. "|h[" .. name .. "]|h|r"
    catchLog:AddMessage(date("%H:%M:%S", catch.time) .. "  " .. itemText ..
        " x" .. (catch.quantity or 1) .. "  [" .. ColorRarity(catch.rarity) .. "]" ..
        (catch.points and ("  " .. catch.points .. " pts") or ""))
end

function CatchLog.Clear()
    catchLog:Clear()
end

function CatchLog.Load()
    catchLog:Clear()
    local catches = BassAmateurShopAddOnDB.catches
    -- Only the newest entries fit in the log; keep each catch's real index for its tooltip link.
    for index = math.max(1, #catches - MAX_LOG_LINES + 1), #catches do
        CatchLog.AddCatch(catches[index], index)
    end
end

ns.RegisterTab({
    name = "Catch Log",
    icon = "Interface\\Icons\\INV_Misc_Fish_02",
    page = catchLog,
})
