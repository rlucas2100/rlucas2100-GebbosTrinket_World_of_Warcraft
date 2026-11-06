local ADDON, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"
local CHANNELS = { "Master", "SFX", "Dialog", "Ambience", "Music" }
local ENGINE = { auto = "Auto", on = "Always", off = "Off" }
local NEXT_ENGINE = { auto = "on", on = "off", off = "auto" }

local function Tip(widget, text)
	if not text then return end
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Label(parent, text, size, flags)
	local t = parent:CreateFontString(nil, "OVERLAY")
	t:SetFont(FONT, size or 11, flags or "OUTLINE")
	t:SetText(text)
	t:SetTextColor(1, 0.95, 0.85)
	return t
end

local function Check(parent, y, label, tip, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", 14, y)
	local t = Label(parent, label)
	t:SetPoint("LEFT", cb, "RIGHT", 4, 1)
	cb:SetChecked(get())
	cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	Tip(cb, tip)
	return cb
end

local function Slider(parent, y, label, minV, maxV, step, display, get, set)
	local t = Label(parent, label)
	t:SetPoint("TOPLEFT", 18, y)
	local val = Label(parent, "", 12, "THICKOUTLINE")
	val:SetPoint("TOPRIGHT", -18, y)
	val:SetTextColor(1, 0.82, 0.3)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetPoint("TOPLEFT", 18, y - 18)
	s:SetPoint("TOPRIGHT", -18, y - 18)
	s:SetHeight(16)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s:EnableMouseWheel(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetTexture(WHITE) track:SetVertexColor(0, 0, 0, 0.6) track:SetHeight(6)
	track:SetPoint("LEFT") track:SetPoint("RIGHT")
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetTexture(WHITE) fill:SetHeight(6) fill:SetPoint("LEFT")
	fill:SetGradient("HORIZONTAL", CreateColor(0.75, 0.3, 1, 1), CreateColor(1, 0.6, 0.15, 1))
	s:SetThumbTexture(WHITE)
	local thumb = s:GetThumbTexture()
	thumb:SetSize(10, 18)
	thumb:SetVertexColor(1, 0.95, 0.8, 1)
	local syncing = false
	function s:Sync()
		syncing = true
		self:SetValue(get())
		syncing = false
	end
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v / step + 0.5) * step
		val:SetText(display(v))
		local w = self:GetWidth() or 0
		fill:SetWidth(math.max(1, w * (v - minV) / (maxV - minV)))
		if not syncing then set(v) end
	end)
	s:SetScript("OnMouseWheel", function(self, d) self:SetValue(self:GetValue() + d * step) end)
	s:SetScript("OnShow", function(self) self:Sync() end)
	s:Sync()
	return s
end

