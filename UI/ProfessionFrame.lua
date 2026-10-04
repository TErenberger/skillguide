local addonName, ns = ...

local ROW_HEIGHT = 42
local HEADER_HEIGHT = 22
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
    -- Wowhead sometimes stores orange as 0 for recipe-taught spells; fall back
    -- to the learn skill (Requires Profession (N) on the teaching recipe).
    local orange = entry.orange or 0
    if orange <= 0 then
        orange = entry.skill or 0
        if orange <= 0 and (entry.yellow or 0) > 0 then
            orange = 1
        end
    end
    return string.format(
        "%s%d|r/%s%d|r/%s%d|r/%s%d|r",
        SKILL_ORANGE, orange,
        SKILL_YELLOW, entry.yellow or 0,
        SKILL_GREEN, entry.green or 0,
        SKILL_GRAY, entry.gray or 0
    )
end

-- Learn skill lives on section headers; rows show source / cost / breakpoints / status.
local function FormatSubtext(entry, status, subColor)
    local parts = {}
    if entry.trainer then
        parts[#parts + 1] = TintText(subColor, "Trainer")
    else
        parts[#parts + 1] = TintText(subColor, "Recipe")
    end
    local costText = ns.FormatCopper and ns.FormatCopper(entry.cost)
    if costText then
        parts[#parts + 1] = TintText(subColor, costText)
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
    if #parts == 0 then
        return ""
    end
    return table.concat(parts, TintText(subColor, "  -  "))
end

local function BuildSkillGroupedList(recipes)
    local list = {}
    local lastSkill = nil
    for _, entry in ipairs(recipes) do
        local skill = entry.skill or 0
        if skill ~= lastSkill then
            list[#list + 1] = { kind = "header", skill = skill }
            lastSkill = skill
        end
        list[#list + 1] = { kind = "recipe", entry = entry }
    end
    return list
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

local function ConfigureHeaderRow(row, skill)
    row.kind = "header"
    row.spellID = nil
    row.displayName = nil
    row.statusText = nil
    row:SetHeight(HEADER_HEIGHT)
    row:EnableMouse(false)
    row.iconBorder:Hide()
    row.icon:Hide()
    row.sub:Hide()
    SafeSetText(row.sub, "")
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    SafeSetText(row.name, "Skill " .. tostring(skill or 0))
    row.name:SetTextColor(COLOR_LABEL[1], COLOR_LABEL[2], COLOR_LABEL[3])
    local hl = row:GetHighlightTexture()
    if hl then
        hl:SetAlpha(0)
    end
end

local function ConfigureRecipeRow(row, entry)
    row.kind = "recipe"
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row.iconBorder:Show()
    row.icon:Show()
    row.sub:Show()
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row.iconBorder, "TOPRIGHT", 6, -4)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)

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

    local costText = ns.FormatCopper and ns.FormatCopper(entry.cost)
    row:SetAlpha(1)
    if status == "known" then
        row.statusText = "Already known"
        row.icon:SetDesaturated(true)
        row.icon:SetVertexColor(0.85, 0.85, 0.85)
    elseif status == "locked" then
        row.statusText = "Requires skill " .. tostring(entry.skill)
        if costText then
            row.statusText = row.statusText .. "  -  Trainer cost " .. costText
        end
        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)
    elseif status == "available" then
        row.statusText = "Available to learn"
        if costText then
            row.statusText = row.statusText .. "  -  " .. costText
        end
        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)
    else
        row.statusText = costText and ("Trainer cost " .. costText) or nil
        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)
    end

    local hl = row:GetHighlightTexture()
    if hl then
        hl:SetAlpha(0.25)
        hl:SetVertexColor(0.6, 0.45, 0.2)
    end
end

local function IsHideKnownEnabled()
    return ns.db and ns.db.hideKnownProfession
end

