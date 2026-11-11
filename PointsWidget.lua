local _, ns = ...

-- Small draggable widget to display angler points
local widget = CreateFrame("Frame", "BassAmateurShopAddOnPointsWidget", UIParent)
widget:SetSize(160, 50)
widget:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
widget:EnableMouse(true)
widget:SetMovable(true)
widget:SetUserPlaced(true)
widget:RegisterForDrag("LeftButton")

widget:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

widget:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)

-- Background
local background = widget:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0, 0, 0, 0.7)

local border = widget:CreateTexture(nil, "BORDER")
border:SetAllPoints()
border:SetColorTexture(1, 0.82, 0, 0.3)
border:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)
border:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, 0)
border:SetHeight(2)

local bottomBorder = widget:CreateTexture(nil, "BORDER")
bottomBorder:SetAllPoints()
bottomBorder:SetColorTexture(1, 0.82, 0, 0.3)
bottomBorder:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 0, 0)
bottomBorder:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 0, 0)
bottomBorder:SetHeight(2)

-- Label
local label = widget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("TOPLEFT", widget, "TOPLEFT", 6, -4)
label:SetText("ANGLER POINTS™")

-- Points display
local pointsDisplay = widget:CreateFontString(nil, "OVERLAY")
pointsDisplay:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
pointsDisplay:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -6, 4)
pointsDisplay:SetShadowOffset(1, -1)
pointsDisplay:SetTextColor(1, 0.82, 0)
pointsDisplay:SetText("0")

-- Catch count display
local catchCountDisplay = widget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
catchCountDisplay:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 6, 6)
catchCountDisplay:SetTextColor(0.8, 0.8, 0.8)
catchCountDisplay:SetText("0 catches")

widget:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

widget:Hide()

function ns.UpdatePointsWidget(points, catchCount)
    pointsDisplay:SetText(tostring(points))
    if catchCount then
        catchCountDisplay:SetText(tostring(catchCount) .. " catch" .. (catchCount == 1 and "" or "es"))
    end
end

function ns.ShowPointsWidget(show)
    if show then
        widget:Show()
    else
        widget:Hide()
    end
end

function ns.GetPointsWidgetVisible()
    return widget:IsShown()
end

ns.PointsWidget = widget
