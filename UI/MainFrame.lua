local addonName, ns = ...

-- Spellbook-like row: icon + name + subtext (rank / status)
local ROW_HEIGHT = 42
local HEADER_HEIGHT = 22
local FRAME_WIDTH = 384
local FRAME_HEIGHT = 512
local LIST_INSET = 12

local mainFrame
local scrollChild
local scrollFrame
local rowPool = {}
local pendingSpellIDs = {}
local attachedHost = nil

-- Light text for ButtonFrameTemplate's dark inset (Forever Character-pane style)
local COLOR_NAME = { 1.00, 0.82, 0.00 } -- gold
local COLOR_SUB = { 0.90, 0.85, 0.70 } -- cream
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

local function GetClassIconTexture(classFile)
    if CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile] then
        return "Interface\\TargetingFrame\\UI-Classes-Circles", CLASS_ICON_TCOORDS[classFile]
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark", nil
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

local function GetRowStatus(entry, viewingOwnClass)
    if not viewingOwnClass then
        return "normal", COLOR_NAME, COLOR_SUB
    end
    if ns.IsPlayerSpellKnown(entry.spellID) then
        return "known", COLOR_KNOWN, COLOR_KNOWN_SUB
    end
    local playerLevel = ns.GetPlayerLevel()
    if playerLevel and entry.level > playerLevel then
        return "locked", COLOR_LOCKED, COLOR_LOCKED_SUB
    end
    return "available", COLOR_AVAILABLE, COLOR_AVAILABLE_SUB
end

