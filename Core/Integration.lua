local addonName, ns = ...

-- Lightweight callback registry (no LibStub / Ace dependency).
-- Skin addons (ElvUI_AddOnSkins, etc.) and other tools can subscribe here.
local listeners = {}

local VALID_STRATA = {
    BACKGROUND = true,
    LOW = true,
    MEDIUM = true,
    HIGH = true,
    DIALOG = true,
    FULLSCREEN = true,
    FULLSCREEN_DIALOG = true,
    TOOLTIP = true,
}

function ns.EnsureIntegrationDefaults()
    local db = ns.db
    if not db then
        return
    end
    if db.allowExternalSkins == nil then
        db.allowExternalSkins = true
    end
    if db.windowScale == nil then
        db.windowScale = 1
    end
    if type(db.windowScale) ~= "number" or db.windowScale < 0.6 or db.windowScale > 1.6 then
        db.windowScale = 1
    end
    if db.frameStrata == nil or not VALID_STRATA[db.frameStrata] then
        db.frameStrata = "HIGH"
    end
    if db.addonCompartment == nil then
        db.addonCompartment = true
    end
    if db.builtInSkin == nil then
        db.builtInSkin = "blizzard"
    end
    if db.spellbookPane == nil then
        db.spellbookPane = true
    end
    if db.professionsBookPane == nil then
        db.professionsBookPane = true
    end
end

function ns.ShouldFireSkinEvents()
    if not ns.db then
        return false
    end
    if ns.db.allowExternalSkins then
        return true
    end
    -- Built-in test skins use the same callback bus as ElvUI / AddOnSkins.
    local skin = ns.db.builtInSkin
    return skin ~= nil and skin ~= "blizzard"
end

