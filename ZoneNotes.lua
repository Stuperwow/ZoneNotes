-- ZoneNotes
-- Leave yourself reminders that pop up when you walk into a place:
--   "Any city with an Auction House" - Stormwind, Orgrimmar, Booty Bay, ...
--   "Any inn or rested area"
--   A specific zone or subzone - "Orgrimmar", "Trade District", "Gadgetzan", ...
-- /zn opens the notes window. Quick add: /zn city <text>, /zn here <text>, /zn inn <text>.

local ADDON_NAME = ...

-- Zones/subzones with an Auction House (Booty Bay, Gadgetzan and Everlook are subzones; all expansions; ones that don't exist on Forever just never match).
local AH_CITIES = {
	["Stormwind City"] = true, ["Ironforge"] = true, ["Darnassus"] = true, ["The Exodar"] = true,
	["Orgrimmar"] = true, ["Thunder Bluff"] = true, ["Undercity"] = true, ["Silvermoon City"] = true,
	["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true,
	["Shattrath City"] = true, ["Dalaran"] = true, ["Area 52"] = true,
}

local KIND_LABEL = { city = "Any city with an Auction House", rested = "Any inn or rested area" }
local REPOP_COOLDOWN = 120 -- seconds: don't re-pop a note just because you crossed a zone border twice

local db
local active = {}      -- [note id] = true while you're inside its place
local lastShown = {}   -- [note id] = GetTime()
local popup, manager, editor

local function Print(msg) print("|cffffd200ZoneNotes|r: " .. msg) end

local function MyName()
	local first, surname = UnitName("player")
	if type(surname) == "string" and surname ~= "" then return first .. " " .. surname end
	return first
end

local function Lower(s) return strtrim(s or ""):lower() end

local function WhereText(n)
	if n.kind == "place" then return n.place end
	return KIND_LABEL[n.kind] or "?"
end

------------------------------------------------------------------------
-- Matching
------------------------------------------------------------------------

local function Here()
	return GetRealZoneText() or "", GetZoneText() or "", GetSubZoneText() or ""
end

local function IsAHCity()
	local real, zone, sub = Here()
	return AH_CITIES[real] or AH_CITIES[zone] or AH_CITIES[sub] or false
end

local function Matches(n)
	if n.char and n.char ~= MyName() then return false end
	if n.kind == "city" then return IsAHCity() end
	if n.kind == "rested" then return IsResting() and true or false end
	if n.kind == "place" then
		local want = Lower(n.place)
		if want == "" then return false end
		local real, zone, sub = Here()
		return Lower(real) == want or Lower(zone) == want or Lower(sub) == want
	end
	return false
end

------------------------------------------------------------------------
-- Popup
------------------------------------------------------------------------

local ShowPopup -- forward
local RefreshManager -- forward

local function RemoveNote(id)
	for i, n in ipairs(db.notes) do
		if n.id == id then table.remove(db.notes, i) break end
	end
	active[id], lastShown[id] = nil, nil
end

local function CreatePopup()
	popup = CreateFrame("Frame", "ZoneNotesPopup", UIParent, "BackdropTemplate")
	popup:SetFrameStrata("DIALOG")
	popup:SetWidth(400)
	popup:SetClampedToScreen(true)
	popup:SetMovable(true)
	popup:EnableMouse(true)
	popup:RegisterForDrag("LeftButton")
	popup:SetScript("OnDragStart", popup.StartMoving)
	popup:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		db.popupPos = { p, rp, x, y }
	end)
	if popup.SetBackdrop then
		popup:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
			tile = true, tileSize = 32, edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 },
		})
	end
	local p = db.popupPos
	if p then popup:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else popup:SetPoint("TOP", UIParent, "TOP", 0, -140) end

	popup.icon = popup:CreateTexture(nil, "ARTWORK")
	popup.icon:SetSize(28, 28)
	popup.icon:SetPoint("TOPLEFT", 16, -14)
	popup.icon:SetTexture("Interface\\AddOns\\ZoneNotes\\ZoneNotes.tga")
	popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	popup.title:SetPoint("LEFT", popup.icon, "RIGHT", 8, 0)
	popup.title:SetPoint("RIGHT", popup, "RIGHT", -36, 0)
	popup.title:SetJustifyH("LEFT")

	local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() popup:Hide() end)

	popup.closeAll = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
	popup.closeAll:SetSize(90, 22)
	popup.closeAll:SetPoint("BOTTOMRIGHT", -16, 14)
	popup.closeAll:SetText("Close")
	popup.closeAll:SetScript("OnClick", function() popup:Hide() end)

	popup.rows = {}
	popup.queue = {}
	popup:Hide()
	tinsert(UISpecialFrames, "ZoneNotesPopup")
