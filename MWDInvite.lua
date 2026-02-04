local ADDON_NAME = ...

MWDInviteDB = MWDInviteDB or {}
local addonWindow

local DEFAULTS = {
  version = 1,
  minimap = {
    show = true,
    angle = 225,
  },
}

local function ApplyDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then
      target[k] = v
    end
  end
end

local function EnsureDefaults()
  ApplyDefaults(MWDInviteDB, DEFAULTS)
end

local guildRoster = {}
local filteredRoster = {}
local selectedInvites = {}
local rosterFilterText = ""
local rosterSortKey = "default"
local rosterSortAsc = true

local function GetGuildKey()
  local guildName, _, _, realmName = GetGuildInfo("player")
  if not guildName then
    return nil
  end
  realmName = realmName or GetRealmName()
  if not realmName or realmName == "" then
    return guildName
  end
  return guildName .. "-" .. realmName
end

local function BuildGRMMainLookup()
  local lookup = {}
  if not GRM_Alts then
    return lookup
  end

  local guildKey = GetGuildKey()
  local guildAlts = guildKey and GRM_Alts[guildKey] or nil
  if type(guildAlts) ~= "table" then
    return lookup
  end

  for _, group in pairs(guildAlts) do
    if type(group) == "table" and type(group.main) == "string" and group.main ~= "" then
      lookup[group.main] = group.main
      local shortMain = Ambiguate(group.main, "short")
      if shortMain then
        lookup[shortMain] = group.main
      end
      for _, member in ipairs(group) do
        local memberName = member.name
        if memberName then
          lookup[memberName] = group.main
          local shortName = Ambiguate(memberName, "short")
          if shortName then
            lookup[shortName] = group.main
          end
        end
      end
    end
  end

  return lookup
end

function RefreshGuildRoster()
  guildRoster = {}
  if not IsInGuild() then
    return
  end

  if GuildRosterSetShowOffline then
    GuildRosterSetShowOffline(true)
  end
  if GuildRoster then
    GuildRoster()
  elseif C_GuildInfo and C_GuildInfo.GuildRoster then
    C_GuildInfo.GuildRoster()
  end

  local mainLookup = BuildGRMMainLookup()
  local total = 0
  if GetNumGuildMembers then
    total = GetNumGuildMembers()
  elseif C_GuildInfo and C_GuildInfo.GetNumGuildMembers then
    total = C_GuildInfo.GetNumGuildMembers()
  end
  for i = 1, total do
    local name, rankName, rankIndex, level, class, zone, _, _, online, _, classFileName
    if GetGuildRosterInfo then
      name, rankName, rankIndex, level, class, zone, _, _, online, _, classFileName = GetGuildRosterInfo(i)
    elseif C_GuildInfo and C_GuildInfo.GetGuildRosterInfo then
      name, rankName, rankIndex, level, class, zone, _, _, online, _, classFileName = C_GuildInfo.GetGuildRosterInfo(i)
    end
    local isRetired = rankName and rankName:lower():find("retired", 1, true)
    local displayName = name and Ambiguate(name, "none") or ""
    local shortName = name and Ambiguate(name, "short") or displayName
    local mainName = ""
    if name then
      mainName = mainLookup[name] or mainLookup[displayName] or mainLookup[shortName] or ""
    end
    if name and not isRetired then
      guildRoster[#guildRoster + 1] = {
        inviteName = name,
        displayName = displayName,
        level = level or 0,
        class = class or "",
        classFileName = classFileName,
        online = online and true or false,
        rankIndex = rankIndex or 99,
        rankName = rankName or "",
        zone = zone or "",
        main = mainName,
      }
    end
  end
end

