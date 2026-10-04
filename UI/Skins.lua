local addonName, ns = ...

-- Built-in skins that consume SkillGuideForeverAPI the same way ElvUI / AddOnSkins would.
-- This lets you preview the hook path without installing a third-party skinner.

local OWNER = "SkillGuideForever.BuiltInSkin"
local registered = false
local menuHooksInstalled = false
local activeColors = nil -- design tokens for the current non-Blizzard skin

local SKIN_ORDER = { "blizzard", "flat", "midnight" }

local SKIN_LABELS = {
    blizzard = "Blizzard (default)",
    flat = "Flat Dark (test skin)",
    midnight = "Midnight Gold (test skin)",
}

local OUR_DROPDOWNS = {
    SkillGuideForeverClassDropdown = true,
    SkillGuideForeverProfessionDropdown = true,
}

local function CurrentSkinKey()
    local key = ns.db and ns.db.builtInSkin or "blizzard"
    if not SKIN_LABELS[key] then
        return "blizzard"
    end
    return key
end

local function IsOurDropDown(menu)
    if not menu then
        return false
    end
    local name = menu.GetName and menu:GetName()
    return name and OUR_DROPDOWNS[name] or false
end

local function GetActiveColors()
    if CurrentSkinKey() == "blizzard" then
        return nil
    end
    return activeColors
end

local function GetWidgets(frame)
    return frame and (frame.SkillGuideForeverWidgets or {}) or {}
end

local function HideObj(obj, state, key)
    if not obj or not obj.Hide then
        return
    end
    if state[key] == nil then
        state[key] = obj:IsShown()
    end
    obj:Hide()
end

local function RestoreObj(obj, state, key)
    if not obj then
        return
    end
    if state[key] then
        obj:Show()
    end
end

local function EnsureBackdrop(parent, name, strataOffset)
    local bag = parent[name]
    if bag then
        if bag.EnableMouse then
            bag:EnableMouse(false)
        end
        return bag
    end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    bag = CreateFrame("Frame", nil, parent, template)
    -- Decorative only: never steal clicks from the real controls.
    if bag.EnableMouse then
        bag:EnableMouse(false)
    end
    if bag.EnableMouseWheel then
        bag:EnableMouseWheel(false)
    end
    bag:SetFrameLevel(math.max(0, (parent:GetFrameLevel() or 1) + (strataOffset or -1)))
    bag:SetAllPoints(parent)
    if bag.SetBackdrop then
        bag:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
    end
    parent[name] = bag
    return bag
end

local function FadeTexture(region, store)
    if not region or not region.SetAlpha then
        return
    end
    if store[region] == nil then
        store[region] = region:GetAlpha()
    end
    region:SetAlpha(0)
end

local function RestoreFadedTextures(store)
    if not store then
        return
    end
    for region, alpha in pairs(store) do
        if region and region.SetAlpha then
            region:SetAlpha(alpha or 1)
        end
    end
end

local function StyleEditBox(editBox, r, g, b, a, br, bg, bb)
    if not editBox then
        return
    end
    local bag = EnsureBackdrop(editBox, "SGFSkinEditBackdrop", -1)
    bag:ClearAllPoints()
    bag:SetPoint("TOPLEFT", editBox, "TOPLEFT", -4, 2)
    bag:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 4, -2)
    if bag.SetBackdropColor then
        bag:SetBackdropColor(r, g, b, a)
        bag:SetBackdropBorderColor(br, bg, bb, 1)
    end
    bag:Show()
    if editBox.Left then editBox.Left:SetAlpha(0) end
    if editBox.Middle then editBox.Middle:SetAlpha(0) end
    if editBox.Right then editBox.Right:SetAlpha(0) end
    if editBox.Mid then editBox.Mid:SetAlpha(0) end
end

