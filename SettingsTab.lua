local _, ns = ...

local page = CreateFrame("Frame", nil, ns.content)
page:SetAllPoints(ns.content)

local rarities = ns.RARITY_CHANCES

local slider = CreateFrame("Slider", "BassAmateurShopAddOnBannerRaritySlider", page, "OptionsSliderTemplate")
slider:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -16)
slider:SetWidth(260)
slider:SetMinMaxValues(1, #rarities)
slider:SetValueStep(1)
slider:SetObeyStepOnDrag(true)
slider.Low:SetText(rarities[1].name)
slider.High:SetText(rarities[#rarities].name)

local function UpdateLabel(index)
    slider.Text:SetText("Show banner for catches of this rarity or better: " .. ns.ColorRarity(rarities[index].name))
end
slider.Text:ClearAllPoints()
slider.Text:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 6)

slider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value + 0.5)
    UpdateLabel(value)
    BassAmateurShopAddOnDB.bannerMinRarity = value
end)

ns.RegisterTab({
    name = "Settings",
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    page = page,
    onSelect = function()
        slider:SetValue(ns.GetBannerMinRarity())
        UpdateLabel(ns.GetBannerMinRarity())
    end,
})
