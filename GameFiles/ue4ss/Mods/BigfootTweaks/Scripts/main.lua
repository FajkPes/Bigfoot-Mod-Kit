-- BigfootTweaks - live bridge between the Bigfoot Mod Manager app and the game.
--
-- Safety rules this file follows, in order:
--   1. every game call is wrapped in pcall - a bad value logs, it never crashes
--   2. every value is clamped to a sane range before it reaches the engine
--   3. gameplay values are only written when we hold authority (we are the host);
--      client-side keys (perf.*, view.*) are exempt because they change nothing
--      anyone else can see
--   4. no assets are touched, only live property values and existing functions
--
-- Performance rules (the mod must not be the reason the game stutters):
--   a. FindAllOf walks the whole UObject array, so lookups are cached for the
--      duration of one pass - and never beyond it, because a UObject reference
--      held between ticks pins the World and crashes the game on level teardown
--   b. the state file is only written when its contents actually change
--   c. the expensive readback runs on a slow beat, the config poll on a fast one
--
-- Files (next to Bigfoot-Win64-Shipping.exe, the Lua working directory):
--   BigfootTweaks_config.ini   written by the app, read here
--   BigfootTweaks_state.ini    written here, read by the app

local CONFIG = "BigfootTweaks_config.ini"
local STATE  = "BigfootTweaks_state.ini"

local POLL_MS        = 1000  -- config poll; reading a <4 KB file is cheap
local READBACK_EVERY = 4     -- ticks between full property readbacks

local ticks = 0              -- liveness counter; os.* may be sandboxed by UE4SS
local lastError = nil        -- surfaced to the app so failures are visible there

local function say(m) print("[BigfootTweaks] " .. m .. "\n") end

-- ---------------------------------------------------------------------------
-- results / reporting
-- ---------------------------------------------------------------------------
-- Declared up here on purpose: every helper below closes over these. A local
-- declared further down resolves to a nil global inside functions defined above
-- it - which is exactly the bug that silently broke the pickup multipliers.
local results = {}

local function note(key, ok, detail)
    results[#results + 1] = string.format("%s=%s%s", key, ok and "ok" or "fail",
        detail and (" ; " .. detail) or "")
end

-- A Blueprint call that did not throw is still not proof it had an effect, so
-- call results are labelled differently from a verified property write.
local function noteCall(key, ok)
    note(key, ok, "called, effect unverified")
end

-- ---------------------------------------------------------------------------
-- tiny ini reader / writer
-- ---------------------------------------------------------------------------
local function readIni(path)
    local f = io.open(path, "r")
    if not f then return nil, nil end
    local raw = f:read("*a"); f:close()
    local t = {}
    for line in raw:gmatch("[^\r\n]+") do
        if not line:match("^%s*[;#]") then
            local k, v = line:match("^%s*([%w%._]+)%s*=%s*(.-)%s*$")
            if k then t[k] = v end
        end
    end
    return t, raw
end

-- Only touches the disk when the text differs from what we last wrote. The app
-- polls on mtime, so rewriting an identical file every second is both a wasted
-- disk write and a wasted wake-up on the other side.
local lastStateText = nil

local function writeIniIfChanged(path, lines)
    local text = table.concat(lines, "\n") .. "\n"
    if text == lastStateText then return true end
    local f = io.open(path, "w")
    if not f then return false end
    f:write(text)
    f:close()
    lastStateText = text
    return true
end

local function num(t, key)
    local v = t[key]
    if v == nil then return nil end
    return tonumber(v)
end

local function clamp(v, lo, hi)
    if v == nil then return nil end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ---------------------------------------------------------------------------
-- engine helpers (cached)
-- ---------------------------------------------------------------------------
local function alive(o)
    if o == nil then return false end
    local ok, res = pcall(function() return o:IsValid() end)
    return ok and res
end

-- WITHIN ONE TICK ONLY. Holding a UObject here between ticks kept a pawn's
-- input component alive across a level teardown, which stopped the old World
-- from being garbage collected and crashed the game on "save and quit to lobby"
-- with "Fatal world leaks detected". Nothing in here may outlive a tick.
local cache = {}

local function invalidate()
    cache = {}
end

