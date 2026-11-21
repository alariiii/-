-- ============================================================================
-- BE A PIMP  -  Prostitute Manager
-- Open spots, build sex places with the OpenSex animations, hire women, men (and Dolls) as sex workers that dance at their spot,
-- let the clients come (mostly at night), and collect the money at the spot. A Pimp level (1-20) opens more workers and spots.
--
-- Requires: Cyber Engine Tweaks, Codeware, Appearance Menu Mod (+ the OpenSex pose pack installed in AMM), Audioware, Bag of Dicks.
-- The scene engine (workspots, positioning sliders, undress by appearance tags) comes from OpenSex Manager.
-- ============================================================================

local U        = require("Core/util.lua")
local Cron     = require("Core/cron.lua")
local Data     = require("Core/data.lua")
local Levels   = require("Core/levels.lua")
local Catalog  = require("Core/catalog.lua")
local Template = require("Core/template.lua")
local Ent      = require("Core/ent.lua")
local Looks    = require("Core/looks.lua")
local Bod      = require("Core/bod.lua")
local Pool     = require("Core/pool.lua")
local Roster   = require("Core/roster.lua")
local Pair     = require("Core/pairscene.lua")
local Audio    = require("Core/audio.lua")
local Editor   = require("Core/placeeditor.lua")
local Economy  = require("Core/economy.lua")
local Cars     = require("Core/cars.lua")
local World    = require("Core/world.lua")
local Mark     = require("Core/parkmark.lua")
local Hiring   = require("Core/hiring.lua")
local Rpg      = require("Core/rpg.lua")
local Inbox    = require("Core/inbox.lua")
local Book     = require("Core/book.lua")
local Trouble  = require("Core/trouble.lua")
local Guards   = require("Core/guards.lua")
local JoyRide  = require("Core/joyride.lua")
local Notify   = require("Core/notify.lua")
local Loc      = require("Core/loc.lua")
local UI       = require("UI/window.lua")
local K        = require("UI/common.lua")
local Hud      = require("UI/hud.lua")

local Pimp = {
    name = "Be a Pimp - Prostitute Manager",
    version = UI.version,
    ready = false,
}

local hadPlayer = false
local catalogTries, catalogT = 0, 0.0
local errT = {}

