local _, ns = ...

local FADE_IN, HOLD, FADE_OUT = 0.4, 2.5, 1.0
local TOTAL = FADE_IN + HOLD + FADE_OUT

local banner = CreateFrame("Frame", "BassAmateurShopAddOnBanner", UIParent)
banner:SetSize(460, 90)
banner:SetPoint("TOP", UIParent, "TOP", 0, -240)
banner:SetFrameStrata("FULLSCREEN_DIALOG")
banner:EnableMouse(false)
banner:SetAlpha(0)
banner:Hide()

local background = banner:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0, 0, 0, 0.6)

local topBar = banner:CreateTexture(nil, "BORDER")
topBar:SetPoint("TOPLEFT")
topBar:SetPoint("TOPRIGHT")
topBar:SetHeight(3)

local bottomBar = banner:CreateTexture(nil, "BORDER")
bottomBar:SetPoint("BOTTOMLEFT")
bottomBar:SetPoint("BOTTOMRIGHT")
bottomBar:SetHeight(3)

local heading = banner:CreateFontString(nil, "OVERLAY")
heading:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE")
heading:SetPoint("TOP", banner, "TOP", 0, -16)

local subtext = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
subtext:SetPoint("TOP", heading, "BOTTOM", 0, -8)

local elapsedTime = 0
banner:SetScript("OnUpdate", function(self, elapsed)
    elapsedTime = elapsedTime + elapsed
    if elapsedTime >= TOTAL then
        self:Hide()
        return
    end
    if elapsedTime < FADE_IN then
        self:SetAlpha(elapsedTime / FADE_IN)
    elseif elapsedTime < FADE_IN + HOLD then
        self:SetAlpha(1)
    else
        self:SetAlpha(1 - (elapsedTime - FADE_IN - HOLD) / FADE_OUT)
    end
end)

-- Shows the banner; a new call replaces any banner already on screen.
-- color is an "rrggbb" hex string.
function ns.ShowBanner(headingText, subText, color)
    local r = tonumber(color:sub(1, 2), 16) / 255
    local g = tonumber(color:sub(3, 4), 16) / 255
    local b = tonumber(color:sub(5, 6), 16) / 255
    topBar:SetColorTexture(r, g, b, 1)
    bottomBar:SetColorTexture(r, g, b, 1)
    heading:SetTextColor(r, g, b)
    heading:SetText(headingText)
    subtext:SetText(subText or "")
    elapsedTime = 0
    banner:SetAlpha(0)
    banner:Show()
end
