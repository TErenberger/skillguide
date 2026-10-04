local addonName, ns = ...

ns.CLASS_ORDER = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "DRUID",
}

local CLASS_DISPLAY = {
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
    HUNTER = "Hunter",
    ROGUE = "Rogue",
    PRIEST = "Priest",
    SHAMAN = "Shaman",
    MAGE = "Mage",
    WARLOCK = "Warlock",
    DRUID = "Druid",
}

function ns.GetClassDisplayName(classFile)
    return CLASS_DISPLAY[classFile] or classFile
end

--- Format Wowhead/trainer copper using Blizzard gold/silver/copper coin icons when available.
--- Returns nil when copper is missing or zero so callers can omit the segment.
function ns.FormatCopper(copper, fontHeight)
    copper = tonumber(copper)
    if not copper or copper <= 0 then
        return nil
    end
    copper = math.floor(copper + 0.5)
    fontHeight = tonumber(fontHeight) or 10

    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        local ok, text = pcall(C_CurrencyInfo.GetCoinTextureString, copper, fontHeight)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end
    if GetCoinTextureString then
        local ok, text = pcall(GetCoinTextureString, copper, fontHeight)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end

    -- Fallback if coin-texture APIs are unavailable.
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperOnly = copper % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if copperOnly > 0 or #parts == 0 then
        parts[#parts + 1] = copperOnly .. "c"
    end
    return table.concat(parts, " ")
end

function ns.GetPlayerClassFile()
    local classFile
    if UnitClassBase then
        classFile = UnitClassBase("player")
    end
    if not classFile then
        local _, file = UnitClass("player")
        classFile = file
    end
    if type(classFile) == "string" then
        return string.upper(classFile)
    end
    return "WARRIOR"
end

function ns.GetSkillsForClass(classFile)
    if not classFile or not ns.SkillData then
        return nil
    end
    return ns.SkillData[string.upper(classFile)]
end

function ns.IsPlayerSpellKnown(spellID)
    if not spellID then
        return false
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known then
            return true
        end
    end
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, spellID)
        if ok and known then
            return true
        end
    end
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, spellID)
        if ok and known then
            return true
        end
    end
    return false
end

function ns.GetPlayerLevel()
    local level = UnitLevel("player")
    if type(issecretvalue) == "function" and issecretvalue(level) then
        return nil
    end
    return level
end

--- Build a spell hyperlink and insert it into the active chat edit box (Shift-click / CHATLINK).
--- Returns true if a link was inserted.
function ns.TryInsertSpellChatLink(spellID, fallbackName)
    if not spellID then
        return false
    end
    if IsModifiedClick and not IsModifiedClick("CHATLINK") then
        return false
    end

    local link
    if C_Spell and C_Spell.GetSpellLink then
        local ok, result = pcall(C_Spell.GetSpellLink, spellID)
        if ok then
            link = result
        end
    end
    if (not link or link == "") and GetSpellLink then
        local ok, result = pcall(GetSpellLink, spellID)
        if ok then
            link = result
        end
    end

    -- Some clients return a bare name; build a proper |Hspell:| hyperlink.
    if type(link) ~= "string" or link == "" or not string.find(link, "|H", 1, true) then
        local name = fallbackName
        if (not name or name == "") and C_Spell and C_Spell.GetSpellName then
            local ok, result = pcall(C_Spell.GetSpellName, spellID)
            if ok then
                name = result
            end
        end
        if not name or name == "" then
            name = "Spell " .. tostring(spellID)
        end
        name = string.gsub(name, "[%[%]]", "")
        link = string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r", spellID, name)
    end

    if ChatEdit_InsertLink then
        local ok, inserted = pcall(ChatEdit_InsertLink, link)
        if ok and inserted then
            return true
        end
    end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        local ok, inserted = pcall(ChatFrameUtil.InsertLink, link)
        if ok and inserted then
            return true
        end
    end

    local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if editBox and editBox.Insert then
        editBox:Insert(link)
        return true
    end
    return false
end
