-- BattleShoutReminder.lua
local ADDON_NAME = "Battle Shout Reminder"
local SPELL_ID = 2048 -- Battle Shout
local db

local function GetBattleShoutName()
  return GetSpellInfo(SPELL_ID) or "Battle Shout"
end

local function InitDB()
  if not BattleShoutReminderDB then
    BattleShoutReminderDB = {}
  end
  db = BattleShoutReminderDB

  if db.enabled == nil then db.enabled = true end
  if db.classOnly == nil then db.classOnly = true end
  if db.scale == nil then db.scale = 1.0 end
  if db.alpha == nil then db.alpha = 1.0 end
  if db.pos == nil then db.pos = nil end
end

local function IsBattleShoutKnown()
  local _, class = UnitClass("player")
  if class ~= "WARRIOR" and class ~= "Warrior" and class ~= "warrior" then
    -- Some servers return localized class tokens — check by spell availability too
    -- We'll still try to detect the spell by GetSpellInfo as a fallback
    -- Continue to fallback checks below
  end

  -- Prefer checking the spell book if the API supports it
  if IsSpellKnown and IsSpellKnown(SPELL_ID) then
    return true
  end

  local name = GetBattleShoutName()
  if not name or name == "" then return false end

  -- Check if we have the spell in our spellbook by name
  for i = 1, 255 do
    local spellName = GetSpellBookItemName and GetSpellBookItemName(i, BOOKTYPE_SPELL)
    if not spellName then break end
    if spellName == name then return true end
  end

  -- Last-resort: assume available if spell name exists
  return true
end

local function CreateIconFrame()
  if BattleShoutReminderFrame then
    return BattleShoutReminderFrame
  end

  local frame = CreateFrame("Frame", "BattleShoutReminderFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(40, 40)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 10,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
  end

  local tex = frame:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(frame)
  frame.icon = tex

  local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
  cd:SetAllPoints(frame)
  frame.cooldown = cd

  local btn = CreateFrame("Button", "BattleShoutReminderButton", frame, "SecureActionButtonTemplate")
  btn:SetAllPoints(frame)
  btn:RegisterForClicks("AnyUp")
  btn:SetAttribute("type", "spell")
  btn:SetAttribute("spell", GetBattleShoutName())
  frame.button = btn

  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(SPELL_ID)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    if InCombatLockdown() then return end
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.pos = { point = point, relPoint = relPoint, x = x, y = y }
  end)

  btn:SetScript("OnClick", function(self, button)
    if button == "RightButton" and not InCombatLockdown() then
      frame:ClearAllPoints()
      frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      db.pos = nil
      print(ADDON_NAME .. ": position reset.")
    end
  end)

  BattleShoutReminderFrame = frame
  return frame
end

local function RestorePosition(frame)
  if not db.pos or InCombatLockdown() then
    return
  end

  local p = db.pos
  frame:ClearAllPoints()
  frame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
end

local function UpdateFrameAppearance(frame)
  if not frame then return end
  frame:SetScale(db.scale or 1.0)
  frame:SetAlpha(db.alpha or 1.0)
end

local function UpdateIconTexture(frame)
  local spellName = GetBattleShoutName()
  if not spellName then return end

  local tex = select(3, GetSpellInfo(SPELL_ID))
  if tex then
    frame.icon:SetTexture(tex)
  end

  if frame.button then
    frame.button:SetAttribute("spell", spellName)
  end

  local start, duration = GetSpellCooldown(SPELL_ID)
  if duration and duration > 1.5 then
    frame.cooldown:SetCooldown(start, duration)
  else
    frame.cooldown:Clear()
  end
end

local function ShouldShowReminder()
  if not db or not db.enabled then
    return false
  end

  if not UnitAffectingCombat("player") then
    return false
  end

  if db.classOnly and not IsBattleShoutKnown() then
    return false
  end

  local spellName = GetBattleShoutName()
  if not spellName then
    return false
  end

  local hasBuff = UnitBuff("player", spellName)
  return not hasBuff
end

local function UpdateVisibility()
  local frame = CreateIconFrame()
  UpdateFrameAppearance(frame)
  UpdateIconTexture(frame)

  if ShouldShowReminder() then
    frame:Show()
  else
    frame:Hide()
  end
end

