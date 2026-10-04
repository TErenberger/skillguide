local addonName, ns = ...

-- Forever uses Blizzard_PlayerSpells (PlayerSpellsFrame), not classic SpellBookFrame.
-- Toggle button sits immediately left of SpellBookFrame.SearchBox.

local hookedHosts = {}
local wantAttached = false
local watcher
local button

local function IsEnabled()
    return ns.db and ns.db.spellbookPane ~= false
end

local function IsFrame(value)
    return type(value) == "table" and value.GetObjectType and pcall(value.GetObjectType, value)
end

local function TryLoadPlayerSpells()
    if _G.PlayerSpellsFrame then
        return true
    end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_PlayerSpells")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_PlayerSpells")
    end
    return _G.PlayerSpellsFrame ~= nil
end

--- Outer chrome frame to dock against (minimize/close chrome).
local function ResolveHostFrame()
    TryLoadPlayerSpells()
    -- Prefer Forever / modern spellbook.
    if IsFrame(_G.PlayerSpellsFrame) then
        return _G.PlayerSpellsFrame
    end
    if IsFrame(_G.SpellBookFrame) then
        return _G.SpellBookFrame
    end
    return nil
end

--- Inner spellbook page that owns the search box and category tabs.
local function ResolveSpellBookPage(host)
    if not IsFrame(host) then
        return nil
    end
    if IsFrame(host.SpellBookFrame) then
        return host.SpellBookFrame
    end
    return host
end

local function FindSearchBox(host)
    local page = ResolveSpellBookPage(host)
    if not IsFrame(page) then
        return nil
    end

    local box = page.SearchBox or page.searchBox or host.SearchBox
    if IsFrame(box) then
        return box
    end

    -- Named globals used by some builds.
    for _, name in ipairs({
        "SpellBookFrameSearchBox",
        "PlayerSpellsFrameSpellBookFrameSearchBox",
    }) do
        local candidate = _G[name]
        if IsFrame(candidate) then
            return candidate
        end
    end

    return nil
end

local function UpdateButtonState()
    if not button then
        return
    end
    local attached = ns.IsMainFrameAttached and ns.IsMainFrameAttached()
    if button.SetText then
        button:SetText(attached and "Hide" or "SkillGuide")
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

local function OnSpellbookButtonClick()
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
    UpdateButtonState()
end

local function CreateToggleButton(parent)
    local created
    local ok = pcall(function()
        created = CreateFrame("Button", "SkillGuideForeverSpellbookButton", parent, "UIPanelButtonTemplate")
    end)
    if not ok or not created then
        created = CreateFrame("Button", "SkillGuideForeverSpellbookButton", parent)
        created:SetNormalFontObject("GameFontNormalSmall")
        created:SetHighlightFontObject("GameFontHighlightSmall")
        local bg = created:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.12, 0.10, 0.08, 0.95)
        local border = created:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0.75, 0.65, 0.35, 0.9)
    end
    created:SetSize(88, 22)
    return created
end

local function AnchorBesideSearch(host, searchBox)
    local parent = searchBox:GetParent() or ResolveSpellBookPage(host) or host
    if button:GetParent() ~= parent then
        button:SetParent(parent)
    end
    button.sgfHost = host
    button:ClearAllPoints()
    button:SetPoint("RIGHT", searchBox, "LEFT", -8, 0)
    button:SetFrameLevel((searchBox:GetFrameLevel() or 1) + 5)
    button:Show()
    if button.Raise then
        button:Raise()
    end
end

local function EnsureSpellbookButton(host)
    if not IsFrame(host) then
        return nil
    end

    local searchBox = FindSearchBox(host)
    local parent = (searchBox and searchBox:GetParent()) or ResolveSpellBookPage(host) or host
    if not button then
        button = CreateToggleButton(parent)
        button:SetScript("OnClick", OnSpellbookButtonClick)
        button:SetScript("OnEnter", function(self)
            if not GameTooltip then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("SkillGuide Forever")
            GameTooltip:AddLine("Show class skills with train levels beside the spellbook.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
    end

    button.sgfHost = host
    if searchBox then
        AnchorBesideSearch(host, searchBox)
    else
        button:SetParent(parent)
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -120, -28)
        button:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
        button:Show()
    end

    UpdateButtonState()
    return button
end

local function SyncHost(host)
    if not IsFrame(host) then
        return
    end
    if not EnsureSpellbookButton(host) then
        return
    end

    if IsEnabled() then
        button:Show()
        if host:IsShown() and wantAttached then
            ShowAttachedPane(host)
        elseif not wantAttached then
            if ns.IsMainFrameAttached and ns.IsMainFrameAttached() then
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
    if not IsFrame(host) or hookedHosts[host] then
        if IsFrame(host) then
            SyncHost(host)
        end
        return
    end
    hookedHosts[host] = true

    host:HookScript("OnShow", function(self)
        SyncHost(self)
    end)
    host:HookScript("OnHide", function()
        if ns.IsMainFrameAttached and ns.IsMainFrameAttached() then
            HideAttachedPane()
        end
        UpdateButtonState()
    end)

    -- Spellbook page may be built/shown after the outer frame.
    local page = ResolveSpellBookPage(host)
    if IsFrame(page) and page ~= host and not hookedHosts[page] then
        hookedHosts[page] = true
        page:HookScript("OnShow", function()
            SyncHost(host)
        end)
    end

    SyncHost(host)
end

local function TryHookSpellbook()
    local host = ResolveHostFrame()
    if not host then
        return false
    end
    HookHost(host)
    return true
end

local function HookMainFrameClose()
    local frame = (ns.GetMainFrame and ns.GetMainFrame()) or _G.SkillGuideForeverFrame
    if not frame or frame.sgfSpellbookHideHooked then
        return
    end
    frame.sgfSpellbookHideHooked = true
    frame:HookScript("OnHide", function(self)
        if not self.sgfAttached then
            return
        end
        local host = ResolveHostFrame()
        if not (host and host:IsShown()) then
            return
        end
        wantAttached = false
        if ns.DetachMainFrame then
            ns.DetachMainFrame(true)
        end
        UpdateButtonState()
    end)
end

function ns.RefreshSpellbookIntegration()
    HookMainFrameClose()
    local host = ResolveHostFrame()
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

    if watcher then
        return
    end
    watcher = CreateFrame("Frame")
    watcher.elapsed = 0
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(_, event, loaded)
        if event == "ADDON_LOADED" and type(loaded) == "string" then
            if string.find(string.lower(loaded), "spell", 1, true) then
                TryHookSpellbook()
            end
        end
    end)
    watcher:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if TryHookSpellbook() or self.elapsed > 60 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

ns.RegisterCallback("OptionsChanged", function(_, _event, key, _value)
    if key == "spellbookPane" or key == nil then
        if not IsEnabled() then
            wantAttached = false
        end
        ns.RefreshSpellbookIntegration()
    end
end)