local function Button(parent, text, w, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetText(text)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

function ns:BuildOptions()
	if self.options then return self.options end
	local db = self.db
	local o = CreateFrame("Frame", "GebboBagTrackerOptions", UIParent)
	self.options = o
	o:SetSize(320, 530)
	o:SetPoint("CENTER", 0, 40)
	o:SetFrameStrata("DIALOG")
	o:SetClampedToScreen(true)
	o:SetMovable(true)
	o:EnableMouse(true)
	o:RegisterForDrag("LeftButton")
	o:SetScript("OnDragStart", o.StartMoving)
	o:SetScript("OnDragStop", o.StopMovingOrSizing)
	tinsert(UISpecialFrames, "GebboBagTrackerOptions")

	-- Juggernaut Mode palette: purple into orange, rainbow-gold edges
	local glow = o:CreateTexture(nil, "BACKGROUND", nil, -1)
	glow:SetTexture(ns.MEDIA .. "glow_outer")
	glow:SetPoint("TOPLEFT", -30, 30) glow:SetPoint("BOTTOMRIGHT", 30, -30)
	glow:SetBlendMode("ADD") glow:SetVertexColor(0.75, 0.35, 1, 0.6)
	local bg = o:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints() bg:SetTexture(WHITE)
	bg:SetGradient("VERTICAL", CreateColor(0.10, 0.02, 0.18, 0.97), CreateColor(0.34, 0.05, 0.55, 0.97))
	local band = o:CreateTexture(nil, "BORDER")
	band:SetPoint("TOPLEFT") band:SetPoint("TOPRIGHT") band:SetHeight(40) band:SetTexture(WHITE)
	band:SetGradient("HORIZONTAL", CreateColor(0.40, 0.04, 0.70, 1), CreateColor(1.0, 0.45, 0.0, 1))
	for _, edge in ipairs(ns.Edges(o, 2, 5)) do edge:SetVertexColor(1, 0.85, 0.3, 1) end

	local title = Label(o, "GEBBO'S BAG", 18, "THICKOUTLINE")
	title:SetPoint("TOP", 0, -11)
	local close = CreateFrame("Button", nil, o, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	local y = -52
	local function nextY(d) y = y - (d or 26) return y + (d or 26) end

	Check(o, nextY(), "Play pull sounds", "Original retro chimes: a long glittering staircase for the Salmon jackpot, a short sparkle for other pulls.",
		function() return db.sound end, function(v) db.sound = v ns:RegisterNativeSounds() end)
	Check(o, nextY(), "Let the game play them (raids & M+)", "Registers the chimes with the game so they still play where addons can't see buffs. Untick if you ever hear a pull twice.",
		function() return db.nativeSound end, function(v) db.nativeSound = v ns:RegisterNativeSounds() end)
	Check(o, nextY(), "Sad sound on Rotting Voidfin", nil,
		function() return db.sadSound end, function(v) db.sadSound = v ns:RegisterNativeSounds() end)
	Check(o, nextY(), "Screen flash on Jackpot and Voidfin", nil,
		function() return db.flash end, function(v) db.flash = v end)
	Check(o, nextY(), "Show the bag between pulls", "Off: the alert only pops up while a pull is active, like Juggernaut Mode.",
		function() return db.showIdle end, function(v) db.showIdle = v ns:ApplyVisibility() end)

	nextY(6)
	local engineBtn = Button(o, "Raid & M+ display: " .. ENGINE[db.engine or "auto"], 284)
	engineBtn:SetPoint("TOP", 0, nextY(28))
	engineBtn:SetScript("OnClick", function(self)
		db.engine = NEXT_ENGINE[db.engine or "auto"]
		self:SetText("Raid & M+ display: " .. ENGINE[db.engine])
	end)
	Tip(engineBtn, "Auto: the game draws the alert wherever buffs are hidden from addons. Always: use the game-drawn alert everywhere. Off: never.")

	local growBtn = Button(o, "Extra pulls stack: " .. (db.growUp and "Upwards" or "Downwards"), 284)
	growBtn:SetPoint("TOP", 0, nextY(28))
	growBtn:SetScript("OnClick", function(self)
		db.growUp = not db.growUp
		self:SetText("Extra pulls stack: " .. (db.growUp and "Upwards" or "Downwards"))
		ns.engineDirty = true
		ns:UI_Layout()
	end)
	Tip(growBtn, "When two pulls are up at once they get a panel each. Pick Upwards if the alert sits near the bottom of your screen.")

	local chanBtn = Button(o, "Sound channel: " .. db.channel, 284)
	chanBtn:SetPoint("TOP", 0, nextY(34))
	chanBtn:SetScript("OnClick", function(self)
		local idx = 1
		for i, c in ipairs(CHANNELS) do if c == db.channel then idx = i end end
		db.channel = CHANNELS[idx % #CHANNELS + 1]
		self:SetText("Sound channel: " .. db.channel)
		ns:RegisterNativeSounds()
		ns:PlayArtifactSound("gralstone", true)
	end)

	o.scaleSlider = Slider(o, nextY(48), "Size", 0.3, 3, 0.05,
		function(v) return ("%.2fx"):format(v) end,
		function() return db.scale end, function(v) ns:SetScale(v) end)

	o.lockBtn = Button(o, "Unlock & move", 138, function() ns:SetUnlocked(not ns.unlocked) end)
	o.lockBtn:SetPoint("TOPLEFT", 18, nextY(0))
	Button(o, "Recentre", 138, function()
		db.point, db.relPoint, db.x, db.y = "CENTER", "CENTER", 0, -140
		ns:ApplyPosition()
	end):SetPoint("TOPRIGHT", -18, nextY(34))

	local hdr = Label(o, "PREVIEW", 12, "THICKOUTLINE")
	hdr:SetPoint("TOPLEFT", 18, nextY(22))
	hdr:SetTextColor(1, 0.82, 0.3)
	local row = y
	Button(o, "Jackpot", 138, function() ns:SimulateProc("salmon") end):SetPoint("TOPLEFT", 18, row)
	Button(o, "Voidfin", 138, function() ns:SimulateProc("voidfin") end):SetPoint("TOPRIGHT", -18, row)
	nextY(26)
	row = y
	Button(o, "Fading Scroll", 138, function() ns:SimulateProc("scroll") end):SetPoint("TOPLEFT", 18, row)
	Button(o, "Random pull", 138, function() ns:SimulateProc() end):SetPoint("TOPRIGHT", -18, row)

	local foot = Label(o, "/gbag for commands. Unlocked: drag to move, Ctrl + mouse wheel or the corner grip to resize.", 10, "")
	foot:SetPoint("BOTTOMLEFT", 18, 14)
	foot:SetPoint("BOTTOMRIGHT", -18, 14)
	foot:SetJustifyH("LEFT")
	foot:SetTextColor(0.85, 0.78, 0.95)

	o:Hide()
	return o
end

function ns:ToggleOptions(forceShow)
	local o = self:BuildOptions()
	if forceShow or not o:IsShown() then o:Show() else o:Hide() end
end

-- An entry under Options > AddOns that opens the window above
function ns:BuildSettingsStub()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local p = CreateFrame("Frame")
	p.name = "Gebbo's Bag Tracker"
	local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText("Gebbo's Bottomless Bag Tracker")
	local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	b:SetSize(200, 26)
	b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -14)
	b:SetText("Open settings window")
	b:SetScript("OnClick", function() ns:ToggleOptions(true) end)
	local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, p, p.name)
	if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
end
