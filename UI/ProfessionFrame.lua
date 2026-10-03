local addonName, ns = ...

local ROW_HEIGHT = 42
local FRAME_WIDTH = 400
local FRAME_HEIGHT = 512
local LIST_INSET = 12

local profFrame
local scrollChild
local scrollFrame
local rowPool = {}
local pendingSpellIDs = {}

local COLOR_NAME = { 1.00, 0.82, 0.00 }
local COLOR_SUB = { 0.90, 0.85, 0.70 }
local COLOR_KNOWN = { 0.80, 0.80, 0.80 }
local COLOR_KNOWN_SUB = { 0.70, 0.70, 0.70 }
local COLOR_LOCKED = { 1.00, 0.45, 0.40 }
local COLOR_LOCKED_SUB = { 0.95, 0.65, 0.55 }
local COLOR_AVAILABLE = { 0.35, 1.00, 0.40 }
local COLOR_AVAILABLE_SUB = { 0.75, 0.95, 0.75 }
local COLOR_LABEL = { 1.00, 0.82, 0.00 }
local ICON_BORDER = "Interface\\Buttons\\UI-Quickslot2"

local function SafeSetText(fontString, text)
    if not fontString then
        return
    end
    if type(issecretvalue) == "function" and issecretvalue(text) then
        fontString:SetText("?")
        return
    end
    fontString:SetText(text or "")
end

local function GetSpellDisplay(spellID, fallbackName)
    local name, iconID
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            name = info.name
            iconID = info.iconID
        elseif C_Spell.RequestLoadSpellData then
            pendingSpellIDs[spellID] = true
            C_Spell.RequestLoadSpellData(spellID)
        end
    end
    if not name then
        name = fallbackName or ("Spell " .. tostring(spellID))
    end
    if not iconID then
        iconID = 134400
    end
    return name, iconID
end

local function UpdateProfessionPortrait(key)
    if not profFrame then
        return
    end
    local portrait = profFrame.PortraitContainer and profFrame.PortraitContainer.portrait
        or profFrame.portrait
    if not portrait then
        return
    end
    local iconSpell = ns.GetProfessionIconSpell(key)
    local _, iconID = GetSpellDisplay(iconSpell, nil)
    portrait:SetTexture(iconID)
    portrait:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

-- Classic tradeskill difficulty colors (orange / yellow / green / grey).
local SKILL_ORANGE = "|cffff7f3f"
local SKILL_YELLOW = "|cffffff00"
local SKILL_GREEN = "|cff40c040"
local SKILL_GRAY = "|cff9d9d9d"

local function HexFromColor(color)
    return string.format(
        "%02x%02x%02x",
        math.floor((color[1] or 1) * 255 + 0.5),
        math.floor((color[2] or 1) * 255 + 0.5),
        math.floor((color[3] or 1) * 255 + 0.5)
    )
end

local function TintText(color, text)
    return "|cff" .. HexFromColor(color) .. (text or "") .. "|r"
end

local function FormatSkillBreakpoints(entry)
    return string.format(
        "%s%d|r/%s%d|r/%s%d|r/%s%d|r",
        SKILL_ORANGE, entry.orange or 0,
        SKILL_YELLOW, entry.yellow or 0,
        SKILL_GREEN, entry.green or 0,
        SKILL_GRAY, entry.gray or 0
    )
end