-- FindAllOf scans the entire UObject array, and a single pass touches a dozen
-- classes several times over (apply, readback, health split). Caching for the
-- duration of the pass removes that duplication without keeping any reference
-- once the tick is over.
local function allOf(className, fresh)
    if not fresh then
        local c = cache[className]
        if c then return c end
    end
    local out = {}
    local ok, insts = pcall(FindAllOf, className)
    if ok and insts then
        for _, o in ipairs(insts) do
            if alive(o) then out[#out + 1] = o end
        end
    end
    cache[className] = out
    return out
end

local function firstOf(className)
    return allOf(className)[1]
end

-- In multiplayer several copies of a component can exist (one per player).
-- Always prefer the one we hold authority over, or we would drive someone
-- else's copy and the change would silently do nothing.
local function firstAuth(className)
    local list = allOf(className)
    for _, o in ipairs(list) do
        local ok, res = pcall(function() return o:HasAuthority() end)
        if ok and res then return o end
    end
    return list[1]
end

-- HasAuthority is an AActor function; asking a component returns nothing, which
-- is why this reported "unknown" forever. The GameMode object only ever exists
-- on the server, so finding one is by itself proof that we are the host.
local function sessionAuthority()
    if firstOf("GM_World_C") then return true end
    for _, cls in ipairs({ "BP_AIBigfoot_Base_C", "BP_PlayerCharacter_C", "BP_Hunter_Base_C" }) do
        local o = firstOf(cls)
        if o then
            local ok, res = pcall(function() return o:HasAuthority() end)
            if ok and type(res) == "boolean" then return res end
        end
    end
    return nil
end

local function hasAuthority(o)
    if o == nil then return nil end
    local ok, res = pcall(function() return o:HasAuthority() end)
    if ok then return res end
    return nil
end

local function classNameOf(o)
    local n = ""
    pcall(function() n = o:GetClass():GetFName():ToString() end)
    return n
end

local function getProp(obj, name)
    if obj == nil then return nil end
    local ok, v = pcall(function() return obj[name] end)
    if ok then return v end
    return nil
end

-- Set a property, then read it back so we report what actually took.
local function setProp(obj, name, value)
    if obj == nil or value == nil then return false end
    local ok = pcall(function() obj[name] = value end)
    if not ok then return false end
    local back = getProp(obj, name)
    if type(back) == "number" and type(value) == "number" then
        return math.abs(back - value) < 0.01
    end
    return ok
end

-- Call a Blueprint function whose name may contain spaces.
local function callFn(obj, name, ...)
    if obj == nil then return false end
    local args = table.pack(...)
    local ok = pcall(function() obj[name](obj, table.unpack(args, 1, args.n)) end)
    return ok
end

-- The player character we actually control. Anything cosmetic (FOV, third
-- person, sensitivity) must go here and nowhere else, or in multiplayer we would
-- be reaching into someone else's camera.
local function localPlayer()
    for _, p in ipairs(allOf("BP_PlayerCharacter_C")) do
        local ok, res = pcall(function() return p:IsLocallyControlled() end)
        if ok and res then return p end
    end
    return nil
end

-- Console variables are per-machine. They never leave this client, so they are
-- allowed even when we are not the host.
--
-- Two routes, because every perf.* key reported "fail" with only the first one:
-- APlayerController::ConsoleCommand is not always reachable through the Lua
-- binding. The reason is returned so a failure says which step gave out instead
-- of just "fail".
local function console(cmd)
    local pc = firstOf("PC_World_C")
    if pc == nil then return false, "no player controller" end

    if pcall(function() pc:ConsoleCommand(cmd, false) end) then return true, "pc" end

    local lib = nil
    pcall(function()
        lib = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    end)
    if lib and pcall(function() lib:ExecuteConsoleCommand(pc, cmd, pc) end) then
        return true, "kismet"
    end
    return false, "both routes refused"
end

-- Bigfoot and hunters share HealthComponent_C, so split them by their owner.
local function healthComponents()
    local bf, hunters = {}, {}
    for _, hc in ipairs(allOf("HealthComponent_C")) do
        local owner = getProp(hc, "OwnerCharacter")
        local cname = owner and classNameOf(owner) or ""
        if cname:find("Bigfoot") then
            bf[#bf + 1] = hc
        elseif cname ~= "" then
            hunters[#hunters + 1] = hc
        end
    end
    return bf, hunters
end

-- ---------------------------------------------------------------------------
-- player roster
-- ---------------------------------------------------------------------------
-- A player is identified by name, not by list position: someone joining or
-- dying reorders the list, and an index would silently retarget a command at
-- whoever slid into that slot.
local function playerName(p, fallbackIndex)
    local ps = getProp(p, "PlayerState")
    if ps then
        local ok, n = pcall(function() return ps:GetPlayerName():ToString() end)
        if ok and type(n) == "string" and #n > 0 then return n end
        local pn = getProp(ps, "PlayerNamePrivate")
        if pn then
            local ok2, n2 = pcall(function() return pn:ToString() end)
            if ok2 and type(n2) == "string" and #n2 > 0 then return n2 end
        end
    end
    return "Player " .. fallbackIndex
end

local function boolCall(obj, fn)
    local ok, res = pcall(function() return obj[fn](obj) end)
    if ok and type(res) == "boolean" then return res end
    return nil
end

local function roster()
    -- Match health components to characters by identity. Comparing UObjects
    -- directly is not reliable here, but full names are unique per instance.
    local byOwner = {}
    for _, hc in ipairs(allOf("HealthComponent_C")) do
        local owner = getProp(hc, "OwnerCharacter")
        if owner then
            local ok, id = pcall(function() return owner:GetFullName() end)
            if ok and id then byOwner[id] = hc end
        end
    end

    local out = {}
    local used = {}
    for i, p in ipairs(allOf("BP_PlayerCharacter_C")) do
        local ok, id = pcall(function() return p:GetFullName() end)
        local hc = ok and byOwner[id] or nil
        local health = hc and getProp(hc, "Health") or nil
        local maxHp = hc and getProp(hc, "MaxHealth") or nil
        local isLocal = false
        local okl, res = pcall(function() return p:IsLocallyControlled() end)
        if okl and res then isLocal = true end

        local dead = hc and boolCall(hc, "GetIsDead")
        if dead == nil and type(health) == "number" then dead = health <= 0 end

        -- The creature is a player character too, and being AI-driven it has no
        -- PlayerState name - so it used to come out as "Player 1" and read like a
        -- second human. Its class is what tells the two apart.
        local isBigfoot = classNameOf(p):find("Bigfoot") ~= nil
        local name = playerName(p, i)
        if isBigfoot and name == "Player " .. i then name = "Bigfoot" end

        -- Names are the identity commands are addressed by, so a collision would
        -- silently retarget one entry at another.
        local base, n = name, 2
        while used[name] do
            name = base .. " " .. n
            n = n + 1
        end
        used[name] = true

        out[#out + 1] = {
            obj    = p,
            hc     = hc,
            name   = name,
            kind   = isBigfoot and "bigfoot" or "hunter",
            local_ = isLocal,
            health = type(health) == "number" and health or -1,
            max    = type(maxHp) == "number" and maxHp or -1,
            dead   = dead == true,
            down   = hc and boolCall(hc, "GetIsKnockedDown") == true or false,
        }
    end
    return out
end

local function findPlayer(name)
    for _, p in ipairs(roster()) do
        if p.name == name then return p end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- achievement diagnosis
-- ---------------------------------------------------------------------------
-- Nothing here unlocks anything. The point is to find out *where* the chain
-- breaks: whether the game ever asks for an achievement at all, and whether the
-- per-row "AchievementReleased" gate in its data table is open.
local ACH_TABLE = "/Game/Core/DataTables/AchievementStructDataTable.AchievementStructDataTable"
local achHooked = false
local achCalls = 0
local achLast = ""
local achNote = "not attempted"

local function hookAchievements()
    if achHooked or type(RegisterHook) ~= "function" then return end
    local targets = {
        "/Game/Core/MainClasses/World/PC_World.PC_World_C:SetAchievement",
        "/Game/Core/MainClasses/World/PC_World.PC_World_C:CheckAchievement",
        "/Game/Core/MainClasses/World/PC_World.PC_World_C:A_Achievement Rep",
    }
    local n = 0
    for _, t in ipairs(targets) do
        local short = t:match("([^:]+)$")
        local ok = pcall(RegisterHook, t, function(_, stat)
            achCalls = achCalls + 1
            local v = "?"
            pcall(function() v = tostring(stat:get()) end)
            achLast = short .. "(" .. v .. ")"
        end)
        if ok then n = n + 1 end
    end
    achHooked = n > 0
    say("achievement hooks registered: " .. n)
end

-- The row gate. UE4SS cannot walk a DataTable's TMap row storage from Lua, so
-- this reports what it could and could not reach rather than pretending.
local function inspectAchievementTable()
    local ok, dt = pcall(StaticFindObject, ACH_TABLE)
    if not ok or not alive(dt) then return "data table not loaded" end

    local lib = nil
    pcall(function()
        lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
    end)
    if not lib then return "table found, DataTableFunctionLibrary missing" end

    local got, names = pcall(function()
        local out = {}
        lib:GetDataTableRowNames(dt, out)
        return out
    end)
    if got and type(names) == "table" and #names > 0 then
        return string.format("table found, %d rows readable", #names)
    end
    return "table found, rows not reachable from Lua"
end

-- ---------------------------------------------------------------------------
-- pickup multipliers
-- ---------------------------------------------------------------------------
local pickupMult = {}
local cdoBase = {}   -- [class path] = the class default Number, captured once

-- "/Game/X/Pickup_Camera.Pickup_Camera_C" -> its class default object
local function pickupCDO(path)
    local cdoPath = path:gsub("%.([^%.]+)$", ".Default__%1")
    local ok, obj = pcall(StaticFindObject, cdoPath)
    if ok and alive(obj) then return obj end
    return nil
end

local P = "/Game/Actors/Pickups/"
local MEL = P .. "HunterMeleeWeapon/"
local BFP = P .. "BigfootPickups/"

local function one(name, dir)
    return { (dir or P) .. name .. "." .. name .. "_C" }
end

-- Every entry the app can address individually. Keys here must match the
-- pickup.<key>_mult keys in the app's catalog.
local PICKUP_CLASSES = {
    camera           = one("Pickup_Camera"),
    nightcam         = one("Pickup_NightCam"),
    photocamera      = one("Pickup_PhotoCamera"),
    drone            = one("Pickup_Drone"),
    tablet           = one("Pickup_Tablet"),
    gps              = one("Pickup_GPS_Sensor"),

    medicine         = one("Pickup_Medicine"),
    meat             = one("Pickup_Meat"),

    trap             = one("Pickup_Trap"),
    tnt              = one("Pickup_TNT"),
    totem            = one("Pickup_Totem"),

    flaregun         = one("Pickup_FlareGun"),
    flarebullet      = one("Pickup_FlareGunBullet"),
    signalflare      = one("Pickup_SignalFlare"),

    battery_drone    = one("Pickup_DroneBattery"),
    battery_nightcam = one("Pickup_NightCamBattery"),

    ammo_9           = one("Pickup_Ammo_9"),
    ammo_12          = one("Pickup_Ammo_12"),
    ammo_556         = one("Pickup_Ammo_5_56"),
    ammo_762         = one("Pickup_Ammo_7_62"),

    weapon           = { P .. "Pickup_Glock17.Pickup_Glock17_C",
                         P .. "Pickup_M4.Pickup_M4_C",
                         P .. "Pickup_AWM.Pickup_AWM_C",
                         P .. "Pickup_Remington700.Pickup_Remington700_C",
                         P .. "Pickup_Remington870.Pickup_Remington870_C" },

    melee            = { MEL .. "Pickup_AxeBig.Pickup_AxeBig_C",
                         MEL .. "Pickup_BaseballBat.Pickup_BaseballBat_C",
                         MEL .. "Pickup_Bayonet.Pickup_Bayonet_C",
                         MEL .. "Pickup_Cleaver.Pickup_Cleaver_C",
                         MEL .. "Pickup_Crowbar.Pickup_Crowbar_C",
                         MEL .. "Pickup_Pickaxe.Pickup_Pickaxe_C",
                         MEL .. "Pickup_PipeWrench.Pickup_PipeWrench_C" },

    bigfoot_item     = { BFP .. "Pickup_BirdHouse.Pickup_BirdHouse_C",
                         BFP .. "Pickup_Guitar.Pickup_Guitar_C",
                         BFP .. "Pickup_Shovel.Pickup_Shovel_C",
                         BFP .. "Pickup_Spear.Pickup_Spear_C" },
}

-- Multiplying the class default is what actually sticks: loot is generated when
-- the map loads, and a pickup's own BeginPlay would overwrite a value we set on
-- the instance afterwards. We still sweep live instances so a mid-session change
-- fixes anything not picked up yet.
local function applyPickups(cfg)
    local g = clamp(num(cfg, "pickup.global_mult"), 1, 20)
    local gm = g or 1

    for key, paths in pairs(PICKUP_CLASSES) do
        local own = clamp(num(cfg, "pickup." .. key .. "_mult"), 1, 20)
        -- The global multiplier alone is enough to act; a per-item value stacks
        -- on top of it, so "everything x2, medkits x3" gives medkits x6.
        if own ~= nil or g ~= nil then
            local m = clamp((own or 1) * gm, 1, 50)
            pickupMult[key] = m
            local cdoOk, touched = false, 0
            for _, path in ipairs(paths) do
                local cdo = pickupCDO(path)
                if cdo then
                    if cdoBase[path] == nil then
                        local base = getProp(cdo, "Number")
                        cdoBase[path] = (type(base) == "number" and base >= 1) and base or 1
                    end
                    if setProp(cdo, "Number", math.floor(cdoBase[path] * m)) then cdoOk = true end
                end
                local short = path:match("([^%.]+)$")
                for _, inst in ipairs(allOf(short, true)) do
                    if setProp(inst, "Number", math.floor((cdoBase[path] or 1) * m)) then
                        touched = touched + 1
                    end
                end
            end
            note("pickup." .. key, cdoOk, string.format("x%g, %d in world", m, touched))
        end
    end
end

local function watchPickups()
    if type(NotifyOnNewObject) ~= "function" then
        say("NotifyOnNewObject unavailable - pickup multipliers inactive")
        return
    end
    local n = 0
    for key, paths in pairs(PICKUP_CLASSES) do
        for _, path in ipairs(paths) do
            local ok = pcall(function()
                NotifyOnNewObject(path, function(obj)
                    local mult = pickupMult[key]
                    if not mult or mult <= 1 then return end
                    if hasAuthority(obj) == false then return end
                    local base = cdoBase[path]
                    if base == nil then
                        local v = getProp(obj, "Number")
                        base = (type(v) == "number" and v >= 1) and v or 1
                    end
                    setProp(obj, "Number", math.floor(base * mult))
                end)
            end)
            if ok then n = n + 1 end
        end
    end
    say("pickup watchers registered: " .. n)
end

-- ---------------------------------------------------------------------------
-- client-side console variables
-- ---------------------------------------------------------------------------
-- These only change what this machine renders. Nothing here is replicated and
-- nothing here is gameplay, so they run regardless of authority.
local PERF_CVARS = {
    ["perf.screen_percentage"] = { "r.ScreenPercentage %d",         25,  200,  "int" },
    ["perf.view_distance"]     = { "r.ViewDistanceScale %.2f",      0.2, 4,    "float" },
    ["perf.foliage_distance"]  = { "foliage.LODDistanceScale %.2f", 0.1, 4,    "float" },
    ["perf.shadow_quality"]    = { "sg.ShadowQuality %d",           0,   4,    "int" },
    ["perf.shadow_distance"]   = { "r.Shadow.DistanceScale %.2f",   0.1, 4,    "float" },
    ["perf.texture_quality"]   = { "sg.TextureQuality %d",          0,   4,    "int" },
    ["perf.effects_quality"]   = { "sg.EffectsQuality %d",          0,   4,    "int" },
    ["perf.postprocess"]       = { "sg.PostProcessQuality %d",      0,   4,    "int" },
    ["perf.foliage_quality"]   = { "sg.FoliageQuality %d",          0,   4,    "int" },
    ["perf.aa_quality"]        = { "sg.AntiAliasingQuality %d",     0,   4,    "int" },
    ["perf.volumetric_fog"]    = { "r.VolumetricFog %d",            0,   1,    "int" },
    ["perf.motion_blur"]       = { "r.MotionBlurQuality %d",        0,   4,    "int" },
    ["perf.dof"]               = { "r.DepthOfFieldQuality %d",      0,   4,    "int" },
    ["perf.ssr"]               = { "r.SSR.Quality %d",              0,   4,    "int" },
    ["perf.bloom"]             = { "r.BloomQuality %d",             0,   5,    "int" },
    ["perf.lens_flare"]        = { "r.LensFlareQuality %d",         0,   3,    "int" },
    ["perf.max_fps"]           = { "t.MaxFPS %d",                   0,   1000, "int" },
    ["perf.vsync"]             = { "r.VSync %d",                    0,   1,    "int" },
}

local function applyPerf(cfg)
    for key, spec in pairs(PERF_CVARS) do
        local v = clamp(num(cfg, key), spec[2], spec[3])
        if v ~= nil then
            local cmd = spec[4] == "int" and string.format(spec[1], math.floor(v))
                                          or string.format(spec[1], v)
            local ok, why = console(cmd)
            note(key, ok, cmd .. " ; " .. why)
        end
    end
end

-- ---------------------------------------------------------------------------
-- generic appliers
-- ---------------------------------------------------------------------------
local function applyMap(obj, cfg, map)
    for key, spec in pairs(map) do
        local v = clamp(num(cfg, key), spec[2], spec[3])
        if v ~= nil then note(key, setProp(obj, spec[1], v)) end
    end
end

-- Apply the same numeric map across a list of components.
local function applyMapAll(list, cfg, map)
    if #list == 0 then return false end
    for key, spec in pairs(map) do
        local v = clamp(num(cfg, key), spec[2], spec[3])
        if v ~= nil then
            local okAll = true
            for _, o in ipairs(list) do
                if not setProp(o, spec[1], v) then okAll = false end
            end
            note(key, okAll, "x" .. #list)
        end
    end
    return true
end

local function applyBoolAll(list, cfg, key, prop)
    local v = num(cfg, key)
    if v == nil or #list == 0 then return end
    local okAll = true
    for _, o in ipairs(list) do
        if not setProp(o, prop, v == 1) then okAll = false end
    end
    note(key, okAll, "x" .. #list)
end

-- MaxHealth and Health both have setter functions and OnRep_ handlers. Writing
-- the raw property changes the number on the server but skips the notify, so the
-- setter goes first and the property is only a fallback.
local function setHealthValue(hc, fn, prop, value)
    if callFn(hc, fn, value) then
        local back = getProp(hc, prop)
        if type(back) == "number" and math.abs(back - value) < 0.5 then return true end
    end
    return setProp(hc, prop, value)
end

-- ---------------------------------------------------------------------------
-- health
-- ---------------------------------------------------------------------------
local function applyHealth(list, cfg, prefix)
    local wanted = cfg[prefix .. ".max_health"] or cfg[prefix .. ".health_pct"]
                   or cfg[prefix .. ".gradual_heal"]
    if wanted == nil then return end
    if #list == 0 then
        note(prefix .. ".health", false, "no health component found")
        return
    end

    local maxHp = clamp(num(cfg, prefix .. ".max_health"), 1, 1000000)
    if maxHp then
        local okAll = true
        for _, hc in ipairs(list) do
            if not setHealthValue(hc, "SetMaxHealth", "MaxHealth", maxHp) then okAll = false end
        end
        note(prefix .. ".max_health", okAll, "x" .. #list)
    end

    -- Current HP as a percentage of max: an absolute number would be wrong the
    -- moment max health changes, and "put everyone back to full" is the case
    -- people actually want.
    local pct = clamp(num(cfg, prefix .. ".health_pct"), 0, 100)
    if pct and pct > 0 then
        local okAll = true
        for _, hc in ipairs(list) do
            local mx = getProp(hc, "MaxHealth")
            if type(mx) == "number" then
                if not setHealthValue(hc, "SetHealth", "Health", mx * pct / 100) then okAll = false end
            else
                okAll = false
            end
        end
        note(prefix .. ".health_pct", okAll, pct .. "% of max")
    end

    -- "Gradual Healing" is a BoolProperty gate, not a function. Setting only the
    -- per-tick amount left the gate closed, which is why self-healing never did
    -- anything in game.
    local heal = clamp(num(cfg, prefix .. ".gradual_heal"), 0, 10000)
    if heal then
        local okAll = true
        for _, hc in ipairs(list) do
            if not setProp(hc, "Gradual Heal", heal) then okAll = false end
            if not setProp(hc, "Gradual Healing", heal > 0) then okAll = false end
        end
        note(prefix .. ".gradual_heal", okAll,
             heal > 0 and ("on, " .. heal .. "/tick") or "off")
    end

    -- Lowering MaxHealth below the current Health leaves the actor in a state the
    -- game never produces on its own, so pull Health back down with it.
    for _, hc in ipairs(list) do
        local h, m = getProp(hc, "Health"), getProp(hc, "MaxHealth")
        if type(h) == "number" and type(m) == "number" and h > m then
            setHealthValue(hc, "SetHealth", "Health", m)
        end
    end
end

-- ---------------------------------------------------------------------------
-- one-shot actions
-- ---------------------------------------------------------------------------
local lastActionSeq = nil

-- Commands aimed at one named player. Every one of them reports the name it
-- resolved, so "nothing happened" can be told apart from "wrong person".
local function runPlayerCommand(name, who, val)
    local p = findPlayer(who or "")
    if p == nil then
        note("action." .. name, false, "player not found: " .. tostring(who))
        return
    end
    if p.hc == nil then
        note("action." .. name, false, p.name .. " has no health component")
        return
    end

    if name == "pcmd_hp" then
        local mx = getProp(p.hc, "MaxHealth")
        local pct = clamp(val or 100, 0, 100)
        if type(mx) ~= "number" then
            note("action.pcmd_hp", false, p.name .. ": max health unreadable")
            return
        end
        note("action.pcmd_hp", setHealthValue(p.hc, "SetHealth", "Health", mx * pct / 100),
             string.format("%s -> %d%%", p.name, pct))
    elseif name == "pcmd_maxhp" then
        local v = clamp(val or 100, 1, 1000000)
        note("action.pcmd_maxhp", setHealthValue(p.hc, "SetMaxHealth", "MaxHealth", v),
             string.format("%s -> %g", p.name, v))
    elseif name == "pcmd_heal" then
        local mx = getProp(p.hc, "MaxHealth")
        note("action.pcmd_heal",
             type(mx) == "number" and setHealthValue(p.hc, "SetHealth", "Health", mx),
             p.name)
    elseif name == "pcmd_revive" then
        -- SetCure is the game's own way out of the knocked-down state; topping
        -- health up afterwards is what makes it stick.
        local ok = callFn(p.hc, "SetCure")
        callFn(p.hc, "StopKnockDownDamage")
        local mx = getProp(p.hc, "MaxHealth")
        if type(mx) == "number" then setHealthValue(p.hc, "SetHealth", "Health", mx) end
        noteCall("action.pcmd_revive", ok)
    elseif name == "pcmd_fly" or name == "pcmd_ghost" or name == "pcmd_god" then
        -- Each player controller carries its own cheat component, so aiming at
        -- one person means finding the component whose outer is that person's
        -- controller. The shared one would only ever affect the host.
        local ctrl = getProp(p.obj, "Controller")
        local target = nil
        if ctrl then
            local wantOk, want = pcall(function() return ctrl:GetFullName() end)
            if wantOk then
                for _, c in ipairs(allOf("CheatManager_Component_C")) do
                    local ok2, outer = pcall(function() return c:GetOuter():GetFullName() end)
                    if ok2 and outer == want then target = c break end
                end
            end
        end
        if target == nil then
            note("action." .. name, false, p.name .. ": no cheat component on their controller")
            return
        end
        if name == "pcmd_fly" then
            noteCall("action.pcmd_fly", callFn(target, "FlyMode"))
        elseif name == "pcmd_ghost" then
            noteCall("action.pcmd_ghost", callFn(target, "Player Ghost", (val or 0) == 1))
        else
            noteCall("action.pcmd_god", callFn(target, "Player Damage Immunity", (val or 0) == 1))
        end
    elseif name == "pcmd_kill" then
        note("action.pcmd_kill", setHealthValue(p.hc, "SetHealth", "Health", 0), p.name)
    else
        note("action." .. name, false, "unknown player command")
    end
end

local function runAction(cfg)
    local seq = num(cfg, "action_seq")
    local name = cfg["action"]
    if seq == nil or name == nil or seq == lastActionSeq then return end
    lastActionSeq = seq

    if name:sub(1, 5) == "pcmd_" then
        runPlayerCommand(name, cfg["action_arg"], num(cfg, "action_val"))
        return
    end

    local cheat = firstAuth("CheatManager_Component_C")
    if name == "kill_bigfoot" then
        noteCall("action.kill_bigfoot", callFn(cheat, "S_Kill Bigfoot"))
    elseif name == "kill_hunters" then
        noteCall("action.kill_hunters", callFn(cheat, "S_Kill Hunters"))
    elseif name == "suicide" then
        noteCall("action.suicide", callFn(cheat, "Player Suicide"))
    elseif name == "heal_full" then
        local _, hunters = healthComponents()
        local okAll = #hunters > 0
        for _, hc in ipairs(hunters) do
            local mx = getProp(hc, "MaxHealth")
            if type(mx) ~= "number" or not setHealthValue(hc, "SetHealth", "Health", mx) then
                okAll = false
            end
        end
        note("action.heal_full", okAll, "x" .. #hunters)
    elseif name == "refresh" then
        invalidate()
        note("action.refresh", true, "lookup cache cleared")
    else
        note("action." .. tostring(name), false, "unknown action")
    end
end

-- ---------------------------------------------------------------------------
-- apply
-- ---------------------------------------------------------------------------
local function applyConfig(cfg)
    results = {}

    -- A fresh apply must see the world as it is now, not as it was cached.
    invalidate()

    -- Client-side first: these must work even as a guest, and they must not be
    -- lost to the authority gate below returning early.
    applyPerf(cfg)

    local lp = localPlayer()
    if lp then
        applyMap(lp, cfg, {
            ["view.fov"]         = { "DefaultCameraFOV",            50,   130 },
            ["view.sensitivity"] = { "Mouse Sensitivity",           0.05, 10 },
            ["view.aim_coef"]    = { "Aim Sensitivity Coefficient", 0.05, 10 },
        })
        -- DefaultCameraFOV is only consulted when the camera is set up, which is
        -- why writing it reported ok and changed nothing on screen. The live
        -- CameraComponent has to be told as well.
        local fov = clamp(num(cfg, "view.fov"), 50, 130)
        if fov then
            local cam = getProp(lp, "Camera")
            local applied = cam ~= nil and setProp(cam, "FieldOfView", fov)
            if not applied then applied = console(string.format("fov %d", math.floor(fov))) end
            note("view.fov_live", applied and true or false,
                 cam and "CameraComponent" or "no camera component")
        end

        local tpv = num(cfg, "view.third_person")
        if tpv ~= nil then note("view.third_person", setProp(lp, "TPV", tpv == 1)) end
        local head = num(cfg, "view.show_head")
        if head ~= nil then note("view.show_head", setProp(lp, "AlwaysShowHead", head == 1)) end
    end

    -- authority gate: refuse to write gameplay values as a client
    local auth = sessionAuthority()
    if auth == false then
        note("authority", false, "client - gameplay values not written")
        return auth
    end

    runAction(cfg)

    local vision  = firstOf("AIVisionComponent_C")
    local sound   = firstOf("AISoundDetectionComponent_C")
    local smell   = firstOf("SmellComponent_C")
    local timeMgr = firstAuth("TimeManagerComponent_C")
    local cheat   = firstAuth("CheatManager_Component_C")
    local bigfoot = firstOf("BP_AIBigfoot_Base_C")
    local loot    = firstOf("LootSpawnManager_C")
    local bfHp, hunterHp = healthComponents()

    -- ---- bigfoot senses ----
    if vision then
        applyMap(vision, cfg, {
            ["vision.day_radius"]      = { "VisionRadius (Day)",            0, 100000 },
            ["vision.night_radius"]    = { "VisionRadius (Night)",          0, 100000 },
            ["vision.half_angle"]      = { "VisionHalfAngle",               0, 180 },
            ["vision.lost_radius"]     = { "VisionLostRadius",              0, 100000 },
            ["vision.back_radius"]     = { "BackVisionRadius",              0, 100000 },
            ["vision.force_detect"]    = { "ForceDetectRadius",             0, 100000 },
            ["vision.forget_time"]     = { "LastSeenLocationForgetTime",    0, 600 },
            ["vision.detect_lag_min"]  = { "Detection Lag Min",             0, 60 },
            ["vision.detect_lag_max"]  = { "Detection Lag Max",             0, 60 },
            ["vision.crouch_lag_mult"] = { "Crouching Detection Lag Mult",  0, 100 },
            ["vision.flashlight_mult"] = { "FlashLight Detection Lag Mult", 0, 100 },
        })
    elseif cfg["vision.day_radius"] then
        note("vision", false, "no AIVisionComponent - not in a session")
    end

    if sound then
        applyMap(sound, cfg, {
            ["sound.reveal_radius"] = { "NearSoundCharacterRevealingRadius", 0, 100000 },
        })
    end

    if smell then
        applyMap(smell, cfg, {
            ["smell.probability"] = { "Probability",  0, 100 },
            ["smell.height"]      = { "Smell Height", 0, 100000 },
        })
        local sen = num(cfg, "smell.enabled")
        if sen ~= nil then note("smell.enabled", setProp(smell, "Is Enabled Default", sen == 1)) end
    end

    -- ---- how quickly bigfoot fixates on a target ----
    applyMapAll(allOf("BigfootAttentionComponent_C"), cfg, {
        ["attn.vision_weight"]    = { "VisionWeight",          0, 1000 },
        ["attn.light_weight"]     = { "LightWeight",           0, 1000 },
        ["attn.near_weight"]      = { "NearSenceWeight",       0, 1000 },
        ["attn.base_reduction"]   = { "BaseWeightReduction",   0, 1000 },
        ["attn.vision_reduction"] = { "VisionWeightReduction", 0, 1000 },
        ["attn.distance_coef"]    = { "DistanceCoefficient",   0, 1000 },
    })

    -- ---- bigfoot movement ----
    if bigfoot then
        applyMap(bigfoot, cfg, {
            ["ai.focus_distance"]    = { "Focus Distance",                0, 100000 },
            ["ai.teleport_distance"] = { "TeleportToTargetDistance",      0, 100000 },
            ["ai.rot_base"]          = { "BaseControlRotationSpeed",      0, 1000 },
            ["ai.rot_smooth"]        = { "SmoothControlRotationSpeed",    0, 1000 },
            ["ai.rot_aggressive"]    = { "AgressiveControlRotationSpeed", 0, 1000 },
            ["ai.strength_freq"]     = { "AddStrengthFrequency",          0, 10000 },
        })
    end

    -- ---- attack pacing (lives on the hunter, one entry per player) ----
    applyMapAll(allOf("BP_Hunter_Base_C"), cfg, {
        ["hunter.attack_min"]       = { "Attack Min Time (Real Minutes)", 0, 600 },
        ["hunter.attack_max"]       = { "Attack Max Time (Real Minutes)", 0, 600 },
        ["hunter.attack_min_night"] = { "Attack Min Time Night",          0, 600 },
        ["hunter.attack_cooldown"]  = { "AttackCooldownTime",             0, 600 },
        ["hunter.post_attack_time"] = { "PostAttackTime",                 0, 600 },
    })

    -- ---- durability ----
    applyHealth(bfHp, cfg, "bigfoot")
    if #bfHp > 0 then
        applyMapAll(bfHp, cfg, {
            ["bigfoot.knockdown_range"] = { "KnockDownHealthRange", 0, 100000 },
            ["bigfoot.night_resist"]    = { "NightDamageResist",    0, 100 },
            ["bigfoot.rage_resist"]     = { "RageDamageResist",     0, 100 },
        })
        applyBoolAll(bfHp, cfg, "bigfoot.use_night_resist", "UseNightDamageResist")
        applyBoolAll(bfHp, cfg, "bigfoot.use_rage_resist",  "UseRageDamageResist")
    end

    applyHealth(hunterHp, cfg, "hunter")
    if #hunterHp > 0 then
        applyMapAll(hunterHp, cfg, {
            ["hunter.fall_min"]        = { "FallDamageHeightMin",    0, 100000 },
            ["hunter.fall_max"]        = { "FallDamageHeightMax",    0, 100000 },
            ["hunter.knockdown_dmg"]   = { "RegularKnockDownDamage", 0, 100000 },
            ["hunter.recent_dmg_time"] = { "MaxRecentDamageTime",    0, 600 },
        })
        applyBoolAll(hunterHp, cfg, "hunter.can_knockdown", "CanBeKnockedDown")
        applyBoolAll(hunterHp, cfg, "hunter.fall_damage",   "CanGetFallDamage")
    end

    -- ---- stamina ----
    applyMapAll(allOf("MovementInputComponent_C"), cfg, {
        ["stamina.max"]        = { "StaminaMax",           1, 100000 },
        ["stamina.drain"]      = { "StaminaDecreasing",    0, 10000 },
        ["stamina.regen"]      = { "StaminaIncreasing",    0, 10000 },
        ["stamina.block"]      = { "StaminaBlockLimit",    0, 100000 },
        ["stamina.parkour"]    = { "Parkur Stamina Cost",  0, 100000 },
        ["stamina.water_mult"] = { "WaterMovementMult",    0, 20 },
        ["stamina.bash_mult"]  = { "SpeedBashMult",        0, 20 },
    })

    -- ---- swimming / sinking ----
    local playerChars = allOf("BP_PlayerCharacter_C")
    applyMapAll(playerChars, cfg, {
        ["player.swim_duration"] = { "MaxSwimmingDuration", 0, 10000 },
        ["player.sink_damage"]   = { "Sinking Damage",      0, 10000 },
    })

    -- Jump height and gravity are not Blueprint variables - they live on the
    -- native CharacterMovement component every ACharacter carries.
    local moveComps = {}
    for _, p in ipairs(playerChars) do
        local mc = getProp(p, "CharacterMovement")
        if mc then moveComps[#moveComps + 1] = mc end
    end
    applyMapAll(moveComps, cfg, {
        ["player.jump_z"]      = { "JumpZVelocity",  0, 100000 },
        ["player.gravity"]     = { "GravityScale",   0, 20 },
        ["player.air_control"] = { "AirControl",     0, 10 },
        ["player.walk_speed"]  = { "MaxWalkSpeed",   1, 100000 },
        ["player.crouch_speed"] = { "MaxWalkSpeedCrouched", 1, 100000 },
    })

    -- ---- day / night ----
    if timeMgr then
        applyMap(timeMgr, cfg, {
            ["time.day_length_min"]     = { "Day Length (Real Minutes)",     0.1,  100000 },
            ["time.day_duration_min"]   = { "Day Duration (Real Minutes)",   0.1,  100000 },
            ["time.night_duration_min"] = { "Night Duration (Real Minutes)", 0.1,  100000 },
            ["time.night_slowdown"]     = { "NightTimeSlowdown",             0.01, 1000 },
        })
        local paused = num(cfg, "time.paused")
        if paused ~= nil then
            -- the cheat manager version replicates; the raw property does not
            local ok = cheat and callFn(cheat, "World Pause Time", paused == 1)
            if not ok then ok = setProp(timeMgr, "Pause Time", paused == 1) end
            noteCall("time.paused", ok)
        end
    end

    -- The clock goes through the cheat manager so the change replicates.
    local hour = num(cfg, "time.set_hour")
    if hour and hour >= 0 then
        local h = math.floor(clamp(hour, 0, 23))
        local ok = false
        if cheat then ok = callFn(cheat, "World Set Time", h) end
        if not ok and timeMgr then ok = callFn(timeMgr, "SetTime_Cheat", h + 0.0) end
        noteCall("time.set_hour", ok)
    end

    local day = num(cfg, "time.set_day")
    if day and day >= 1 and cheat then
        noteCall("time.set_day", callFn(cheat, "WorldSetDay", math.floor(clamp(day, 1, 999))))
    end

    local dayLen = clamp(num(cfg, "time.day_length_min"), 0.1, 100000)
    if dayLen and cheat then
        noteCall("time.day_length_replicated", callFn(cheat, "World Set Day Duration", dayLen))
    end

    local speed = clamp(num(cfg, "time.speed"), 0.01, 100)
    if speed and cheat then
        noteCall("time.speed", callFn(cheat, "World Time Speed", speed))
    end

    -- ---- world toggles ----
    if cheat then
        local BOOL_CHEATS = {
            ["world.friendly_fire"] = "World Friendly Fire",
            ["world.bust_damage"]   = "World BustDamage",
            ["world.show_bigfoot"]  = "World Show Bigfoot",
            ["world.show_hunters"]  = "World Show Hunters",
            ["world.show_dead"]     = "World Show Dead",
            ["world.show_animals"]  = "World Show Animals",
            ["player.god"]          = "Player Damage Immunity",
            ["player.ghost"]        = "Player Ghost",
            ["view.hide_hud"]       = "Hide Hud",
        }
        for key, fn in pairs(BOOL_CHEATS) do
            local v = num(cfg, key)
            if v ~= nil then noteCall(key, callFn(cheat, fn, v == 1)) end
        end

        local weather = num(cfg, "world.weather")
        if weather and weather >= 0 then
            noteCall("world.weather", callFn(cheat, "World Set Weather", math.floor(weather)))
        end
        local psp = clamp(num(cfg, "player.speed"), 0, 5000)
        if psp and psp > 0 then
            noteCall("player.speed", callFn(cheat, "Player Speed", math.floor(psp)))
        end
    end

    -- ---- gear ----
    applyMapAll(allOf("Drone_C"), cfg, {
        ["drone.max_distance"] = { "Max Distance to Char",     0, 1000000 },
        ["drone.min_bigfoot"]  = { "Min Distance to Bigfoot",  0, 1000000 },
        ["drone.battery"]      = { "Battery_Rep",              0, 100 },
        ["drone.speed"]        = { "SpeedHUDScale",            0, 100 },
    })

    applyMapAll(allOf("Hand_NightCam_C"), cfg, {
        ["nightcam.drain"] = { "ChargeDecreasingPerSec", 0, 1000 },
    })

    -- Guns are instances of Gun_HandItem_C subclasses; the count in the result
    -- tells you how many actually got written, since only guns that exist right
    -- now can be touched.
    applyMapAll(allOf("Gun_HandItem_C"), cfg, {
        ["gun.fire_rate"]      = { "FireFrequency",        0.01, 100 },
        ["gun.reload_speed"]   = { "ReloadSpeed",          0.05, 20 },
        ["gun.mag_speed"]      = { "ChangeMagSpeed",       0.05, 20 },
        ["gun.shot_anim"]      = { "ShotAnimationSpeed",   0.05, 20 },
        ["gun.recoil"]         = { "FireRecoil",           0, 100 },
        ["gun.scatter"]        = { "Scatter",              0, 100 },
        ["gun.bullet_speed"]   = { "Bullet Speed (m/s)",   1, 10000 },
        ["gun.mag_size"]       = { "MaxAmmoNum",           1, 1000 },
    })

    -- The interact trace is a line from the camera. Its distance and radius are
    -- here because they are also the first thing to check when picking things up
    -- stops working.
    applyMapAll(allOf("InteractTraceComponent_C"), cfg, {
        ["interact.distance"] = { "InteractDistance",   1, 100000 },
        ["interact.radius"]   = { "InteractLineRadius", 0, 1000 },
        ["interact.hold_time"] = { "HoldTime",          0, 60 },
        ["interact.cooldown"]  = { "CoolDownTime",      0, 60 },
    })

    -- ---- GPS sensors and the minimap ----
    -- Lifetime is how long a placed sensor keeps working. Blocking bigfoot from
    -- smashing one is not reachable from Lua (destruction runs through a
    -- Blueprint event that cannot be cancelled), so a long lifetime is the
    -- closest thing on offer.
    local gpsLife = clamp(num(cfg, "gps.lifetime"), 1, 100000)
    if gpsLife then
        local cdo = pickupCDO(P .. "Pickup_GPS_Sensor.Pickup_GPS_Sensor_C")
        local okCdo = cdo ~= nil and setProp(cdo, "Lifetime", gpsLife)
        local live = 0
        for _, s in ipairs(allOf("Pickup_GPS_Sensor_C", true)) do
            if setProp(s, "Lifetime", gpsLife) then live = live + 1 end
        end
        note("gps.lifetime", okCdo, live .. " placed")
    end

    -- Permanent bigfoot marker: his minimap component normally stays hidden from
    -- humans until a sensor tags him. Flipping that shows the dot regardless.
    local mapBf = num(cfg, "map.show_bigfoot")
    if mapBf ~= nil then
        local hits = 0
        for _, m in ipairs(allOf("MinimapCharacterManager_C")) do
            local owner = nil
            pcall(function() owner = m:GetOuter() end)
            if owner and classNameOf(owner):find("Bigfoot") then
                callFn(m, "SetVisibleForHumans", mapBf == 1)
                if setProp(m, "IsVisibleForHumans", mapBf == 1) then hits = hits + 1 end
            end
        end
        note("map.show_bigfoot", hits > 0, hits .. " marker(s)")
    end

    -- ---- fixes ----
    local achFix = num(cfg, "fix.achievements")
    if achFix ~= nil then
        if achFix == 1 then
            hookAchievements()
            achNote = inspectAchievementTable()
            note("fix.achievements", achHooked, achNote)
        else
            achNote = "off"
            note("fix.achievements", true, "off")
        end
    end

    -- ---- loot ----
    if loot then
        applyMap(loot, cfg, {
            ["loot.totems"] = { "TotemsSpawnCount", 0, 1000 },
        })
    end

    local okp, errp = pcall(applyPickups, cfg)
    if not okp then note("pickup", false, tostring(errp)) end

    return auth
end

-- ---------------------------------------------------------------------------
-- state report back to the app
-- ---------------------------------------------------------------------------
local READBACK = {
    { "AIVisionComponent_C", {
        ["vision.day_radius"]      = "VisionRadius (Day)",
        ["vision.night_radius"]    = "VisionRadius (Night)",
        ["vision.half_angle"]      = "VisionHalfAngle",
        ["vision.lost_radius"]     = "VisionLostRadius",
        ["vision.back_radius"]     = "BackVisionRadius",
        ["vision.force_detect"]    = "ForceDetectRadius",
        ["vision.forget_time"]     = "LastSeenLocationForgetTime",
        ["vision.detect_lag_min"]  = "Detection Lag Min",
        ["vision.detect_lag_max"]  = "Detection Lag Max",
        ["vision.crouch_lag_mult"] = "Crouching Detection Lag Mult",
        ["vision.flashlight_mult"] = "FlashLight Detection Lag Mult",
    }},
    { "AISoundDetectionComponent_C", {
        ["sound.reveal_radius"] = "NearSoundCharacterRevealingRadius",
    }},
    { "SmellComponent_C", {
        ["smell.probability"] = "Probability",
        ["smell.height"]      = "Smell Height",
    }},
    { "BigfootAttentionComponent_C", {
        ["attn.vision_weight"]    = "VisionWeight",
        ["attn.light_weight"]     = "LightWeight",
        ["attn.near_weight"]      = "NearSenceWeight",
        ["attn.base_reduction"]   = "BaseWeightReduction",
        ["attn.vision_reduction"] = "VisionWeightReduction",
        ["attn.distance_coef"]    = "DistanceCoefficient",
    }},
    { "TimeManagerComponent_C", {
        ["time.day_length_min"]     = "Day Length (Real Minutes)",
        ["time.day_duration_min"]   = "Day Duration (Real Minutes)",
        ["time.night_duration_min"] = "Night Duration (Real Minutes)",
        ["time.night_slowdown"]     = "NightTimeSlowdown",
        ["time.world_minutes"]      = "World Time (Minutes)",
    }},
    { "BP_AIBigfoot_Base_C", {
        ["ai.focus_distance"]    = "Focus Distance",
        ["ai.teleport_distance"] = "TeleportToTargetDistance",
        ["ai.rot_base"]          = "BaseControlRotationSpeed",
        ["ai.rot_smooth"]        = "SmoothControlRotationSpeed",
        ["ai.rot_aggressive"]    = "AgressiveControlRotationSpeed",
        ["ai.strength_freq"]     = "AddStrengthFrequency",
    }},
    { "BP_Hunter_Base_C", {
        ["hunter.attack_min"]       = "Attack Min Time (Real Minutes)",
        ["hunter.attack_max"]       = "Attack Max Time (Real Minutes)",
        ["hunter.attack_min_night"] = "Attack Min Time Night",
        ["hunter.attack_cooldown"]  = "AttackCooldownTime",
        ["hunter.post_attack_time"] = "PostAttackTime",
    }},
    { "MovementInputComponent_C", {
        ["stamina.max"]        = "StaminaMax",
        ["stamina.drain"]      = "StaminaDecreasing",
        ["stamina.regen"]      = "StaminaIncreasing",
        ["stamina.block"]      = "StaminaBlockLimit",
        ["stamina.parkour"]    = "Parkur Stamina Cost",
        ["stamina.water_mult"] = "WaterMovementMult",
        ["stamina.bash_mult"]  = "SpeedBashMult",
    }},
    { "BP_PlayerCharacter_C", {
        ["view.fov"]             = "DefaultCameraFOV",
        ["view.sensitivity"]     = "Mouse Sensitivity",
        ["view.aim_coef"]        = "Aim Sensitivity Coefficient",
        ["player.swim_duration"] = "MaxSwimmingDuration",
        ["player.sink_damage"]   = "Sinking Damage",
    }},
    { "Gun_HandItem_C", {
        ["gun.fire_rate"]    = "FireFrequency",
        ["gun.reload_speed"] = "ReloadSpeed",
        ["gun.mag_speed"]    = "ChangeMagSpeed",
        ["gun.shot_anim"]    = "ShotAnimationSpeed",
        ["gun.recoil"]       = "FireRecoil",
        ["gun.scatter"]      = "Scatter",
        ["gun.bullet_speed"] = "Bullet Speed (m/s)",
        ["gun.mag_size"]     = "MaxAmmoNum",
    }},
    { "Drone_C", {
        ["drone.max_distance"] = "Max Distance to Char",
        ["drone.min_bigfoot"]  = "Min Distance to Bigfoot",
        ["drone.battery"]      = "Battery_Rep",
        ["drone.speed"]        = "SpeedHUDScale",
    }},
    { "Hand_NightCam_C", {
        ["nightcam.drain"] = "ChargeDecreasingPerSec",
    }},
    { "InteractTraceComponent_C", {
        ["interact.distance"]  = "InteractDistance",
        ["interact.radius"]    = "InteractLineRadius",
        ["interact.hold_time"] = "HoldTime",
        ["interact.cooldown"]  = "CoolDownTime",
    }},
    { "LootSpawnManager_C", {
        ["loot.totems"] = "TotemsSpawnCount",
    }},
}

local HEALTH_READBACK = {
    { prefix = "bigfoot", props = {
        ["bigfoot.max_health"]      = "MaxHealth",
        ["bigfoot.knockdown_range"] = "KnockDownHealthRange",
        ["bigfoot.night_resist"]    = "NightDamageResist",
        ["bigfoot.rage_resist"]     = "RageDamageResist",
        ["bigfoot.gradual_heal"]    = "Gradual Heal",
    }},
    { prefix = "hunter", props = {
        ["hunter.max_health"]      = "MaxHealth",
        ["hunter.gradual_heal"]    = "Gradual Heal",
        ["hunter.fall_min"]        = "FallDamageHeightMin",
        ["hunter.fall_max"]        = "FallDamageHeightMax",
        ["hunter.knockdown_dmg"]   = "RegularKnockDownDamage",
        ["hunter.recent_dmg_time"] = "MaxRecentDamageTime",
    }},
}

-- A stamp that only moves every HEARTBEAT_TICKS is what keeps the app able to
-- tell "running" from "closed" without forcing a disk write every second: the
-- file text is otherwise identical while nothing changes, so nothing is written.
local HEARTBEAT_TICKS = 10

local function heartbeat()
    return math.floor(ticks / HEARTBEAT_TICKS)
end

-- Everything after the header block, kept so a light tick can reuse it instead
-- of walking every class again.
local cachedBody = nil

local function buildState(auth, full)
    if not full and cachedBody then
        local lines = { "; written by the BigfootTweaks mod - do not edit by hand" }
        lines[#lines + 1] = "meta.in_session=" .. (firstOf("BP_AIBigfoot_Base_C") and "1" or "0")
        lines[#lines + 1] = "meta.authority=" ..
            (auth == nil and "unknown" or (auth and "host" or "client"))
        lines[#lines + 1] = "meta.stamp=" .. tostring(heartbeat())
        for _, l in ipairs(cachedBody) do lines[#lines + 1] = l end
        return lines
    end

    local body = {}
    if lastError then
        -- %s covers newlines as well, so the message stays on one ini line
        local msg = tostring(lastError):gsub("%s+", " ")
        body[#body + 1] = "meta.error=" .. msg
    end

    for _, entry in ipairs(READBACK) do
        local obj = firstOf(entry[1])
        if obj then
            for key, prop in pairs(entry[2]) do
                local v = getProp(obj, prop)
                if type(v) == "number" then
                    body[#body + 1] = string.format("%s=%.4f", key, v)
                end
            end
        end
    end

    -- CharacterMovement is reached through the pawn, so it cannot go in the
    -- class-keyed table above.
    local lp0 = allOf("BP_PlayerCharacter_C")[1]
    local mc0 = lp0 and getProp(lp0, "CharacterMovement") or nil
    if mc0 then
        for key, prop in pairs({
            ["player.jump_z"]       = "JumpZVelocity",
            ["player.gravity"]      = "GravityScale",
            ["player.air_control"]  = "AirControl",
            ["player.walk_speed"]   = "MaxWalkSpeed",
            ["player.crouch_speed"] = "MaxWalkSpeedCrouched",
        }) do
            local v = getProp(mc0, prop)
            if type(v) == "number" then
                body[#body + 1] = string.format("%s=%.4f", key, v)
            end
        end
    end

    local bfHp, hunterHp = healthComponents()
    local lists = { bigfoot = bfHp[1], hunter = hunterHp[1] }
    for _, entry in ipairs(HEALTH_READBACK) do
        local obj = lists[entry.prefix]
        if obj then
            for key, prop in pairs(entry.props) do
                local v = getProp(obj, prop)
                if type(v) == "number" then
                    body[#body + 1] = string.format("%s=%.4f", key, v)
                end
            end
        end
    end

    -- Live roster. The app rebuilds its Players tab whenever these lines change,
    -- so names carry the identity and the index is only a line number.
    local people = roster()
    body[#body + 1] = "roster.count=" .. #people
    for i, p in ipairs(people) do
        local k = "roster." .. (i - 1) .. "."
        body[#body + 1] = k .. "name=" .. p.name
        body[#body + 1] = k .. "kind=" .. p.kind
        body[#body + 1] = k .. "local=" .. (p.local_ and "1" or "0")
        body[#body + 1] = string.format("%shealth=%.1f", k, p.health)
        body[#body + 1] = string.format("%smax=%.1f", k, p.max)
        body[#body + 1] = k .. "dead=" .. (p.dead and "1" or "0")
        body[#body + 1] = k .. "down=" .. (p.down and "1" or "0")
    end

    body[#body + 1] = "fix.ach_state=" .. achNote
    body[#body + 1] = "fix.ach_calls=" .. achCalls
    if achLast ~= "" then body[#body + 1] = "fix.ach_last=" .. achLast end

    for _, r in ipairs(results) do body[#body + 1] = "result." .. r end
    cachedBody = body

    local lines = { "; written by the BigfootTweaks mod - do not edit by hand" }
    lines[#lines + 1] = "meta.in_session=" .. (firstOf("BP_AIBigfoot_Base_C") and "1" or "0")
    lines[#lines + 1] = "meta.authority=" ..
        (auth == nil and "unknown" or (auth and "host" or "client"))
    lines[#lines + 1] = "meta.stamp=" .. tostring(heartbeat())
    for _, l in ipairs(body) do lines[#lines + 1] = l end
    return lines
end

-- ---------------------------------------------------------------------------
-- poll loop
-- ---------------------------------------------------------------------------
local lastRaw = nil
local lastAuth = nil

local function tick()
    ticks = ticks + 1
    invalidate()
    local ok, err = pcall(function()
        local cfg, raw = readIni(CONFIG)
        local applied = false
        if cfg and raw ~= lastRaw then
            lastRaw = raw
            if cfg.apply == "1" then
                lastAuth = applyConfig(cfg)
                applied = true
                say("config applied (" .. #results .. " entries)")
            end
        end
        -- A full readback right after an apply, otherwise on the slow beat.
        local full = applied or cachedBody == nil or (ticks % READBACK_EVERY == 0)
        writeIniIfChanged(STATE, buildState(lastAuth, full))
    end)
    -- Always, including after a failure: a reference left here would outlive the
    -- tick and can pin the whole World past a level teardown.
    invalidate()
    if ok then
        lastError = nil
    else
        lastError = err
        say("tick error: " .. tostring(err))
    end
    if type(ExecuteWithDelay) == "function" then ExecuteWithDelay(POLL_MS, tick) end
end

watchPickups()

if type(ExecuteWithDelay) == "function" then
    ExecuteWithDelay(5000, tick)
    say("bridge active - polling " .. CONFIG .. " every " .. POLL_MS .. " ms")
else
    say("ExecuteWithDelay unavailable - bridge inactive, F6 still applies once")
end

RegisterKeyBind(Key.F6, function()
    pcall(function()
        local cfg = readIni(CONFIG)
        if cfg then
            lastAuth = applyConfig(cfg)
            writeIniIfChanged(STATE, buildState(lastAuth, true))
            say("manual apply")
        end
    end)
end)

say("loaded")

-- Created by FajkPes with assistance from ChatGPT Codex and Claude Code.
