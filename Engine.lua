--[[ Gebbo's Bag - ENGINE DISPLAY (Mythic+, raids, boss fights)
  Inside those, WoW hides buffs from addons. Patch 12.1's AuraContainer lets the GAME
  find the buff, set the icon and run the timer and bar, while the addon only decides
  how it looks (same approach as Juggernaut Mode and Sunwell Infusion).

  One container holds a group per pull, in the same order as the normal stack
  (Salmon first). The game only fills a group while that pull is on you and packs
  the filled ones together, so two pulls at once show as two stacked panels.

  The game can't tell us the exact number in here, so the amount line shows the
  calibrated estimate for your item level (marked with ~). For the fading/growing
  pulls a small timer on our own text layer runs the curve down from when the
  panel appeared; if the game ever blocks that, the text simply stays on the
  starting value. Everything else is AnimationGroups. ]]

local ADDON, ns = ...
local ARTS, THEME, STAT = ns.ARTIFACTS, ns.THEME, ns.STAT
local M = ns.MEDIA
local W, H, ICON, CAMEO, MID_L, MID_R, GAP = ns.W, ns.H, ns.ICON, ns.CAMEO, ns.MID_L, ns.MID_R, ns.GAP
local Anim, HSV, Lighten, Text = ns.Anim, ns.HSV, ns.Lighten, ns.Text

local parent, built = nil, false
local container, signature = nil, nil
local serial = 0

local supported
local function Supported()
	if supported ~= nil then return supported end
	supported = false
	if not C_AuraContainerUtil then return false end
	local ok, f = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
	if ok and f then f:Hide() supported = true end
	return supported
end

local function Loop(region, steps)
	for i, st in ipairs(steps) do st.order = i st.type = st.type or "Alpha" end
	local ag = Anim(region, "REPEAT", steps)
	ag:Play()
	return ag
end