local function UnstyleEditBox(editBox)
    if not editBox then
        return
    end
    if editBox.SGFSkinEditBackdrop then
        editBox.SGFSkinEditBackdrop:Hide()
    end
    if editBox.Left then editBox.Left:SetAlpha(1) end
    if editBox.Middle then editBox.Middle:SetAlpha(1) end
    if editBox.Right then editBox.Right:SetAlpha(1) end
    if editBox.Mid then editBox.Mid:SetAlpha(1) end
end

local function GetDropDownParts(dropdown)
    if not dropdown then
        return nil
    end
    local name = dropdown.GetName and dropdown:GetName()
    local left = dropdown.Left or (name and _G[name .. "Left"])
    local middle = dropdown.Middle or (name and _G[name .. "Middle"])
    local right = dropdown.Right or (name and _G[name .. "Right"])
    local text = dropdown.Text or (name and _G[name .. "Text"])
    local button = dropdown.Button
        or dropdown.DropdownButton
        or (name and _G[name .. "Button"])
    return left, middle, right, text, button
end

local function CloseOurDropDownMenus()
    local open = UIDROPDOWNMENU_OPEN_MENU
    if open and IsOurDropDown(open) then
        if CloseDropDownMenus then
            CloseDropDownMenus()
        else
            local maxLevels = UIDROPDOWNMENU_MAXLEVELS or 2
            for i = 1, maxLevels do
                local list = _G["DropDownList" .. i]
                if list then
                    list:Hide()
                end
            end
        end
    end
end

-- Overlay-only dropdown skinning: never ClearAllPoints / SetSize / replace textures
-- on Blizzard widgets, so switching back to default cannot strand the toggle button.
local function IsSaneMenuWidth(width)
    return type(width) == "number" and width >= 40 and width <= 320
end

local function GetDropDownMenuWidth(dropdown)
    if not dropdown then
        return 150
    end
    if IsSaneMenuWidth(dropdown.SGFMenuWidth) then
        return dropdown.SGFMenuWidth
    end
    if IsSaneMenuWidth(dropdown.width) then
        return dropdown.width
    end
    local fromApi = UIDropDownMenu_GetWidth and UIDropDownMenu_GetWidth(dropdown)
    if IsSaneMenuWidth(fromApi) then
        return fromApi
    end
    local name = dropdown.GetName and dropdown:GetName()
    if name and name:find("Class", 1, true) then
        return 130
    end
    return 150
end

local function EnforceDropDownWidth(dropdown)
    if not dropdown or not UIDropDownMenu_SetWidth then
        return GetDropDownMenuWidth(dropdown)
    end
    local width = GetDropDownMenuWidth(dropdown)
    dropdown.SGFMenuWidth = width
    UIDropDownMenu_SetWidth(dropdown, width)
    return width
end

local function StyleDropDownButton(button, colors)
    if not button then
        return
    end
    button.SGFTexAlphas = button.SGFTexAlphas or {}
    local store = button.SGFTexAlphas
    local nt = button.GetNormalTexture and button:GetNormalTexture()
    local pt = button.GetPushedTexture and button:GetPushedTexture()
    local ht = button.GetHighlightTexture and button:GetHighlightTexture()
    local dt = button.GetDisabledTexture and button:GetDisabledTexture()
    FadeTexture(nt, store)
    FadeTexture(pt, store)
    FadeTexture(ht, store)
    FadeTexture(dt, store)

    local btnBag = EnsureBackdrop(button, "SGFSkinDropButtonBackdrop", -1)
    btnBag:ClearAllPoints()
    btnBag:SetAllPoints(button)
    if btnBag.SetBackdropColor then
        btnBag:SetBackdropColor(colors.insetR, colors.insetG, colors.insetB, 0.98)
        btnBag:SetBackdropBorderColor(colors.borderR, colors.borderG, colors.borderB, 1)
    end
    btnBag:Show()

    if not button.SGFArrow then
        button.SGFArrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.SGFArrow:SetPoint("CENTER", 0, 1)
        button.SGFArrow:SetText("v")
    end
    button.SGFArrow:Show()
    button.SGFArrow:SetTextColor(colors.titleR, colors.titleG, colors.titleB)
end