local function FormatSubtext(entry, status, subColor)
    local parts = {}
    parts[#parts + 1] = TintText(subColor, "Skill " .. tostring(entry.skill or 0))
    if entry.trainer then
        parts[#parts + 1] = TintText(subColor, "Trainer")
    else
        parts[#parts + 1] = TintText(subColor, "Recipe")
    end
    if entry.orange and entry.gray and entry.gray > 0 then
        parts[#parts + 1] = FormatSkillBreakpoints(entry)
    end
    if status == "known" then
        parts[#parts + 1] = TintText(subColor, "Known")
    elseif status == "available" then
        parts[#parts + 1] = TintText(subColor, "Available")
    elseif status == "locked" then
        parts[#parts + 1] = TintText(subColor, "Locked")
    end
    return table.concat(parts, TintText(subColor, "  -  "))
end

local function GetPlayerProfessionSkill(key)
    -- Best-effort: match profession name via GetProfessions / GetProfessionInfo.
    if not GetProfessions or not GetProfessionInfo then
        return nil
    end
    local display = ns.GetProfessionDisplayName(key)
    local ok, p1, p2, _, fish, cook, firstAid = pcall(GetProfessions)
    if not ok then
        return nil
    end
    for _, idx in ipairs({ p1, p2, cook, firstAid, fish }) do
        if idx then
            local name, _, skillLevel = GetProfessionInfo(idx)
            if type(name) == "string" and string.lower(name) == string.lower(display) then
                if type(issecretvalue) == "function" and issecretvalue(skillLevel) then
                    return nil
                end
                return skillLevel
            end
        end
    end
    return nil
end

local function GetRowStatus(entry)
    if ns.IsPlayerSpellKnown(entry.spellID) then
        return "known", COLOR_KNOWN, COLOR_KNOWN_SUB
    end
    local skillLevel = GetPlayerProfessionSkill(profFrame and profFrame.selectedProfession)
    if skillLevel and entry.skill and entry.skill > skillLevel then
        return "locked", COLOR_LOCKED, COLOR_LOCKED_SUB
    end
    if skillLevel then
        return "available", COLOR_AVAILABLE, COLOR_AVAILABLE_SUB
    end
    return "normal", COLOR_NAME, COLOR_SUB
end

local function AcquireRow(index)
    local row = rowPool[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    local hl = row:GetHighlightTexture()
    if hl then
        hl:SetAlpha(0.25)
        hl:SetVertexColor(0.6, 0.45, 0.2)
    end

    row.iconBorder = row:CreateTexture(nil, "BACKGROUND")
    row.iconBorder:SetSize(40, 40)
    row.iconBorder:SetPoint("LEFT", 2, 0)
    row.iconBorder:SetTexture(ICON_BORDER)
    row.iconBorder:SetVertexColor(0.7, 0.6, 0.4)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("CENTER", row.iconBorder, "CENTER", 0, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.iconBorder, "TOPRIGHT", 6, -4)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self)
        if self.spellID then
            ns.TryInsertSpellChatLink(self.spellID, self.displayName)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.spellID then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(self.spellID)
        else
            GameTooltip:SetText(self.displayName or "")
        end
        if self.statusText then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.statusText, 0.9, 0.85, 0.7)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift-click to link in chat", 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    rowPool[index] = row
    return row
end

local function HideUnusedRows(fromIndex)
    for i = fromIndex, #rowPool do
        rowPool[i]:Hide()
    end
end

local function IsHideKnownEnabled()
    return ns.db and ns.db.hideKnownProfession
end

local function GetSearchQuery()
    if not profFrame then
        return ""
    end
    local text = profFrame.searchText or ""
    if type(text) ~= "string" then
        return ""
    end
    text = strtrim(text)
    if text == "" then
        return ""
    end
    return string.lower(text)
end

local function EntryMatchesSearch(entry, query)
    if query == "" then
        return true
    end
    local name = entry.name and string.lower(entry.name) or ""
    if string.find(name, query, 1, true) then
        return true
    end
    if entry.skill and (query == tostring(entry.skill) or string.find("skill " .. entry.skill, query, 1, true)) then
        return true
    end
    if entry.trainer and string.find("trainer", query, 1, true) then
        return true
    end
    if (not entry.trainer) and string.find("recipe", query, 1, true) then
        return true
    end
    return false
end

local function BuildVisibleRecipes(recipes)
    local hideKnown = IsHideKnownEnabled()
    local query = GetSearchQuery()
    local visible = {}
    local hiddenKnown = 0
    local hiddenSearch = 0
    for _, entry in ipairs(recipes) do
        if hideKnown and ns.IsPlayerSpellKnown(entry.spellID) then
            hiddenKnown = hiddenKnown + 1
        elseif not EntryMatchesSearch(entry, query) then
            hiddenSearch = hiddenSearch + 1
        else
            visible[#visible + 1] = entry
        end
    end
    return visible, hiddenKnown, hiddenSearch
end

function ns.RefreshProfessionList()
    if not profFrame or not scrollChild then
        return
    end

    local key = profFrame.selectedProfession or ns.GetDefaultProfessionKey()
    local allRecipes = ns.GetRecipesForProfession(key) or {}
    local recipes, hiddenKnown, hiddenSearch = BuildVisibleRecipes(allRecipes)

    UpdateProfessionPortrait(key)

    if profFrame.hideKnownCheck then
        profFrame.hideKnownCheck:SetChecked(IsHideKnownEnabled())
    end

    local y = -4
    for i, entry in ipairs(recipes) do
        local row = AcquireRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)

        local name, iconID = GetSpellDisplay(entry.spellID, entry.name)
        local status, nameColor, subColor = GetRowStatus(entry)

        row.spellID = entry.spellID
        row.displayName = name
        row.icon:SetTexture(iconID)
        SafeSetText(row.name, name)
        SafeSetText(row.sub, FormatSubtext(entry, status, subColor))
        row.name:SetTextColor(nameColor[1], nameColor[2], nameColor[3])
        -- Subtext embeds its own |c colors (incl. O/Y/G/Gray breakpoints).
        row.sub:SetTextColor(1, 1, 1)

        row:SetAlpha(1)
        if status == "known" then
            row.statusText = "Already known"
            row.icon:SetDesaturated(true)
            row.icon:SetVertexColor(0.85, 0.85, 0.85)
        elseif status == "locked" then
            row.statusText = "Requires skill " .. tostring(entry.skill)
            row.icon:SetDesaturated(false)
            row.icon:SetVertexColor(1, 1, 1)
        elseif status == "available" then
            row.statusText = "Available to learn"
            row.icon:SetDesaturated(false)
            row.icon:SetVertexColor(1, 1, 1)
        else
            row.statusText = nil
            row.icon:SetDesaturated(false)
            row.icon:SetVertexColor(1, 1, 1)
        end

        row:Show()
        y = y - ROW_HEIGHT
    end

    HideUnusedRows(#recipes + 1)
    scrollChild:SetHeight(math.max(1, #recipes * ROW_HEIGHT + 8))

    local parts = {
        string.format("%s - %d recipes", ns.GetProfessionDisplayName(key), #recipes),
    }
    if hiddenKnown > 0 then
        parts[#parts + 1] = string.format("%d known hidden", hiddenKnown)
    end
    if hiddenSearch > 0 then
        parts[#parts + 1] = string.format("%d filtered", hiddenSearch)
    end
    local subtitle = parts[1]
    if #parts > 1 then
        subtitle = parts[1] .. " (" .. table.concat(parts, ", ", 2) .. ")"
    end
    if profFrame.subtitle then
        SafeSetText(profFrame.subtitle, subtitle)
    end
end

function ns.OnProfessionSpellDataLoaded(spellID, success)
    if not success or not spellID or not pendingSpellIDs[spellID] then
        return
    end
    pendingSpellIDs[spellID] = nil
    if profFrame and profFrame:IsShown() then
        ns.RefreshProfessionList()
    end
end

local function SetSelectedProfession(key)
    if not profFrame then
        return
    end
    profFrame.selectedProfession = key
    if ns.db then
        ns.db.selectedProfession = key
    end
    if profFrame.professionDropdown then
        UIDropDownMenu_SetText(profFrame.professionDropdown, ns.GetProfessionDisplayName(key))
    end
    ns.RefreshProfessionList()
end

local function InitProfessionDropdown(dropdown)
    UIDropDownMenu_Initialize(dropdown, function()
        for _, key in ipairs(ns.PROFESSION_ORDER) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = ns.GetProfessionDisplayName(key)
            info.checked = (profFrame.selectedProfession == key)
            info.func = function()
                SetSelectedProfession(key)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetWidth(dropdown, 150)
    UIDropDownMenu_JustifyText(dropdown, "LEFT")
end

local function SavePosition()
    if not profFrame or not ns.db then
        return
    end
    local point, _, _, x, y = profFrame:GetPoint(1)
    ns.db.professionPoint = point or "CENTER"
    ns.db.professionX = x or 40
    ns.db.professionY = y or 0
end

local function ApplyTitle(frame, text)
    if frame.SetTitle then
        frame:SetTitle(text)
        return
    end
    if frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText(text)
        return
    end
    if frame.TitleText then
        frame.TitleText:SetText(text)
    end
end

local function GetInset(frame)
    return frame.Inset or frame.inset
end

local function StyleContentInset(inset)
    if not inset then
        return
    end
    if inset.Bg then
        inset.Bg:SetVertexColor(0.05, 0.05, 0.06, 1)
    end
    local panel = inset.SkillGuideForeverProfPanel
    if not panel then
        panel = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
        inset.SkillGuideForeverProfPanel = panel
    end
    panel:SetPoint("TOPLEFT", 3, -3)
    panel:SetPoint("BOTTOMRIGHT", -3, 3)
    panel:SetColorTexture(0.04, 0.04, 0.05, 0.96)
end

function ns.CreateProfessionFrame()
    if profFrame then
        return profFrame
    end

    profFrame = CreateFrame("Frame", "SkillGuideForeverProfessionFrame", UIParent, "ButtonFrameTemplate")
    profFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    profFrame:SetFrameStrata("HIGH")
    profFrame:SetToplevel(true)
    profFrame:SetMovable(true)
    profFrame:EnableMouse(true)
    profFrame:RegisterForDrag("LeftButton")
    profFrame:SetClampedToScreen(true)
    profFrame:Hide()

    ApplyTitle(profFrame, "SkillGuide Forever - Professions")

    if ButtonFrameTemplate_HideButtonBar then
        ButtonFrameTemplate_HideButtonBar(profFrame)
    end
    if ButtonFrameTemplate_HideAttic then
        ButtonFrameTemplate_HideAttic(profFrame)
    end

    local point = (ns.db and ns.db.professionPoint) or "CENTER"
    local x = (ns.db and ns.db.professionX) or 40
    local y = (ns.db and ns.db.professionY) or 0
    profFrame:SetPoint(point, UIParent, point, x, y)

    profFrame:SetScript("OnDragStart", function(self)
        if not InCombatLockdown or not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    profFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    local titleRegion = profFrame.TitleContainer or profFrame
    if titleRegion and titleRegion ~= profFrame then
        titleRegion:EnableMouse(true)
        titleRegion:RegisterForDrag("LeftButton")
        titleRegion:SetScript("OnDragStart", function()
            if profFrame:IsMovable() and (not InCombatLockdown or not InCombatLockdown()) then
                profFrame:StartMoving()
            end
        end)
        titleRegion:SetScript("OnDragStop", function()
            profFrame:StopMovingOrSizing()
            SavePosition()
        end)
    end

    local inset = GetInset(profFrame)
    StyleContentInset(inset)

    -- Clear the large ButtonFrame portrait that overlaps the top-left inset.
    local TOOLBAR_LEFT = 56
    local toolbar = CreateFrame("Frame", nil, profFrame)
    toolbar:SetHeight(72)
    if inset then
        toolbar:SetPoint("TOPLEFT", inset, "TOPLEFT", TOOLBAR_LEFT, -4)
        toolbar:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -8, -4)
    else
        toolbar:SetPoint("TOPLEFT", TOOLBAR_LEFT + 4, -60)
        toolbar:SetPoint("TOPRIGHT", -12, -60)
    end

    local dropdown = CreateFrame("Frame", "SkillGuideForeverProfessionDropdown", toolbar, "UIDropDownMenuTemplate")
    -- UIDropDownMenuTemplate has empty left padding; pull slightly left within the cleared margin.
    dropdown:SetPoint("TOPLEFT", toolbar, "TOPLEFT", -16, -4)
    profFrame.professionDropdown = dropdown
    InitProfessionDropdown(dropdown)

    local hideKnown = CreateFrame("CheckButton", "SkillGuideForeverProfHideKnownCheck", toolbar, "UICheckButtonTemplate")
    hideKnown:SetSize(24, 24)
    hideKnown:SetPoint("TOPRIGHT", 4, 2)
    hideKnown:SetChecked(IsHideKnownEnabled())
    hideKnown:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.hideKnownProfession = self:GetChecked() and true or false
        end
        ns.RefreshProfessionList()
    end)
    hideKnown:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Hide known")
        GameTooltip:AddLine("Hide recipes you have already learned.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    hideKnown:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    local hideKnownLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideKnownLabel:SetPoint("RIGHT", hideKnown, "LEFT", -2, 0)
    hideKnownLabel:SetText("Hide known")
    hideKnownLabel:SetTextColor(COLOR_SUB[1], COLOR_SUB[2], COLOR_SUB[3])
    profFrame.hideKnownCheck = hideKnown

    local search
    local okSearch = pcall(function()
        search = CreateFrame("EditBox", "SkillGuideForeverProfSearchBox", toolbar, "SearchBoxTemplate")
    end)
    if not okSearch or not search then
        search = CreateFrame("EditBox", "SkillGuideForeverProfSearchBox", toolbar, "InputBoxTemplate")
        search:SetTextInsets(8, 8, 0, 0)
    end
    search:SetHeight(22)
    search:SetPoint("TOPLEFT", 4, -28)
    search:SetPoint("TOPRIGHT", -4, -28)
    search:SetAutoFocus(false)
    if search.Instructions then
        search.Instructions:SetText("Search recipes")
    end
    profFrame.searchText = ""
    search:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then
            SearchBoxTemplate_OnTextChanged(self)
        end
        local text = self:GetText() or ""
        if profFrame.searchText == text then
            return
        end
        profFrame.searchText = text
        ns.RefreshProfessionList()
    end)
    search:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then
            self:SetText("")
            profFrame.searchText = ""
            ns.RefreshProfessionList()
        end
        self:ClearFocus()
    end)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    profFrame.searchBox = search

    profFrame.subtitle = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profFrame.subtitle:SetPoint("BOTTOMLEFT", 2, 2)
    profFrame.subtitle:SetPoint("BOTTOMRIGHT", -2, 2)
    profFrame.subtitle:SetJustifyH("LEFT")
    profFrame.subtitle:SetTextColor(COLOR_SUB[1], COLOR_SUB[2], COLOR_SUB[3])
    SafeSetText(profFrame.subtitle, "")

    scrollFrame = CreateFrame("ScrollFrame", "SkillGuideForeverProfessionScrollFrame", profFrame, "UIPanelScrollFrameTemplate")
    if inset then
        scrollFrame:SetPoint("TOPLEFT", inset, "TOPLEFT", LIST_INSET, -80)
        scrollFrame:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -28, LIST_INSET)
    else
        scrollFrame:SetPoint("TOPLEFT", 20, -140)
        scrollFrame:SetPoint("BOTTOMRIGHT", -36, 20)
    end

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(FRAME_WIDTH - 72)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local selected = (ns.db and ns.db.selectedProfession) or ns.GetDefaultProfessionKey()
    if not ns.GetRecipesForProfession(selected) then
        selected = ns.GetDefaultProfessionKey()
    end
    SetSelectedProfession(selected)

    profFrame:SetScript("OnShow", function()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        end
    end)
    profFrame:SetScript("OnHide", function()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        end
    end)

    tinsert(UISpecialFrames, "SkillGuideForeverProfessionFrame")
    return profFrame
end

function ns.ToggleProfessionFrame()
    if not profFrame then
        ns.CreateProfessionFrame()
    end
    if profFrame:IsShown() then
        profFrame:Hide()
    else
        if not profFrame.selectedProfession then
            SetSelectedProfession(ns.GetDefaultProfessionKey())
        else
            ns.RefreshProfessionList()
        end
        profFrame:Show()
    end
end