-- a colour that fades in and out in its own time slot -> several of these = cycling rainbow
local function RainbowLayers(owner, texture, inset, layer, sub, count, alpha, period)
	local slot = period / count
	for i = 1, count do
		local r, g, b = HSV((i - 1) / count, 0.9, 1)
		local t = owner:CreateTexture(nil, layer, nil, sub)
		t:SetTexture(texture)
		t:SetPoint("TOPLEFT", inset, -inset)
		t:SetPoint("BOTTOMRIGHT", -inset, inset)
		t:SetBlendMode("ADD")
		t:SetVertexColor(r, g, b, alpha)
		t:SetAlpha(0)
		local steps = {}
		if i > 1 then steps[#steps + 1] = { from = 0, to = 0, d = (i - 1) * slot } end
		steps[#steps + 1] = { from = 0, to = 1, d = slot, smooth = "IN_OUT" }
		steps[#steps + 1] = { from = 1, to = 0, d = slot, smooth = "IN_OUT" }
		local rest = period - (i + 1) * slot
		if rest > 0.01 then steps[#steps + 1] = { from = 0, to = 0, d = rest } end
		Loop(t, steps)
	end
end

local function Estimate(key)
	local art = ARTS[key]
	local f = ns:GetScaleFactor()
	return art.amount * f
end

-- the engine drives these: icon texture, radial sweep + countdown numbers, draining bar
local function EngineParts(button, above, r, g, b)
	local icon = button:CreateTexture(nil, "ARTWORK", nil, 1)
	icon:SetSize(ICON, ICON)
	icon:SetPoint("LEFT", 12, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button:SetIcon(icon)

	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cd:SetAllPoints(icon)
	cd:SetReverse(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetSwipeColor(0, 0, 0, 0.55)
	cd:SetHideCountdownNumbers(false)
	pcall(cd.SetCountdownFont, cd, "GebboBagTimerFont")
	cd:SetFrameLevel(above + 2)
	button:SetDurationCooldown(cd)

	if button.SetDurationBar then
		local bar = CreateFrame("StatusBar", nil, button)
		bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		bar:SetStatusBarColor(r, g, b)
		bar:SetPoint("BOTTOMLEFT", MID_L, 12)
		bar:SetPoint("BOTTOMRIGHT", -MID_R, 12)
		bar:SetHeight(9)
		bar:SetFrameLevel(above + 2)
		local bg = bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints() bg:SetColorTexture(0, 0, 0, 0.6)
		local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Linear
		pcall(button.SetDurationBar, button, bar, interp and { interpolation = interp } or {})
	end
	return icon
end

---------------------------------------------------------------------------
-- One themed panel (built by the game, once per button)
---------------------------------------------------------------------------
local function BuildPanel(button, key)
	local th, art = THEME[key], ARTS[key]
	local r, g, b = ns.ThemeColor(key)
	local r2, g2, b2 = Lighten(r, g, b, 0.3)
	button:SetSize(W, H)

	local bg = button:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	bg:SetGradient("HORIZONTAL", CreateColor(th.bgA[1], th.bgA[2], th.bgA[3], 1), CreateColor(th.bgB[1], th.bgB[2], th.bgB[3], 1))

	if th.rainbow then
		RainbowLayers(button, M .. "glow_inner", 0, "BACKGROUND", -4, 6, 0.55, 3.0)
		RainbowLayers(button, M .. "glow_outer", -30, "BACKGROUND", -6, 6, 0.8, 2.4)
	else
		local fast = th.danger and 0.22 or 0.6
		local outer = button:CreateTexture(nil, "BACKGROUND", nil, -6)
		outer:SetTexture(M .. "glow_outer")
		outer:SetPoint("TOPLEFT", -36, 36) outer:SetPoint("BOTTOMRIGHT", 36, -36)
		outer:SetBlendMode("ADD")
		outer:SetVertexColor(r, g, b, 1)
		Loop(outer, { { from = 0.4, to = 0.9, d = fast }, { from = 0.9, to = 0.4, d = fast } })
		local inner = button:CreateTexture(nil, "BACKGROUND", nil, -4)
		inner:SetTexture(M .. "glow_inner")
		inner:SetAllPoints()
		inner:SetBlendMode("ADD")
		inner:SetVertexColor(r2, g2, b2, 1)
		Loop(inner, { { from = 0.25, to = th.danger and 1 or 0.55, d = fast }, { from = th.danger and 1 or 0.55, to = 0.25, d = fast } })
	end
	local er, eg, eb = r2, g2, b2
	if th.rainbow then er, eg, eb = 1, 0.85, 0.3 end
	for _, spec in ipairs({
		{ "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
	}) do
		local t = button:CreateTexture(nil, "OVERLAY", nil, 6)
		t:SetColorTexture(er, eg, eb, 1)
		t:SetPoint(spec[1]) t:SetPoint(spec[2])
		if spec[3] then t:SetHeight(2) else t:SetWidth(2) end
	end

	-- bubbles (clipped layer)
	local clip = CreateFrame("Frame", nil, button)
	clip:SetAllPoints()
	clip:SetClipsChildren(true)
	for i, bub in ipairs(ns.BuildBubbles(clip, 9)) do
		if th.rainbow then bub:SetVertexColor(HSV(i / 9, 0.45, 1))
		elseif th.danger then bub:SetVertexColor(0.6, 1, 0.35)
		else bub:SetVertexColor(Lighten(r, g, b, 0.55)) end
		bub.ag:Play()
	end
	local above = clip:GetFrameLevel()

	-- glow, rays and the metal frame behind the icon
	local cx = 12 + ICON / 2
	local function behind(file, size, sub, blend)
		local t = button:CreateTexture(nil, "BORDER", nil, sub)
		t:SetTexture(M .. file)
		t:SetSize(size, size)
		t:SetPoint("CENTER", button, "LEFT", cx, 0)
		if blend then t:SetBlendMode(blend) end
		return t
	end
	local glow2 = behind("glow_outer", ICON + 88, 0, "ADD")
	if th.rainbow then glow2:SetVertexColor(0.45, 0.02, 0.95, 1) else glow2:SetVertexColor(r * 0.6, g * 0.6, b * 0.6, 1) end
	Loop(glow2, { { from = 0.5, to = 1, d = 0.8 }, { from = 1, to = 0.5, d = 0.8 } })
	local glow = behind("glow_outer", ICON + 60, 1, "ADD")
	glow:SetVertexColor(r, g, b, 1)
	Loop(glow, { { from = 0.6, to = 1, d = 0.35 }, { from = 1, to = 0.6, d = 0.35 } })
	local rays = behind("rays_white", ICON * 1.6, 2)
	rays:SetVertexColor(Lighten(r, g, b, 0.2))
	rays:SetAlpha(0.6)
	Anim(rays, "REPEAT", { { type = "Rotation", deg = -360, d = 12 } }):Play()
	local metal = button:CreateTexture(nil, "BORDER", nil, 4)
	metal:SetTexture(M .. "metal_rainbow", "REPEAT", "REPEAT")
	metal:SetSize(ICON + 10, ICON + 10)
	metal:SetPoint("LEFT", 7, 0)
	if not th.rainbow then metal:SetDesaturated(true) metal:SetVertexColor(Lighten(r, g, b, 0.25)) end
	Loop(metal, { { from = 1, to = 0.65, d = 0.5 }, { from = 0.65, to = 1, d = 0.5 } })

	local icon = EngineParts(button, above, r, g, b)
	if th.danger then icon:SetDesaturated(true) icon:SetVertexColor(0.65, 1, 0.5) end
	local iconGlow = button:CreateTexture(nil, "ARTWORK", nil, 3)
	iconGlow:SetTexture(M .. "glow_inner")
	iconGlow:SetAllPoints(icon)
	iconGlow:SetBlendMode("ADD")
	iconGlow:SetVertexColor(r2, g2, b2, 0.8)
	Loop(iconGlow, { { from = 0.2, to = 1, d = 0.4 }, { from = 1, to = 0.2, d = 0.4 } })

	if not th.danger then
		local sparkF = CreateFrame("Frame", nil, button)
		sparkF:SetAllPoints()
		sparkF:SetFrameLevel(above + 4)
		for i, sp in ipairs(ns.BuildSparks(sparkF, icon, ICON)) do
			if th.rainbow then sp:SetVertexColor(HSV(i / 10, 0.55, 1)) else sp:SetVertexColor(Lighten(r, g, b, 0.25 + (i % 3) * 0.2)) end
			sp.ag:Play()
		end
	end

	-- cameo: the bag's own icon as a cartoon badge (Voidfin: the rotten fish)
	local cameoX = W - 12 - CAMEO / 2
	if th.cameo == "voidfin" then
		local ring = button:CreateTexture(nil, "BORDER", nil, 1)
		ring:SetTexture(M .. "glow_outer")
		ring:SetSize(CAMEO + 36, CAMEO + 36)
		ring:SetPoint("CENTER", button, "LEFT", cameoX, 0)
		ring:SetBlendMode("ADD")
		ring:SetVertexColor(r2, g2, b2, 1)
		Loop(ring, { { from = 0.3, to = 1, d = 0.22 }, { from = 1, to = 0.3, d = 0.22 } })
		local fish = button:CreateTexture(nil, "ARTWORK", nil, 2)
		fish:SetTexture(M .. "voidfin")
		fish:SetSize(CAMEO, CAMEO)
		fish:SetPoint("CENTER", button, "LEFT", cameoX, 0)
		Loop(fish, { { type = "Scale", from = 1, to = 1.06, d = 0.9, smooth = "IN_OUT" },
		             { type = "Scale", from = 1.06, to = 1, d = 0.9, smooth = "IN_OUT" } })
	else
		local badge = ns.BuildBadge(button, CAMEO, r, g, b, th.rainbow)
		badge:SetPoint("CENTER", button, "LEFT", cameoX, 0)
		badge:SetFrameLevel(above + 1)
		Loop(badge.ring, { { from = 0.4, to = 1, d = 0.7 }, { from = 1, to = 0.4, d = 0.7 } })
	end

	-- words sit above the bubbles
	local textF = CreateFrame("Frame", nil, button)
	textF:SetAllPoints()
	textF:SetFrameLevel(above + 3)
	local tr, tg, tb = Lighten(r, g, b, 0.55)
	if th.rainbow then tr, tg, tb = 1, 0.95, 0.8 elseif th.danger then tr, tg, tb = 0.7, 1, 0.3 end
	local title = Text(textF, 20, "THICKOUTLINE", tr, tg, tb, th.title)
	title:SetPoint("TOPLEFT", MID_L, -12) title:SetPoint("TOPRIGHT", -MID_R, -12)
	title:SetJustifyH("CENTER")
	Loop(title, { { from = 1, to = 0.6, d = th.danger and 0.22 or 0.35 }, { from = 0.6, to = 1, d = th.danger and 0.22 or 0.35 } })
	local sub = Text(textF, 11, "OUTLINE", 1, 0.9, 0.6, art.name)
	sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
	local est = Estimate(key)
	local amount = Text(textF, 24, "THICKOUTLINE", 1, 1, 1, "~" .. ns.FmtAmt(est) .. " " .. ns.StatWord(art))
	amount:SetPoint("TOP", sub, "BOTTOM", 0, -4)
	if est < 0 then amount:SetTextColor(0.7, 1, 0.4) end

	local gems = ns.BuildGemRow(textF, MID_L, 26)
	for _, chip in pairs(gems) do
		chip:SetFrameLevel(above + 3)
		chip:SetLit(false)
	end
	for _, s in ipairs(art.stats) do
		gems[s]:SetLit(true)
		gems[s].value:SetText(ns.FmtChip(est))
	end

	-- fading / growing pulls: run the number down (or up) on our own text layer.
	-- OnUpdate only runs while the panel is visible, so a gap means a fresh pull.
	if art.decayPerSec or art.decayPerCast or art.growPerSec then
		local live = { lastTick = 0, start = 0, castBase = 0, acc = 0 }
		local word = ns.StatWord(art)
		local ok = pcall(textF.SetScript, textF, "OnUpdate", function(self, e)
			local okRun, err = pcall(function()
				local now = GetTime()
				if now - live.lastTick > 0.3 then live.start, live.castBase = now, ns.castCount or 0 end
				live.lastTick = now
				live.acc = live.acc + e
				if live.acc < 0.1 then return end
				live.acc = 0
				local v = ns:ModelAt(key, now - live.start, (ns.castCount or 0) - live.castBase)
				amount:SetText("~" .. ns.FmtAmt(v) .. " " .. word)
				for _, s in ipairs(art.stats) do gems[s].value:SetText(ns.FmtChip(v)) end
				ns.engineLive = true
			end)
			if not okRun then
				ns.engineLive = false
				self:SetScript("OnUpdate", nil)
			end
		end)
		if not ok then ns.engineLive = false end
	end
end

---------------------------------------------------------------------------
-- Container
---------------------------------------------------------------------------
-- Which aura list each pull lives in. Learned in the open world (the core records
-- whether each spell is a buff or a debuff); sensible guesses until then.
local function GroupsFor(key)
	local art = ARTS[key]
	local kinds = ns.db.auraKind or {}
	local help, harm = {}, {}
	local nh, nd = 0, 0
	for _, id in ipairs(art.idlist) do
		local k = kinds[id]
		if k == "HARMFUL" then harm[id] = true nd = nd + 1
		elseif k == "HELPFUL" then help[id] = true nh = nh + 1
		elseif key == "voidfin" then harm[id] = true help[id] = true nd = nd + 1 nh = nh + 1
		else help[id] = true nh = nh + 1 end
	end
	local out = {}
	if key == "voidfin" then
		if nd > 0 then out[#out + 1] = { filter = "HARMFUL", ids = harm } end
		if nh > 0 then out[#out + 1] = { filter = "HELPFUL", ids = help } end
	else
		-- Seashell: the crit buff is what matters; skip its bleed so it doesn't show twice
		if nh > 0 then out[#out + 1] = { filter = "HELPFUL", ids = help }
		elseif nd > 0 then out[#out + 1] = { filter = "HARMFUL", ids = harm } end
	end
	return out
end

local function Signature()
	local parts = { tostring(ns.db.growUp) }
	for _, key in ipairs(ns.STACK_ORDER) do
		for _, grp in ipairs(GroupsFor(key)) do
			local ids = {}
			for id in pairs(grp.ids) do ids[#ids + 1] = id end
			table.sort(ids)
			parts[#parts + 1] = key .. grp.filter .. table.concat(ids, ",")
		end
	end
	return table.concat(parts, "|")
end

local function SetLayout(c)
	local up = ns.db.growUp
	local ok = pcall(function()
		local axis, dir = AnchorUtil.FlowLayoutAxis, AnchorUtil.FlowDirection
		assert(axis.Vertical and dir.Down and dir.Up)
		c:SetFlowLayoutAxis(axis.Vertical)
		c:SetFlowLayoutAnchorPoint(up and "BOTTOMLEFT" or "TOPLEFT")
		c:SetFlowLayoutGrowthDirection(up and dir.Up or dir.Down, dir.Right)
	end)
	if ok then ns.engineLayout = "stacked " .. (up and "upwards" or "downwards") return end
	ok = pcall(function()
		c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
		c:SetFlowLayoutAnchorPoint("TOPLEFT")
		c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
	end)
	ns.engineLayout = ok and "side by side (this client has no vertical stacking)" or "default"
end

local function MakeContainer()
	serial = serial + 1
	local up = ns.db.growUp
	local c = CreateFrame("AuraContainer", "GebboBagEngine" .. serial, parent, "CustomAuraContainerTemplate")
	c:Hide()
	c:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", parent, up and "BOTTOMLEFT" or "TOPLEFT")
	c:SetFrameStrata("HIGH")
	c:SetFrameLevel(20)
	SetLayout(c)
	c:SetUnit("player")
	local index = 0
	for _, key in ipairs(ns.STACK_ORDER) do
		for _, grp in ipairs(GroupsFor(key)) do
			index = index + 1
			c:AddAuraGroup(key .. grp.filter, grp.filter, {
				maxFrameCount = 1,
				candidateFilters = { includeSpellIDs = grp.ids },
				initializeFrame = function(button)
					local ok, err = pcall(BuildPanel, button, key)
					if not ok then ns.Print("engine panel build error: " .. tostring(err)) end
				end,
				layout = { elementWidth = W, elementHeight = H, elementSpacing = GAP, lineSpacing = GAP,
				           elementSpacingX = GAP, elementSpacingY = GAP, layoutIndex = index },
			})
		end
	end
	c:Show()
	return c, index
end

local function Build()
	if not Supported() then return false end
	if InCombatLockdown() then ns.engineDirty = true return false end
	if not parent then
		parent = CreateFrame("Frame", "GebboBagEngine", ns.anchor)
		parent:SetSize(W, H)
		parent:SetPoint("CENTER", ns.anchor, "CENTER")
		parent:SetFrameStrata("HIGH")
		parent:Hide()
	end
	local sig = Signature()
	if built and sig == signature then ns.engineDirty = nil return true end
	local ok, err = pcall(function()
		if container then container:Hide() end
		local groups
		container, groups = MakeContainer()
		ns.engineGroups = groups
	end)
	if not ok then
		ns.Print("Engine display unavailable: " .. tostring(err))
		return false
	end
	signature, built = sig, true
	ns.engineDirty = nil
	return true
end

local function Wanted()
	local mode = ns.db and ns.db.engine or "auto"
	if mode == "off" then return false end
	if mode == "on" then return true end
	return ns:AurasSecret()
end

function ns:EngineIsActive()
	return built and parent and parent:IsShown() or false
end

function ns:EngineRebuild()
	if InCombatLockdown() then ns.engineDirty = true return end
	pcall(Build)
end

function ns:EngineStatus()
	if not built then
		return Supported() and "Engine display: ready (not built yet)" or "Engine display: |cffff4040not supported on this client|r"
	end
	local seen = {}
	local n = 0
	for _, key in ipairs(ns.STACK_ORDER) do if #GroupsFor(key) > 0 and not seen[key] then seen[key] = true n = n + 1 end end
	return ("Engine display: |cff00ff00built|r for %d of 6 pulls, %s (mode %s)"):format(n,
		parent:IsShown() and "|cff00ff00ACTIVE|r" or "standby", tostring(ns.db.engine or "auto"))
end

function ns:EngineInit()
	pcall(Build)
	C_Timer.NewTicker(0.25, function()
		if ns.engineDirty and not InCombatLockdown() then pcall(Build) end
		if not built then return end
		local want = Wanted()
		if want ~= parent:IsShown() then
			parent:SetShown(want)
			ns:UI_UpdateVisibility()
		end
	end)
end