-- one failing part never stops the others
local function step(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local last = errT[name]
        if not last or (U.clock - last) > 10.0 then
            errT[name] = U.clock
            U.log(name .. ": " .. tostring(err))
        end
    end
end

local function playerPresent()
    local ok, p = pcall(function() return Game.GetPlayer() end)
    return ok and p ~= nil
end

-- the game session ended (main menu / loading a save): every entity is gone already - forget them without touching them
local function sessionEnded()
    step("session/editor", Editor.Shutdown)
    step("session/scenes", Pair.StopAll, true, "session")
    step("session/cars", Cars.Shutdown)
    step("session/joyride", JoyRide.Reset)
    step("session/world", World.ResetRuntime)
    step("session/book", Book.ResetRuntime)
    step("session/roster", Roster.Reset)
    step("session/parkmark", Mark.Reset)
    step("session/notify", Notify.Reset)
    step("session/looks", Looks.Reset)
    step("session/bod", Bod.Reset)
    step("session/template", Template.Clear)
    step("session/audio", Audio.Shutdown)
    Cron.Clear()
    step("session/save", Data.SaveNow)
    U.log("session ended - runtime cleared")
end

-- ----------------------------------------------------------------------------
-- events
-- ----------------------------------------------------------------------------
registerForEvent("onInit", function()
    -- the random numbers must differ in every session (without a seed the first picks are always the same)
    pcall(function() math.randomseed(os.time() + math.floor((os.clock() or 0) * 1000)) end)
    for _ = 1, 4 do math.random() end
    Data.Load()
    Loc.init()
    U.notifyOn = Data.s.notify ~= false
    U.toast = UI.Toast
    Inbox.SetNamer(Book.AnyName)
    step("trouble/expire", Trouble.ExpireOld)          -- questions that were open when the game closed cannot be answered any more
    step("pool", Pool.Load)
    step("catalog/meta", Catalog.LoadMeta)
    local ok, err = Catalog.Build()
    Pimp.ready = true

    print("----------------------------------------------------------------------------")
    print(Pimp.name .. " " .. Pimp.version)
    if ok then
        print("  " .. Loc.t("%d two-person AMM poses found", {count = Catalog.count}))
    else
        print("  " .. Loc.t("pose list not ready yet (%s) - it is retried while the game runs", {err = tostring(err)}))
    end
    print("  " .. Loc.t("%d spot(s), %d worker(s), Pimp level %d", {spots = #Data.d.spots, workers = #Data.d.hookers, level = Levels.Level()}))
    print("  " .. Loc.t("Open the CET overlay to see the menu. Bind the keys in CET > Bindings > Be a Pimp"))
    print("----------------------------------------------------------------------------")
end)

registerForEvent("onUpdate", function(delta)
    delta = tonumber(delta) or 0.016
    local dt = math.min(delta, 2.0)
    U.clock = U.clock + dt
    UI.Tick(delta)
    step("data", Data.Update, dt)
    step("cron", Cron.Update, dt)

    local has = playerPresent()
    if hadPlayer and not has then sessionEnded() end
    hadPlayer = has
    if not has then return end

    -- AMM may start after this mod: look for the pose list again for a while
    if not Catalog.ok and catalogTries < 12 then
        catalogT = catalogT + dt
        if catalogT >= 8.0 then
            catalogT = 0.0
            catalogTries = catalogTries + 1
            step("catalog", Catalog.Build)
        end
    end

    step("template", Template.Update, dt)
    step("looks/preview", Looks.PreviewTick)
    step("bod", Bod.Update, dt)
    step("rpg", Rpg.Update, dt)
    step("inbox", Inbox.Update, dt)
    step("world", World.Update, dt)
    step("parkmark", Mark.Update, dt)
    step("joyride", JoyRide.Update, dt)
    step("scenes", Pair.Update, dt)
    step("cars", Cars.Update, dt)
    step("audio", Audio.Update, dt, Pair.all)
    step("editor", Editor.Update, dt)
end)

registerForEvent("onShutdown", function()
    step("shutdown/editor", Editor.Shutdown)
    step("shutdown/preview", Looks.PreviewStop)
    step("shutdown/scenes", Pair.StopAll, true, "shutdown")
    step("shutdown/joyride", JoyRide.Shutdown)
    step("shutdown/world", World.Shutdown)
    step("shutdown/cars", Cars.Shutdown)
    step("shutdown/roster", Roster.Shutdown)
    step("shutdown/parkmark", Mark.Reset)
    step("shutdown/bod", Bod.RemoveAll)
    step("shutdown/audio", Audio.Shutdown)
    step("shutdown/save", Data.SaveNow)
    step("shutdown/settings", Data.SaveSettings)
end)

registerForEvent("onOverlayOpen", function() UI.open = true Hud.overlay = true end)
registerForEvent("onOverlayClose", function()
    UI.open = false
    Hud.overlay = false
    step("overlay/preview", Looks.PreviewStop)          -- the "view naked" preview ends: the clothes are put back
end)
registerForEvent("onDraw", function()
    step("ui", UI.Draw)                 -- the menu: only while the CET overlay is open
    step("hud", Hud.Draw)               -- the 3D name of the spot, the tags over the workers' heads, the pop-up: ALWAYS, overlay open or not
end)

-- ----------------------------------------------------------------------------
-- keys  (CET > Bindings)
-- ----------------------------------------------------------------------------
-- the spot the person under the crosshair stands in (else the one chosen in the window, else the nearest to V)
local function spotForPropose()
    local c = Hiring.Candidate()
    if c and c.ent then
        local x, y = Ent.Pos(c.ent)
        if x then
            local best, bestD
            for _, sp in ipairs(Data.d.spots) do
                local d = U.dist2(x, y, sp.x, sp.y)
                if d <= sp.radius and (not bestD or d < bestD) then best, bestD = sp, d end
            end
            if best then return best end
        end
    end
    local chosen = K.spot()
    if chosen then return chosen end
    local px, py = Ent.PlayerPos()
    local best, bestD
    if px then
        for _, sp in ipairs(Data.d.spots) do
            local d = U.dist2(px, py, sp.x, sp.y)
            if not bestD or d < bestD then best, bestD = sp, d end
        end
    end
    return best
end

registerHotkey("BeAPimp_Propose", Loc.t("Be a Pimp: Propose the job (to the woman or man I'm looking at)"), function()
    local okSpot, sp = pcall(spotForPropose)
    if not okSpot then sp = nil end
    if not sp then
        U.notify(Loc.t("Open a spot first (CET window > Spots)"), true)
        return
    end
    local ok, err = pcall(Hiring.Propose, sp.id)
    if not ok then U.log("propose: " .. tostring(err)) end
end)

registerHotkey("BeAPimp_Offer", Loc.t("Be a Pimp: Change the money offered when proposing the job (next amount)"), function()
    local steps = Levels.OFFER_STEPS
    local cur = Data.s.offer or 0
    local nxt = steps[1]
    for _, v in ipairs(steps) do
        if v > cur then nxt = v break end
    end
    Data.s.offer = nxt
    Data.SaveSettings()
    local chance = Levels.AcceptChanceWith("none", Levels.Level(), nxt) or 0
    U.notify(Loc.t("Offer: %s - an ordinary person says yes %d%% of the time (paid only if somebody accepts)", {money = U.fmtMoney(nxt), chance = math.floor(chance * 100 + 0.5)}), true)
end)

-- the client under the crosshair goes on / off the BLACK LIST
registerHotkey("BeAPimp_Blacklist", Loc.t("Be a Pimp: Put the client I'm looking at on the black list (press again to take him off)"), function()
    local ok, err = pcall(function()
        local ent = Ent.LookedAt()
        if not ent then U.notify(Loc.t("Aim at a client (his name is over his head)"), true) return end
        local prof = World.ProfileOfEntity(ent)
        if not prof then U.notify(Loc.t("That is not one of your clients"), true) return end
        Trouble.Toggle(prof)
    end)
    if not ok then U.log("blacklist: " .. tostring(err)) end
end)

-- the armed (or unarmed) NPC under the crosshair becomes the bodyguard of the spot
registerHotkey("BeAPimp_HireGuard", Loc.t("Be a Pimp: Hire the person I'm looking at as a guard (spot: the one chosen in the window / the one I'm in)"), function()
    local ok, err = pcall(function()
        local sp = K.spot()
        if not sp then
            local px, py = Ent.PlayerPos()
            local bestD
            if px then
                for _, s in ipairs(Data.d.spots) do
                    local d = U.dist2(px, py, s.x, s.y)
                    if d <= s.radius + 4.0 and (not bestD or d < bestD) then sp, bestD = s, d end
                end
            end
        end
        if not sp then U.notify(Loc.t("Stand in a spot (or choose it in the window) to hire a guard"), true) return end
        Guards.Hire(sp.id)
    end)
    if not ok then U.log("hire guard: " .. tostring(err)) end
end)

registerHotkey("BeAPimp_Collect", Loc.t("Be a Pimp: Collect the money (at the spot)"), function()
    local took, total, why = 0, 0, nil
    for _, sp in ipairs(Data.d.spots) do
        local can, reason = Economy.CanWithdraw(sp)
        if can then
            local ok, amount = Economy.Withdraw(sp)
            if ok then
                took = took + 1
                total = total + (amount or 0)
            end
        elseif not why and sp.pending > 0 then
            why = reason
        end
    end
    if took == 0 then U.notify(why or Loc.t("Nothing to collect here"), true) end
end)

registerHotkey("BeAPimp_ParkSet", Loc.t("Be a Pimp: Set the Client Sex Park here (while the green rectangle is shown)"), function()
    if not Mark.Active() then
        U.notify(Loc.t("No Client Sex Park is being placed: press CREATE in the Spots tab first"), true)
        return
    end
    local okCall, ok, why = pcall(Mark.Set)
    if not okCall then U.log("park set: " .. tostring(ok)) return end
    if not ok then U.notify(why or Loc.t("The Client Sex Park could not be saved"), true) end
end)

registerHotkey("BeAPimp_ParkCancel", Loc.t("Be a Pimp: Stop placing the Client Sex Park (nothing is changed)"), function()
    if Mark.Cancel() then U.notify(Loc.t("Client Sex Park: nothing was changed"), true) end
end)

registerHotkey("BeAPimp_CancelEditor", Loc.t("Be a Pimp: Stop editing the sex place (nothing is saved)"), function()
    if Editor.Active() then Editor.Cancel() end
end)

return Pimp