local function StyleDropDown(dropdown, colors)
    if not dropdown then
        return
    end
    local left, middle, right, text, button = GetDropDownParts(dropdown)

    -- Keep Blizzard middle/button geometry on the configured width (never trust
    -- Left/Right texture spans — they can measure far wider than the menu).
    local width = EnforceDropDownWidth(dropdown)

    dropdown.SGFChromeAlphas = dropdown.SGFChromeAlphas or {}
    local store = dropdown.SGFChromeAlphas
    FadeTexture(left, store)
    FadeTexture(middle, store)
    FadeTexture(right, store)

    local bag = EnsureBackdrop(dropdown, "SGFSkinDropBackdrop", -1)
    bag:ClearAllPoints()
    bag:SetSize(width + 28, 22)
    if button then
        bag:SetPoint("RIGHT", button, "RIGHT", 2, 0)
    elseif text then
        bag:SetPoint("LEFT", text, "LEFT", -8, 0)
    else
        bag:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 16, -5)
    end
    if bag.SetBackdropColor then
        bag:SetBackdropColor(colors.editR, colors.editG, colors.editB, colors.editA)
        bag:SetBackdropBorderColor(colors.borderR, colors.borderG, colors.borderB, 1)
    end
    bag:Show()

    if text and text.SetTextColor then
        if dropdown.SGFTextColor == nil then
            local r, g, b, a = text:GetTextColor()
            dropdown.SGFTextColor = { r, g, b, a }
        end
        text:SetTextColor(colors.titleR, colors.titleG, colors.titleB)
    end

    StyleDropDownButton(button, colors)
    dropdown.SGFDropDownSkinned = colors.id
end

local function UnstyleDropDown(dropdown)
    if not dropdown then
        return
    end
    if dropdown.SGFSkinDropBackdrop then
        dropdown.SGFSkinDropBackdrop:Hide()
    end
    RestoreFadedTextures(dropdown.SGFChromeAlphas)

    local _, _, _, text, button = GetDropDownParts(dropdown)
    if text and text.SetTextColor then
        local c = dropdown.SGFTextColor
        if c then
            text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        else
            text:SetTextColor(1, 0.82, 0)
        end
    end
    if button then
        if button.SGFSkinDropButtonBackdrop then
            button.SGFSkinDropButtonBackdrop:Hide()
        end
        if button.SGFArrow then
            button.SGFArrow:Hide()
        end
        RestoreFadedTextures(button.SGFTexAlphas)
    end
    EnforceDropDownWidth(dropdown)
    dropdown.SGFDropDownSkinned = nil
end

local function HideNineSlice(frame, store, key)
    if not frame or not frame.NineSlice then
        return
    end
    if store[key] == nil then
        store[key] = frame.NineSlice:IsShown()
    end
    frame.NineSlice:Hide()
end

