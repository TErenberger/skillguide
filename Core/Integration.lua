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
    -- Docked side panes hide the portrait; never reserve its gutter (skins may
    -- call this with true on show — attached layout wins).
    if frame.sgfAttached then
        needClearance = false
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

    -- Profession dropdown is absolutely placed; tighten its pull-left when skinned/attached.
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

    if frame.SGFLayoutToolbar then
        frame.SGFLayoutToolbar()
    end
end

local function ForceShow(obj)
    if obj and obj.Show then
        obj:Show()
    end
end

local function ForceHide(obj)
    if obj and obj.Hide then
        obj:Hide()
    end
end

--- Compact side-pane chrome when docked to Blizzard spellbook / craft UI:
--- hide the duplicate portrait circle and use the full top for toolbar controls.
function ns.ApplyAttachedPaneLayout(frame)
    if not frame then
        return
    end
    local state = frame.sgfAttachedChrome
    if not state then
        state = {}
        frame.sgfAttachedChrome = state
    end

    if state.prevClearance == nil then
        state.prevClearance = frame.SGFPortraitClearance ~= false
    end

    -- Official ButtonFrameTemplate helper removes the portrait *and* the ring.
    if ButtonFrameTemplate_HidePortrait then
        state.usedTemplateHidePortrait = true
        pcall(ButtonFrameTemplate_HidePortrait, frame)
    end

    -- Force-hide leftovers the template helper misses (extra ring children/regions).
    -- Do not snapshot IsShown() after HidePortrait — that records "false" and would
    -- re-hide the chrome on restore after ButtonFrameTemplate_ShowPortrait.
    local portrait = frame.PortraitContainer
    if portrait then
        ForceHide(portrait)
        ForceHide(portrait.portrait)
        ForceHide(portrait.Portrait)
        ForceHide(portrait.CircleMask)
        if portrait.GetChildren then
            local kids = { portrait:GetChildren() }
            for i = 1, #kids do
                ForceHide(kids[i])
            end
        end
        if portrait.GetRegions then
            local regions = { portrait:GetRegions() }
            for i = 1, #regions do
                ForceHide(regions[i])
            end
        end
    end
    ForceHide(frame.portrait)
    ForceHide(frame.PortraitFrame)
    local frameName = frame.GetName and frame:GetName()
    if frameName then
        ForceHide(_G[frameName .. "PortraitFrame"])
        ForceHide(_G[frameName .. "Portrait"])
    end

    if ns.SetPortraitClearance then
        ns.SetPortraitClearance(frame, false)
    end
end

function ns.RestoreAttachedPaneLayout(frame)
    if not frame then
        return
    end
    local state = frame.sgfAttachedChrome
    local prevClearance = true
    if state then
        prevClearance = state.prevClearance ~= false
        if state.usedTemplateHidePortrait and ButtonFrameTemplate_ShowPortrait then
            pcall(ButtonFrameTemplate_ShowPortrait, frame)
        end
        -- Always put standalone portrait chrome back; UpdatePortrait paints the icon.
        local portrait = frame.PortraitContainer
        if portrait then
            ForceShow(portrait)
            ForceShow(portrait.portrait)
            ForceShow(portrait.Portrait)
            ForceShow(portrait.CircleMask)
            if portrait.GetChildren then
                local kids = { portrait:GetChildren() }
                for i = 1, #kids do
                    ForceShow(kids[i])
                end
            end
            if portrait.GetRegions then
                local regions = { portrait:GetRegions() }
                for i = 1, #regions do
                    ForceShow(regions[i])
                end
            end
        end
        ForceShow(frame.portrait)
        ForceShow(frame.PortraitFrame)
        local frameName = frame.GetName and frame:GetName()
        if frameName then
            ForceShow(_G[frameName .. "PortraitFrame"])
            ForceShow(_G[frameName .. "Portrait"])
        end
        frame.sgfAttachedChrome = nil
    end

    if ns.SetPortraitClearance then
        ns.SetPortraitClearance(frame, prevClearance)
    end
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
