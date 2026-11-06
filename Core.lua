local ADDON, ns = ...

local GetTime, pcall, pairs, ipairs, type, tonumber = GetTime, pcall, pairs, ipairs, type, tonumber
local abs, max, min, floor = math.abs, math.max, math.min, math.floor
local ARTS = ns.ARTIFACTS

---------------------------------------------------------------------------
-- Secret-value safety (Midnight 12.x)
-- Never compare, index or do maths on a value before checking it is readable.
---------------------------------------------------------------------------
local isSecret = issecretvalue or function() return false end
local function Readable(v)
	if isSecret(v) then return false end
	return v ~= nil
end
local function Field(t, k)
	local ok, v = pcall(function() return t[k] end)
	if ok then return v end
end
ns.Readable, ns.IsSecret = Readable, isSecret

local function Print(msg)
	print("|cff5fe3d0Gebbo's|r|cffffd27fBag|r: " .. tostring(msg))
end
ns.Print = Print

-- Never let a game restriction spam errors: catch, store, notify once (/gbag errors)
local errLog, errNotified = {}, false
ns.errLog = errLog
local function Safe(fn)
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			if #errLog >= 20 then table.remove(errLog, 1) end
			errLog[#errLog + 1] = date("%H:%M:%S") .. "  " .. tostring(err)
			if not errNotified then
				errNotified = true
				Print("hit a game restriction (handled). Type /gbag errors to see it.")
			end
		end
	end
end
ns.Safe = Safe

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
local DEFAULTS = {
	point = "CENTER", relPoint = "CENTER", x = 0, y = -140, scale = 1.0,
	sound = true, nativeSound = true, sadSound = true, channel = "Master",
	flash = true, engine = "auto", showIdle = false, growUp = false,
	learnedIDs = {}, manualIDs = {}, calib = {}, auraKind = {},
}

local function ApplyDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			if type(v) == "table" then db[k] = {} ApplyDefaults(db[k], v) else db[k] = v end
		end
	end
end

ns.session = { total = 0, counts = {}, history = {}, combatTime = 0, buffTime = 0 }
ns.states = {}
local states = ns.states

---------------------------------------------------------------------------
-- Spell ID discovery
---------------------------------------------------------------------------
local idToKey = {}

local function SpellName(id)
	local fn = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
	if not fn then return end
	local ok, name = pcall(fn, id)
	if ok and Readable(name) and type(name) == "string" then return name end
end

local function SpellIcon(id)
	local fn = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
	if not fn then return end
	local ok, icon = pcall(fn, id)
	if ok and Readable(icon) then return icon end
end

function ns:AddID(key, id, persist)
	local art = ARTS[key]
	id = tonumber(id)
	if not art or not id or art.idset[id] then return false end
	art.idset[id] = true
	art.idlist[#art.idlist + 1] = id
	table.sort(art.idlist)
	idToKey[id] = key
	if not art.icon then art.icon = SpellIcon(id) end
	if persist then
		local list = self.db.learnedIDs[key] or {}
		self.db.learnedIDs[key] = list
		list[#list + 1] = id
	end
	return true
end

function ns:ScanSpellRanges()
	for _, range in ipairs(ns.SCAN_RANGES) do
		for id = range[1], range[2] do
			local name = SpellName(id)
			if name then
				local lname = name:lower()
				for key, art in pairs(ARTS) do
					for _, pat in ipairs(art.match) do
						if lname:find(pat, 1, true) then self:AddID(key, id, false) end
					end
				end
			end
		end
	end
end

function ns:RebuildIDs()
	wipe(idToKey)
	for key, art in pairs(ARTS) do
		art.idset, art.idlist, art.icon = {}, {}, nil
		for _, id in ipairs(art.ids or {}) do self:AddID(key, id) end
		for _, id in ipairs(self.db.manualIDs[key] or {}) do self:AddID(key, id) end
		for _, id in ipairs(self.db.learnedIDs[key] or {}) do self:AddID(key, id) end
	end
	self:ScanSpellRanges()
	self.needLearn = false
	for _, art in pairs(ARTS) do
		if #art.idlist == 0 then self.needLearn = true end
		art.icon = art.icon or ns.FALLBACK_ICON
	end
end

-- Out of restricted content aura names are readable, so unknown pulls can be learned live.
function ns:MaybeLearn(now)
	if not self.needLearn or now - (self.lastLearn or 0) < 1 then return end
	self.lastLearn = now
	local getByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not getByIndex then return end
	local learned = false
	for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
		for i = 1, 60 do
			local ok, aura = pcall(getByIndex, "player", i, filter)
			if not ok or isSecret(aura) then return end
			if not aura then break end
			local name, id = Field(aura, "name"), Field(aura, "spellId")
			if Readable(name) and Readable(id) and type(name) == "string" and not idToKey[id] then
				local lname = name:lower()
				for key, art in pairs(ARTS) do
					for _, pat in ipairs(art.match) do
						if lname:find(pat, 1, true) and self:AddID(key, id, true) then
							learned = true
							Print(("learned |cffffd27f%s|r = spell %d"):format(art.name, id))
						end
					end
				end
			end
		end
	end
	if learned then
		self.needLearn = false
		for _, art in pairs(ARTS) do if #art.idlist == 0 then self.needLearn = true end end
		self:RegisterNativeSounds()
		if self.EngineRebuild then self:EngineRebuild() end
	end
end

---------------------------------------------------------------------------
-- Item level, equip state, calibration
---------------------------------------------------------------------------
function ns:UpdateEquip()
	local slot
	for _, s in ipairs({ 13, 14 }) do
		local id = GetInventoryItemID("player", s)
		if Readable(id) and id == ns.ITEM_ID then slot = s end
	end
	self.equipped, self.slot = slot ~= nil, slot
	if slot and ItemLocation and C_Item and C_Item.GetCurrentItemLevel then
		local ok, il = pcall(C_Item.GetCurrentItemLevel, ItemLocation:CreateFromEquipmentSlot(slot))
		if ok and Readable(il) and type(il) == "number" then self.ilvl = il end
	end
	self:ApplyVisibility()
end

function ns:GetScaleFactor()
	local il = self.ilvl or ns.BASE_ILVL
	local calib = self.db.calib
	if calib[il] then return calib[il], true end
	local best, bestD
	for k, v in pairs(calib) do
		local d = abs(k - il)
		if not bestD or d < bestD then best, bestD = k, d end
	end
	if best then return calib[best] * ns.ILVL_GROWTH ^ (il - best), true end
	return ns.NERF * ns.ILVL_GROWTH ^ (il - ns.BASE_ILVL), false
end

-- Raw community model for a pull, before scaling
local function Model(art, st, now)
	local el = now - st.start
	if art.decayPerSec then return max(0, art.amount - art.decayPerSec * el) end
	if art.decayPerCast then return max(0, art.amount - art.decayPerCast * (st.casts or 0)) end
	if art.growPerSec then return art.growPerSec * min(art.duration or 12, floor(el) + 1) end
	return art.amount
end

-- the documented curve for a pull, scaled to your item level (el = seconds since it landed)
function ns:ModelAt(key, el, casts)
	return Model(ARTS[key], { start = 0, casts = casts or 0 }, el) * self:GetScaleFactor()
end

-- Rating -> percent, using your current totals (close enough for a readout)
function ns:RatingToPct(stat, amount)
	local cr = ns.STAT[stat] and ns.STAT[stat].cr
	if not cr or not GetCombatRating or not GetCombatRatingBonus then return end
	local ok1, rating = pcall(GetCombatRating, cr)
	local ok2, bonus = pcall(GetCombatRatingBonus, cr)
	if not (ok1 and ok2 and Readable(rating) and Readable(bonus)) or rating <= 0 then return end
	local per = bonus / rating
	if stat == "mastery" and GetMasteryEffect then
		local ok3, _, coeff = pcall(GetMasteryEffect)
		if ok3 and Readable(coeff) and type(coeff) == "number" and coeff > 0 then per = per * coeff end
	end
	return amount * per
end

---------------------------------------------------------------------------
-- Proc lifecycle
---------------------------------------------------------------------------
local function ReadAura(id)
	local fn = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	if not fn then return nil end
	local ok, aura = pcall(fn, id)
	if not ok or isSecret(aura) then
		ns.secretSeen = GetTime()
		return "secret"
	end
	return aura
end

function ns:AnyActive()
	return next(states) ~= nil
end

function ns:StartProc(key, now, fake)
	local art = ARTS[key]
	local st = { key = key, start = now, casts = 0, fake = fake or nil }
	if art.duration then
		st.duration, st.expires = art.duration, now + art.duration
	elseif art.softCap then
		st.softExpire = now + (fake and 14 or art.softCap)
	end
	states[key] = st
	self.featured = key

	local S = self.session
	S.total = S.total + 1
	S.counts[key] = (S.counts[key] or 0) + 1
	table.insert(S.history, 1, key)
	while #S.history > 10 do table.remove(S.history) end

	self:ApplyVisibility()
	return st
end

-- Called once a new pull's numbers are known: sound + on-screen fanfare
function ns:Announce(key, st)
	if st.fake or not ARTS[key].nativeHandle then self:PlayArtifactSound(key) end
	if self.UI_OnProc then self:UI_OnProc(key, st) end
end

function ns:EndProc(key)
	states[key] = nil
	if self.featured == key then
		local best, bestT
		for k, st in pairs(states) do
			if not bestT or st.start > bestT then best, bestT = k, st.start end
		end
		self.featured = best
	end
	if self.UI_OnProcEnd then self:UI_OnProcEnd(key) end
	self:ApplyVisibility()
end

function ns:UpdateFromAura(key, st, aura, now)
	local art = ARTS[key]
	local exp, dur = Field(aura, "expirationTime"), Field(aura, "duration")
	if Readable(exp) and Readable(dur) and type(dur) == "number" and dur > 0 and exp > 0 then
		st.expires, st.duration = exp, dur
		st.softExpire = nil
	end
	local icon = Field(aura, "icon")
	if Readable(icon) then art.icon = icon end
	local stacks = Field(aura, "applications")
	if Readable(stacks) and type(stacks) == "number" then st.stacks = stacks end

	local pts = Field(aura, "points")
	if isSecret(pts) then
		st.secretAmount, st.source = pts, "secret"
		return
	end
	if type(pts) ~= "table" then return end
	local best
	for i = 1, #pts do
		local p = pts[i]
		if isSecret(p) then
			st.secretAmount, st.source = p, "secret"
			return
		elseif type(p) == "number" and p ~= 0 and (not best or abs(p) > abs(best)) then
			best = p
		end
	end
	if not best then return end

	local amount = abs(best)
	if art.stackScaled and (st.stacks or 0) > 1 then amount = amount * st.stacks end
	if art.amount < 0 then amount = -amount end

	if st.liveAmount and st.liveAmount ~= amount then st.liveChanged = true end
	st.firstLive = st.firstLive or amount
	st.liveAmount, st.source, st.secretAmount = amount, "live", nil

	if art.calibrate and self.ilvl then
		local f = abs(amount) / abs(art.amount)
		if f > 0.05 and f < 10 then self.db.calib[self.ilvl] = f end
	end
end

function ns:RefreshAmount(key, st, now)
	local art = ARTS[key]
	local dynamic = art.decayPerSec or art.decayPerCast or art.growPerSec
	if st.source == "secret" then
		-- a hidden number can't be animated, and the buff's own number doesn't tick:
		-- for fading/growing pulls show the moving estimate instead of a frozen value
		st.amount = dynamic and (Model(art, st, now) * self:GetScaleFactor()) or nil
	elseif st.source == "live" and st.liveAmount then
		if dynamic and st.firstLive then
			-- run the documented curve from the real starting value; if the buff's own
			-- number does tick, whichever is further along wins
			local first = Model(art, { start = st.start, casts = 0 }, st.start)
			local model = Model(art, st, now) * (st.firstLive / first)
			if art.growPerSec then st.amount = max(st.liveAmount, model)
			else st.amount = min(st.liveAmount, model) end
		else
			st.amount = st.liveAmount
		end
	else
		st.amount = Model(art, st, now) * self:GetScaleFactor()
		st.source = st.fake and "test" or "est"
	end
end

function ns:Poll()
	local now = GetTime()
	for key, art in pairs(ARTS) do
		local st = states[key]
		if st and st.fake then
			if (st.expires and now >= st.expires) or (st.softExpire and now >= st.softExpire)
				or (art.decayPerCast and (st.amount or 1) <= 0) then
				self:EndProc(key)
			end
		else
			local seen, unknown, aura = false, false, nil
			for _, id in ipairs(art.idlist) do
				local a = ReadAura(id)
				if a == "secret" then
					unknown = true
				elseif a then
					local helpful = Field(a, "isHelpful")
					if Readable(helpful) then
						local kind = helpful and "HELPFUL" or "HARMFUL"
						if self.db.auraKind[id] ~= kind then
							self.db.auraKind[id] = kind
							self.engineDirty = true
						end
					end
					if not aura or (Readable(helpful) and helpful and art.amount > 0) then aura = a end
					seen = true
				end
			end
			if seen then
				local isNew = not st
				st = st or self:StartProc(key, now)
				self:UpdateFromAura(key, st, aura, now)
				if isNew then
					self:RefreshAmount(key, st, now)
					self:Announce(key, st)
				end
			elseif st then
				local over = (st.expires and now >= st.expires) or (st.softExpire and now >= st.softExpire)
				if not unknown or over then self:EndProc(key) end
			end
		end
		if states[key] then self:RefreshAmount(key, states[key], now) end
	end

	self:MaybeLearn(now)

	-- uptime bookkeeping (only while in combat with the bag on)
	local dt = now - (self.lastAcc or now)
	self.lastAcc = now
	if dt > 0 and dt < 1 and InCombatLockdown() and self.equipped then
		local S = self.session
		S.combatTime = S.combatTime + dt
		for key in pairs(states) do
			if ARTS[key].amount > 0 then S.buffTime = S.buffTime + dt break end
		end
	end
end

function ns:AurasSecret()
	if C_Secrets and C_Secrets.ShouldAurasBeSecret then
		local ok, v = pcall(C_Secrets.ShouldAurasBeSecret)
		if ok then return v == true end
	end
	return false
end

function ns:IsRestricted()
	if self:AurasSecret() then return true end
	if self.secretSeen ~= nil and GetTime() - self.secretSeen < 3 then return true end
	-- Blizzard may also just return nothing inside boss fights and keys
	if InCombatLockdown() then
		local ok1, enc = pcall(function() return IsEncounterInProgress and IsEncounterInProgress() end)
		local ok2, key = pcall(function() return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() end)
		if (ok1 and Readable(enc) and enc) or (ok2 and Readable(key) and key) then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Test pulls
---------------------------------------------------------------------------
local keys = {}
for k in pairs(ARTS) do keys[#keys + 1] = k end
table.sort(keys, function(a, b) return ARTS[a].order < ARTS[b].order end)
ns.KEYS = keys

function ns:SimulateProc(key)
	if not key or not ARTS[key] then key = keys[math.random(#keys)] end
	if states[key] then states[key] = nil end
	local st = self:StartProc(key, GetTime(), true)
	self:RefreshAmount(key, st, GetTime())
	self:Announce(key, st)
	return key
end

---------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------
function ns:PlayArtifactSound(key, force)
	local db = self.db
	if not force and not db.sound then return end
	local art = ARTS[key]
	if art.sound == "womp" and not db.sadSound and not force then return end
	PlaySoundFile(ns.SOUNDS[art.sound], db.channel)
end

-- Blizzard's own aura-sound engine (12.1+) keeps playing even where aura data is hidden from addons.
function ns:UnregisterNativeSounds()
	local remove = C_UnitAuras and C_UnitAuras.RemoveAuraSound
	for _, art in pairs(ARTS) do
		if art.nativeHandle and remove then pcall(remove, art.nativeHandle) end
		art.nativeHandle = nil
	end
end

function ns:RegisterNativeSounds()
	if not (C_UnitAuras and C_UnitAuras.AddAuraSound) then return end
	if InCombatLockdown() then self.pendingNative = true return end
	self:UnregisterNativeSounds()
	local db = self.db
	if not (db.sound and db.nativeSound) then return end
	local trigger = (Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added) or 0
	for _, art in pairs(ARTS) do
		local id = art.idlist[1]
		if id and not (art.sound == "womp" and not db.sadSound) then
			local ok, handle = pcall(C_UnitAuras.AddAuraSound, trigger, {
				unitToken = "player", spellID = id,
				soundFileName = ns.SOUNDS[art.sound], outputChannel = db.channel,
			})
			if ok and handle then art.nativeHandle = handle end
		end
	end
end

---------------------------------------------------------------------------
-- Visibility (the alert decides; this just pokes it)
---------------------------------------------------------------------------
function ns:ApplyVisibility()
	if self.UI_UpdateVisibility then self:UI_UpdateVisibility() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local E = CreateFrame("Frame")
ns.engine = E
E:RegisterEvent("ADDON_LOADED")
E:RegisterEvent("PLAYER_LOGIN")
E:RegisterEvent("PLAYER_ENTERING_WORLD")
E:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
E:RegisterEvent("PLAYER_REGEN_DISABLED")
E:RegisterEvent("PLAYER_REGEN_ENABLED")
E:RegisterUnitEvent("UNIT_AURA", "player")
E:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

E:SetScript("OnEvent", Safe(function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		GebboBagTrackerDB = GebboBagTrackerDB or {}
		ApplyDefaults(GebboBagTrackerDB, DEFAULTS)
		ns.db = GebboBagTrackerDB
	elseif event == "PLAYER_LOGIN" then
		ns:RebuildIDs()
		ns:BuildUI()
		ns:BuildSettingsStub()
		if ns.EngineInit then ns:EngineInit() end
		ns:RegisterNativeSounds()
		ns:UpdateEquip()
		local v = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version")
		Print("v" .. tostring(v) .. " loaded. |cffffd27f/gbag test|r to preview, |cffffd27f/gbag|r for commands.")
	elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_EQUIPMENT_CHANGED" then
		ns:UpdateEquip()
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		if event == "PLAYER_REGEN_ENABLED" and ns.pendingNative then
			ns.pendingNative = nil
			ns:RegisterNativeSounds()
		end
		ns:ApplyVisibility()
	elseif event == "UNIT_AURA" then
		local now = GetTime()
		if ns.db and now - (ns.lastAuraPoll or 0) > 0.03 then
			ns.lastAuraPoll = now
			ns:Poll()
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		ns.castCount = (ns.castCount or 0) + 1
		local st = states.totem
		if st then st.casts = (st.casts or 0) + 1 end
	end
end))

local acc = 0
local SafePoll = Safe(function() ns:Poll() end)
E:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.1 or not ns.db then return end
	acc = 0
	SafePoll()
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Help()
	Print("/gbag test [salmon|scroll|totem|gralstone|seashell|voidfin]  - preview a pull (no name = random)")
	Print("/gbag unlock  - drag it, Ctrl+wheel or the corner grip to resize, then /gbag lock")
	Print("/gbag scale 1.3 | grow up|down | sound | flash | idle | engine auto|on|off | status | stats")
	Print("/gbag config  - settings window   /gbag ids | setid <pull> <id> | errors | reset")
end

SLASH_GEBBOBAG1, SLASH_GEBBOBAG2 = "/gbag", "/gebbo"
SlashCmdList.GEBBOBAG = function(msg)
	local cmd, a, b = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
	local db = ns.db
	if cmd == "test" then
		local key = ns:SimulateProc(ARTS[a] and a or nil)
		Print("preview: " .. ARTS[key].name)
	elseif cmd == "unlock" then
		ns:SetUnlocked(true)
		Print("Drag it where you want (Ctrl+wheel or the corner grip resizes), then /gbag lock")
	elseif cmd == "lock" then
		ns:SetUnlocked(false)
		Print("Locked.")
	elseif cmd == "scale" then
		local v = tonumber(a)
		if v and v >= 0.3 and v <= 3 then ns:SetScale(v) Print("Scale " .. v)
		else Print("Usage: /gbag scale 0.3-3") end
	elseif cmd == "sound" then
		db.sound = not db.sound
		ns:RegisterNativeSounds()
		Print("Sounds " .. (db.sound and "ON" or "OFF"))
	elseif cmd == "flash" then
		db.flash = not db.flash
		Print("Screen flash " .. (db.flash and "ON" or "OFF"))
	elseif cmd == "grow" then
		db.growUp = (a == "up")
		ns:ApplyPosition()
		if ns.EngineRebuild then ns.engineDirty = true end
		Print("Extra pulls stack " .. (db.growUp and "UPWARDS" or "DOWNWARDS"))
	elseif cmd == "idle" then
		db.showIdle = not db.showIdle
		ns:ApplyVisibility()
		Print("Show the bag between pulls: " .. (db.showIdle and "ON" or "OFF"))
	elseif cmd == "engine" then
		if a == "auto" or a == "on" or a == "off" then db.engine = a end
		Print("Engine display: " .. tostring(db.engine) .. " (auto = only where buffs are hidden: M+, raids, boss fights)")
		if ns.EngineStatus then Print(ns:EngineStatus()) end
	elseif cmd == "status" then
		Print("Bag equipped: " .. (ns.equipped and ("|cff00ff00yes|r, item level " .. tostring(ns.ilvl or "?")) or "|cffff4040no|r"))
		Print("Buffs hidden right now: " .. tostring(ns:AurasSecret()))
		if ns.EngineStatus then Print(ns:EngineStatus()) end
		if ns.engineLayout then Print("Raid/M+ stacking: " .. ns.engineLayout) end
		if ns.engineLive ~= nil then Print("Raid/M+ fading numbers: " .. (ns.engineLive and "|cff00ff00live|r" or "start value only (the game blocked the countdown)")) end
		local n = 0
		for _, art in pairs(ARTS) do if art.nativeHandle then n = n + 1 end end
		Print("Game-side pull sounds registered: " .. n .. " of 6")
	elseif cmd == "stats" then
		local S = ns.session
		Print(("%d pulls this session, buff uptime %d%%"):format(S.total,
			S.combatTime > 0 and floor(S.buffTime / S.combatTime * 100 + 0.5) or 0))
		for _, k in ipairs(keys) do Print(("  %s: %d"):format(ARTS[k].name, S.counts[k] or 0)) end
	elseif cmd == "ids" then
		for _, k in ipairs(keys) do
			local art = ARTS[k]
			Print(("|cffffd27f%s|r (%s): %s"):format(art.name, k,
				#art.idlist > 0 and table.concat(art.idlist, ", ") or "|cffff6060not found yet|r"))
		end
		local f, cal = ns:GetScaleFactor()
		Print(("item level %s, estimate factor %.3f (%s)"):format(tostring(ns.ilvl or "?"), f, cal and "calibrated" or "rough"))
	elseif cmd == "setid" and ARTS[a] and tonumber(b) then
		local list = db.manualIDs[a] or {}
		db.manualIDs[a] = list
		list[#list + 1] = tonumber(b)
		ns:RebuildIDs()
		ns:RegisterNativeSounds()
		if ns.EngineRebuild then ns:EngineRebuild() end
		Print(("added spell %s to %s"):format(b, ARTS[a].name))
	elseif cmd == "errors" then
		if #errLog == 0 then Print("No errors caught.") end
		for _, e in ipairs(errLog) do Print(e) end
	elseif cmd == "config" or cmd == "options" then
		ns:ToggleOptions()
	elseif cmd == "reset" then
		db.point, db.relPoint, db.x, db.y, db.scale = "CENTER", "CENTER", 0, -140, 1
		ns:ApplyPosition()
		Print("Reset.")
	else
		Help()
	end
end

function GebboBagTracker_OnAddonCompartmentClick()
	ns:ToggleOptions()
end