local function StyleDropDownList(level, colors)
    if not colors then
        return
    end
    level = level or 1
    local list = _G["DropDownList" .. level]
    if not list then
        return
    end

    local state = list.SGFMenuState or {}
    list.SGFMenuState = state
    state.regionAlphas = state.regionAlphas or {}
    state.highlight = state.highlight or {}
    state.textColor = state.textColor or {}
    state.checkColor = state.checkColor or {}

    local backdrop = _G["DropDownList" .. level .. "Backdrop"] or list
    local menuBackdrop = _G["DropDownList" .. level .. "MenuBackdrop"]

    -- Overlay our bag; do not SetBackdrop on Blizzard frames (hard to restore).
    local bag = EnsureBackdrop(backdrop, "SGFSkinMenuBag", 1)
    bag:ClearAllPoints()
    bag:SetAllPoints(backdrop)
    if bag.SetBackdropColor then
        bag:SetBackdropColor(colors.bgR, colors.bgG, colors.bgB, colors.bgA)
        bag:SetBackdropBorderColor(colors.borderR, colors.borderG, colors.borderB, 1)
    end
    bag:Show()

    if menuBackdrop and menuBackdrop ~= backdrop then
        local menuBag = EnsureBackdrop(menuBackdrop, "SGFSkinMenuBag", 1)
        menuBag:ClearAllPoints()
        menuBag:SetAllPoints(menuBackdrop)
        if menuBag.SetBackdropColor then
            menuBag:SetBackdropColor(colors.bgR, colors.bgG, colors.bgB, colors.bgA)
            menuBag:SetBackdropBorderColor(colors.borderR, colors.borderG, colors.borderB, 1)
        end
        menuBag:Show()
        -- Hide Blizzard art under our overlay.
        if menuBackdrop.SetBackdropColor then
            if state.menuBackdropColor == nil then
                state.menuBackdropColor = true
            end
            menuBackdrop:SetBackdropColor(0, 0, 0, 0)
            menuBackdrop:SetBackdropBorderColor(0, 0, 0, 0)
        end
    end
    if backdrop.SetBackdropColor then
        if state.backdropColor == nil then
            state.backdropColor = true
        end
        backdrop:SetBackdropColor(0, 0, 0, 0)
        backdrop:SetBackdropBorderColor(0, 0, 0, 0)
    end

    if list.GetRegions then
        local regions = { list:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                FadeTexture(region, state.regionAlphas)
            end
        end
    end
    HideNineSlice(list, state, "listNine")
    HideNineSlice(backdrop, state, "backdropNine")
    HideNineSlice(menuBackdrop, state, "menuNine")

    local maxButtons = UIDROPDOWNMENU_MAXBUTTONS or 40
    for j = 1, maxButtons do
        local button = _G["DropDownList" .. level .. "Button" .. j]
        if button then
            local highlight = _G["DropDownList" .. level .. "Button" .. j .. "Highlight"]
            local normalText = _G["DropDownList" .. level .. "Button" .. j .. "NormalText"]
            local check = _G["DropDownList" .. level .. "Button" .. j .. "Check"]
            local uncheck = _G["DropDownList" .. level .. "Button" .. j .. "UnCheck"]

            if highlight then
                if state.highlight[j] == nil then
                    local r, g, b, a = 1, 1, 1, 0.25
                    if highlight.GetVertexColor then
                        r, g, b, a = highlight:GetVertexColor()
                    end
                    state.highlight[j] = { r, g, b, a }
                end
                if highlight.SetColorTexture then
                    highlight:SetColorTexture(colors.borderR, colors.borderG, colors.borderB, 0.28)
                elseif highlight.SetVertexColor then
                    highlight:SetVertexColor(colors.borderR, colors.borderG, colors.borderB, 0.35)
                end
            end
            if normalText and normalText.SetTextColor then
                if state.textColor[j] == nil then
                    local r, g, b, a = normalText:GetTextColor()
                    state.textColor[j] = { r, g, b, a }
                end
                normalText:SetTextColor(colors.titleR, colors.titleG, colors.titleB)
            end
            if check and check.SetVertexColor then
                if state.checkColor[j] == nil then
                    local r, g, b, a = check:GetVertexColor()
                    state.checkColor[j] = { r, g, b, a }
                end
                check:SetVertexColor(colors.borderR, colors.borderG, colors.borderB)
            end
            if uncheck and uncheck.SetVertexColor then
                uncheck:SetVertexColor(colors.borderR, colors.borderG, colors.borderB)
            end
        end
    end
    list.SGFMenuSkinned = colors.id
end

local function UnstyleDropDownList(level)
    level = level or 1
    local list = _G["DropDownList" .. level]
    if not list or not list.SGFMenuSkinned then
        return
    end
    local state = list.SGFMenuState or {}
    local backdrop = _G["DropDownList" .. level .. "Backdrop"] or list
    local menuBackdrop = _G["DropDownList" .. level .. "MenuBackdrop"]

    if backdrop.SGFSkinMenuBag then
        backdrop.SGFSkinMenuBag:Hide()
    end
    if menuBackdrop and menuBackdrop.SGFSkinMenuBag then
        menuBackdrop.SGFSkinMenuBag:Hide()
    end

    -- Restore opaque Blizzard tooltip-like backdrop.
    if backdrop.SetBackdropColor and state.backdropColor then
        backdrop:SetBackdropColor(0, 0, 0, 1)
        backdrop:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    end
    if menuBackdrop and menuBackdrop.SetBackdropColor and state.menuBackdropColor then
        menuBackdrop:SetBackdropColor(0, 0, 0, 1)
        menuBackdrop:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    end

    RestoreFadedTextures(state.regionAlphas)
    if state.listNine and list.NineSlice then list.NineSlice:Show() end
    if state.backdropNine and backdrop.NineSlice then backdrop.NineSlice:Show() end
    if state.menuNine and menuBackdrop and menuBackdrop.NineSlice then menuBackdrop.NineSlice:Show() end

    local maxButtons = UIDROPDOWNMENU_MAXBUTTONS or 40
    for j = 1, maxButtons do
        local highlight = _G["DropDownList" .. level .. "Button" .. j .. "Highlight"]
        local normalText = _G["DropDownList" .. level .. "Button" .. j .. "NormalText"]
        local check = _G["DropDownList" .. level .. "Button" .. j .. "Check"]
        local uncheck = _G["DropDownList" .. level .. "Button" .. j .. "UnCheck"]
        local hc = state.highlight and state.highlight[j]
        if highlight and hc then
            if highlight.SetVertexColor then
                highlight:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 1)
            end
        end
        local tc = state.textColor and state.textColor[j]
        if normalText and tc and normalText.SetTextColor then
            normalText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        end
        local cc = state.checkColor and state.checkColor[j]
        if check and cc and check.SetVertexColor then
            check:SetVertexColor(cc[1], cc[2], cc[3], cc[4] or 1)
        end
        if uncheck and cc and uncheck.SetVertexColor then
            uncheck:SetVertexColor(cc[1], cc[2], cc[3], cc[4] or 1)
        end
    end

    list.SGFMenuSkinned = nil