-- Train level lives on section headers; rows show rank / quest / cost / status.
local function FormatSubtext(entry, status)
    local parts = {}
    if entry.rank and entry.rank > 0 then
        parts[#parts + 1] = "Rank " .. entry.rank
    end
    if entry.quest then
        parts[#parts + 1] = "Quest"
    end
    local costText = ns.FormatCopper and ns.FormatCopper(entry.cost)
    if costText then
        parts[#parts + 1] = costText
    end
    if status == "known" then
        parts[#parts + 1] = "Known"
    elseif status == "available" then
        parts[#parts + 1] = "Available"
    elseif status == "locked" then
        parts[#parts + 1] = "Locked"
    end
    if #parts == 0 then
        return ""
    end
    return table.concat(parts, "  -  ")
end

local function BuildLevelGroupedList(skills)
    local list = {}
    local lastLevel = nil
    for _, entry in ipairs(skills) do
        local level = entry.level or 0
        if level ~= lastLevel then
            list[#list + 1] = { kind = "header", level = level }
            lastLevel = level
        end
        list[#list + 1] = { kind = "skill", entry = entry }
    end
    return list
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

local function ConfigureHeaderRow(row, level)
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
    SafeSetText(row.name, "Level " .. tostring(level or 0))
    row.name:SetTextColor(COLOR_LABEL[1], COLOR_LABEL[2], COLOR_LABEL[3])
    local hl = row:GetHighlightTexture()
    if hl then
        hl:SetAlpha(0)
    end
end

local function ConfigureSkillRow(row, entry, viewingOwnClass)
    row.kind = "skill"
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row.iconBorder:Show()
    row.icon:Show()
    row.sub:Show()
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row.iconBorder, "TOPRIGHT", 6, -4)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    local name, iconID = GetSpellDisplay(entry.spellID, entry.name)
    local status, nameColor, subColor = GetRowStatus(entry, viewingOwnClass)

    row.spellID = entry.spellID
    row.displayName = name
    row.icon:SetTexture(iconID)
    SafeSetText(row.name, name)
    SafeSetText(row.sub, FormatSubtext(entry, status))
    row.name:SetTextColor(nameColor[1], nameColor[2], nameColor[3])
    row.sub:SetTextColor(subColor[1], subColor[2], subColor[3])

    local costText = ns.FormatCopper and ns.FormatCopper(entry.cost)
    row:SetAlpha(1)
    if status == "known" then
        row.statusText = "Already known"
        row.icon:SetDesaturated(true)
        row.icon:SetVertexColor(0.85, 0.85, 0.85)
    elseif status == "locked" then
        row.statusText = "Requires level " .. tostring(entry.level)
        if entry.quest then
            row.statusText = row.statusText .. "  -  Class quest reward"
        elseif costText then
            row.statusText = row.statusText .. "  -  Trainer cost " .. costText
        end
        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)
    elseif status == "available" then
        if entry.quest then
            row.statusText = "Available from class quest"
        else
            row.statusText = "Available to train"
        end
        if costText then
            row.statusText = row.statusText .. "  -  " .. costText
        end
        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)
    else
        if entry.quest then
            row.statusText = "Class quest reward"
        else
            row.statusText = costText and ("Trainer cost " .. costText) or nil
        end
        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)
    end

    local hl = row:GetHighlightTexture()
    if hl then
        hl:SetAlpha(0.25)
        hl:SetVertexColor(0.6, 0.45, 0.2)
    end
end

local function GetPortraitTexture(frame)
    if not frame then
        return nil
    end
    local container = frame.PortraitContainer
    if container then
        return container.portrait or container.Portrait or container.Icon
    end
    return frame.portrait or frame.Portrait
end

local function UpdatePortrait(classFile)
    if not mainFrame then
        return
    end
    -- Never paint the portrait while docked; attach layout hides that chrome.
    if mainFrame.sgfAttached then
        return
    end
    if ButtonFrameTemplate_ShowPortrait then
        pcall(ButtonFrameTemplate_ShowPortrait, mainFrame)
    end
    local path, coords = GetClassIconTexture(classFile)
    local container = mainFrame.PortraitContainer
    if container then
        container:Show()
        if container.CircleMask then
            container.CircleMask:Show()
        end
    end
    if mainFrame.PortraitFrame then
        mainFrame.PortraitFrame:Show()
    end
    local portrait = GetPortraitTexture(mainFrame)
    if not portrait then
        return
    end
    portrait:Show()
    -- Class circle sheet needs SetTexture + texcoords; SetPortraitToTexture
    -- would flatten the crop. Prefer atlas when Forever provides one.
    local atlas = classFile and ("classicon-" .. string.lower(classFile))
    if atlas and portrait.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        portrait:SetAtlas(atlas)
    else
        portrait:SetTexture(path)
        if coords then
            portrait:SetTexCoord(unpack(coords))
        else
            portrait:SetTexCoord(0, 1, 0, 1)
        end
    end
end

local function IsHideKnownEnabled()
    return ns.db and ns.db.hideKnown
end

local function GetSearchQuery()
    if not mainFrame then
        return ""
    end
    local text = mainFrame.searchText or ""
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
    local name = entry.name
    if not name and entry.spellID then
        name = select(1, GetSpellDisplay(entry.spellID, nil))
    end
    name = name and string.lower(name) or ""
    if string.find(name, query, 1, true) then
        return true
    end
    if entry.rank and entry.rank > 0 then
        local rankText = "rank " .. tostring(entry.rank)
        if string.find(rankText, query, 1, true) then
            return true
        end
    end
    if entry.level then
        local levelText = "level " .. tostring(entry.level)
        if string.find(levelText, query, 1, true) or query == tostring(entry.level) then
            return true
        end
    end
    if entry.quest and string.find("quest", query, 1, true) then
        return true
    end
    return false
end

local function BuildVisibleSkills(skills, viewingOwnClass)
    local hideKnown = IsHideKnownEnabled()
    local query = GetSearchQuery()
    local visible = {}
    local hiddenKnown = 0
    local hiddenSearch = 0

    for _, entry in ipairs(skills) do
        if hideKnown and viewingOwnClass and ns.IsPlayerSpellKnown(entry.spellID) then
            hiddenKnown = hiddenKnown + 1
        elseif not EntryMatchesSearch(entry, query) then
            hiddenSearch = hiddenSearch + 1
        else
            visible[#visible + 1] = entry
        end
    end
    return visible, hiddenKnown, hiddenSearch
end

function ns.RefreshSkillList()
    if not mainFrame or not scrollChild then
        return
    end

    local classFile = mainFrame.selectedClass or ns.GetPlayerClassFile()
    local allSkills = ns.GetSkillsForClass(classFile) or {}
    local playerClass = ns.GetPlayerClassFile()
    local viewingOwnClass = (classFile == playerClass)
    local skills, hiddenKnown, hiddenSearch = BuildVisibleSkills(allSkills, viewingOwnClass)

    UpdatePortrait(classFile)

    if mainFrame.hideKnownCheck then
        mainFrame.hideKnownCheck:SetChecked(IsHideKnownEnabled())
        if viewingOwnClass then
            mainFrame.hideKnownCheck:Enable()
            mainFrame.hideKnownCheck:SetAlpha(1)
        else
            -- Known state only applies to your own class
            mainFrame.hideKnownCheck:Disable()
            mainFrame.hideKnownCheck:SetAlpha(0.5)
        end
    end

    local list = BuildLevelGroupedList(skills)
    local y = -4
    local totalHeight = 8
    for i, item in ipairs(list) do
        local row = AcquireRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)

        local rowHeight
        if item.kind == "header" then
            ConfigureHeaderRow(row, item.level)
            rowHeight = HEADER_HEIGHT
        else
            ConfigureSkillRow(row, item.entry, viewingOwnClass)
            rowHeight = ROW_HEIGHT
        end

        row:Show()
        y = y - rowHeight
        totalHeight = totalHeight + rowHeight
    end

    HideUnusedRows(#list + 1)
    scrollChild:SetHeight(math.max(1, totalHeight))

    local parts = {
        string.format("%s - %d skills", ns.GetClassDisplayName(classFile), #skills),
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
    if mainFrame.subtitle then
        SafeSetText(mainFrame.subtitle, subtitle)
    end
end

function ns.OnSpellDataLoaded(spellID, success)
    if not success or not spellID then
        return
    end
    if not pendingSpellIDs[spellID] then
        return
    end
    pendingSpellIDs[spellID] = nil
    if mainFrame and mainFrame:IsShown() then
        ns.RefreshSkillList()
    end
end

local function SetSelectedClass(classFile)
    if not mainFrame then
        return
    end
    mainFrame.selectedClass = classFile
    if ns.db then
        ns.db.selectedClass = classFile
    end
    if mainFrame.classDropdown then
        UIDropDownMenu_SetText(mainFrame.classDropdown, ns.GetClassDisplayName(classFile))
    end
    ns.RefreshSkillList()
end

local DROPDOWN_WIDTH_FREE = 130
local DROPDOWN_TEMPLATE_PAD = 28

local function InitClassDropdown(dropdown)
    UIDropDownMenu_Initialize(dropdown, function()
        for _, classFile in ipairs(ns.CLASS_ORDER) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = ns.GetClassDisplayName(classFile)
            info.checked = (mainFrame.selectedClass == classFile)
            info.func = function()
                SetSelectedClass(classFile)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetWidth(dropdown, DROPDOWN_WIDTH_FREE)
    dropdown.SGFMenuWidth = DROPDOWN_WIDTH_FREE
    UIDropDownMenu_JustifyText(dropdown, "LEFT")
end

--- Re-anchor toolbar/scroll/controls for free-float vs docked (no portrait gutter).
local function LayoutMainToolbar()
    if not mainFrame then
        return
    end
    local toolbar = mainFrame.toolbar
    local dropdown = mainFrame.classDropdown
    local classLabel = mainFrame.classLabel
    local hideKnownLabel = mainFrame.hideKnownLabel
    local search = mainFrame.searchBox
    local layout = mainFrame.SGFLayout
    if not toolbar or not dropdown or not layout then
        return
    end

    local attached = mainFrame.sgfAttached == true
    local left = attached and (layout.toolbarLeftSkinned or 8) or (layout.toolbarLeftPortrait or 56)
    local inset = mainFrame.Inset or mainFrame.inset
    local widgets = mainFrame.SkillGuideForeverWidgets
    local scroll = (widgets and widgets.scrollFrame) or mainFrame.sgfScrollFrame

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

    if classLabel then
        if attached then
            classLabel:Hide()
        else
            classLabel:Show()
        end
    end

    dropdown:ClearAllPoints()
    if attached then
        dropdown:SetPoint("TOPLEFT", toolbar, "TOPLEFT", -4, -2)
        local tw = toolbar:GetWidth() or 0
        if tw < 40 then
            tw = (mainFrame:GetWidth() or FRAME_WIDTH) - 20
        end
        -- Leave room for the right-aligned "Hide known" control.
        local reserved = hideKnownLabel and 96 or 8
        local width = math.max(100, math.floor(tw - reserved - DROPDOWN_TEMPLATE_PAD))
        dropdown.SGFMenuWidth = width
        if UIDropDownMenu_SetWidth then
            UIDropDownMenu_SetWidth(dropdown, width)
        end
    else
        if classLabel then
            dropdown:SetPoint("LEFT", classLabel, "RIGHT", -12, -2)
        else
            dropdown:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 0, -2)
        end
        dropdown.SGFMenuWidth = DROPDOWN_WIDTH_FREE
        if UIDropDownMenu_SetWidth then
            UIDropDownMenu_SetWidth(dropdown, DROPDOWN_WIDTH_FREE)
        end
    end

    if search then
        local pad = attached and 0 or 4
        search:ClearAllPoints()
        search:SetPoint("TOPLEFT", toolbar, "TOPLEFT", pad, -28)
        search:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", -pad, -28)
    end

    mainFrame.SGFPortraitClearance = not attached
end

local function SavePosition()
    if not mainFrame or not ns.db then
        return
    end
    -- Spellbook-attached layout is transient; keep the free-float SavedVariables.
    if mainFrame.sgfAttached then
        return
    end
    local point, _, _, x, y = mainFrame:GetPoint(1)
    ns.db.point = point or "CENTER"
    ns.db.x = x or 0
    ns.db.y = y or 0
end

local function RestoreFreePosition()
    if not mainFrame then
        return
    end
    local point = (ns.db and ns.db.point) or "CENTER"
    local x = (ns.db and ns.db.x) or 0
    local y = (ns.db and ns.db.y) or 0
    mainFrame:ClearAllPoints()
    mainFrame:SetParent(UIParent)
    mainFrame:SetPoint(point, UIParent, point, x, y)
    mainFrame:SetMovable(true)
    mainFrame:SetToplevel(true)
    if ns.ApplyFrameAppearance then
        ns.ApplyFrameAppearance(mainFrame)
    end
end

local function EnsureMainFrameContent()
    if not mainFrame then
        ns.CreateMainFrame()
    end
    if not mainFrame.selectedClass then
        SetSelectedClass(ns.GetPlayerClassFile())
    else
        ns.RefreshSkillList()
    end
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

    -- Darker list well so gold / cream / green text stays high-contrast
    local panel = inset.SkillGuideForeverPanel
    if not panel then
        panel = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
        inset.SkillGuideForeverPanel = panel
    end
    panel:SetPoint("TOPLEFT", 3, -3)
    panel:SetPoint("BOTTOMRIGHT", -3, 3)
    panel:SetColorTexture(0.04, 0.04, 0.05, 0.96)
end

function ns.CreateMainFrame()
    if mainFrame then
        return mainFrame
    end

    -- ButtonFrameTemplate = Forever Character/Spellbook chrome (portrait, gold title, close)
    mainFrame = CreateFrame("Frame", "SkillGuideForeverFrame", UIParent, "ButtonFrameTemplate")
    mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetToplevel(true)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()

    ApplyTitle(mainFrame, "SkillGuide Forever")

    if ButtonFrameTemplate_HideButtonBar then
        ButtonFrameTemplate_HideButtonBar(mainFrame)
    end
    if ButtonFrameTemplate_HideAttic then
        ButtonFrameTemplate_HideAttic(mainFrame)
    end

    local point = (ns.db and ns.db.point) or "CENTER"
    local x = (ns.db and ns.db.x) or 0
    local y = (ns.db and ns.db.y) or 0
    mainFrame:SetPoint(point, UIParent, point, x, y)

    mainFrame:SetScript("OnDragStart", function(self)
        if self.sgfAttached then
            return
        end
        if not InCombatLockdown or not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    -- Drag from the title bar region as well
    local titleRegion = mainFrame.TitleContainer or mainFrame
    if titleRegion and titleRegion ~= mainFrame then
        titleRegion:EnableMouse(true)
        titleRegion:RegisterForDrag("LeftButton")
        titleRegion:SetScript("OnDragStart", function()
            if mainFrame.sgfAttached then
                return
            end
            if mainFrame:IsMovable() and (not InCombatLockdown or not InCombatLockdown()) then
                mainFrame:StartMoving()
            end
        end)
        titleRegion:SetScript("OnDragStop", function()
            mainFrame:StopMovingOrSizing()
            SavePosition()
        end)
    end

    local inset = GetInset(mainFrame)
    StyleContentInset(inset)

    -- Toolbar: class, hide known, search, count
    -- Clear the large ButtonFrame portrait that overlaps the top-left inset.
    -- Alt skins hide the portrait and call ns.SetPortraitClearance(frame, false).
    local TOOLBAR_LEFT = 56
    mainFrame.SGFLayout = {
        hasInset = inset ~= nil,
        toolbarLeftPortrait = TOOLBAR_LEFT,
        toolbarLeftSkinned = 8,
        toolbarTop = -4,
        toolbarRight = -8,
        listInset = LIST_INSET,
        scrollGap = -6,
        scrollRight = -28,
        scrollBottom = LIST_INSET,
        dropdownUsesToolbarAnchor = false,
    }
    local toolbar = CreateFrame("Frame", nil, mainFrame)
    toolbar:SetHeight(72)
    mainFrame.toolbar = toolbar
    mainFrame.SGFLayoutToolbar = LayoutMainToolbar
    if inset then
        toolbar:SetPoint("TOPLEFT", inset, "TOPLEFT", TOOLBAR_LEFT, -4)
        toolbar:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -8, -4)
    else
        toolbar:SetPoint("TOPLEFT", TOOLBAR_LEFT + 4, -60)
        toolbar:SetPoint("TOPRIGHT", -12, -60)
    end
    toolbar:SetScript("OnSizeChanged", function()
        LayoutMainToolbar()
    end)

    local classLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classLabel:SetPoint("TOPLEFT", 0, -2)
    classLabel:SetText("Class")
    classLabel:SetTextColor(COLOR_LABEL[1], COLOR_LABEL[2], COLOR_LABEL[3])
    mainFrame.classLabel = classLabel

    local dropdown = CreateFrame("Frame", "SkillGuideForeverClassDropdown", toolbar, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", classLabel, "RIGHT", -12, -2)
    mainFrame.classDropdown = dropdown
    InitClassDropdown(dropdown)

    local hideKnown = CreateFrame("CheckButton", "SkillGuideForeverHideKnownCheck", toolbar, "UICheckButtonTemplate")
    hideKnown:SetSize(24, 24)
    hideKnown:SetPoint("TOPRIGHT", 4, 2)
    hideKnown:SetChecked(IsHideKnownEnabled())
    hideKnown:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.hideKnown = self:GetChecked() and true or false
        end
        ns.RefreshSkillList()
    end)
    hideKnown:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Hide known")
        GameTooltip:AddLine("Hide skills and ranks you have already learned.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    hideKnown:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    local hideKnownLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideKnownLabel:SetPoint("RIGHT", hideKnown, "LEFT", -2, 0)
    hideKnownLabel:SetText("Hide known")
    hideKnownLabel:SetTextColor(COLOR_SUB[1], COLOR_SUB[2], COLOR_SUB[3])
    mainFrame.hideKnownCheck = hideKnown
    mainFrame.hideKnownLabel = hideKnownLabel

    local search
    local okSearch = pcall(function()
        search = CreateFrame("EditBox", "SkillGuideForeverSearchBox", toolbar, "SearchBoxTemplate")
    end)
    if not okSearch or not search then
        search = CreateFrame("EditBox", "SkillGuideForeverSearchBox", toolbar, "InputBoxTemplate")
        search:SetTextInsets(8, 8, 0, 0)
    end
    search:SetHeight(22)
    search:SetPoint("TOPLEFT", 4, -28)
    search:SetPoint("TOPRIGHT", -4, -28)
    search:SetAutoFocus(false)
    if search.Instructions then
        search.Instructions:SetText("Search skills")
    end
    mainFrame.searchText = ""
    search:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then
            SearchBoxTemplate_OnTextChanged(self)
        end
        local text = self:GetText() or ""
        if mainFrame.searchText == text then
            return
        end
        mainFrame.searchText = text
        ns.RefreshSkillList()
    end)
    search:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then
            self:SetText("")
            mainFrame.searchText = ""
            ns.RefreshSkillList()
        end
        self:ClearFocus()
    end)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    mainFrame.searchBox = search

    mainFrame.subtitle = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mainFrame.subtitle:SetPoint("BOTTOMLEFT", 2, 2)
    mainFrame.subtitle:SetPoint("BOTTOMRIGHT", -2, 2)
    mainFrame.subtitle:SetJustifyH("LEFT")
    mainFrame.subtitle:SetTextColor(COLOR_SUB[1], COLOR_SUB[2], COLOR_SUB[3])
    SafeSetText(mainFrame.subtitle, "")

    -- Scrollable skill list (anchored under toolbar so skin clearance can shift it)
    scrollFrame = CreateFrame("ScrollFrame", "SkillGuideForeverScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
    mainFrame.sgfScrollFrame = scrollFrame
    if inset then
        scrollFrame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", LIST_INSET - TOOLBAR_LEFT, -6)
        scrollFrame:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -28, LIST_INSET)
    else
        scrollFrame:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", -36, -6)
        scrollFrame:SetPoint("BOTTOMRIGHT", -36, 20)
    end

    -- Tint scrollbar to bronze so it sits on parchment
    local scrollBar = scrollFrame.ScrollBar or _G["SkillGuideForeverScrollFrameScrollBar"]
    if scrollBar then
        scrollBar:SetFrameLevel(scrollFrame:GetFrameLevel() + 2)
    end

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(FRAME_WIDTH - 72)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local selected = (ns.db and ns.db.selectedClass) or ns.GetPlayerClassFile()
    if not ns.GetSkillsForClass(selected) then
        selected = ns.GetPlayerClassFile()
    end
    SetSelectedClass(selected)

    mainFrame:SetScript("OnShow", function(self)
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        end
        if not self.sgfAttached then
            UpdatePortrait(self.selectedClass or ns.GetPlayerClassFile())
        end
        if ns.NotifyFrameShow then
            ns.NotifyFrameShow("main", self)
        end
    end)
    mainFrame:SetScript("OnHide", function(self)
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        end
        if ns.NotifyFrameHide then
            ns.NotifyFrameHide("main", self)
        end
    end)

    tinsert(UISpecialFrames, "SkillGuideForeverFrame")

    if ns.NotifyFrameCreated then
        ns.NotifyFrameCreated("main", mainFrame, {
            frame = mainFrame,
            inset = GetInset(mainFrame),
            dropdown = mainFrame.classDropdown,
            searchBox = mainFrame.searchBox,
            hideKnownCheck = mainFrame.hideKnownCheck,
            scrollFrame = scrollFrame,
            scrollChild = scrollChild,
            subtitle = mainFrame.subtitle,
            toolbar = mainFrame.toolbar,
        })
    end

    return mainFrame
end

function ns.IsMainFrameAttached()
    return mainFrame ~= nil and mainFrame.sgfAttached == true
end

function ns.GetMainFrame()
    return mainFrame
end

--- Show the free-floating class skill window (detaches from spellbook if needed).
function ns.ShowMainFrame()
    EnsureMainFrameContent()
    if mainFrame.sgfAttached then
        ns.DetachMainFrame(false)
    else
        RestoreFreePosition()
        mainFrame:Show()
    end
    UpdatePortrait(mainFrame.selectedClass or ns.GetPlayerClassFile())
end

function ns.HideMainFrame()
    if not mainFrame then
        return
    end
    if mainFrame.sgfAttached then
        ns.DetachMainFrame(true)
        return
    end
    mainFrame:Hide()
end

--- Dock the existing class skill pane to the right of a host frame (spellbook).
function ns.AttachMainFrameTo(host)
    if not host then
        return false
    end
    EnsureMainFrameContent()
    attachedHost = host
    mainFrame.sgfAttached = true
    mainFrame:SetMovable(false)
    mainFrame:SetToplevel(false)
    mainFrame:ClearAllPoints()
    mainFrame:SetParent(host)
    -- Slightly shorter than the host so the side pane reads as a distinct panel.
    mainFrame:SetPoint("TOPLEFT", host, "TOPRIGHT", -6, -22)
    mainFrame:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", -6, 40)
    mainFrame:SetWidth(FRAME_WIDTH)
    local hostStrata = host.GetFrameStrata and host:GetFrameStrata()
    if hostStrata then
        mainFrame:SetFrameStrata(hostStrata)
    end
    if host.GetFrameLevel then
        mainFrame:SetFrameLevel(host:GetFrameLevel() + 2)
    end
    if ns.ApplyAttachedPaneLayout then
        ns.ApplyAttachedPaneLayout(mainFrame)
    end
    mainFrame:Show()
    -- After OnShow/skins so the no-portrait toolbar wins the layout race.
    LayoutMainToolbar()
    return true
end

--- Restore free-float parenting/position. hide=false leaves the window open.
function ns.DetachMainFrame(hide)
    if not mainFrame then
        attachedHost = nil
        return
    end
    if not mainFrame.sgfAttached then
        if hide then
            mainFrame:Hide()
        end
        return
    end
    mainFrame.sgfAttached = false
    attachedHost = nil
    if ns.RestoreAttachedPaneLayout then
        ns.RestoreAttachedPaneLayout(mainFrame)
    end
    RestoreFreePosition()
    mainFrame:SetWidth(FRAME_WIDTH)
    mainFrame:SetHeight(FRAME_HEIGHT)
    LayoutMainToolbar()
    UpdatePortrait(mainFrame.selectedClass or ns.GetPlayerClassFile())
    if hide ~= false then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

function ns.ToggleMainFrame()
    if not mainFrame then
        ns.CreateMainFrame()
    end
    if mainFrame:IsShown() then
        ns.HideMainFrame()
    else
        ns.ShowMainFrame()
    end
end
