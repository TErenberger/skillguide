local addonName, ns = ...

local optionsCategory
local compartmentRegistered = false

local STRATA_ORDER = {
    "BACKGROUND",
    "LOW",
    "MEDIUM",
    "HIGH",
    "DIALOG",
    "FULLSCREEN",
    "FULLSCREEN_DIALOG",
    "TOOLTIP",
}

local function ClampScale(value)
    value = tonumber(value) or 1
    if value < 0.6 then
        return 0.6
    end
    if value > 1.6 then
        return 1.6
    end
    return math.floor(value * 100 + 0.5) / 100
end

function ns.OpenOptions()
    if Settings and Settings.OpenToCategory and optionsCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
        return true
    end
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("SkillGuide Forever")
        return true
    end
    print("|cff71d5ffSkillGuide Forever|r: Options are available in Esc → Options → AddOns.")
    return false
end

local function RegisterAddonCompartment()
    if compartmentRegistered then
        return
    end
    if not ns.db or not ns.db.addonCompartment then
        return
    end

    -- Prefer TOC-driven registration; also support manual API when available.
    if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
        AddonCompartmentFrame:RegisterAddon({
            text = "SkillGuide Forever",
            icon = "Interface\\Icons\\INV_Misc_Book_09",
            notCheckable = true,
            func = function()
                if ns.ToggleMainFrame then
                    ns.ToggleMainFrame()
                end
            end,
            funcOnEnter = function(button)
                if not GameTooltip then
                    return
                end
                GameTooltip:SetOwner(button, "ANCHOR_LEFT")
                GameTooltip:SetText("SkillGuide Forever")
                GameTooltip:AddLine("Left-click: class skills (/sg)", 1, 1, 1)
                GameTooltip:AddLine("Use /pg for professions", 0.8, 0.8, 0.8)
                GameTooltip:AddLine("Use /sg config for settings", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end,
            funcOnLeave = function()
                if GameTooltip then
                    GameTooltip:Hide()
                end
            end,
        })
        compartmentRegistered = true
    end
end

-- Global for ## AddonCompartmentFunc TOC metadata (modern clients).
function SkillGuideForever_OnAddonCompartmentClick()
    if ns.ToggleMainFrame then
        ns.ToggleMainFrame()
    end
end

function SkillGuideForever_OnAddonCompartmentEnter(addonNameArg, button)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("SkillGuide Forever")
    GameTooltip:AddLine("/sg class skills  ·  /pg professions", 1, 1, 1)
    GameTooltip:AddLine("/sg config for settings", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function SkillGuideForever_OnAddonCompartmentLeave()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function RegisterSettingsPanel()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then
        return
    end
    if optionsCategory then
        return
    end

    ns.EnsureIntegrationDefaults()

    local category, layout = Settings.RegisterVerticalLayoutCategory("SkillGuide Forever")
    optionsCategory = category

    -- Built-in / test skins (same SkillGuideForeverAPI callback path as ElvUI)
    if Settings.CreateDropdown and Settings.CreateControlTextContainer and ns.GetBuiltInSkinOptions then
        pcall(function()
            local setting = Settings.RegisterAddOnSetting(
                category,
                "SkillGuideForever_builtInSkin",
                "builtInSkin",
                ns.db,
                Settings.VarType.String,
                "Window skin",
                "blizzard"
            )
            if setting.SetValueChangedCallback then
                setting:SetValueChangedCallback(function(_, value)
                    if ns.SetBuiltInSkin then
                        ns.SetBuiltInSkin(value)
                    else
                        ns.NotifyOptionsChanged("builtInSkin", value)
                    end
                end)
            end
            local order, labels = ns.GetBuiltInSkinOptions()
            local function getOptions()
                local container = Settings.CreateControlTextContainer()
                for _, key in ipairs(order) do
                    container:Add(key, labels[key] or key)
                end
                return container:GetData()
            end
            Settings.CreateDropdown(
                category,
                setting,
                getOptions,
                "Built-in skins register through SkillGuideForeverAPI just like ElvUI / AddOnSkins, so you can test that path without installing them."
            )
        end)
    end

    -- External skinning
    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "SkillGuideForever_allowExternalSkins",
            "allowExternalSkins",
            ns.db,
            Settings.VarType.Boolean,
            "Allow external skins",
            true
        )
        if setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(function(_, value)
                ns.NotifyOptionsChanged("allowExternalSkins", value)
                if ns.InitBuiltInSkins then
                    ns.InitBuiltInSkins()
                end
            end)
        end
        Settings.CreateCheckbox(
            category,
            setting,
            "Let ElvUI, AddOnSkins, and similar addons restyle SkillGuide windows via the public skin API. Also required for built-in test skins."
        )
    end

    -- Addon compartment
    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "SkillGuideForever_addonCompartment",
            "addonCompartment",
            ns.db,
            Settings.VarType.Boolean,
            "Show in Addon Compartment",
            true
        )
        if setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(function(_, value)
                ns.NotifyOptionsChanged("addonCompartment", value)
                if value then
                    RegisterAddonCompartment()
                end
            end)
        end
        Settings.CreateCheckbox(
            category,
            setting,
            "List SkillGuide Forever in the character-select Addon Compartment menu (when the client supports it)."
        )
    end

    -- Window scale (guarded: slider helpers vary slightly by client build)
    if Settings.CreateSlider and Settings.CreateSliderOptions then
        local ok = pcall(function()
            local setting = Settings.RegisterAddOnSetting(
                category,
                "SkillGuideForever_windowScale",
                "windowScale",
                ns.db,
                Settings.VarType.Number,
                "Window scale",
                1
            )
            if setting.SetValueChangedCallback then
                setting:SetValueChangedCallback(function(_, value)
                    local clamped = ClampScale(value)
                    if ns.db.windowScale ~= clamped then
                        ns.db.windowScale = clamped
                    end
                    ns.NotifyOptionsChanged("windowScale", clamped)
                end)
            end
            local options = Settings.CreateSliderOptions(0.6, 1.6, 0.05)
            if options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
                    return string.format("%.0f%%", value * 100)
                end)
            end
            Settings.CreateSlider(
                category,
                setting,
                options,
                "Scale both SkillGuide windows. Useful when using UI scale packs."
            )
        end)
        if not ok then
            -- Slider unavailable on this build; scale still adjustable via SavedVariables.
        end
    end

    -- Frame strata
    if Settings.CreateDropdown and Settings.CreateControlTextContainer then
        pcall(function()
            local setting = Settings.RegisterAddOnSetting(
                category,
                "SkillGuideForever_frameStrata",
                "frameStrata",
                ns.db,
                Settings.VarType.String,
                "Frame strata",
                "HIGH"
            )
            if setting.SetValueChangedCallback then
                setting:SetValueChangedCallback(function(_, value)
                    ns.NotifyOptionsChanged("frameStrata", value)
                end)
            end
            local function getOptions()
                local container = Settings.CreateControlTextContainer()
                for _, name in ipairs(STRATA_ORDER) do
                    container:Add(name, name)
                end
                return container:GetData()
            end
            Settings.CreateDropdown(
                category,
                setting,
                getOptions,
                "Controls whether SkillGuide draws above or below other addon windows."
            )
        end)
    end

    Settings.RegisterAddOnCategory(category)
end

function ns.InitOptions()
    ns.EnsureIntegrationDefaults()
    if ns.InitBuiltInSkins then
        ns.InitBuiltInSkins()
    end
    RegisterSettingsPanel()
    RegisterAddonCompartment()
end