end

local function PopupRow(i)
	local r = popup.rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, popup)
	r.bullet = r:CreateTexture(nil, "ARTWORK")
	r.bullet:SetSize(8, 8)
	r.bullet:SetPoint("TOPLEFT", 0, -5)
	r.bullet:SetColorTexture(1, 0.82, 0, 1)
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.text:SetPoint("TOPLEFT", 16, 0)
	r.text:SetWidth(250)
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(true)
	r.where = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.where:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
	r.where:SetWidth(250)
	r.where:SetJustifyH("LEFT")
	local function Dismiss(n)
		for k, sn in ipairs(popup.queue) do
			if sn == n then table.remove(popup.queue, k) break end
		end
		ShowPopup(nil)
	end
	-- Done: you've done it - the note is deleted.
	r.done = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
	r.done:SetSize(72, 22)
	r.done:SetPoint("TOPRIGHT", 0, 2)
	r.done:SetText("Done")
	r.done:SetScript("OnClick", function(self)
		local n = self:GetParent().note
		if not n then return end
		RemoveNote(n.id)
		Print("done - \"" .. n.text .. "\" removed.")
		if RefreshManager then RefreshManager() end
		Dismiss(n)
	end)
	r.done:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Done")
		GameTooltip:AddLine("Finished - delete this note.", 1, 1, 1)
		GameTooltip:Show()
	end)
	r.done:SetScript("OnLeave", GameTooltip_Hide)
	-- Next time: keep the note and remind me on my next visit.
	r.later = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
	r.later:SetSize(72, 22)
	r.later:SetPoint("TOPRIGHT", r.done, "BOTTOMRIGHT", 0, -2)
	r.later:SetText("Next time")
	r.later:SetScript("OnClick", function(self)
		local n = self:GetParent().note
		if n then Dismiss(n) end
	end)
	r.later:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Next time")
		GameTooltip:AddLine("Keep this note and remind me on my next visit.", 1, 1, 1)
		GameTooltip:Show()
	end)
	r.later:SetScript("OnLeave", GameTooltip_Hide)
	popup.rows[i] = r
	return r
end

-- Add notes to the popup (or just re-lay it out when notes is nil).
ShowPopup = function(notes, titleWhere)
	if not popup then CreatePopup() end
	if notes then
		if not popup:IsShown() then wipe(popup.queue) end
		for _, n in ipairs(notes) do
			local dup = false
			for _, sn in ipairs(popup.queue) do if sn == n then dup = true break end end
			if not dup then popup.queue[#popup.queue + 1] = n end
		end
		popup.title:SetText("Reminder" .. (titleWhere and titleWhere ~= "" and (" - " .. titleWhere) or ""))
	end
	local list = popup.queue
	if #list == 0 then popup:Hide() return end
	local y = -54
	for i, n in ipairs(list) do
		local r = PopupRow(i)
		r.note = n
		r.text:SetText(n.text)
		r.where:SetText(WhereText(n))
		local h = math.max(48, r.text:GetStringHeight() + r.where:GetStringHeight() + 6)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", popup, "TOPLEFT", 22, y)
		r:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -18, y)
		r:SetHeight(h)
		r:Show()
		y = y - h - 10
	end
	for i = #list + 1, #popup.rows do popup.rows[i]:Hide() end
	popup:SetHeight(-y + 44)
	popup:Show()
end

------------------------------------------------------------------------
-- Zone checks
------------------------------------------------------------------------

