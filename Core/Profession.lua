local addonName, ns = ...

ns.PROFESSION_ORDER = {
    "ALCHEMY",
    "BLACKSMITHING",
    "ENCHANTING",
    "ENGINEERING",
    "HERBALISM",
    "LEATHERWORKING",
    "MINING",
    "SKINNING",
    "TAILORING",
    "COOKING",
    "FIRST_AID",
    "FISHING",
}

local PROFESSION_DISPLAY = {
    ALCHEMY = "Alchemy",
    BLACKSMITHING = "Blacksmithing",
    ENCHANTING = "Enchanting",
    ENGINEERING = "Engineering",
    HERBALISM = "Herbalism",
    LEATHERWORKING = "Leatherworking",
    MINING = "Mining",
    SKINNING = "Skinning",
    TAILORING = "Tailoring",
    COOKING = "Cooking",
    FIRST_AID = "First Aid",
    FISHING = "Fishing",
}

-- Rough icon spell IDs for portrait (resolved via C_Spell when possible).
local PROFESSION_ICON_SPELL = {
    ALCHEMY = 2259,
    BLACKSMITHING = 2018,
    ENCHANTING = 7411,
    ENGINEERING = 4036,
    HERBALISM = 2366,
    LEATHERWORKING = 2108,
    MINING = 2575,
    SKINNING = 8613,
    TAILORING = 3908,
    COOKING = 2550,
    FIRST_AID = 3273,
    FISHING = 7620,
}

function ns.GetProfessionDisplayName(key)
    return PROFESSION_DISPLAY[key] or key
end

function ns.GetProfessionIconSpell(key)
    return PROFESSION_ICON_SPELL[key]
end

function ns.GetRecipesForProfession(key)
    if not key or not ns.ProfessionData then
        return nil
    end
    return ns.ProfessionData[key]
end

function ns.GetDefaultProfessionKey()
    -- Prefer a profession the player actually has when the API is available.
    if GetProfessions then
        local ok, p1, p2, arch, fish, cook, firstAid = pcall(GetProfessions)
        if ok then
            local indices = { p1, p2, cook, firstAid, fish }
            for _, idx in ipairs(indices) do
                if idx then
                    local name = GetProfessionInfo(idx)
                    if type(name) == "string" then
                        local upper = string.upper(name)
                        upper = string.gsub(upper, "%s+", "_")
                        if ns.ProfessionData and ns.ProfessionData[upper] then
                            return upper
                        end
                        -- First Aid -> FIRST_AID already handled; try display map reverse.
                        for key, display in pairs(PROFESSION_DISPLAY) do
                            if string.lower(display) == string.lower(name) then
                                return key
                            end
                        end
                    end
                end
            end
        end
    end
    return "ALCHEMY"
end
