local addonName, ns = ...

-- Profession SkillGuide integration for craft UIs (TradeSkill / ProfessionsFrame).
-- Attaches the recipe pane beside craft windows when those UIs are shown.

local hookedHosts = {}
local wantAttached = false
local watcher
local button
local movedTabs = {}
local eventFrame

local function IsEnabled()
    return ns.db and ns.db.professionsBookPane ~= false
end

local function IsFrame(value)
    return type(value) == "table" and value.GetObjectType and pcall(value.GetObjectType, value)
end

local function TryLoadCraftUI()
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_Professions")
        pcall(C_AddOns.LoadAddOn, "Blizzard_ProfessionsBook")
        pcall(C_AddOns.LoadAddOn, "Blizzard_TradeSkillUI")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_Professions")
        pcall(LoadAddOn, "Blizzard_ProfessionsBook")
        pcall(LoadAddOn, "Blizzard_TradeSkillUI")
    end
end

local function ResolveHostFrame()
    TryLoadCraftUI()

    -- Prefer a currently shown craft / professions UI.
    local named = {
        _G.ProfessionsFrame,
        _G.TradeSkillFrame,
        _G.ProfessionsBookFrame,
        _G.CraftFrame,
    }
    for i = 1, #named do
        local frame = named[i]
        if IsFrame(frame) and frame:IsShown() then
            return frame
        end
    end
    for i = 1, #named do
        if IsFrame(named[i]) then
            return named[i]
        end
    end
    return nil
end

local function CaptureAnchor(frame)
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    return {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x,
        y = y,
        parent = frame:GetParent(),
    }
end

local function RestoreAnchor(frame, anchor)
    if not frame or not anchor then
        return
    end
    frame:ClearAllPoints()
    if anchor.parent then
        frame:SetParent(anchor.parent)
    end
    if anchor.point and anchor.relativeTo and anchor.relativePoint then
        frame:SetPoint(anchor.point, anchor.relativeTo, anchor.relativePoint, anchor.x or 0, anchor.y or 0)
    elseif anchor.point then
        frame:SetPoint(anchor.point, anchor.x or 0, anchor.y or 0)
    end
end

local function IsSideTabSize(frame)
    local w = frame.GetWidth and frame:GetWidth() or 0
    local h = frame.GetHeight and frame:GetHeight() or 0
    return w >= 20 and w <= 48 and h >= 20 and h <= 48
end

local function IsAnchoredToHostRight(frame, host)
    if not frame.GetPoint then
        return false
    end
    local point, relativeTo, relativePoint = frame:GetPoint(1)
    if relativeTo ~= host then
        return false
    end
    return relativePoint == "TOPRIGHT"
        or relativePoint == "RIGHT"
        or relativePoint == "BOTTOMRIGHT"
        or (point == "TOPLEFT" and relativePoint == "TOPRIGHT")
        or (point == "LEFT" and relativePoint == "RIGHT")
end