local function Check(silent)
	if not db then return end
	local now = GetTime()
	local fire = {}
	for _, n in ipairs(db.notes) do
		local m = Matches(n)
		if m and not active[n.id] then
			if not silent and now - (lastShown[n.id] or -1e9) > REPOP_COOLDOWN then
				fire[#fire + 1] = n
				lastShown[n.id] = now
			end
		end
		active[n.id] = m or nil
	end
	if #fire > 0 then
		local _, zone, sub = Here()
		ShowPopup(fire, (sub ~= "" and sub ~= zone) and (sub .. ", " .. zone) or zone)
		if db.sound ~= false then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
		for _, n in ipairs(fire) do Print("|cffffffff" .. n.text .. "|r") end
	end
end

local checkQueued = false
local function QueueCheck()
	if checkQueued then return end
	checkQueued = true
	-- Zone text settles a moment after the zone events fire.
	local function run() checkQueued = false Check() end
	if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end

------------------------------------------------------------------------
-- Notes window
------------------------------------------------------------------------

local function Button(parent, text, w, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function Check_(parent, label)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
	c.label:SetText(label)
	if c.Text then c.Text:SetText("") end
	return c
end

local function CreateEditor()
	editor = CreateFrame("Frame", "ZoneNotesEditor", UIParent, "BasicFrameTemplateWithInset")
	editor:SetSize(400, 360)
	editor:SetPoint("CENTER", 0, 40)
	editor:SetFrameStrata("DIALOG")
	editor:SetMovable(true)
	editor:EnableMouse(true)
	editor:RegisterForDrag("LeftButton")
	editor:SetScript("OnDragStart", editor.StartMoving)
	editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
	editor:SetClampedToScreen(true)
	if editor.TitleText then editor.TitleText:SetText("ZoneNotes - Note") end
	tinsert(UISpecialFrames, "ZoneNotesEditor")

	local l1 = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l1:SetPoint("TOPLEFT", 16, -34)
	l1:SetText("Remind me to...")

	local bg = CreateFrame("Frame", nil, editor, "BackdropTemplate")
	bg:SetPoint("TOPLEFT", 16, -52)
	bg:SetSize(368, 84)
	if bg.SetBackdrop then
		bg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		bg:SetBackdropColor(0, 0, 0, 0.5)
		bg:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
	end
	local text = CreateFrame("EditBox", nil, bg)
	text:SetMultiLine(true)
	text:SetFontObject(ChatFontNormal)
	text:SetPoint("TOPLEFT", 6, -6)
	text:SetPoint("BOTTOMRIGHT", -6, 6)
	text:SetAutoFocus(false)
	text:SetMaxLetters(400)
	text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	bg:EnableMouse(true)
	bg:SetScript("OnMouseDown", function() text:SetFocus() end)
	editor.text = text

	local l2 = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l2:SetPoint("TOPLEFT", 16, -148)
	l2:SetText("When I enter...")

	editor.radios = {}
	local function Radio(kind, label, y)
		local c = Check_(editor, label)
		c:SetPoint("TOPLEFT", 20, y)
		c.kind = kind
		c:SetScript("OnClick", function(self)
			editor.kind = self.kind
			for _, r in ipairs(editor.radios) do r:SetChecked(r.kind == editor.kind) end
			if self.kind == "place" then editor.place:SetFocus() end
		end)
		editor.radios[#editor.radios + 1] = c
		return c
	end
	Radio("city", KIND_LABEL.city, -166)
	Radio("rested", KIND_LABEL.rested, -190)
	local pr = Radio("place", "This place:", -214)

	local place = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
	place:SetSize(150, 20)
	place:SetPoint("LEFT", pr.label, "RIGHT", 10, 0)
	place:SetAutoFocus(false)
	place:SetMaxLetters(60)
	place:SetScript("OnEditFocusGained", function()
		editor.kind = "place"
		for _, r in ipairs(editor.radios) do r:SetChecked(r.kind == "place") end
	end)
	place:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	place:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	editor.place = place

	local useZone = Button(editor, "Current zone", 100, function()
		local _, zone = Here(); place:SetText(zone); place:SetFocus(); place:ClearFocus()
	end)
	useZone:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 22, -4)
	local useSub = Button(editor, "Current subzone", 110, function()
		local _, zone, sub = Here(); place:SetText(sub ~= "" and sub or zone); place:SetFocus(); place:ClearFocus()
	end)
	useSub:SetPoint("LEFT", useZone, "RIGHT", 6, 0)

	editor.onlyMe = Check_(editor, "Only on this character")
	editor.onlyMe:SetPoint("TOPLEFT", 20, -276)
	local how = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	how:SetPoint("TOPLEFT", 20, -304)
	how:SetWidth(360)
	how:SetJustifyH("LEFT")
	how:SetText("The note pops up every time you arrive until you click Done on it.")

	local save = Button(editor, "Save", 90, function()
		local t = strtrim(editor.text:GetText() or "")
		if t == "" then Print("write the note first.") return end
		local kind = editor.kind
		local placeName = strtrim(place:GetText() or "")
		if kind == "place" and placeName == "" then Print("type a zone or subzone name, or use the Current zone button.") return end
		local n = editor.note
		if not n then
			n = { id = db.nextId }
			db.nextId = db.nextId + 1
			db.notes[#db.notes + 1] = n
		end
		n.text, n.kind = t, kind
		n.place = kind == "place" and placeName or nil
		n.char = editor.onlyMe:GetChecked() and MyName() or nil
		active[n.id] = Matches(n) or nil -- don't pop instantly for a note made where you're standing
		editor:Hide()
		RefreshManager()
	end)
	save:SetPoint("BOTTOMRIGHT", -14, 12)
	local cancel = Button(editor, "Cancel", 90, function() editor:Hide() end)
	cancel:SetPoint("RIGHT", save, "LEFT", -6, 0)
end

local function OpenEditor(note)
	if not editor then CreateEditor() end
	editor.note = note
	editor.text:SetText(note and note.text or "")
	editor.kind = note and note.kind or "city"
	for _, r in ipairs(editor.radios) do r:SetChecked(r.kind == editor.kind) end
	local _, zone = Here()
	editor.place:SetText(note and note.place or zone)
	editor.onlyMe:SetChecked(note and note.char ~= nil or false)
	editor:Show()
	editor.text:SetFocus()
end

local function CreateManager()
	manager = CreateFrame("Frame", "ZoneNotesFrame", UIParent, "BasicFrameTemplateWithInset")
	manager:SetSize(440, 400)
	manager:SetPoint("CENTER")
	manager:SetMovable(true)
	manager:EnableMouse(true)
	manager:RegisterForDrag("LeftButton")
	manager:SetScript("OnDragStart", manager.StartMoving)
	manager:SetScript("OnDragStop", manager.StopMovingOrSizing)
	manager:SetClampedToScreen(true)
	if manager.TitleText then manager.TitleText:SetText("ZoneNotes") end
	tinsert(UISpecialFrames, "ZoneNotesFrame")

	manager.here = manager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	manager.here:SetPoint("TOPLEFT", 16, -32)
	manager.here:SetJustifyH("LEFT")

	local add = Button(manager, "New note", 100, function() OpenEditor(nil) end)
	add:SetPoint("BOTTOMLEFT", 14, 12)
	local test = Button(manager, "Show reminders here", 150, function()
		local list = {}
		for _, n in ipairs(db.notes) do if Matches(n) then list[#list + 1] = n end end
		if #list == 0 then Print("no notes for this spot.") return end
		local _, zone = Here()
		ShowPopup(list, zone)
	end)
	test:SetPoint("LEFT", add, "RIGHT", 6, 0)
	manager.sound = Check_(manager, "Sound")
	manager.sound:SetPoint("BOTTOMRIGHT", -60, 12)
	manager.sound:SetScript("OnClick", function(self) db.sound = self:GetChecked() and true or false end)

	local sf = CreateFrame("ScrollFrame", "ZoneNotesScroll", manager, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 12, -52)
	sf:SetPoint("BOTTOMRIGHT", -32, 42)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(390, 1)
	sf:SetScrollChild(child)
	manager.child = child
	manager.rows = {}
	manager.empty = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	manager.empty:SetPoint("TOPLEFT", 6, -8)
	manager.empty:SetWidth(370)
	manager.empty:SetJustifyH("LEFT")
	manager.empty:SetText("No notes yet. Click New note to add one.\n\nExample: \"Post the herbs on the AH\" when entering Any city with an Auction House.")
	manager:SetScript("OnShow", function() RefreshManager() end)
	manager:Hide() -- new frames start visible; let the /zn toggle show it
end

local function ManagerRow(i)
	local r = manager.rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, manager.child)
	r:SetSize(390, 44)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.text:SetPoint("TOPLEFT", 6, -5)
	r.text:SetWidth(250)
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(false)
	r.where = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.where:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
	r.where:SetWidth(250)
	r.where:SetJustifyH("LEFT")
	r.where:SetWordWrap(false)
	r.del = Button(r, "Delete", 60, function(self)
		RemoveNote(self:GetParent().note.id)
		RefreshManager()
	end)
	r.del:SetPoint("RIGHT", -4, 0)
	r.edit = Button(r, "Edit", 50, function(self) OpenEditor(self:GetParent().note) end)
	r.edit:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
	manager.rows[i] = r
	return r
end

RefreshManager = function()
	if not manager or not manager:IsShown() then return end
	local _, zone, sub = Here()
	manager.here:SetText("You're in: |cffffffff" .. zone .. (sub ~= "" and sub ~= zone and (" - " .. sub) or "") .. "|r"
		.. (IsAHCity() and "  |cff40ff40(AH city)|r" or "") .. (IsResting() and "  |cff8080ff(rested)|r" or ""))
	manager.sound:SetChecked(db.sound ~= false)
	local me = MyName()
	for i, n in ipairs(db.notes) do
		local r = ManagerRow(i)
		r.note = n
		r:SetPoint("TOPLEFT", 0, -(i - 1) * 48)
		r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)
		r.text:SetText((n.text:gsub("\n", " ")))
		local extra = n.char and ("  -  " .. (n.char == me and "this character" or n.char)) or ""
		r.where:SetText(WhereText(n) .. extra)
		local here = Matches(n)
		r.text:SetTextColor(here and 0.4 or 1, 1, here and 0.4 or 1)
		r:Show()
	end
	for i = #db.notes + 1, #manager.rows do manager.rows[i]:Hide() end
	manager.child:SetHeight(math.max(1, #db.notes * 48))
	manager.empty:SetShown(#db.notes == 0)
end

------------------------------------------------------------------------
-- Events & slash
------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED")
f:RegisterEvent("ZONE_CHANGED_INDOORS")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_UPDATE_RESTING")
f:SetScript("OnEvent", function(self, event, arg1, arg2)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		ZoneNotesDB = ZoneNotesDB or {}
		db = ZoneNotesDB
		db.notes = db.notes or {}
		db.nextId = db.nextId or 1
		for _, n in ipairs(db.notes) do if n.id >= db.nextId then db.nextId = n.id + 1 end end
		self:UnregisterEvent("ADDON_LOADED")
		return
	end
	if not db then return end
	if event == "PLAYER_ENTERING_WORLD" then
		local isLogin, isReload = arg1, arg2
		if isReload then
			-- After /reload, don't nag about the place you're already standing in.
			Check(true)
			return
		end
	end
	QueueCheck()
	if manager and manager:IsShown() then RefreshManager() end
end)

local function QuickAdd(kind, text, place)
	text = strtrim(text or "")
	if text == "" then Print("usage: /zn " .. (kind == "place" and "here" or kind == "city" and "city" or "inn") .. " <note text>") return end
	local n = { id = db.nextId, text = text, kind = kind, place = place }
	db.nextId = db.nextId + 1
	db.notes[#db.notes + 1] = n
	active[n.id] = Matches(n) or nil
	Print("added: \"" .. text .. "\" - " .. WhereText(n) .. ". /zn to edit.")
	RefreshManager()
end

SLASH_ZONENOTES1 = "/zn"
SLASH_ZONENOTES2 = "/zonenotes"
SlashCmdList.ZONENOTES = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		if not manager then CreateManager() end
		manager:SetShown(not manager:IsShown())
	elseif cmd == "city" or cmd == "ah" then
		QuickAdd("city", rest)
	elseif cmd == "inn" or cmd == "rested" then
		QuickAdd("rested", rest)
	elseif cmd == "here" then
		local _, zone = Here()
		QuickAdd("place", rest, zone)
	elseif cmd == "list" then
		if #db.notes == 0 then Print("no notes yet.") return end
		for i, n in ipairs(db.notes) do Print(i .. ". " .. n.text .. "  |cff888888(" .. WhereText(n) .. ")|r") end
	elseif cmd == "sound" then
		db.sound = db.sound == false
		Print("sound " .. (db.sound and "on." or "off."))
	elseif cmd == "test" then
		local list = {}
		for _, n in ipairs(db.notes) do if Matches(n) then list[#list + 1] = n end end
		if #list == 0 then Print("no notes for this spot.") return end
		local _, zone = Here()
		ShowPopup(list, zone)
	else
		Print("/zn - open notes   /zn city <text>   /zn inn <text>   /zn here <text>   /zn list   /zn test   /zn sound")
	end
end