function ApplyRosterFilter()
  filteredRoster = {}
  local filter = rosterFilterText and rosterFilterText:lower() or ""
  for _, entry in ipairs(guildRoster) do
    if filter == "" or entry.displayName:lower():find(filter, 1, true) then
      filteredRoster[#filteredRoster + 1] = entry
    end
  end

  local function defaultSort(a, b)
    if a.online ~= b.online then
      return a.online
    end
    if a.rankIndex ~= b.rankIndex then
      return a.rankIndex < b.rankIndex
    end
    return a.displayName < b.displayName
  end

  local function nameSort(a, b)
    if a.online ~= b.online then
      return a.online
    end
    if a.displayName == b.displayName then
      return defaultSort(a, b)
    end
    return a.displayName < b.displayName
  end

  local function classSort(a, b)
    if a.online ~= b.online then
      return a.online
    end
    local classA = a.class or ""
    local classB = b.class or ""
    if classA == classB then
      return nameSort(a, b)
    end
    return classA < classB
  end

  local function zoneSort(a, b)
    if a.online ~= b.online then
      return a.online
    end
    local zoneA = a.zone or ""
    local zoneB = b.zone or ""
    if zoneA == zoneB then
      return nameSort(a, b)
    end
    return zoneA < zoneB
  end

  local function mainSort(a, b)
    if a.online ~= b.online then
      return a.online
    end
    local mainA = a.main or ""
    local mainB = b.main or ""
    if mainA == mainB then
      return nameSort(a, b)
    end
    return mainA < mainB
  end

  local sorter = defaultSort
  if rosterSortKey == "name" then
    sorter = nameSort
  elseif rosterSortKey == "class" then
    sorter = classSort
  elseif rosterSortKey == "zone" then
    sorter = zoneSort
  elseif rosterSortKey == "main" then
    sorter = mainSort
  elseif rosterSortKey == "status" then
    sorter = defaultSort
  end

  table.sort(filteredRoster, function(a, b)
    local result = sorter(a, b)
    if rosterSortAsc then
      return result
    end
    return not result
  end)
end

local function ShowPartyInviteLimitPopup(count)
  local text = "You selected " .. count .. " members.\n\nParty invites support up to 4. Reduce the selection and try again."
  if not StaticPopupDialogs["MWDINV_PARTY_LIMIT"] then
    StaticPopupDialogs["MWDINV_PARTY_LIMIT"] = {
      text = text,
      button1 = "OK",
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  else
    StaticPopupDialogs["MWDINV_PARTY_LIMIT"].text = text
  end
  StaticPopup_Show("MWDINV_PARTY_LIMIT")
end

local function ShowRaidInviteMinimumPopup(count)
  local text = "You selected " .. count .. " members.\n\nRaid invites require 5 or more. Add more and try again."
  if not StaticPopupDialogs["MWDINV_RAID_MIN"] then
    StaticPopupDialogs["MWDINV_RAID_MIN"] = {
      text = text,
      button1 = "OK",
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  else
    StaticPopupDialogs["MWDINV_RAID_MIN"].text = text
  end
  StaticPopup_Show("MWDINV_RAID_MIN")
end

local function ShowSelfSelectPopup()
  if not StaticPopupDialogs["MWDINV_SELF_SELECT"] then
    StaticPopupDialogs["MWDINV_SELF_SELECT"] = {
      text = "You selected your own character. Deselecting it.",
      button1 = "OK",
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  end
  StaticPopup_Show("MWDINV_SELF_SELECT")
end

local function GetSelectedMembers()
  local selected = {}
  for name, isSelected in pairs(selectedInvites) do
    if isSelected then
      selected[#selected + 1] = name
    end
  end
  return selected
end

local function ConvertToRaidIfNeeded(onReady)
  if IsInRaid() then
    onReady()
    return
  end

  if not IsInGroup() then
    onReady()
    return
  end

  if not UnitIsGroupLeader("player") then
    print("MWD Invite: you must be party leader to convert to a raid.")
    onReady()
    return
  end

  if C_PartyInfo and C_PartyInfo.ConvertToRaid then
    C_PartyInfo.ConvertToRaid()
  elseif ConvertToRaid then
    ConvertToRaid()
  end

  C_Timer.After(0.2, onReady)
end

local function InviteMembers(selected)
  for _, name in ipairs(selected) do
    if InviteUnit then
      InviteUnit(name)
    elseif C_PartyInfo and C_PartyInfo.InviteUnit then
      C_PartyInfo.InviteUnit(name)
    end
  end
end

local function InviteToParty()
  local selected = GetSelectedMembers()

  if #selected == 0 then
    print("MWD Invite: no members selected.")
    return
  end

  if #selected <= 4 then
    InviteMembers(selected)
    print("MWD Invite: invited " .. #selected .. " to party.")
    return
  end
  ShowPartyInviteLimitPopup(#selected)
end

local function InviteToRaid()
  local selected = GetSelectedMembers()

  if #selected == 0 then
    print("MWD Invite: no members selected.")
    return
  end

  if #selected < 5 then
    ShowRaidInviteMinimumPopup(#selected)
    return
  end

  ConvertToRaidIfNeeded(function()
    InviteMembers(selected)
    print("MWD Invite: invited " .. #selected .. " to raid.")
  end)
end

local function InviteNoLimit()
  local selected = GetSelectedMembers()

  if #selected == 0 then
    print("MWD Invite: no members selected.")
    return
  end

  if #selected > 4 then
    ConvertToRaidIfNeeded(function()
      InviteMembers(selected)
      print("MWD Invite: invited " .. #selected .. " to your group.")
    end)
    return
  end

  InviteMembers(selected)
  print("MWD Invite: invited " .. #selected .. " to your group.")
end

local function ClearSelectedMembers()
  selectedInvites = {}
end

EnsureDefaults()
local function CreateAddonWindow()
  local window = CreateFrame("Frame", "MWDInviteWindow", UIParent, "BasicFrameTemplateWithInset")
  window:SetSize(560, 680)
  window:SetPoint("CENTER")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:Hide()

  window.TitleText:SetText("MWD Invite to Play")

  local subtitle = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  subtitle:SetPoint("TOPLEFT", 16, -40)
  subtitle:SetWidth(528)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("Quickly invite guild members to your party or raid.")

  local note = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  note:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
  note:SetWidth(528)
  note:SetJustifyH("LEFT")
  note:SetText("Select members, then use the invite buttons below.")

  local filterLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  filterLabel:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -14)
  filterLabel:SetText("Search")

  local filterBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
  filterBox:SetSize(280, 20)
  filterBox:SetPoint("LEFT", filterLabel, "RIGHT", 8, 0)
  filterBox:SetAutoFocus(false)
  filterBox:SetScript("OnTextChanged", function(self)
    rosterFilterText = self:GetText() or ""
    ApplyRosterFilter()
    window.UpdateRoster()
  end)

  local refreshBtn = CreateFrame("Button", nil, window, "GameMenuButtonTemplate")
  refreshBtn:SetPoint("LEFT", filterBox, "RIGHT", 8, 0)
  refreshBtn:SetSize(90, 22)
  refreshBtn:SetText("Refresh")
  refreshBtn:SetScript("OnClick", function()
    RefreshGuildRoster()
    ApplyRosterFilter()
    window.UpdateRoster()
  end)

  local clearSortBtn = CreateFrame("Button", nil, window, "GameMenuButtonTemplate")
  clearSortBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
  clearSortBtn:SetSize(90, 22)
  clearSortBtn:SetText("Clear Sort")
  clearSortBtn:SetScript("OnClick", function()
    filterBox:SetText("")
    rosterSortKey = "default"
    rosterSortAsc = true
    RefreshGuildRoster()
    ApplyRosterFilter()
    window.UpdateRoster()
  end)

  local listHeader = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  listHeader:SetPoint("TOPLEFT", filterLabel, "BOTTOMLEFT", 0, -10)
  listHeader:SetText("Guild Members")

  local listFrame = CreateFrame("Frame", nil, window, "InsetFrameTemplate3")
  listFrame:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -6)
  listFrame:SetSize(528, 420)

  local headerHeight = 18
  local headerRow = CreateFrame("Frame", nil, listFrame)
  headerRow:SetPoint("TOPLEFT", 6, -6)
  headerRow:SetPoint("RIGHT", -28, 0)
  headerRow:SetHeight(headerHeight)

  local headerName = headerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  headerName:SetPoint("LEFT", headerRow, "LEFT", 0, 0)
  headerName:SetJustifyH("LEFT")
  headerName:SetText("Name")

  local headerClass = headerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  headerClass:SetPoint("LEFT", headerName, "RIGHT", 4, 0)
  headerClass:SetJustifyH("LEFT")
  headerClass:SetText("Class")

  local headerZone = headerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  headerZone:SetPoint("LEFT", headerClass, "RIGHT", 4, 0)
  headerZone:SetJustifyH("LEFT")
  headerZone:SetText("Zone")

  local headerMain = headerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  headerMain:SetPoint("LEFT", headerZone, "RIGHT", 4, 0)
  headerMain:SetJustifyH("LEFT")
  headerMain:SetText("Main")

  local headerStatus = headerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  headerStatus:SetPoint("LEFT", headerMain, "RIGHT", 4, 0)
  headerStatus:SetJustifyH("LEFT")
  headerStatus:SetText("Status")

  local function SetRosterSort(key)
    if rosterSortKey == key then
      rosterSortAsc = not rosterSortAsc
    else
      rosterSortKey = key
      rosterSortAsc = true
    end
    ApplyRosterFilter()
    window.UpdateRoster()
  end

  local function AttachHeaderClick(fontString, key)
    local button = CreateFrame("Button", nil, headerRow)
    button:SetAllPoints(fontString)
    button:SetScript("OnClick", function()
      if key == "status" then
        rosterSortKey = "default"
        rosterSortAsc = true
      else
        SetRosterSort(key)
        return
      end
      ApplyRosterFilter()
      window.UpdateRoster()
    end)
  end

  AttachHeaderClick(headerName, "name")
  AttachHeaderClick(headerClass, "class")
  AttachHeaderClick(headerZone, "zone")
  AttachHeaderClick(headerMain, "main")
  AttachHeaderClick(headerStatus, "status")

  local scrollFrame = CreateFrame("ScrollFrame", nil, listFrame, "FauxScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 6, -(6 + headerHeight))
  scrollFrame:SetPoint("BOTTOMRIGHT", -28, 6)

  local rowHeight = 20
  local rows = {}
  for i = 1, 18 do
    local row = CreateFrame("Button", nil, listFrame)
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", 6, -(6 + headerHeight) - (i - 1) * rowHeight)
    row:SetPoint("RIGHT", -30, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetSize(14, 14)
    check:SetPoint("LEFT", 0, 0)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check = check

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local classText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    classText:SetPoint("LEFT", row, "LEFT", 0, 0)
    classText:SetJustifyH("LEFT")
    row.classText = classText

    local zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    zoneText:SetPoint("LEFT", row, "LEFT", 0, 0)
    zoneText:SetJustifyH("LEFT")
    row.zoneText = zoneText

    local mainText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mainText:SetPoint("LEFT", row, "LEFT", 0, 0)
    mainText:SetJustifyH("LEFT")
    row.mainText = mainText

    local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetPoint("LEFT", row, "LEFT", 0, 0)
    statusText:SetJustifyH("LEFT")
    row.statusText = statusText

    row:SetScript("OnClick", function(self)
      local entry = filteredRoster[self.index]
      if entry then
        local playerName = UnitName("player")
        if entry.displayName == playerName then
          selectedInvites[entry.inviteName] = false
          ShowSelfSelectPopup()
        else
          selectedInvites[entry.inviteName] = not selectedInvites[entry.inviteName]
        end
        window.UpdateRoster()
      end
    end)

    rows[i] = row
  end

  local countText = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  countText:SetPoint("TOPRIGHT", listFrame, "BOTTOMRIGHT", -8, -6)
  countText:SetText("0 members")

  local partyBtn = CreateFrame("Button", nil, window, "GameMenuButtonTemplate")
  partyBtn:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -10)
  partyBtn:SetSize(120, 26)
  partyBtn:SetText("Invite Party")
  partyBtn:SetScript("OnClick", InviteToParty)

  local raidBtn = CreateFrame("Button", nil, window, "GameMenuButtonTemplate")
  raidBtn:SetPoint("LEFT", partyBtn, "RIGHT", 8, 0)
  raidBtn:SetSize(120, 26)
  raidBtn:SetText("Invite Raid")
  raidBtn:SetScript("OnClick", InviteToRaid)

  local inviteBtn = CreateFrame("Button", nil, window, "GameMenuButtonTemplate")
  inviteBtn:SetPoint("LEFT", raidBtn, "RIGHT", 8, 0)
  inviteBtn:SetSize(120, 26)
  inviteBtn:SetText("Invite")
  inviteBtn:SetScript("OnClick", InviteNoLimit)

  local clearBtn = CreateFrame("Button", nil, window, "GameMenuButtonTemplate")
  clearBtn:SetPoint("TOPLEFT", partyBtn, "BOTTOMLEFT", 0, -8)
  clearBtn:SetSize(120, 26)
  clearBtn:SetText("Clear Selection")
  clearBtn:SetScript("OnClick", function()
    ClearSelectedMembers()
    window.UpdateRoster()
  end)

  local closeBtn = CreateFrame("Button", nil, window, "GameMenuButtonTemplate")
  closeBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
  closeBtn:SetSize(100, 26)
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function() window:Hide() end)

  local minimapCheck = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
  minimapCheck:SetPoint("LEFT", closeBtn, "RIGHT", 8, 0)
  minimapCheck.text:SetText("Show minimap button")
  minimapCheck:SetChecked(MWDInviteDB.minimap.show)
  minimapCheck:SetScript("OnClick", function(self)
    MWDInviteDB.minimap.show = self:GetChecked()
    if MWDInviteMinimapButton then
      if MWDInviteDB.minimap.show then
        MWDInviteMinimapButton:Show()
      else
        MWDInviteMinimapButton:Hide()
      end
    end
  end)

  local function ApplyColumnLayout()
    local listWidth = listFrame:GetWidth() or 0
    local paddingRight = 28
    local usable = math.max(0, listWidth - paddingRight)
    local checkWidth = 16
    local gap = 4
    local nameX = checkWidth + gap
    local nameWidth = math.floor((usable - nameX) * 0.26)
    local classWidth = math.floor((usable - nameX) * 0.16)
    local zoneWidth = math.floor((usable - nameX) * 0.26)
    local mainWidth = math.floor((usable - nameX) * 0.20)
    local statusWidth = math.max(60, (usable - nameX) - nameWidth - classWidth - zoneWidth - mainWidth)
    local classX = nameX + nameWidth + gap
    local zoneX = classX + classWidth + gap
    local mainX = zoneX + zoneWidth + gap
    local statusX = mainX + mainWidth + gap

    headerName:SetPoint("LEFT", headerRow, "LEFT", nameX, 0)
    headerClass:SetPoint("LEFT", headerRow, "LEFT", classX, 0)
    headerZone:SetPoint("LEFT", headerRow, "LEFT", zoneX, 0)
    headerMain:SetPoint("LEFT", headerRow, "LEFT", mainX, 0)
    headerStatus:SetPoint("LEFT", headerRow, "LEFT", statusX, 0)

    headerName:SetWidth(nameWidth)
    headerClass:SetWidth(classWidth)
    headerZone:SetWidth(zoneWidth)
    headerMain:SetWidth(mainWidth)
    headerStatus:SetWidth(statusWidth)

    for i = 1, #rows do
      rows[i].nameText:SetPoint("LEFT", rows[i], "LEFT", nameX, 0)
      rows[i].classText:SetPoint("LEFT", rows[i], "LEFT", classX, 0)
      rows[i].zoneText:SetPoint("LEFT", rows[i], "LEFT", zoneX, 0)
      rows[i].mainText:SetPoint("LEFT", rows[i], "LEFT", mainX, 0)
      rows[i].statusText:SetPoint("LEFT", rows[i], "LEFT", statusX, 0)

      rows[i].nameText:SetWidth(nameWidth)
      rows[i].classText:SetWidth(classWidth)
      rows[i].zoneText:SetWidth(zoneWidth)
      rows[i].mainText:SetWidth(mainWidth)
      rows[i].statusText:SetWidth(statusWidth)
    end
  end

  function window.UpdateRoster()
    ApplyColumnLayout()
    if not IsInGuild() then
      for i = 1, #rows do
        rows[i]:Hide()
      end
      countText:SetText("Not in a guild")
      FauxScrollFrame_Update(scrollFrame, 0, #rows, rowHeight)
      return
    end

    ApplyRosterFilter()
    FauxScrollFrame_Update(scrollFrame, #filteredRoster, #rows, rowHeight)
    local offset = FauxScrollFrame_GetOffset(scrollFrame)

    for i = 1, #rows do
      local row = rows[i]
      local entry = filteredRoster[i + offset]
      if entry then
        row.index = i + offset
        row:Show()
        row.check:SetShown(selectedInvites[entry.inviteName] and true or false)
        row.nameText:SetText(entry.displayName)
        row.classText:SetText(entry.class)
        row.zoneText:SetText(entry.zone or "")
        row.mainText:SetText(entry.online and (entry.main or "") or "")
        row.statusText:SetText(entry.online and "Online" or "Offline")
        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFileName]
        if classColor then
          row.classText:SetTextColor(classColor.r, classColor.g, classColor.b)
        else
          row.classText:SetTextColor(0.7, 0.7, 0.7)
        end
        if entry.online then
          row.statusText:SetTextColor(0.2, 1.0, 0.2)
        else
          row.statusText:SetTextColor(0.6, 0.6, 0.6)
        end
      else
        row.index = nil
        row:Hide()
      end
    end

    countText:SetText(#filteredRoster .. " members")
  end

  window:SetScript("OnShow", function()
    ClearSelectedMembers()
    RefreshGuildRoster()
    ApplyRosterFilter()
    window.UpdateRoster()
  end)

  scrollFrame:SetScript("OnVerticalScroll", function(_, offset)
    FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, rowHeight, window.UpdateRoster)
  end)

  return window
end

addonWindow = CreateAddonWindow()

local function UpdateMinimapButtonPosition(button)
  local angle = (MWDInviteDB.minimap and MWDInviteDB.minimap.angle) or 225
  local radius = 80
  local rad = math.rad(angle)
  local x = math.cos(rad) * radius
  local y = math.sin(rad) * radius
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function SetMinimapButtonAngleFromCursor(button)
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  cx = cx / scale
  cy = cy / scale
  local angle = math.deg(math.atan2(cy - my, cx - mx))
  MWDInviteDB.minimap.angle = angle
  UpdateMinimapButtonPosition(button)
end

local function CreateMinimapButton()
  local button = CreateFrame("Button", "MWDInviteMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:EnableMouse(true)
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnDragStart", function(self)
    self.isDragging = true
  end)
  button:SetScript("OnDragStop", function(self)
    self.isDragging = false
  end)
  button:SetScript("OnUpdate", function(self)
    if self.isDragging then
      SetMinimapButtonAngleFromCursor(self)
    end
  end)
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 0)
  icon:SetTexture("Interface\\Calendar\\UI-Calendar-Button")
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT", 0, 0)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  button.border = border

  local function ToggleWindow()
    if addonWindow:IsShown() then
      addonWindow:Hide()
    else
      ShowAddonWindow()
    end
  end

  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "LeftButton" then
      ToggleWindow()
    end
  end)

  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("MWD Invite")
    GameTooltip:Show()
  end)

  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  UpdateMinimapButtonPosition(button)
  return button
end

local function PositionAddonWindow()
  addonWindow:ClearAllPoints()
  if CommunitiesFrame and CommunitiesFrame:IsShown() then
    addonWindow:SetPoint("TOPLEFT", CommunitiesFrame, "TOPRIGHT", 8, 0)
  else
    addonWindow:SetPoint("CENTER")
  end
end

function ShowAddonWindow()
  PositionAddonWindow()
  addonWindow:SetFrameStrata("DIALOG")
  addonWindow:SetFrameLevel(50)
  addonWindow:Show()
end

local function ToggleAddonWindow()
  if addonWindow:IsShown() then
    addonWindow:Hide()
  else
    ShowAddonWindow()
  end
end

function EnsureCommunitiesTab()
  if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
    C_AddOns.LoadAddOn("Blizzard_Communities")
  end

  if not CommunitiesFrame then
    if not communitiesTabPending then
      communitiesTabPending = true
      C_Timer.After(1, function()
        communitiesTabPending = false
        EnsureCommunitiesTab()
      end)
    end
    return
  end

  local button = MWDInviteCommunitiesTab
  if not button then
    button = CreateFrame("Button", "MWDInviteCommunitiesTab", CommunitiesFrame, "UIPanelButtonTemplate")
    button:SetText("MWD Invite")
    button:SetSize(90, 22)
    button:SetScript("OnClick", function()
      ToggleAddonWindow()
    end)
  end

  local anchor = CommunitiesFrame.MacroToolButton or CommunitiesFrame.GuildLogButton
  if anchor then
    button:ClearAllPoints()
    button:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    button:SetFrameStrata(anchor:GetFrameStrata() or "HIGH")
    button:SetFrameLevel((anchor:GetFrameLevel() or 0) + 1)
  else
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", CommunitiesFrame, "TOPRIGHT", -120, -26)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(50)
  end

  button:Show()

  if CommunitiesFrame and not CommunitiesFrame.MWDInviteHooked then
    CommunitiesFrame.MWDInviteHooked = true
    CommunitiesFrame:HookScript("OnShow", function()
      EnsureCommunitiesTab()
    end)
  end
end

local minimapButton = CreateMinimapButton()
if MWDInviteDB.minimap and not MWDInviteDB.minimap.show then
  minimapButton:Hide()
end

local function HandleEvent(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    EnsureDefaults()
    EnsureCommunitiesTab()
    return
  end

  if event == "ADDON_LOADED" and arg1 == "Blizzard_Communities" then
    EnsureCommunitiesTab()
    return
  end

  if event == "GUILD_ROSTER_UPDATE" then
    if addonWindow and addonWindow:IsShown() then
      RefreshGuildRoster()
      ApplyRosterFilter()
      addonWindow.UpdateRoster()
    end
    return
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", HandleEvent)

SLASH_MWDINVITE1 = "/mwdinv"
SlashCmdList.MWDINVITE = function(msg)
  msg = msg and msg:lower() or ""
  if msg == "ui" or msg == "window" then
    if addonWindow:IsShown() then
      addonWindow:Hide()
    else
      ShowAddonWindow()
    end
    return
  end

  print("MWD Invite commands:")
  print("/mwdinv ui - toggle the invite window")
end