function ns.RegisterCallback(event, callback, owner)
    if type(event) ~= "string" or event == "" or type(callback) ~= "function" then
        return false
    end
    local list = listeners[event]
    if not list then
        list = {}
        listeners[event] = list
    end
    list[#list + 1] = { fn = callback, owner = owner }
    return true
end

function ns.UnregisterCallback(event, callback, owner)
    local list = listeners[event]
    if not list then
        return
    end
    for i = #list, 1, -1 do
        local entry = list[i]
        if entry.fn == callback and (owner == nil or entry.owner == owner) then
            table.remove(list, i)
        end
    end
end

function ns.FireCallback(event, ...)
    local list = listeners[event]
    if not list then
        return
    end
    for i = 1, #list do
        local entry = list[i]
        local ok, err = pcall(entry.fn, entry.owner, event, ...)
        if not ok then
            -- Keep other listeners alive if one skin errors.
            geterrorhandler()(err)
        end
    end
end

function ns.ApplyFrameAppearance(frame)
    if not frame or not ns.db then
        return
    end
    local scale = ns.db.windowScale or 1
    if type(scale) == "number" then
        frame:SetScale(scale)
    end
    local strata = ns.db.frameStrata or "HIGH"
    if VALID_STRATA[strata] then
        frame:SetFrameStrata(strata)
    end
end

--- Shift toolbar/search into the portrait gap when alt skins hide the icon.
--- needClearance=true keeps the Blizzard portrait margin; false uses the full width.
function ns.SetPortraitClearance(frame, needClearance)
    if not frame then
        return
    end
    local layout = frame.SGFLayout
    local widgets = frame.SkillGuideForeverWidgets or {}
    local toolbar = widgets.toolbar or frame.toolbar
    local inset = widgets.inset or frame.Inset or frame.inset
    local scroll = widgets.scrollFrame
    if not layout or not toolbar then
        return
    end

    local left = needClearance and layout.toolbarLeftPortrait or layout.toolbarLeftSkinned
    toolbar:ClearAllPoints()
    if layout.hasInset and inset then
        toolbar:SetPoint("TOPLEFT", inset, "TOPLEFT", left, layout.toolbarTop or -4)
        toolbar:SetPoint("TOPRIGHT", inset, "TOPRIGHT", layout.toolbarRight or -8, layout.toolbarTop or -4)
    else
        toolbar:SetPoint("TOPLEFT", left + 4, -60)
        toolbar:SetPoint("TOPRIGHT", -12, -60)
    end

    if scroll then
        scroll:ClearAllPoints()
        if layout.hasInset and inset then
            scroll:SetPoint(
                "TOPLEFT",
                toolbar,
                "BOTTOMLEFT",
                (layout.listInset or 12) - left,
                layout.scrollGap or -6
            )
            scroll:SetPoint(
                "BOTTOMRIGHT",
                inset,
                "BOTTOMRIGHT",
                layout.scrollRight or -28,
                layout.scrollBottom or 12
            )
        else
            scroll:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", -36, -6)
            scroll:SetPoint("BOTTOMRIGHT", -36, 20)
        end
    end

    -- Profession dropdown is absolutely placed; tighten its pull-left when skinned.
    local dropdown = widgets.dropdown
    if dropdown and layout.dropdownUsesToolbarAnchor then
        dropdown:ClearAllPoints()
        dropdown:SetPoint(
            "TOPLEFT",
            toolbar,
            "TOPLEFT",
            needClearance and (layout.dropdownLeftPortrait or -16) or (layout.dropdownLeftSkinned or -4),
            layout.dropdownTop or -2
        )
    end

    frame.SGFPortraitClearance = needClearance and true or false
end

function ns.NotifyOptionsChanged(key, value)
    ns.FireCallback("OptionsChanged", key, value)
    if key == "windowScale" or key == "frameStrata" or key == nil then
        local main = _G.SkillGuideForeverFrame
        local prof = _G.SkillGuideForeverProfessionFrame
        if main then
            ns.ApplyFrameAppearance(main)
        end
        if prof then
            ns.ApplyFrameAppearance(prof)
        end
    end
    if key == "allowExternalSkins" or key == "builtInSkin" or key == nil then
        if ns.ShouldFireSkinEvents() then
            ns.RequestSkinRefresh()
        end
    end
end

function ns.RequestSkinRefresh()
    if not ns.ShouldFireSkinEvents() then
        return
    end
    local main = _G.SkillGuideForeverFrame
    local prof = _G.SkillGuideForeverProfessionFrame
    if main then
        ns.FireCallback("SkinRefresh", main, "main")
    end
    if prof then
        ns.FireCallback("SkinRefresh", prof, "profession")
    end
end

function ns.NotifyFrameCreated(kind, frame, widgets)
    if not frame then
        return
    end
    frame.SkillGuideForeverKind = kind
    frame.SkillGuideForeverWidgets = widgets or frame.SkillGuideForeverWidgets
    ns.ApplyFrameAppearance(frame)
    if ns.ShouldFireSkinEvents() then
        if kind == "main" then
            ns.FireCallback("MainFrameCreated", frame, widgets)
        elseif kind == "profession" then
            ns.FireCallback("ProfessionFrameCreated", frame, widgets)
        end
        ns.FireCallback("FrameCreated", frame, kind, widgets)
    end
end

function ns.NotifyFrameShow(kind, frame)
    if not frame then
        return
    end
    ns.ApplyFrameAppearance(frame)
    if ns.ShouldFireSkinEvents() then
        if kind == "main" then
            ns.FireCallback("MainFrameShow", frame)
        elseif kind == "profession" then
            ns.FireCallback("ProfessionFrameShow", frame)
        end
        ns.FireCallback("FrameShow", frame, kind)
    end
end

function ns.NotifyFrameHide(kind, frame)
    if not frame then
        return
    end
    if ns.ShouldFireSkinEvents() then
        if kind == "main" then
            ns.FireCallback("MainFrameHide", frame)
        elseif kind == "profession" then
            ns.FireCallback("ProfessionFrameHide", frame)
        end
        ns.FireCallback("FrameHide", frame, kind)
    end
end

-- Public global for other addons (stable name, no LibStub required).
SkillGuideForeverAPI = SkillGuideForeverAPI or {}
local api = SkillGuideForeverAPI

api.RegisterCallback = function(_, event, callback, owner)
    return ns.RegisterCallback(event, callback, owner)
end

api.UnregisterCallback = function(_, event, callback, owner)
    ns.UnregisterCallback(event, callback, owner)
end

api.GetMainFrame = function()
    return _G.SkillGuideForeverFrame
end

api.GetProfessionFrame = function()
    return _G.SkillGuideForeverProfessionFrame
end

api.GetFrames = function()
    return {
        main = _G.SkillGuideForeverFrame,
        profession = _G.SkillGuideForeverProfessionFrame,
    }
end

api.GetVersion = function()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, "Version")
    end
    if GetAddOnMetadata then
        return GetAddOnMetadata(addonName, "Version")
    end
    return nil
end

api.OpenOptions = function()
    if ns.OpenOptions then
        ns.OpenOptions()
    end
end

api.RefreshSkins = function()
    ns.RequestSkinRefresh()
end

api.IsExternalSkinningEnabled = function()
    return ns.ShouldFireSkinEvents and ns.ShouldFireSkinEvents() or false
end

api.GetBuiltInSkin = function()
    return ns.db and ns.db.builtInSkin or "blizzard"
end
