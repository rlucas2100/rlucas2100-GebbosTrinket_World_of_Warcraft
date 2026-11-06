--[[ Gebbo's Bag - ALERTS
  Same recipe as Juggernaut Mode / Sunwell Infusion:
    [ big pull icon: rainbow-metal frame, ants, sweep, countdown ]  [ title / amount / stat gems / bar ]  [ cartoon badge ]
  Every pull gets its own panel. Two at once stack (Jackpot on top), with a TOTAL strip
  underneath adding them up. Each panel pops in when its pull lands and leaves when it ends.
  The right side is the bag's own icon as a cel-shaded badge; Voidfin gets the rotten fish. ]]

local ADDON, ns = ...
local ARTS, STAT, ORDER, THEME = ns.ARTIFACTS, ns.STAT, ns.STAT_ORDER, ns.THEME
local M = ns.MEDIA
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"
local GetTime, pairs, ipairs, pcall = GetTime, pairs, ipairs, pcall
local abs, floor, min, max, sin, ceil = math.abs, math.floor, math.min, math.max, math.sin, math.ceil

local W, H, ICON, CAMEO, GAP, TOTAL_H = 448, 132, 100, 84, 14, 40
local MID_L, MID_R = 12 + ICON + 18, 12 + CAMEO + 14
ns.W, ns.H, ns.ICON, ns.CAMEO, ns.MID_L, ns.MID_R, ns.GAP = W, H, ICON, CAMEO, MID_L, MID_R, GAP

-- big countdown font, also used by the game-drawn timer in Engine.lua
local timerFont = CreateFont("GebboBagTimerFont")
timerFont:SetFont(FONT, 36, "THICKOUTLINE")

---------------------------------------------------------------------------
-- Shared helpers (pure AnimationGroups, so Engine.lua can use them too)
---------------------------------------------------------------------------
local function HSV(h, s, v)
	h = (h % 1) * 6
	local i = floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
	elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v else return v, p, q end
end
ns.HSV = HSV

local function Anim(region, looping, list)
	local ag = region:CreateAnimationGroup()
	if looping then ag:SetLooping(looping) end
	for _, a in ipairs(list) do
		local an = ag:CreateAnimation(a.type)
		an:SetDuration(a.d)
		an:SetOrder(a.order or 1)
		if a.delay then an:SetStartDelay(a.delay) end
		if a.type == "Alpha" then an:SetFromAlpha(a.from) an:SetToAlpha(a.to)
		elseif a.type == "Rotation" then an:SetDegrees(a.deg)
		elseif a.type == "Translation" then an:SetOffset(a.x, a.y)
		elseif a.type == "Scale" then an:SetScaleFrom(a.from, a.from) an:SetScaleTo(a.to, a.to) end
		if a.smooth then an:SetSmoothing(a.smooth) end
	end
	return ag
end
ns.Anim = Anim

local function Text(owner, size, flags, r, g, b, text, sub)
	local fs = owner:CreateFontString(nil, "OVERLAY", nil, sub or 7)
	fs:SetFont(FONT, size, flags)
	fs:SetTextColor(r, g, b)
	if text then fs:SetText(text) end
	return fs
end
ns.Text = Text

function ns.ThemeColor(key)
	if key == "idle" or not ARTS[key] then return 0.37, 0.89, 0.82 end
	local art = ARTS[key]
	return art.r, art.g, art.b
end

local function Lighten(r, g, b, k)
	return r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
end
ns.Lighten = Lighten

-- bubbles rising out of the bag, across the panel (clipped by the owner)
function ns.BuildBubbles(owner, count)
	local list = {}
	for i = 1, count do
		local t = owner:CreateTexture(nil, "ARTWORK", nil, 1)
		t:SetTexture(M .. "bubble")
		local s = 9 + (i * 7) % 12
		t:SetSize(s, s)
		t:SetPoint("BOTTOM", owner, "BOTTOMLEFT", MID_L - 20 + ((i * 53) % (W - MID_L - MID_R + 60)), -14)
		t:SetAlpha(0)
		local d = 2.3 + (i % 3) * 0.55
		t.ag = Anim(t, "REPEAT", {
			{ type = "Translation", x = ((i % 2 == 0) and 10 or -10), y = H + 28, d = d, delay = i * 0.37, smooth = "IN" },
			{ type = "Alpha", from = 0.9, to = 0, d = d, delay = i * 0.37, smooth = "IN" },
		})
		list[i] = t
	end
	return list
end

-- Sunwell-style sparks flying out of the icon
function ns.BuildSparks(owner, anchor, size)
	local list = {}
	for i = 0, 9 do
		local ang = i * (math.pi * 2 / 10) + 0.3
		local sp = owner:CreateTexture(nil, "OVERLAY", nil, 5)
		sp:SetTexture(M .. "spark")
		sp:SetSize(size * 0.28, size * 0.28)
		sp:SetPoint("CENTER", anchor, "CENTER")
		sp:SetAlpha(0)
		local dist = size * (0.72 + (i % 3) * 0.12)
		sp.ag = Anim(sp, "REPEAT", {
			{ type = "Translation", x = math.cos(ang) * dist, y = math.sin(ang) * dist, d = 0.9, delay = i * 0.13, smooth = "OUT" },
			{ type = "Alpha", from = 1, to = 0, d = 0.9, delay = i * 0.13 },
			{ type = "Scale", from = 1.2, to = 0.4, d = 0.9, delay = i * 0.13 },
		})
		list[#list + 1] = sp
	end
	return list
end

-- four cel-shaded stat gems: lit = that stat is up right now
function ns.BuildGemRow(owner, x, y)
	local row = {}
	for i, s in ipairs(ORDER) do
		local info = STAT[s]
		local chip = CreateFrame("Frame", nil, owner)
		chip:SetSize(52, 22)
		chip:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", x + (i - 1) * 52, y)
		chip.gem = chip:CreateTexture(nil, "ARTWORK", nil, 2)
		chip.gem:SetTexture(M .. "gem_white")
		chip.gem:SetSize(18, 18)
		chip.gem:SetPoint("LEFT", 0, 0)
		chip.gem:SetVertexColor(info.r, info.g, info.b)
		chip.halo = chip:CreateTexture(nil, "ARTWORK", nil, 1)
		chip.halo:SetTexture(M .. "glow_outer")
		chip.halo:SetSize(30, 30)
		chip.halo:SetPoint("CENTER", chip.gem, "CENTER")
		chip.halo:SetBlendMode("ADD")
		chip.halo:SetVertexColor(info.r, info.g, info.b, 0.9)
		chip.letter = Text(chip, 9, "THICKOUTLINE", 1, 1, 1, info.label:sub(1, 1))
		chip.letter:SetPoint("CENTER", chip.gem, "CENTER", 0, 0)
		chip.value = Text(chip, 11, "OUTLINE", Lighten(info.r, info.g, info.b, 0.35))
		chip.value:SetPoint("LEFT", chip.gem, "RIGHT", 2, 0)
		function chip:SetLit(lit)
			self.gem:SetAlpha(lit and 1 or 0.28)
			self.gem:SetDesaturated(not lit)
			self.halo:SetShown(lit)
			self.letter:SetAlpha(lit and 1 or 0.45)
			if not lit then self.value:SetText("") end
		end
		chip.stat = s
		row[s] = chip
	end
	return row
end

function ns.ItemIcon()
	local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(ns.ITEM_ID)
	if not icon and ns.slot and GetInventoryItemTexture then icon = GetInventoryItemTexture("player", ns.slot) end
	return icon
end

-- the trinket's own icon as a cel-shaded sticker: coloured rim, outline, gloss, sparkles.
-- Built on its own frame so the whole badge can squash-and-stretch (masks follow the frame).
function ns.BuildBadge(owner, size, r, g, b, rainbow)
	local f = CreateFrame("Frame", nil, owner)
	f:SetSize(size, size)
	f.ring = f:CreateTexture(nil, "BACKGROUND")
	f.ring:SetTexture(M .. "glow_outer")
	f.ring:SetPoint("TOPLEFT", -20, 20) f.ring:SetPoint("BOTTOMRIGHT", 20, -20)
	f.ring:SetBlendMode("ADD")
	f.ring:SetVertexColor(Lighten(r, g, b, 0.3))
	f.halo = f:CreateTexture(nil, "BORDER")
	f.halo:SetTexture(M .. "ring")
	f.halo:SetSize(size * 1.12, size * 1.12)
	f.halo:SetPoint("CENTER")
	if not rainbow then f.halo:SetVertexColor(Lighten(r, g, b, 0.3)) f.halo:SetAlpha(0.6) end
	Anim(f.halo, "REPEAT", { { type = "Rotation", deg = 360, d = 3.5 } }):Play()
	f.rim = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.rim:SetTexture(M .. "badge_rim")
	f.rim:SetAllPoints()
	if rainbow then f.rim:SetVertexColor(1, 0.82, 0.3) else f.rim:SetVertexColor(Lighten(r, g, b, 0.15)) end
	f.icon = f:CreateTexture(nil, "ARTWORK", nil, 2)
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.icon:SetTexture(ns.ItemIcon() or ns.FALLBACK_ICON)
	local mask = f:CreateMaskTexture()
	mask:SetTexture(M .. "badge_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(f.icon)
	f.icon:AddMaskTexture(mask)
	f.shine = f:CreateTexture(nil, "OVERLAY", nil, 1)
	f.shine:SetTexture(M .. "badge_shine")
	f.shine:SetAllPoints()
	-- cartoon squash-and-stretch hop every couple of seconds
	local ag = f:CreateAnimationGroup()
	ag:SetLooping("REPEAT")
	for i, st in ipairs({ { 1, 1, 1.08, 0.92, 0.16 }, { 1.08, 0.92, 0.95, 1.07, 0.18 }, { 0.95, 1.07, 1, 1, 0.2 } }) do
		local a = ag:CreateAnimation("Scale")
		a:SetOrder(i) a:SetDuration(st[5]) a:SetSmoothing("IN_OUT")
		a:SetScaleFrom(st[1], st[2]) a:SetScaleTo(st[3], st[4])
	end
	local rest = ag:CreateAnimation("Alpha")
	rest:SetOrder(4) rest:SetFromAlpha(1) rest:SetToAlpha(1) rest:SetDuration(1.5)
	ag:Play()
	f.hop = ag
	ns.badges = ns.badges or {}
	ns.badges[#ns.badges + 1] = f
	return f
end

-- the item icon can arrive a moment after login; patch any badge still showing "?"
function ns:RefreshBadgeIcons()
	local icon = ns.ItemIcon()
	if not icon then return end
	for _, f in ipairs(ns.badges or {}) do f.icon:SetTexture(icon) end
end

local function Edges(owner, thick, sub)
	local list = {}
	for i, spec in ipairs({
		{ "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
	}) do
		local t = owner:CreateTexture(nil, "OVERLAY", nil, sub or 2)
		t:SetTexture(WHITE)
		t:SetPoint(spec[1]) t:SetPoint(spec[2])
		if spec[3] then t:SetHeight(thick) else t:SetWidth(thick) end
		t:SetBlendMode("ADD")
		list[i] = t
	end
	return list
end
ns.Edges = Edges

local function FmtAmt(v)
	local n = floor(abs(v) + 0.5)
	return (v < 0 and "-" or "+") .. (BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n))
end
ns.FmtAmt = FmtAmt

-- the gem row is tight: positives drop their "+"
function ns.FmtChip(v)
	local n = floor(abs(v) + 0.5)
	return (v < 0 and "-" or "") .. (BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n))
end

function ns.StatWord(art)
	if #art.stats > 1 then return "ALL STATS" end
	return STAT[art.stats[1]].label:upper()
end

---------------------------------------------------------------------------
-- Full-screen flash (Juggernaut Mode's)
---------------------------------------------------------------------------
local flash = CreateFrame("Frame", nil, UIParent)
flash:SetAllPoints(UIParent)
flash:SetFrameStrata("FULLSCREEN_DIALOG")
flash:Hide()
flash.tex = flash:CreateTexture(nil, "BACKGROUND")
flash.tex:SetAllPoints()
flash.tex:SetBlendMode("ADD")
flash.elapsed, flash.total, flash.rainbow = 0, 0.9, false
flash:SetScript("OnUpdate", function(self, e)
	self.elapsed = self.elapsed + e
	local p = self.elapsed / self.total
	if p >= 1 then self:Hide() return end
	if self.rainbow then self.tex:SetVertexColor(HSV(self.elapsed * 1.5, 0.8, 1)) end
	self:SetAlpha((1 - p) ^ 1.5)
end)

function ns:ScreenFlash(kind)
	if not self.db.flash then return end
	if kind == "jackpot" then
		flash.tex:SetTexture("Interface\\FullScreenTextures\\OutOfControl")
		flash.rainbow, flash.total = true, 1.1
	else
		flash.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
		flash.tex:SetVertexColor(0.45, 1, 0.2)
		flash.rainbow, flash.total = false, 0.8
	end
	flash.elapsed = 0
	flash:SetAlpha(1)
	flash:Show()
end

---------------------------------------------------------------------------
-- One alert panel (one per pull, built the first time that pull lands)
---------------------------------------------------------------------------
local function BuildAlert(key)
	local P = ns.anchor
	local th = THEME[key] or THEME.idle
	local r, g, b = ns.ThemeColor(key)

	local A = CreateFrame("Frame", nil, P)
	A:SetSize(W, H)
	A:SetPoint("CENTER")
	A:SetFrameStrata("HIGH")
	A:Hide()
	A.t, A.key, A.slotY = 0, key, 0

	A.outer = A:CreateTexture(nil, "BACKGROUND")
	A.outer:SetTexture(M .. "glow_outer")
	A.outer:SetPoint("TOPLEFT", -36, 36)
	A.outer:SetPoint("BOTTOMRIGHT", 36, -36)
	A.outer:SetBlendMode("ADD")

	local content = CreateFrame("Frame", nil, A)
	content:SetAllPoints()
	content:SetClipsChildren(true)
	A.content = content
	A.bg = content:CreateTexture(nil, "BACKGROUND")
	A.bg:SetAllPoints()
	A.bg:SetTexture(WHITE)
	A.inner = content:CreateTexture(nil, "ARTWORK")
	A.inner:SetTexture(M .. "glow_inner")
	A.inner:SetAllPoints()
	A.inner:SetBlendMode("ADD")
	A.bubbles = ns.BuildBubbles(content, 9)
	A.edges = Edges(content, 2)

	-- ===== the star: the pull's icon =====
	local iconF = CreateFrame("Frame", nil, A)
	iconF:SetSize(ICON, ICON)
	iconF:SetPoint("LEFT", A, "LEFT", 12, 0)
	iconF:SetFrameLevel(content:GetFrameLevel() + 5)
	A.iconF = iconF
	iconF.glow2 = iconF:CreateTexture(nil, "BACKGROUND", nil, -1)
	iconF.glow2:SetTexture(M .. "glow_outer")
	iconF.glow2:SetPoint("TOPLEFT", -44, 44) iconF.glow2:SetPoint("BOTTOMRIGHT", 44, -44)
	iconF.glow2:SetBlendMode("ADD")
	iconF.glow = iconF:CreateTexture(nil, "BACKGROUND", nil, 0)
	iconF.glow:SetTexture(M .. "glow_outer")
	iconF.glow:SetPoint("TOPLEFT", -30, 30) iconF.glow:SetPoint("BOTTOMRIGHT", 30, -30)
	iconF.glow:SetBlendMode("ADD")
	iconF.rays = iconF:CreateTexture(nil, "BACKGROUND", nil, 1)
	iconF.rays:SetTexture(M .. "rays_white")
	iconF.rays:SetSize(ICON * 1.6, ICON * 1.6)
	iconF.rays:SetPoint("CENTER")
	iconF.raysSpin = Anim(iconF.rays, "REPEAT", { { type = "Rotation", deg = -360, d = 12 } })
	iconF.border = iconF:CreateTexture(nil, "BORDER")
	iconF.border:SetPoint("TOPLEFT", -5, 5) iconF.border:SetPoint("BOTTOMRIGHT", 5, -5)
	iconF.border:SetTexture(M .. "metal_rainbow", "REPEAT", "REPEAT")
	iconF.icon = iconF:CreateTexture(nil, "ARTWORK")
	iconF.icon:SetAllPoints()
	iconF.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	iconF.innerGlow = iconF:CreateTexture(nil, "ARTWORK", nil, 2)
	iconF.innerGlow:SetTexture(M .. "glow_inner")
	iconF.innerGlow:SetAllPoints()
	iconF.innerGlow:SetBlendMode("ADD")
	iconF.ants = iconF:CreateTexture(nil, "OVERLAY")
	iconF.ants:SetPoint("TOPLEFT", -22, 22) iconF.ants:SetPoint("BOTTOMRIGHT", 22, -22)
	if not iconF.ants:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts") then iconF.ants:SetAlpha(0) end
	iconF.ants:SetBlendMode("ADD")
	iconF.cd = CreateFrame("Cooldown", nil, iconF, "CooldownFrameTemplate")
	iconF.cd:SetAllPoints()
	iconF.cd:SetReverse(true)
	iconF.cd:SetDrawEdge(true)
	iconF.cd:SetDrawBling(false)
	if iconF.cd.SetHideCountdownNumbers then iconF.cd:SetHideCountdownNumbers(true) end
	local timerF = CreateFrame("Frame", nil, iconF)
	timerF:SetAllPoints()
	timerF:SetFrameLevel(iconF.cd:GetFrameLevel() + 2)
	A.timer = timerF:CreateFontString(nil, "OVERLAY")
	A.timer:SetFontObject(timerFont)
	A.timer:SetPoint("CENTER", 0, 2)
	A.timerSub = Text(timerF, 10, "OUTLINE", 1, 1, 1, "casts")
	A.timerSub:SetPoint("TOP", A.timer, "BOTTOM", 0, -1)
	A.timerSub:Hide()
	local sparkF = CreateFrame("Frame", nil, A)
	sparkF:SetAllPoints()
	sparkF:SetFrameLevel(iconF:GetFrameLevel() + 4)
	A.sparks = ns.BuildSparks(sparkF, iconF, ICON)

	-- ===== side guest: the bag's own icon as a cartoon badge (Voidfin: the rotten fish) =====
	if th.cameo == "voidfin" then
		local cameoF = CreateFrame("Frame", nil, A)
		cameoF:SetSize(CAMEO, CAMEO)
		cameoF:SetPoint("RIGHT", A, "RIGHT", -12, 0)
		cameoF:SetFrameLevel(content:GetFrameLevel() + 4)
		cameoF.ring = cameoF:CreateTexture(nil, "BACKGROUND")
		cameoF.ring:SetTexture(M .. "glow_outer")
		cameoF.ring:SetPoint("TOPLEFT", -18, 18) cameoF.ring:SetPoint("BOTTOMRIGHT", 18, -18)
		cameoF.ring:SetBlendMode("ADD")
		cameoF.art = cameoF:CreateTexture(nil, "ARTWORK")
		cameoF.art:SetPoint("CENTER")
		cameoF.art:SetSize(CAMEO, CAMEO)
		cameoF.art:SetTexture(M .. "voidfin")
		A.cameoF, A.cameoIsBadge = cameoF, false
	else
		local badge = ns.BuildBadge(A, CAMEO, r, g, b, th.rainbow)
		badge:SetPoint("RIGHT", A, "RIGHT", -12, 0)
		badge:SetFrameLevel(content:GetFrameLevel() + 4)
		A.cameoF, A.cameoIsBadge = badge, true
	end

	-- ===== middle: title / name / amount / gems / bar =====
	A.title = Text(content, 20, "THICKOUTLINE", 1, 1, 1, nil, 3)
	A.title:SetPoint("TOPLEFT", MID_L, -12)
	A.title:SetPoint("TOPRIGHT", -MID_R, -12)
	A.title:SetJustifyH("CENTER")
	A.sub = Text(content, 11, "OUTLINE", 1, 0.9, 0.6, nil, 3)
	A.sub:SetPoint("TOP", A.title, "BOTTOM", 0, -4)
	A.sub:SetWidth(W - MID_L - MID_R + 8)
	A.sub:SetWordWrap(false)
	local amountF = CreateFrame("Frame", nil, A)
	amountF:SetAllPoints()
	amountF:SetFrameLevel(content:GetFrameLevel() + 3)
	A.amount = Text(amountF, 24, "THICKOUTLINE", 1, 1, 1)
	A.amount:SetPoint("TOP", A.sub, "BOTTOM", 0, -4)
	A.amountNum = Text(amountF, 24, "THICKOUTLINE", 1, 1, 1)
	A.amountNum:SetPoint("TOPRIGHT", A.sub, "BOTTOM", -4, -4)
	A.amountWord = Text(amountF, 24, "THICKOUTLINE", 1, 1, 1)
	A.amountWord:SetPoint("LEFT", A.amountNum, "RIGHT", 6, 0)
	A.amountNum:Hide() A.amountWord:Hide()
	A.gems = ns.BuildGemRow(amountF, MID_L, 26)
	A.bar = CreateFrame("StatusBar", nil, content)
	A.bar:SetStatusBarTexture(WHITE)
	A.bar:SetPoint("BOTTOMLEFT", MID_L, 12)
	A.bar:SetPoint("BOTTOMRIGHT", -MID_R, 12)
	A.bar:SetHeight(9)
	A.bar:SetMinMaxValues(0, 1)
	A.bar.bg = A.bar:CreateTexture(nil, "BACKGROUND")
	A.bar.bg:SetAllPoints()
	A.bar.bg:SetColorTexture(0, 0, 0, 0.6)

	-- unlock helpers
	A.dragTint = A:CreateTexture(nil, "OVERLAY", nil, 7)
	A.dragTint:SetAllPoints()
	A.dragTint:SetColorTexture(1, 0.8, 0.2, 0.18)
	A.dragTint:Hide()
	local grip = CreateFrame("Button", nil, A)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(A:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function(self)
		self.startX = GetCursorPosition()
		self.startScale = ns.db.scale
		self:SetScript("OnUpdate", function(gr)
			local x = GetCursorPosition()
			local dx = (x - gr.startX) / UIParent:GetEffectiveScale()
			ns:SetScale(gr.startScale + dx / W)
		end)
	end)
	grip:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	grip:Hide()
	A.grip = grip

	A:RegisterForDrag("LeftButton")
	A:SetScript("OnDragStart", function() P:StartMoving() end)
	A:SetScript("OnDragStop", function()
		P:StopMovingOrSizing()
		local p, _, rp, x, y = P:GetPoint()
		ns.db.point, ns.db.relPoint, ns.db.x, ns.db.y = p, rp, x, y
	end)
	A:SetScript("OnMouseWheel", function(_, delta)
		if IsControlKeyDown() then ns:SetScale(ns.db.scale + delta * 0.05) end
	end)
	A:SetScript("OnUpdate", ns.Safe(function(self, e) ns:UI_Tick(self, e) end))
	A:SetScript("OnShow", function() ns:UI_Layout() end)
	A:SetScript("OnHide", function() ns:UI_Layout() end)

	ns:ApplyMouse(A)
	ns:ApplyTheme(A, key)
	return A
end

function ns:GetAlert(key)
	self.alerts = self.alerts or {}
	if not self.alerts[key] then self.alerts[key] = BuildAlert(key) end
	return self.alerts[key]
end

---------------------------------------------------------------------------
-- TOTAL strip: appears under the stack when two or more pulls are up
---------------------------------------------------------------------------
local function BuildTotals()
	local T = CreateFrame("Frame", nil, ns.anchor)
	T:SetSize(W, TOTAL_H)
	T:SetFrameStrata("HIGH")
	T:Hide()
	T.outer = T:CreateTexture(nil, "BACKGROUND")
	T.outer:SetTexture(M .. "glow_outer")
	T.outer:SetPoint("TOPLEFT", -22, 22) T.outer:SetPoint("BOTTOMRIGHT", 22, -22)
	T.outer:SetBlendMode("ADD")
	T.bg = T:CreateTexture(nil, "BACKGROUND", nil, 1)
	T.bg:SetAllPoints() T.bg:SetTexture(WHITE)
	T.bg:SetGradient("HORIZONTAL", CreateColor(0.10, 0.02, 0.18, 0.92), CreateColor(0.30, 0.06, 0.40, 0.92))
	T.edges = Edges(T, 2)
	T.label = Text(T, 16, "THICKOUTLINE", 1, 0.95, 0.8, "TOTAL")
	T.label:SetPoint("LEFT", 16, 0)
	T.gems = {}
	for i, s in ipairs(ORDER) do
		local info = STAT[s]
		local chip = CreateFrame("Frame", nil, T)
		chip:SetSize(84, TOTAL_H)
		chip:SetPoint("LEFT", T, "LEFT", 100 + (i - 1) * 86, 0)
		chip.gem = chip:CreateTexture(nil, "ARTWORK", nil, 2)
		chip.gem:SetTexture(M .. "gem_white")
		chip.gem:SetSize(24, 24)
		chip.gem:SetPoint("LEFT", 0, 0)
		chip.gem:SetVertexColor(info.r, info.g, info.b)
		chip.letter = Text(chip, 11, "THICKOUTLINE", 1, 1, 1, info.label:sub(1, 1))
		chip.letter:SetPoint("CENTER", chip.gem, "CENTER")
		chip.value = Text(chip, 15, "THICKOUTLINE", Lighten(info.r, info.g, info.b, 0.35))
		chip.value:SetPoint("LEFT", chip.gem, "RIGHT", 4, 0)
		T.gems[s] = chip
	end
	T.t = 0
	T:SetScript("OnUpdate", ns.Safe(function(self, e)
		self.t = self.t + e
		local r, g, b = HSV(self.t * 0.45, 0.7, 1)
		self.outer:SetVertexColor(r, g, b, 0.45 + 0.15 * sin(self.t * 4))
		for i, edge in ipairs(self.edges) do edge:SetVertexColor(HSV(self.t * 0.6 + i * 0.25, 0.8, 1)) end
		local now = GetTime()
		local sums, hidden = {}, {}
		for k, st in pairs(ns.states) do
			local a = ARTS[k]
			local ease = 1 - (1 - min(1, (now - st.start) / 0.45)) ^ 3
			for _, stat in ipairs(a.stats) do
				if st.amount then sums[stat] = (sums[stat] or 0) + st.amount * ease
				elseif st.secretAmount then hidden[stat] = true end
			end
		end
		for _, stat in ipairs(ORDER) do
			local chip = self.gems[stat]
			if sums[stat] then
				chip.value:SetText(FmtAmt(sums[stat]))
				chip.gem:SetAlpha(1) chip.gem:SetDesaturated(false) chip.letter:SetAlpha(1)
			else
				chip.value:SetText(hidden[stat] and "?" or "")
				chip.gem:SetAlpha(0.28) chip.gem:SetDesaturated(true) chip.letter:SetAlpha(0.45)
			end
		end
	end))
	return T
end

function ns:BuildUI()
	local P = CreateFrame("Frame", "GebboBagAnchor", UIParent)
	P:SetSize(W, H)
	P:SetMovable(true)
	P:SetClampedToScreen(true)
	self.anchor = P
	self.alerts = {}
	self.totals = BuildTotals()
	self.frame = self:GetAlert("idle")
	self:ApplyPosition()
	C_Timer.After(2, function() ns:RefreshBadgeIcons() end)
end

-- stack visible panels in a fixed order (Jackpot on top), TOTAL strip after them
function ns:UI_Layout()
	local P, A = self.anchor, self.alerts
	if not P or not A then return end
	local list = {}
	if A.idle and A.idle:IsShown() then list[#list + 1] = A.idle end
	local pulls = 0
	for _, key in ipairs(ns.STACK_ORDER) do
		local a = A[key]
		if a and a:IsShown() then list[#list + 1] = a pulls = pulls + 1 end
	end
	local dir = self.db.growUp and 1 or -1
	for i, a in ipairs(list) do
		a.slotY = dir * (i - 1) * (H + GAP)
		if a.settled ~= false then
			a:ClearAllPoints()
			a:SetPoint("CENTER", P, "CENTER", 0, a.slotY)
		end
	end
	local T = self.totals
	if pulls >= 2 then
		T:ClearAllPoints()
		T:SetPoint("CENTER", P, "CENTER", 0, dir * ((#list - 1) * (H + GAP) + H / 2 + GAP + TOTAL_H / 2))
		T:Show()
	else
		T:Hide()
	end
end

---------------------------------------------------------------------------
-- Position & scale
---------------------------------------------------------------------------
function ns:ApplyPosition()
	local P, db = self.anchor, self.db
	if not P then return end
	P:ClearAllPoints()
	P:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
	P:SetScale(db.scale)
	if self.EngineApplyScale then self:EngineApplyScale() end
end

-- keeps the anchor point where it is on screen while the size changes
function ns:SetScale(v)
	local db = self.db
	v = max(0.3, min(3, floor(v * 100 + 0.5) / 100))
	local old = db.scale or 1
	db.x, db.y = db.x * old / v, db.y * old / v
	db.scale = v
	self:ApplyPosition()
	if self.options and self.options.scaleSlider then self.options.scaleSlider:Sync() end
end

function ns:ApplyMouse(A)
	local u = self.unlocked and true or false
	A:EnableMouse(u)
	A:EnableMouseWheel(u)
	A.grip:SetShown(u)
	A.dragTint:SetShown(u)
end

function ns:SetUnlocked(v)
	self.unlocked = v and true or false
	for key, A in pairs(self.alerts) do
		self:ApplyMouse(A)
		self:ApplyTheme(A, key)
	end
	if self.unlocked then self.alerts.idle.t = 1 end
	if self.options and self.options.lockBtn then
		self.options.lockBtn:SetText(self.unlocked and "Lock" or "Unlock & move")
	end
	self:UI_UpdateVisibility()
end

---------------------------------------------------------------------------
-- Theme a pull onto the panel
---------------------------------------------------------------------------
function ns:ApplyTheme(A, key)
	local th, art = THEME[key] or THEME.idle, ARTS[key]
	A.key = key
	local r, g, b = ns.ThemeColor(key)

	A.bg:SetGradient("HORIZONTAL",
		CreateColor(th.bgA[1], th.bgA[2], th.bgA[3], 0.92),
		CreateColor(th.bgB[1], th.bgB[2], th.bgB[3], 0.92))

	-- icon
	local iconF = A.iconF
	if art then
		iconF.icon:SetTexture(art.icon or ns.FALLBACK_ICON)
	else
		local itemIcon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(ns.ITEM_ID)
		iconF.icon:SetTexture(itemIcon or ns.FALLBACK_ICON)
	end
	iconF.icon:SetDesaturated(th.danger or (key == "idle" and not self.equipped) or false)
	if th.danger then iconF.icon:SetVertexColor(0.65, 1, 0.5) else iconF.icon:SetVertexColor(1, 1, 1) end
	iconF.border:SetDesaturated(not th.rainbow)
	if th.rainbow then iconF.border:SetVertexColor(1, 1, 1, 1) else iconF.border:SetVertexColor(Lighten(r, g, b, 0.25)) end
	iconF.rays:SetVertexColor(Lighten(r, g, b, 0.2))
	iconF.rays:SetAlpha(key == "idle" and 0.25 or 0.6)
	iconF.raysSpin:Play()

	-- words
	if self.unlocked and key == "idle" then
		A.title:SetText("DRAG ME")
	else
		A.title:SetText(th.title)
	end
	local st = self.states[key]
	if art then
		A.sub:SetText(art.name .. ((st and st.fake) and "  (preview)" or ""))
	elseif self.equipped then
		A.sub:SetText(("Rummaging...  %d pulls so far"):format(self.session.total))
	else
		A.sub:SetText("Equip Gebbo's Bottomless Bag")
	end
	A.amount:SetText("")
	A.timerSub:SetShown(art and art.decayPerCast and true or false)

	if A.cameoIsBadge then A.cameoF.icon:SetTexture(ns.ItemIcon() or ns.FALLBACK_ICON) end

	-- bubbles and sparks
	for i, bub in ipairs(A.bubbles) do
		if th.rainbow then bub:SetVertexColor(HSV(i / #A.bubbles, 0.45, 1))
		elseif th.danger then bub:SetVertexColor(0.6, 1, 0.35)
		else bub:SetVertexColor(Lighten(r, g, b, 0.55)) end
		if not bub.ag:IsPlaying() then bub.ag:Play() end
	end
	local sparks = not th.danger and key ~= "idle"
	for i, sp in ipairs(A.sparks) do
		if sparks then
			if th.rainbow then sp:SetVertexColor(HSV(i / #A.sparks, 0.55, 1))
			else sp:SetVertexColor(Lighten(r, g, b, 0.25 + (i % 3) * 0.2)) end
			sp:Show()
			if not sp.ag:IsPlaying() then sp.ag:Play() end
		else
			sp.ag:Stop()
			sp:Hide()
		end
	end

	-- timer sweep
	local cd = iconF.cd
	if st and st.expires and st.duration then
		cd:SetCooldown(st.expires - st.duration, st.duration)
	else
		cd:Clear()
	end
	A.bar:SetStatusBarColor(r, g, b)
	for _, chip in pairs(A.gems) do chip:SetLit(false) end
end

---------------------------------------------------------------------------
-- Events from the core
---------------------------------------------------------------------------
function ns:UI_OnProc(key, st)
	if not self.anchor then return end
	if not st.fake and self:EngineActive() then return end   -- the game is drawing it
	local A = self:GetAlert(key)
	self:ApplyTheme(A, key)
	A.t, A.settled = 0, false
	A:Show()
	self:UI_UpdateVisibility()
	local mood = ARTS[key].mood
	if mood == "jackpot" then self:ScreenFlash("jackpot")
	elseif mood == "bad" then self:ScreenFlash("bad") end
end

function ns:UI_OnProcEnd()
	self:UI_UpdateVisibility()
end

function ns:UI_UpdateVisibility()
	if not self.anchor then return end
	local db, engine = self.db, self:EngineActive()
	local any = false
	for _, key in ipairs(ns.STACK_ORDER) do
		local st, A = self.states[key], self.alerts[key]
		if st and (st.fake or not engine) then
			any = true
			A = self:GetAlert(key)
			if not A:IsShown() then self:ApplyTheme(A, key) A.t = 0.3 A:Show() end
		elseif A then
			A:Hide()
		end
	end
	local idle = self.alerts.idle
	local wantIdle = self.unlocked or (not any and not engine and db.showIdle and self.equipped)
	if wantIdle and not idle:IsShown() then self:ApplyTheme(idle, "idle") end
	idle:SetShown(wantIdle and true or false)
	self:UI_Layout()
end

function ns:EngineActive()
	return self.EngineIsActive and self:EngineIsActive() or false
end

---------------------------------------------------------------------------
-- Every frame while shown
---------------------------------------------------------------------------
function ns:UI_Tick(A, e)
	A.t = A.t + e
	local t, now = A.t, GetTime()
	local key = A.key
	local th = THEME[key] or THEME.idle
	local cr, cg, cb = ns.ThemeColor(key)
	local iconF = A.iconF

	-- colours
	local r, g, b, r2, g2, b2, beat
	if th.rainbow then
		r, g, b = HSV(t * 0.45, 0.85, 1)
		r2, g2, b2 = HSV(t * 0.45 + 0.5, 0.75, 1)
	else
		r, g, b = cr, cg, cb
		r2, g2, b2 = Lighten(cr, cg, cb, 0.3)
	end
	if th.danger then beat = abs(sin(t * 7)) else beat = 0.5 + 0.5 * sin(t * 4) end

	if th.rainbow then
		A.outer:SetVertexColor(r, g, b, 0.55 + 0.15 * sin(t * 5))
		A.inner:SetVertexColor(r2, g2, b2, 0.35 + 0.15 * sin(t * 4))
	elseif th.danger then
		A.outer:SetVertexColor(0.45, 1, 0.15, 0.4 + 0.5 * beat)
		A.inner:SetVertexColor(0.4, 1, 0.1, 0.3 + 0.5 * beat)
	elseif key == "idle" then
		A.outer:SetVertexColor(r, g, b, 0.22 + 0.15 * beat)
		A.inner:SetVertexColor(r2, g2, b2, 0.18)
	else
		A.outer:SetVertexColor(r, g, b, 0.45 + 0.3 * beat)
		A.inner:SetVertexColor(r2, g2, b2, 0.3 + 0.15 * sin(t * 4))
	end
	for i, edge in ipairs(A.edges) do
		if th.rainbow then
			local er, eg, eb = HSV(t * 0.6 + i * 0.25, 0.9, 1)
			edge:SetVertexColor(er, eg, eb, 0.9)
		elseif th.danger then
			edge:SetVertexColor(0.5, 1, 0.2, 0.5 + 0.5 * beat)
		else
			edge:SetVertexColor(r2, g2, b2, 0.85)
		end
	end

	-- the icon gets the strongest glow on the panel
	local fr, fg, fb
	if th.rainbow then fr, fg, fb = HSV(t * 1.1, 1, 1) else fr, fg, fb = r, g, b end
	iconF.glow:SetVertexColor(fr, fg, fb, (key == "idle" and 0.35 or 0.85) + 0.15 * sin(t * 7))
	if th.rainbow then
		iconF.glow2:SetVertexColor(0.45, 0.02, 0.95, 0.75 + 0.25 * sin(t * 2.5))
	else
		iconF.glow2:SetVertexColor(cr * 0.6, cg * 0.6, cb * 0.6, (key == "idle" and 0.3 or 0.65) + 0.25 * sin(t * 2.5))
	end
	local off = t * 0.35
	iconF.border:SetTexCoord(off, off + 1, off * 0.5, off * 0.5 + 1)   -- metal sheen slides around
	local pulse = 0.5 + 0.5 * sin(t * 3)
	iconF.innerGlow:SetVertexColor(Lighten(fr, fg, fb, 0.3 * pulse))
	iconF.innerGlow:SetAlpha(0.35 + 0.25 * sin(t * 6))
	if th.rainbow then iconF.ants:SetVertexColor(HSV(t * 1.6 + 0.5, 0.9, 1)) else iconF.ants:SetVertexColor(r2, g2, b2) end
	iconF.ants:SetShown(key ~= "idle")
	local frame = floor(t * 30) % 22            -- 5x5 ant sheet
	local col, row = frame % 5, floor(frame / 5)
	iconF.ants:SetTexCoord(col * 0.2, col * 0.2 + 0.2, row * 0.2, row * 0.2 + 0.2)
	iconF:SetScale(1 + 0.04 * sin(t * 5))

	-- cameo
	if th.rainbow then A.cameoF.ring:SetVertexColor(r2, g2, b2, 0.85)
	else A.cameoF.ring:SetVertexColor(r2, g2, b2, th.danger and (0.4 + 0.5 * beat) or 0.75) end
	if not A.cameoIsBadge then
		local hs = 1 + 0.05 * sin(t * 3)
		A.cameoF.art:SetSize(CAMEO * hs, CAMEO * hs)
	end

	-- title colour
	if self.unlocked then A.title:SetTextColor(1, 0.85, 0.3)
	elseif th.rainbow then A.title:SetTextColor(HSV(t * 0.8, 0.35, 1))
	elseif th.danger then A.title:SetTextColor(0.55 + 0.45 * beat, 1, 0.3)
	else A.title:SetTextColor(Lighten(cr, cg, cb, 0.55)) end
	if th.rainbow then A.bar:SetStatusBarColor(r, g, b) end

	-- timer + bar
	local st = self.states[key]
	local art = ARTS[key]
	if st and art then
		if st.expires and st.duration then
			local remain = max(0, st.expires - now)
			A.timer:SetText(remain >= 10 and ("%d"):format(remain) or ("%.1f"):format(remain))
			A.bar:SetMinMaxValues(0, st.duration)
			A.bar:SetValue(remain)
			if remain < 3 then A.timer:SetTextColor(1, 0.4, 0.3) else A.timer:SetTextColor(1, 1, 1) end
		elseif art.decayPerCast then
			local total = ceil(art.amount / art.decayPerCast)
			local left = max(0, total - (st.casts or 0))
			A.timer:SetText(tostring(left))
			A.timer:SetTextColor(1, 1, 1)
			A.bar:SetMinMaxValues(0, total)
			A.bar:SetValue(left)
		end
	else
		A.timer:SetText("")
		A.bar:SetValue(0)
	end

	self:UI_Numbers(A, st, art, now)

	-- entrance pop, Voidfin wobble
	if t < 0.25 then A:SetScale(1.35 - 1.4 * t) else A:SetScale(1) end
	if th.danger and t < 0.5 then
		A:ClearAllPoints()
		A:SetPoint("CENTER", self.anchor, "CENTER", math.random(-5, 5), A.slotY + math.random(-5, 5))
	elseif not A.settled then
		A.settled = true
		A:ClearAllPoints()
		A:SetPoint("CENTER", self.anchor, "CENTER", 0, A.slotY)
	end
	if key ~= "idle" and not st and not self.unlocked then A:Hide() end
end

-- featured amount + per-stat totals, counting up for a beat when a pull lands
function ns:UI_Numbers(A, st, art, now)
	if st and art then
		local word = ns.StatWord(art)
		if st.amount then
			local k = min(1, (now - st.start) / 0.45)
			local v = st.amount * (1 - (1 - k) ^ 3)
			A.amount:SetText(((st.source ~= "live") and "~" or "") .. FmtAmt(v) .. " " .. word)
			if v < 0 then A.amount:SetTextColor(0.7, 1, 0.4) else A.amount:SetTextColor(1, 1, 1) end
			A.amount:Show() A.amountNum:Hide() A.amountWord:Hide()
		elseif st.secretAmount then
			A.amount:Hide()
			pcall(A.amountNum.SetText, A.amountNum, st.secretAmount)
			A.amountWord:SetText(word)
			A.amountNum:Show() A.amountWord:Show()
		else
			A.amount:SetText(word) A.amount:Show() A.amountNum:Hide() A.amountWord:Hide()
		end
	else
		A.amount:SetText("") A.amountNum:Hide() A.amountWord:Hide()
	end

	local sums, hidden = {}, {}
	if st and art then
		local ease = 1 - (1 - min(1, (now - st.start) / 0.45)) ^ 3
		for _, stat in ipairs(art.stats) do
			if st.amount then sums[stat] = st.amount * ease
			elseif st.secretAmount then hidden[stat] = st.secretAmount end
		end
	end
	for _, stat in ipairs(ORDER) do
		local chip = A.gems[stat]
		local v = sums[stat]
		if v then
			chip:SetLit(true)
			chip.value:SetText(ns.FmtChip(v))
		elseif hidden[stat] then
			chip:SetLit(true)
			pcall(chip.value.SetText, chip.value, hidden[stat])
		else
			chip:SetLit(false)
		end
	end
end
