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
