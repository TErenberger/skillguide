# SkillGuide Forever — skin & addon integration

Zero-dependency hooks for ElvUI, AddOnSkins, and other tools. No Ace3/LibStub required.

## Public API

Global table: `SkillGuideForeverAPI`

| Method | Purpose |
|--------|---------|
| `RegisterCallback(event, fn [, owner])` | Subscribe to skin/lifecycle events |
| `UnregisterCallback(event, fn [, owner])` | Unsubscribe |
| `GetMainFrame()` / `GetProfessionFrame()` | Stable frame getters |
| `GetFrames()` | `{ main = ..., profession = ... }` |
| `IsExternalSkinningEnabled()` | Player opted into external skins |
| `RefreshSkins()` | Re-fire `SkinRefresh` |
| `OpenOptions()` | Open the Settings category |
| `GetVersion()` | TOC version string |

Callback `fn` signature: `function(owner, event, ...)`

## Events

| Event | Payload |
|-------|---------|
| `MainFrameCreated` | `frame, widgets` |
| `ProfessionFrameCreated` | `frame, widgets` |
| `FrameCreated` | `frame, kind, widgets` (`kind` = `"main"` / `"profession"`) |
| `MainFrameShow` / `ProfessionFrameShow` / `FrameShow` | `frame` [, `kind`] |
| `MainFrameHide` / `ProfessionFrameHide` / `FrameHide` | `frame` [, `kind`] |
| `SkinRefresh` | `frame, kind` |
| `OptionsChanged` | `key, value` |

Events are only fired when the player leaves **Allow external skins** enabled (default on).

## Stable globals

- `SkillGuideForeverFrame`
- `SkillGuideForeverProfessionFrame`
- `SkillGuideForeverClassDropdown` / `SkillGuideForeverProfessionDropdown`
- `SkillGuideForeverSearchBox` / `SkillGuideForeverProfSearchBox`
- `SkillGuideForeverHideKnownCheck` / `SkillGuideForeverProfHideKnownCheck`
- `SkillGuideForeverScrollFrame` / `SkillGuideForeverProfessionScrollFrame`

Each frame also exposes `frame.SkillGuideForeverWidgets` with `inset`, `dropdown`, `searchBox`, `hideKnownCheck`, `scrollFrame`, `scrollChild`, `subtitle`.

## Minimal ElvUI / AddOnSkins example

```lua
local API = SkillGuideForeverAPI
if not API then return end

local function SkinFrame(owner, event, frame, widgets)
    if not frame or not API:IsExternalSkinningEnabled() then
        return
    end
    widgets = widgets or frame.SkillGuideForeverWidgets
    -- S:HandleFrame(frame), S:HandleEditBox(widgets.searchBox), etc.
end

API:RegisterCallback("MainFrameCreated", SkinFrame)
API:RegisterCallback("ProfessionFrameCreated", SkinFrame)
API:RegisterCallback("SkinRefresh", SkinFrame)

-- If SkillGuide loaded first and frames already exist:
if API:GetMainFrame() then
    SkinFrame(nil, "MainFrameCreated", API:GetMainFrame(), API:GetMainFrame().SkillGuideForeverWidgets)
end
```

## Player options

Esc → Options → AddOns → **SkillGuide Forever**, or `/sg config`:

- **Window skin** — Blizzard default, or built-in Flat Dark / Midnight Gold test skins (these register on `SkillGuideForeverAPI` the same way ElvUI would)
- Allow external skins
- Window scale
- Frame strata
- Addon Compartment entry

## Built-in test skins

`UI/Skins.lua` is a reference consumer of this API. When you pick a non-Blizzard skin in options it:

1. Registers for `MainFrameCreated` / `ProfessionFrameCreated` / `SkinRefresh` / show events
2. Applies backdrop + chrome stripping on those callbacks
3. Restores Blizzard chrome when you switch back to **Blizzard (default)**

Use that path to verify hook timing without installing ElvUI or AddOnSkins.