local function FindSideTabs(host)
    local tabs = {}
    local seen = {}

    local function consider(tab)
        if not IsFrame(tab) or seen[tab] then
            return
        end
        if not IsSideTabSize(tab) then
            return
        end
        local parent = tab.GetParent and tab:GetParent()
        local belongs = parent == host or IsAnchoredToHostRight(tab, host)
        if not belongs and tab.sgfOrigAnchor then
            belongs = tab.sgfOrigAnchor.parent == host or tab.sgfOrigAnchor.relativeTo == host
        end
        if not belongs then
            return
        end
        seen[tab] = true
        tabs[#tabs + 1] = tab
    end

    for i = 1, 16 do
        consider(_G["SpellBookSkillLineTab" .. i])
        consider(_G["ProfessionsBookSkillLineTab" .. i])
        consider(_G["ProfessionSkillLineTab" .. i])
        consider(_G["TradeSkillFrameTab" .. i])
    end

    if host.GetChildren then
        local kids = { host:GetChildren() }
        for i = 1, #kids do
            local child = kids[i]
            if IsFrame(child) then
                local objType = child:GetObjectType()
                if (objType == "CheckButton" or objType == "Button") and IsSideTabSize(child) then
                    local name = child.GetName and child:GetName() or ""
                    local lower = string.lower(name or "")
                    if not string.find(lower, "close", 1, true)
                        and not string.find(lower, "help", 1, true)
                        and (
                            IsAnchoredToHostRight(child, host)
                            or string.find(lower, "skillline", 1, true)
                            or string.find(lower, "tab", 1, true)
                        )
                    then
                        consider(child)
                    end
                end
            end
        end
    end

    table.sort(tabs, function(a, b)
        local _, _, _, _, ay = a:GetPoint(1)
        local _, _, _, _, by = b:GetPoint(1)
        return (ay or 0) > (by or 0)
    end)

    return tabs
end

function ns.RestoreProfessionSideTabs()
    for i = 1, #movedTabs do
        local tab = movedTabs[i]
        if IsFrame(tab) and tab.sgfOrigAnchor then
            RestoreAnchor(tab, tab.sgfOrigAnchor)
            tab.sgfMovedToSkillGuide = nil
        end
    end
    wipe(movedTabs)
end

local function MoveSideTabsToPane(host, pane)
    ns.RestoreProfessionSideTabs()
    if not IsFrame(host) or not IsFrame(pane) then
        return
    end

    local tabs = FindSideTabs(host)
    local tabSet = {}
    for i = 1, #tabs do
        tabSet[tabs[i]] = true
    end

    for i = 1, #tabs do
        local tab = tabs[i]
        if not tab.sgfOrigAnchor then
            tab.sgfOrigAnchor = CaptureAnchor(tab)
        end

        local anchor = tab.sgfOrigAnchor
        local rel = anchor.relativeTo
        local anchoredToSibling = rel and tabSet[rel] and rel ~= host

        if not anchoredToSibling then
            tab:ClearAllPoints()
            tab:SetPoint(
                anchor.point or "TOPLEFT",
                pane,
                anchor.relativePoint or "TOPRIGHT",
                anchor.x or 0,
                anchor.y or -36
            )
            if pane.GetFrameLevel then
                tab:SetFrameLevel(pane:GetFrameLevel() + 10)
            end
            tab.sgfMovedToSkillGuide = true
            movedTabs[#movedTabs + 1] = tab
        else
            movedTabs[#movedTabs + 1] = tab
        end
    end
end

local function UpdateButtonState()
    if not button then
        return
    end
    local attached = ns.IsProfessionFrameAttached and ns.IsProfessionFrameAttached()
    if button.SetText then
        button:SetText(attached and "Hide" or "SkillGuide")
    end
end

local function HideAttachedPane()
    ns.RestoreProfessionSideTabs()
    if ns.IsProfessionFrameAttached and ns.IsProfessionFrameAttached() and ns.DetachProfessionFrame then
        ns.DetachProfessionFrame(true)
    end
end

local function ShowAttachedPane(host)
    if not host or not IsEnabled() then
        return
    end
    if ns.IsMainFrameAttached and ns.IsMainFrameAttached() and ns.DetachMainFrame then
        ns.DetachMainFrame(true)
    end
    if ns.AttachProfessionFrameTo then
        ns.AttachProfessionFrameTo(host)
    end
    local pane = ns.GetProfessionFrame and ns.GetProfessionFrame()
    if pane then
        MoveSideTabsToPane(host, pane)
    end
end

local function OnButtonClick()
    local host = button and button.sgfHost
    if not host or not IsEnabled() then
        return
    end
    if ns.IsProfessionFrameAttached and ns.IsProfessionFrameAttached() then
        wantAttached = false
        HideAttachedPane()
    else
        wantAttached = true
        ShowAttachedPane(host)
    end
    UpdateButtonState()
end

local function CreateToggleButton(parent)
    local created
    local ok = pcall(function()
        created = CreateFrame("Button", "SkillGuideForeverCraftUIButton", parent, "UIPanelButtonTemplate")
    end)
    if not ok or not created then
        created = CreateFrame("Button", "SkillGuideForeverCraftUIButton", parent)
        created:SetNormalFontObject("GameFontNormalSmall")
        created:SetHighlightFontObject("GameFontHighlightSmall")
        local bg = created:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.12, 0.08, 1)
        local border = created:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0.85, 0.72, 0.35, 1)
    end
    created:SetSize(96, 22)
    return created
end

local function EnsureButton(host)
    if not IsFrame(host) then
        return nil
    end

    local titleParent = host.TitleContainer
    if not IsFrame(titleParent) then
        titleParent = host
    end

    if not button then
        button = CreateToggleButton(titleParent)
        button:SetScript("OnClick", OnButtonClick)
        button:SetScript("OnEnter", function(self)
            if not GameTooltip then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("SkillGuide Forever")
            GameTooltip:AddLine("Show profession recipes with skill levels beside this window.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
    end

    button.sgfHost = host
    button:SetParent(titleParent)
    button:ClearAllPoints()

    local close = host.CloseButton or host.Close
    if IsFrame(close) then
        button:SetPoint("RIGHT", close, "LEFT", -10, 0)
    elseif titleParent ~= host then
        button:SetPoint("RIGHT", titleParent, "RIGHT", -28, 0)
    else
        button:SetPoint("TOPRIGHT", host, "TOPRIGHT", -40, -4)
    end

    button:SetFrameLevel((titleParent:GetFrameLevel() or 1) + 50)
    if host.GetFrameStrata then
        button:SetFrameStrata(host:GetFrameStrata())
    end
    button:Show()
    UpdateButtonState()
    return button
end

local function SyncHost(host)
    if not IsFrame(host) then
        return
    end
    if not EnsureButton(host) then
        return
    end

    if IsEnabled() then
        button:Show()
        if host:IsShown() and wantAttached then
            ShowAttachedPane(host)
        elseif not wantAttached then
            if ns.IsProfessionFrameAttached and ns.IsProfessionFrameAttached() and button.sgfHost == host then
                HideAttachedPane()
            end
        end
    else
        button:Hide()
        wantAttached = false
        HideAttachedPane()
    end
    UpdateButtonState()
end

local function HookHost(host)
    if not IsFrame(host) then
        return
    end
    if hookedHosts[host] then
        SyncHost(host)
        return
    end
    hookedHosts[host] = true

    host:HookScript("OnShow", function(self)
        SyncHost(self)
    end)
    host:HookScript("OnHide", function()
        ns.RestoreProfessionSideTabs()
        if ns.IsProfessionFrameAttached and ns.IsProfessionFrameAttached() and button and button.sgfHost == host then
            if ns.DetachProfessionFrame then
                ns.DetachProfessionFrame(true)
            end
        end
        UpdateButtonState()
    end)

    SyncHost(host)
end

local function TryHookProfessionUIs()
    TryLoadCraftUI()
    local found = false
    for _, name in ipairs({
        "ProfessionsFrame",
        "TradeSkillFrame",
        "ProfessionsBookFrame",
        "CraftFrame",
    }) do
        local frame = _G[name]
        if IsFrame(frame) then
            HookHost(frame)
            found = true
        end
    end
    return found
end

local function HookProfessionFrameClose()
    local frame = (ns.GetProfessionFrame and ns.GetProfessionFrame()) or _G.SkillGuideForeverProfessionFrame
    if not frame or frame.sgfProfBookHideHooked then
        return
    end
    frame.sgfProfBookHideHooked = true
    frame:HookScript("OnHide", function(self)
        if not self.sgfAttached then
            return
        end
        ns.RestoreProfessionSideTabs()
        local host = button and button.sgfHost
        if host and host:IsShown() then
            wantAttached = false
            if ns.DetachProfessionFrame then
                ns.DetachProfessionFrame(true)
            end
            UpdateButtonState()
        end
    end)
end

function ns.RefreshProfessionsBookIntegration()
    HookProfessionFrameClose()
    if TryHookProfessionUIs() then
        local host = ResolveHostFrame()
        if host and host:IsShown() then
            SyncHost(host)
        end
        return
    end
    if not IsEnabled() then
        wantAttached = false
        HideAttachedPane()
    end
end

function ns.InitProfessionsBookIntegration()
    HookProfessionFrameClose()
    TryHookProfessionUIs()

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:RegisterEvent("ADDON_LOADED")
        eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
        eventFrame:RegisterEvent("TRADE_SKILL_CLOSE")
        eventFrame:SetScript("OnEvent", function(_, event, loaded)
            if event == "ADDON_LOADED" and type(loaded) == "string" then
                if string.find(loaded, "Profession", 1, true) or string.find(loaded, "TradeSkill", 1, true) then
                    TryHookProfessionUIs()
                end
            elseif event == "TRADE_SKILL_SHOW" then
                TryHookProfessionUIs()
                local host = ResolveHostFrame()
                if host then
                    SyncHost(host)
                end
            elseif event == "TRADE_SKILL_CLOSE" then
                if wantAttached then
                    -- Keep wantAttached so reopening craft UI restores the pane.
                    ns.RestoreProfessionSideTabs()
                end
            end
        end)
    end

    if watcher or TryHookProfessionUIs() then
        return
    end
    watcher = CreateFrame("Frame")
    watcher.elapsed = 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if TryHookProfessionUIs() or self.elapsed > 90 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

ns.RegisterCallback("OptionsChanged", function(_, _event, key, _value)
    if key == "professionsBookPane" or key == nil then
        if not IsEnabled() then
            wantAttached = false
            HideAttachedPane()
        end
        ns.RefreshProfessionsBookIntegration()
    end
end)
