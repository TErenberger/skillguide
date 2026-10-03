local addonName, ns = ...

local eventFrame = CreateFrame("Frame")

function eventFrame:ADDON_LOADED(loaded)
    if loaded ~= addonName then
        return
    end
    SkillGuideDB = SkillGuideDB or {}
    ns.db = SkillGuideDB
    if ns.db.point == nil then
        ns.db.point = "CENTER"
        ns.db.x = 0
        ns.db.y = 0
    end
    if ns.db.selectedClass == nil then
        ns.db.selectedClass = nil
    end
    if ns.db.hideKnown == nil then
        ns.db.hideKnown = false
    end
    self:UnregisterEvent("ADDON_LOADED")
end

function eventFrame:PLAYER_LOGIN()
    if not ns.db.selectedClass then
        ns.db.selectedClass = ns.GetPlayerClassFile()
    end
    if ns.CreateMainFrame then
        ns.CreateMainFrame()
    end
end

function eventFrame:SPELL_DATA_LOAD_RESULT(spellID, success)
    if ns.OnSpellDataLoaded then
        ns.OnSpellDataLoaded(spellID, success)
    end
end

function eventFrame:PLAYER_LEVEL_UP()
    if ns.RefreshSkillList then
        ns.RefreshSkillList()
    end
end

function eventFrame:SPELLS_CHANGED()
    if ns.RefreshSkillList then
        ns.RefreshSkillList()
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, ...)
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("SPELLS_CHANGED")

SLASH_SKILLGUIDE1 = "/skillguide"
SLASH_SKILLGUIDE2 = "/sg"
SlashCmdList.SKILLGUIDE = function()
    if ns.ToggleMainFrame then
        ns.ToggleMainFrame()
    end
end