end

local function StyleOpenDropDownMenus(colors)
    if not colors then
        return
    end
    local maxLevels = UIDROPDOWNMENU_MAXLEVELS or 2
    for i = 1, maxLevels do
        local list = _G["DropDownList" .. i]
        if list and (list:IsShown() or IsOurDropDown(UIDROPDOWNMENU_OPEN_MENU)) then
            StyleDropDownList(i, colors)
        end
    end
end

local function UnstyleAllDropDownMenus()
    local maxLevels = UIDROPDOWNMENU_MAXLEVELS or 2
    for i = 1, maxLevels do
        UnstyleDropDownList(i)
    end
end

local function HookAllDropDownLists()
    local maxLevels = UIDROPDOWNMENU_MAXLEVELS or 2
    for i = 1, maxLevels do
        local list = _G["DropDownList" .. i]
        if list and not list.SGFSkinHooked then
            list:HookScript("OnShow", function()
                local colors = GetActiveColors()
                if colors and IsOurDropDown(UIDROPDOWNMENU_OPEN_MENU) then
                    StyleDropDownList(i, colors)
                end
            end)
            list.SGFSkinHooked = true
        end
    end
end

local function InstallMenuHooks()
    if menuHooksInstalled then
        return
    end
    menuHooksInstalled = true

    local function SkinIfOurs()
        local colors = GetActiveColors()
        if not colors then
            return
        end
        local openMenu = UIDROPDOWNMENU_OPEN_MENU or UIDROPDOWNMENU_INIT_MENU
        if IsOurDropDown(openMenu) then
            StyleOpenDropDownMenus(colors)
        end
    end

    -- Blizzard finishes menu backdrop/button art after ToggleDropDownMenu returns;
    -- restyle once on the next frame so our tokens win.
    local function SkinIfOursNextFrame()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, SkinIfOurs)
        else
            SkinIfOurs()
        end
    end

    if hooksecurefunc then
        if UIDropDownMenu_Initialize then
            hooksecurefunc("UIDropDownMenu_Initialize", function(dropdown)
                if IsOurDropDown(dropdown) then
                    SkinIfOursNextFrame()
                end
            end)
        end
        if ToggleDropDownMenu then
            hooksecurefunc("ToggleDropDownMenu", function(_, _, dropdown)
                if IsOurDropDown(dropdown) or IsOurDropDown(UIDROPDOWNMENU_OPEN_MENU) then
                    SkinIfOurs()
                    SkinIfOursNextFrame()
                end
            end)
        end
        if UIDropDownMenu_CreateFrames then
            hooksecurefunc("UIDropDownMenu_CreateFrames", function()
                HookAllDropDownLists()
                SkinIfOursNextFrame()
            end)
        end
    end

    HookAllDropDownLists()
