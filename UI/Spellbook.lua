local addonName, ns = ...

-- Blizzard spellbook side-panel: a toggle button docks the existing class skill pane.

local hookedHosts = {}
local wantAttached = false
local watcher

local function IsEnabled()
    return ns.db and ns.db.spellbookPane ~= false
end

local function ResolveSpellbookFrame()
    -- Forever / Classic use SpellBookFrame; guard PlayerSpellsFrame for future clients.
    if SpellBookFrame and SpellBookFrame.GetObjectType then
        return SpellBookFrame
    end
    if PlayerSpellsFrame and PlayerSpellsFrame.GetObjectType then
        return PlayerSpellsFrame
    end
    return nil
end

local function UpdateButtonState(button)
    if not button then
        return
    end
    local attached = ns.IsMainFrameAttached and ns.IsMainFrameAttached()
    if button.SetText then
        button:SetText(attached and "Hide Skills" or "SkillGuide")
    end
    if button.SetChecked then
        button:SetChecked(attached and true or false)
    end
end

local function HideAttachedPane()
    if ns.IsMainFrameAttached and ns.IsMainFrameAttached() and ns.DetachMainFrame then
        ns.DetachMainFrame(true)
    end
end

local function ShowAttachedPane(host)
    if not host or not IsEnabled() then
        return
    end
    if ns.AttachMainFrameTo then
        ns.AttachMainFrameTo(host)
    end
end

local function OnSpellbookButtonClick(button)
    local host = button and button.sgfHost
    if not host or not IsEnabled() then
        return
    end
    if ns.IsMainFrameAttached and ns.IsMainFrameAttached() then
        wantAttached = false
        HideAttachedPane()
    else
        wantAttached = true
        ShowAttachedPane(host)
    end
    UpdateButtonState(button)
end

local function EnsureSpellbookButton(host)
    if not host then
        return nil
    end
    if host.SGFSkillGuideButton then
        return host.SGFSkillGuideButton
    end

    local button = CreateFrame("Button", "SkillGuideForeverSpellbookButton", host, "UIPanelButtonTemplate")
    button:SetSize(96, 22)
    button.sgfHost = host

    -- Prefer the title bar / close-button region so we don't cover spell icons.
    local close = host.CloseButton or host.Close or _G.SpellBookCloseButton
    if close and close.GetObjectType then
        button:SetPoint("TOPRIGHT", close, "TOPLEFT", -8, 0)
    elseif host.TitleContainer then
        button:SetPoint("TOPRIGHT", host.TitleContainer, "TOPRIGHT", -28, -2)
    else
        button:SetPoint("TOPRIGHT", host, "TOPRIGHT", -40, -30)
    end

    button:SetScript("OnClick", OnSpellbookButtonClick)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("SkillGuide Forever")
        GameTooltip:AddLine("Show class skills with train levels beside the spellbook.", 1, 1, 1, true)
        GameTooltip:AddLine("Toggle this in Esc → Options → AddOns → SkillGuide Forever.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    host.SGFSkillGuideButton = button
    UpdateButtonState(button)
    return button
end

local function SyncHost(host)
    if not host then
        return
    end
    local button = EnsureSpellbookButton(host)
    if not button then
        return
    end

    if IsEnabled() then
        button:Show()
        if host:IsShown() and wantAttached then
            ShowAttachedPane(host)
        elseif not wantAttached then
            -- Leave freestanding /sg windows alone when the spellbook opens.
            if ns.IsMainFrameAttached and ns.IsMainFrameAttached() then
                HideAttachedPane()
            end
        end
    else
        button:Hide()
        wantAttached = false
        HideAttachedPane()
    end
    UpdateButtonState(button)
end

local function HookHost(host)
    if not host or hookedHosts[host] then
        return
    end
    hookedHosts[host] = true

    host:HookScript("OnShow", function(self)
        SyncHost(self)
    end)
    host:HookScript("OnHide", function()
        -- Keep wantAttached so reopening the spellbook restores the side pane.
        if ns.IsMainFrameAttached and ns.IsMainFrameAttached() then
            HideAttachedPane()
        end
        local button = host.SGFSkillGuideButton
        if button then
            UpdateButtonState(button)
        end
    end)

    if host:IsShown() then
        SyncHost(host)
    else
        EnsureSpellbookButton(host)
        local button = host.SGFSkillGuideButton
        if button then
            if IsEnabled() then
                button:Show()
            else
                button:Hide()
            end
            UpdateButtonState(button)
        end
    end
end

local function TryHookSpellbook()
    local host = ResolveSpellbookFrame()
    if host then
        HookHost(host)
        return true
    end
    return false
end

local function HookMainFrameClose()
    local frame = (ns.GetMainFrame and ns.GetMainFrame()) or _G.SkillGuideForeverFrame
    if not frame or frame.sgfSpellbookHideHooked then
        return
    end
    frame.sgfSpellbookHideHooked = true
    frame:HookScript("OnHide", function(self)
        -- User closed the side pane while the spellbook stayed open.
        if not self.sgfAttached then
            return
        end
        local host = ResolveSpellbookFrame()
        if not (host and host:IsShown()) then
            return
        end
        wantAttached = false
        if ns.DetachMainFrame then
            ns.DetachMainFrame(true)
        end
        UpdateButtonState(host.SGFSkillGuideButton)
    end)
end

function ns.RefreshSpellbookIntegration()
    HookMainFrameClose()
    local host = ResolveSpellbookFrame()
    if host then
        HookHost(host)
        SyncHost(host)
        return
    end
    if not IsEnabled() then
        wantAttached = false
        HideAttachedPane()
    end
end

function ns.InitSpellbookIntegration()
    HookMainFrameClose()
    if TryHookSpellbook() then
        return
    end

    -- Spellbook frame may load after login on some clients.
    if watcher then
        return
    end
    watcher = CreateFrame("Frame")
    watcher.elapsed = 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if TryHookSpellbook() or self.elapsed > 30 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)
    watcher:Show()
end

ns.RegisterCallback("OptionsChanged", function(_, _event, key, _value)
    if key == "spellbookPane" or key == nil then
        if not IsEnabled() then
            wantAttached = false
        end
        ns.RefreshSpellbookIntegration()
    end
end)
