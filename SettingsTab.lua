local _, ns = ...

local page = CreateFrame("Frame", nil, ns.content)
page:SetAllPoints(ns.content)

local rarities = ns.RARITY_CHANCES

-- Rarity slider; labelPrefix is followed by the colored rarity name.
local function CreateRaritySlider(name, y, labelPrefix, dbKey, getter)
    local slider = CreateFrame("Slider", name, page, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", page, "TOPLEFT", 4, y)
    slider:SetWidth(260)
    slider:SetMinMaxValues(1, #rarities)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText(rarities[1].name)
    slider.High:SetText(rarities[#rarities].name)
    slider.Text:ClearAllPoints()
    slider.Text:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 6)
    local function UpdateLabel(index)
        slider.Text:SetText(labelPrefix .. ns.ColorRarity(rarities[index].name))
    end
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        UpdateLabel(value)
        BassAmateurShopAddOnDB[dbKey] = value
    end)
    function slider.Refresh()
        slider:SetValue(getter())
        UpdateLabel(getter())
    end
    return slider
end

local bannerSlider = CreateRaritySlider("BassAmateurShopAddOnBannerRaritySlider", -16,
    "Show banner for catches of this rarity or better: ", "bannerMinRarity", ns.GetBannerMinRarity)

local announceCheck = CreateFrame("CheckButton", "BassAmateurShopAddOnAnnounceCheck", page, "UICheckButtonTemplate")
announceCheck:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -64)
announceCheck.text:SetText("Announce achievements in guild chat")
announceCheck:SetScript("OnClick", function(self)
    BassAmateurShopAddOnDB.announceGuild = self:GetChecked() and true or false
end)

local announceNote = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
announceNote:SetPoint("TOPLEFT", announceCheck, "BOTTOMLEFT", 4, 0)
announceNote:SetWidth(440)
announceNote:SetJustifyH("LEFT")

local announceSlider = CreateRaritySlider("BassAmateurShopAddOnAnnounceRaritySlider", -150,
    "Announce catches of this rarity or better: ", "announceMinRarity", ns.GetAnnounceMinRarity)

local function RefreshAnnounceNote()
    if not IsInGuild() then
        announceNote:SetText("|cff888888You are not in a guild.|r")
    elseif ns.AnnouncingEnabled() then
        announceNote:SetText("|cff40ff40Active.|r")
    else
        announceNote:SetText("|cffff8000Inactive until your guild's Info text contains [BAS] (set by an officer) and this is checked.|r")
    end
end

ns.RegisterTab({
    name = "Settings",
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    page = page,
    onSelect = function()
        bannerSlider.Refresh()
        announceSlider.Refresh()
        announceCheck:SetChecked(BassAmateurShopAddOnDB.announceGuild == true)
        RefreshAnnounceNote()
    end,
})