end

local function StripBlizzardChrome(frame, state)
    local portrait = frame.PortraitContainer
    if portrait then
        HideObj(portrait, state, "portraitContainer")
        if portrait.portrait then
            HideObj(portrait.portrait, state, "portrait")
        end
        if portrait.CircleMask then
            HideObj(portrait.CircleMask, state, "circleMask")
        end
    end
    if frame.portrait then
        HideObj(frame.portrait, state, "legacyPortrait")
    end
    if frame.NineSlice then
        HideObj(frame.NineSlice, state, "nineSlice")
    end
    if frame.TopTileStreaks then
        HideObj(frame.TopTileStreaks, state, "topTile")
    end
    if frame.Bg then
        HideObj(frame.Bg, state, "bg")
    end
    if frame.TitleBg then
        HideObj(frame.TitleBg, state, "titleBg")
    end
    if frame.Inset and frame.Inset.Bg then
        -- Keep inset, but darken via bag; hide default parchment-ish bg if present.
        if state.insetBgShown == nil then
            state.insetBgShown = frame.Inset.Bg:IsShown()
            state.insetBgR, state.insetBgG, state.insetBgB, state.insetBgA = frame.Inset.Bg:GetVertexColor()
        end
    end
end

local function RestoreBlizzardChrome(frame, state)
    if not state then
        return
    end
    local portrait = frame.PortraitContainer
    if portrait then
        RestoreObj(portrait, state, "portraitContainer")
        RestoreObj(portrait.portrait, state, "portrait")
        RestoreObj(portrait.CircleMask, state, "circleMask")
    end
    RestoreObj(frame.portrait, state, "legacyPortrait")
    RestoreObj(frame.NineSlice, state, "nineSlice")
    RestoreObj(frame.TopTileStreaks, state, "topTile")
    RestoreObj(frame.Bg, state, "bg")
    RestoreObj(frame.TitleBg, state, "titleBg")
    if frame.Inset and frame.Inset.Bg and state.insetBgShown ~= nil then
        if state.insetBgShown then
            frame.Inset.Bg:Show()
        end
        if state.insetBgR then
            frame.Inset.Bg:SetVertexColor(state.insetBgR, state.insetBgG, state.insetBgB, state.insetBgA or 1)
        end
    end
end