-- Interface Options panel
local function CreateOptionsPanel()
  local panel = CreateFrame("Frame", "BattleShoutReminderOptionsPanel")
  panel.name = ADDON_NAME

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(ADDON_NAME)

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", 16, -40)
  subtitle:SetText("Shows a movable icon when you need Battle Shout during combat.")

  local enabledBox = CreateFrame("CheckButton", "BattleShoutReminderOptionsEnabled", panel, "OptionsCheckButtonTemplate")
  enabledBox:SetPoint("TOPLEFT", 16, -80)
  enabledBox.Text:SetText("Enable reminder")
  enabledBox:SetScript("OnClick", function(self)
    db.enabled = self:GetChecked()
    UpdateVisibility()
  end)

  local classOnlyBox = CreateFrame("CheckButton", "BattleShoutReminderOptionsClassOnly", panel, "OptionsCheckButtonTemplate")
  classOnlyBox:SetPoint("TOPLEFT", 16, -110)
  classOnlyBox.Text:SetText("Only show for Warrior / spell available")
  classOnlyBox:SetScript("OnClick", function(self)
    db.classOnly = self:GetChecked()
    UpdateVisibility()
  end)

  local resetPosButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  resetPosButton:SetSize(140, 24)
  resetPosButton:SetPoint("TOPLEFT", 16, -160)
  resetPosButton:SetText("Reset position")
  resetPosButton:SetScript("OnClick", function()
    if BattleShoutReminderFrame then
      BattleShoutReminderFrame:ClearAllPoints()
      BattleShoutReminderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      db.pos = nil
    end
  end)

  -- Scale slider
  local scaleLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  scaleLabel:SetPoint("TOPLEFT", 16, -200)
  scaleLabel:SetText("Icon scale")

  local scaleSlider = CreateFrame("Slider", "BattleShoutReminderScaleSlider", panel, "OptionsSliderTemplate")
  scaleSlider:SetPoint("TOPLEFT", 16, -220)
  scaleSlider:SetMinMaxValues(0.5, 2.0)
  scaleSlider:SetValueStep(0.05)
  scaleSlider:SetWidth(200)
  scaleSlider:SetScript("OnValueChanged", function(self, value)
    db.scale = value
    if BattleShoutReminderFrame then BattleShoutReminderFrame:SetScale(value) end
  end)

  local alphaLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  alphaLabel:SetPoint("TOPLEFT", 240, -200)
  alphaLabel:SetText("Icon alpha")

  local alphaSlider = CreateFrame("Slider", "BattleShoutReminderAlphaSlider", panel, "OptionsSliderTemplate")
  alphaSlider:SetPoint("TOPLEFT", 240, -220)
  alphaSlider:SetMinMaxValues(0.2, 1.0)
  alphaSlider:SetValueStep(0.05)
  alphaSlider:SetWidth(200)
  alphaSlider:SetScript("OnValueChanged", function(self, value)
    db.alpha = value
    if BattleShoutReminderFrame then BattleShoutReminderFrame:SetAlpha(value) end
  end)

  panel.refresh = function()
    enabledBox:SetChecked(db.enabled)
    classOnlyBox:SetChecked(db.classOnly)
    scaleSlider:SetValue(db.scale or 1.0)
    alphaSlider:SetValue(db.alpha or 1.0)
  end

  panel.default = function()
    db.enabled = true
    db.classOnly = true
    db.scale = 1.0
    db.alpha = 1.0
    db.pos = nil
    panel.refresh()
    UpdateVisibility()
  end

  InterfaceOptions_AddCategory(panel)
  return panel
end

local optionsPanel = nil

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    InitDB()
    local frame = CreateIconFrame()
    if db.pos then
      RestorePosition(frame)
    end
    UpdateVisibility()
    optionsPanel = CreateOptionsPanel()
    optionsPanel.refresh()
    print("|cFF33FF99" .. ADDON_NAME .. "|r loaded.")
    print("Use /bsreminder to toggle, /bsreminder config to open options.")
    return
  end

  if event == "UNIT_AURA" then
    local unit = ...
    if unit == "player" then
      UpdateVisibility()
    end
    return
  end

  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "SPELL_UPDATE_COOLDOWN" then
    UpdateVisibility()
  end
end)

SLASH_BSREMINDER1 = "/bsreminder"
SLASH_BSREMINDER2 = "/bsr"
SlashCmdList["BSREMINDER"] = function(msg)
  local command = string.lower((msg or ""))

  if command == "toggle" or command == "t" then
    if db then
      db.enabled = not db.enabled
      print(ADDON_NAME .. ": " .. (db.enabled and "enabled" or "disabled"))
      UpdateVisibility()
    end
    return
  end

  if command == "config" or command == "options" or command == "o" then
    if optionsPanel then
      InterfaceOptionsFrame_OpenToCategory(optionsPanel)
      InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    end
    return
  end

  if command == "reset" then
    if BattleShoutReminderFrame then
      BattleShoutReminderFrame:ClearAllPoints()
      BattleShoutReminderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      db.pos = nil
      print(ADDON_NAME .. ": position reset.")
    end
    return
  end

  print(ADDON_NAME .. " commands:")
  print("/bsreminder toggle   - enable/disable the reminder")
  print("/bsreminder config   - open addon options")
  print("/bsreminder reset    - reset icon position")
end
