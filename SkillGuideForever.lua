local addonName, ns = ...

local eventFrame = CreateFrame("Frame")

function eventFrame:ADDON_LOADED(loaded)
    if loaded ~= addonName then
        return
    end
    -- Migrate settings from earlier local names if present.
    if SkillGuideForeverDB == nil then
        if type(TrainLedgerDB) == "table" then
            SkillGuideForeverDB = TrainLedgerDB
        elseif type(SkillGuideDB) == "table" then
            SkillGuideForeverDB = SkillGuideDB
        end
    end
    SkillGuideForeverDB = SkillGuideForeverDB or {}
    ns.db = SkillGuideForeverDB
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
    if ns.db.selectedProfession == nil then
        ns.db.selectedProfession = nil
    end
    if ns.db.hideKnownProfession == nil then
        ns.db.hideKnownProfession = false
    end
    if ns.db.hideRecipeProfession == nil then
        ns.db.hideRecipeProfession = false
    end
    if ns.db.professionPoint == nil then
        ns.db.professionPoint = "CENTER"
        ns.db.professionX = 40
        ns.db.professionY = 0
    end
    if ns.EnsureIntegrationDefaults then
        ns.EnsureIntegrationDefaults()
    end
    self:UnregisterEvent("ADDON_LOADED")
end

function eventFrame:PLAYER_LOGIN()
    if not ns.db.selectedClass then
        ns.db.selectedClass = ns.GetPlayerClassFile()
    end
    if not ns.db.selectedProfession then
        ns.db.selectedProfession = ns.GetDefaultProfessionKey and ns.GetDefaultProfessionKey() or "ALCHEMY"
    end
    if ns.InitOptions then
        ns.InitOptions()
    end
    if ns.CreateMainFrame then
        ns.CreateMainFrame()
    end
    if ns.InitSpellbookIntegration then
        ns.InitSpellbookIntegration()
    end
    if ns.CreateProfessionFrame then
        ns.CreateProfessionFrame()
    end
    if ns.InitProfessionsBookIntegration then
        ns.InitProfessionsBookIntegration()
    end
end

function eventFrame:SPELL_DATA_LOAD_RESULT(spellID, success)
    if ns.OnSpellDataLoaded then
        ns.OnSpellDataLoaded(spellID, success)
    end
    if ns.OnProfessionSpellDataLoaded then
        ns.OnProfessionSpellDataLoaded(spellID, success)
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
    if ns.RefreshProfessionList then
        ns.RefreshProfessionList()
    end
end

function eventFrame:SKILL_LINES_CHANGED()
    if ns.RefreshProfessionList then
        ns.RefreshProfessionList()
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
eventFrame:RegisterEvent("SKILL_LINES_CHANGED")

local function HandleClassSlash(msg)
    msg = type(msg) == "string" and strtrim(string.lower(msg)) or ""
    if msg == "config" or msg == "options" or msg == "opt" then
        if ns.OpenOptions then
            ns.OpenOptions()
        end
        return
    end
    if ns.ToggleMainFrame then
        ns.ToggleMainFrame()
    end
end

SLASH_SKILLGUIDEFOREVER1 = "/sg"
SLASH_SKILLGUIDEFOREVER2 = "/skillguideforever"
SlashCmdList.SKILLGUIDEFOREVER = HandleClassSlash

SLASH_SKILLGUIDEFOREVERPROF1 = "/pg"
SLASH_SKILLGUIDEFOREVERPROF2 = "/skillguideprofessions"
SlashCmdList.SKILLGUIDEFOREVERPROF = function(msg)
    msg = type(msg) == "string" and strtrim(string.lower(msg)) or ""
    if msg == "config" or msg == "options" or msg == "opt" then
        if ns.OpenOptions then
            ns.OpenOptions()
        end
        return
    end
    if ns.ToggleProfessionFrame then
        ns.ToggleProfessionFrame()
    end
end