local function ApplyChromeSkin(frame, widgets, colors)
    if not frame then
        return
    end
    local state = frame.SGFSkinState or {}
    frame.SGFSkinState = state
    StripBlizzardChrome(frame, state)

    local bag = EnsureBackdrop(frame, "SGFSkinBag", -1)
    if bag.SetBackdropColor then
        bag:SetBackdropColor(colors.bgR, colors.bgG, colors.bgB, colors.bgA)
        bag:SetBackdropBorderColor(colors.borderR, colors.borderG, colors.borderB, 1)
    end
    bag:Show()

    local inset = widgets.inset or frame.Inset or frame.inset
    if inset then
        local insetBag = EnsureBackdrop(inset, "SGFSkinInsetBag", 0)
        insetBag:ClearAllPoints()
        insetBag:SetPoint("TOPLEFT", inset, "TOPLEFT", 2, -2)
        insetBag:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -2, 2)
        if insetBag.SetBackdropColor then
            insetBag:SetBackdropColor(colors.insetR, colors.insetG, colors.insetB, colors.insetA)
            insetBag:SetBackdropBorderColor(colors.borderR, colors.borderG, colors.borderB, 0.9)
        end
        insetBag:Show()
        if inset.Bg then
            inset.Bg:SetVertexColor(colors.insetR, colors.insetG, colors.insetB, 1)
        end
        if inset.SkillGuideForeverPanel then
            inset.SkillGuideForeverPanel:SetColorTexture(colors.insetR, colors.insetG, colors.insetB, colors.insetA)
        end
        if inset.SkillGuideForeverProfPanel then
            inset.SkillGuideForeverProfPanel:SetColorTexture(colors.insetR, colors.insetG, colors.insetB, colors.insetA)
        end
    end

    -- Layout first so dropdown chrome pieces are in their final place before overlays.
    if ns.SetPortraitClearance then
        ns.SetPortraitClearance(frame, false)
    end

    StyleEditBox(
        widgets.searchBox,
        colors.editR, colors.editG, colors.editB, colors.editA,
        colors.borderR, colors.borderG, colors.borderB
    )
    StyleDropDown(widgets.dropdown, colors)
    InstallMenuHooks()

    local title = frame.TitleContainer and frame.TitleContainer.TitleText or frame.TitleText
    if title and title.SetTextColor then
        if state.titleR == nil then
            state.titleR, state.titleG, state.titleB = title:GetTextColor()
        end
        title:SetTextColor(colors.titleR, colors.titleG, colors.titleB)
    end

    frame.SGFActiveBuiltInSkin = colors.id
end

local function RemoveChromeSkin(frame, widgets)
    if not frame then
        return
    end
    CloseOurDropDownMenus()
    if frame.SGFSkinBag then
        frame.SGFSkinBag:Hide()
    end
    local inset = widgets and (widgets.inset or frame.Inset or frame.inset)
    if inset and inset.SGFSkinInsetBag then
        inset.SGFSkinInsetBag:Hide()
    end
    UnstyleEditBox(widgets and widgets.searchBox)
    UnstyleDropDown(widgets and widgets.dropdown)
    RestoreBlizzardChrome(frame, frame.SGFSkinState)
    local title = frame.TitleContainer and frame.TitleContainer.TitleText or frame.TitleText
    local state = frame.SGFSkinState
    if title and state and state.titleR then
        title:SetTextColor(state.titleR, state.titleG, state.titleB)
    end
    -- Restore Blizzard portrait clearance for the toolbar.
    if ns.SetPortraitClearance then
        ns.SetPortraitClearance(frame, true)
    end
    frame.SGFActiveBuiltInSkin = nil
end

local FLAT_COLORS = {
    id = "flat",
    bgR = 0.07, bgG = 0.07, bgB = 0.09, bgA = 0.96,
    insetR = 0.10, insetG = 0.10, insetB = 0.12, insetA = 0.98,
    borderR = 0.22, borderG = 0.22, borderB = 0.26,
    editR = 0.12, editG = 0.12, editB = 0.14, editA = 0.95,
    titleR = 0.90, titleG = 0.90, titleB = 0.92,
}

local MIDNIGHT_COLORS = {
    id = "midnight",
    bgR = 0.06, bgG = 0.05, bgB = 0.07, bgA = 0.97,
    insetR = 0.09, insetG = 0.08, insetB = 0.10, insetA = 0.98,
    borderR = 0.72, borderG = 0.58, borderB = 0.28,
    editR = 0.11, editG = 0.09, editB = 0.12, editA = 0.95,
    titleR = 1.00, titleG = 0.82, titleB = 0.30,
}

local COLOR_BY_KEY = {
    flat = FLAT_COLORS,
    midnight = MIDNIGHT_COLORS,
}