local function IsHideRecipesEnabled()
    return ns.db and ns.db.hideRecipeProfession
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
    local hideRecipes = IsHideRecipesEnabled()
    local query = GetSearchQuery()
    local visible = {}
    local hiddenKnown = 0
    local hiddenRecipes = 0
    local hiddenSearch = 0
    for _, entry in ipairs(recipes) do
        if hideRecipes and not entry.trainer then
            hiddenRecipes = hiddenRecipes + 1
        elseif hideKnown and ns.IsPlayerSpellKnown(entry.spellID) then
            hiddenKnown = hiddenKnown + 1
        elseif not EntryMatchesSearch(entry, query) then
            hiddenSearch = hiddenSearch + 1
        else
            visible[#visible + 1] = entry
        end
    end
    return visible, hiddenKnown, hiddenRecipes, hiddenSearch
end

function ns.RefreshProfessionList()
    if not profFrame or not scrollChild then
        return
    end

    local key = profFrame.selectedProfession or ns.GetDefaultProfessionKey()
    local allRecipes = ns.GetRecipesForProfession(key) or {}
    local recipes = BuildVisibleRecipes(allRecipes)

    UpdateProfessionPortrait(key)

    if profFrame.hideKnownCheck then
        profFrame.hideKnownCheck:SetChecked(IsHideKnownEnabled())
    end
    if profFrame.hideRecipesCheck then
        profFrame.hideRecipesCheck:SetChecked(IsHideRecipesEnabled())
    end

    local list = BuildSkillGroupedList(recipes)
    local y = -4
    local totalHeight = 8
    for i, item in ipairs(list) do
        local row = AcquireRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)

        local rowHeight
        if item.kind == "header" then
            ConfigureHeaderRow(row, item.skill)
            rowHeight = HEADER_HEIGHT
        else
            ConfigureRecipeRow(row, item.entry)
            rowHeight = ROW_HEIGHT
        end

        row:Show()
        y = y - rowHeight
        totalHeight = totalHeight + rowHeight
    end

    HideUnusedRows(#list + 1)
    scrollChild:SetHeight(math.max(1, totalHeight))

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
    dropdown.SGFMenuWidth = 150
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
    -- Layout (3 rows, no subtitle): dropdown | toggles | search
    -- Alt skins hide the portrait and call ns.SetPortraitClearance(frame, false).
    local TOOLBAR_LEFT = 56
    profFrame.SGFLayout = {
        hasInset = inset ~= nil,
        toolbarLeftPortrait = TOOLBAR_LEFT,
        toolbarLeftSkinned = 8,
        toolbarTop = -4,
        toolbarRight = -8,
        listInset = LIST_INSET,
        scrollGap = -6,
        scrollRight = -28,
        scrollBottom = LIST_INSET,
        dropdownUsesToolbarAnchor = true,
        dropdownLeftPortrait = -16,
        dropdownLeftSkinned = -4,
        dropdownTop = -2,
    }
    local toolbar = CreateFrame("Frame", nil, profFrame)
    toolbar:SetHeight(86)
    if inset then
        toolbar:SetPoint("TOPLEFT", inset, "TOPLEFT", TOOLBAR_LEFT, -4)
        toolbar:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -8, -4)
    else
        toolbar:SetPoint("TOPLEFT", TOOLBAR_LEFT + 4, -60)
        toolbar:SetPoint("TOPRIGHT", -12, -60)
    end
    profFrame.toolbar = toolbar

    local dropdown = CreateFrame("Frame", "SkillGuideForeverProfessionDropdown", toolbar, "UIDropDownMenuTemplate")
    -- UIDropDownMenuTemplate has empty left padding; pull slightly left within the cleared margin.
    dropdown:SetPoint("TOPLEFT", toolbar, "TOPLEFT", -16, -2)
    profFrame.professionDropdown = dropdown
    InitProfessionDropdown(dropdown)

    local hideRecipes = CreateFrame("CheckButton", "SkillGuideForeverProfHideRecipesCheck", toolbar, "UICheckButtonTemplate")
    hideRecipes:SetSize(22, 22)
    hideRecipes:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 4, -30)
    hideRecipes:SetChecked(IsHideRecipesEnabled())
    hideRecipes:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.hideRecipeProfession = self:GetChecked() and true or false
        end
        ns.RefreshProfessionList()
    end)
    hideRecipes:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Hide recipes")
        GameTooltip:AddLine("Hide skills learned from recipe items. Trainer skills stay visible.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    hideRecipes:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    local hideRecipesLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideRecipesLabel:SetPoint("LEFT", hideRecipes, "RIGHT", 2, 0)
    hideRecipesLabel:SetText("Hide recipes")
    hideRecipesLabel:SetTextColor(COLOR_SUB[1], COLOR_SUB[2], COLOR_SUB[3])
    profFrame.hideRecipesCheck = hideRecipes

    local hideKnown = CreateFrame("CheckButton", "SkillGuideForeverProfHideKnownCheck", toolbar, "UICheckButtonTemplate")
    hideKnown:SetSize(22, 22)
    hideKnown:SetPoint("LEFT", hideRecipesLabel, "RIGHT", 14, 0)
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
    hideKnownLabel:SetPoint("LEFT", hideKnown, "RIGHT", 2, 0)
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
    search:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 4, -56)
    search:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", -4, -56)
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

    scrollFrame = CreateFrame("ScrollFrame", "SkillGuideForeverProfessionScrollFrame", profFrame, "UIPanelScrollFrameTemplate")
    if inset then
        scrollFrame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", LIST_INSET - TOOLBAR_LEFT, -6)
        scrollFrame:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -28, LIST_INSET)
    else
        scrollFrame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", -36, -6)
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

    profFrame:SetScript("OnShow", function(self)
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        end
        if ns.NotifyFrameShow then
            ns.NotifyFrameShow("profession", self)
        end
    end)
    profFrame:SetScript("OnHide", function(self)
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        end
        if ns.NotifyFrameHide then
            ns.NotifyFrameHide("profession", self)
        end
    end)

    tinsert(UISpecialFrames, "SkillGuideForeverProfessionFrame")

    if ns.NotifyFrameCreated then
        ns.NotifyFrameCreated("profession", profFrame, {
            frame = profFrame,
            inset = GetInset(profFrame),
            dropdown = profFrame.professionDropdown,
            searchBox = profFrame.searchBox,
            hideKnownCheck = profFrame.hideKnownCheck,
            hideRecipesCheck = profFrame.hideRecipesCheck,
            scrollFrame = scrollFrame,
            scrollChild = scrollChild,
            toolbar = profFrame.toolbar,
        })
    end

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