local function ApplyBuiltInSkin(frame, kind)
    if not frame then
        return
    end
    local widgets = GetWidgets(frame)
    local key = CurrentSkinKey()
    if key == "blizzard" then
        activeColors = nil
        CloseOurDropDownMenus()
        UnstyleAllDropDownMenus()
        RemoveChromeSkin(frame, widgets)
        return
    end
    local colors = COLOR_BY_KEY[key]
    if colors then
        activeColors = colors
        ApplyChromeSkin(frame, widgets, colors)
    end
end

local function OnSkinEvent(owner, event, frame, a2, a3)
    -- Callback signatures:
    -- MainFrameCreated(frame, widgets)
    -- ProfessionFrameCreated(frame, widgets)
    -- FrameCreated(frame, kind, widgets)
    -- SkinRefresh(frame, kind)
    -- FrameShow(frame, kind) / MainFrameShow(frame)
    local kind = nil
    if event == "FrameCreated" or event == "SkinRefresh" or event == "FrameShow" then
        kind = a2
    elseif event == "MainFrameCreated" or event == "MainFrameShow" then
        kind = "main"
        if type(a2) == "table" then
            frame.SkillGuideForeverWidgets = frame.SkillGuideForeverWidgets or a2
        end
    elseif event == "ProfessionFrameCreated" or event == "ProfessionFrameShow" then
        kind = "profession"
        if type(a2) == "table" then
            frame.SkillGuideForeverWidgets = frame.SkillGuideForeverWidgets or a2
        end
    end
    if event == "FrameCreated" and type(a3) == "table" then
        frame.SkillGuideForeverWidgets = frame.SkillGuideForeverWidgets or a3
    end
    ApplyBuiltInSkin(frame, kind)
end

local function RefreshAllBuiltInSkins()
    local api = SkillGuideForeverAPI
    if not api then
        return
    end
    local frames = api:GetFrames()
    if frames.main then
        ApplyBuiltInSkin(frames.main, "main")
    end
    if frames.profession then
        ApplyBuiltInSkin(frames.profession, "profession")
    end
end

function ns.GetBuiltInSkinOptions()
    return SKIN_ORDER, SKIN_LABELS
end

function ns.SetBuiltInSkin(key)
    if not SKIN_LABELS[key] then
        key = "blizzard"
    end
    if ns.db then
        ns.db.builtInSkin = key
    end
    -- Built-in skins ride the same callback bus; keep events enabled while testing.
    if key ~= "blizzard" and ns.db and ns.db.allowExternalSkins == false then
        ns.db.allowExternalSkins = true
    end

    CloseOurDropDownMenus()

    if key == "blizzard" then
        activeColors = nil
        UnstyleAllDropDownMenus()
    else
        activeColors = COLOR_BY_KEY[key]
        InstallMenuHooks()
    end

    RefreshAllBuiltInSkins()

    if ns.RequestSkinRefresh then
        ns.RequestSkinRefresh()
    end
    if ns.FireCallback then
        ns.FireCallback("OptionsChanged", "builtInSkin", key)
    end
end

function ns.InitBuiltInSkins()
    if registered then
        activeColors = COLOR_BY_KEY[CurrentSkinKey()]
        InstallMenuHooks()
        RefreshAllBuiltInSkins()
        return
    end
    local api = SkillGuideForeverAPI
    if not api or not api.RegisterCallback then
        return
    end
    api:RegisterCallback("MainFrameCreated", OnSkinEvent, OWNER)
    api:RegisterCallback("ProfessionFrameCreated", OnSkinEvent, OWNER)
    api:RegisterCallback("FrameCreated", OnSkinEvent, OWNER)
    api:RegisterCallback("SkinRefresh", OnSkinEvent, OWNER)
    api:RegisterCallback("MainFrameShow", OnSkinEvent, OWNER)
    api:RegisterCallback("ProfessionFrameShow", OnSkinEvent, OWNER)
    api:RegisterCallback("FrameShow", OnSkinEvent, OWNER)
    registered = true
    activeColors = COLOR_BY_KEY[CurrentSkinKey()]
    InstallMenuHooks()
    RefreshAllBuiltInSkins()
end
