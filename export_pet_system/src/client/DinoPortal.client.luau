--======================================================================
-- DinoPortal.client.luau  (LocalScript)   [SENDING PLACE]
--======================================================================
-- TEMPLATE -- the CLIENT half of the Dino Realm transition. Mirrors WorldClient's black-hole orb.
-- Its ONLY jobs are: (1) detect that the local player touched the portal, (2) fire INTENT to the
-- server, (3) render whatever status string the server sends back. It NEVER teleports anyone --
-- the server does that (see DinoRealmTeleport.server.lua).
--
-- FINDING THE PORTAL: this looks for a Part/Model named "DinoPortal" anywhere in Workspace, so you
-- can just build one in Studio and name it. If you'd rather build it in code, replace findPortal().
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--======================================================================
-- STATUS MESSAGES ARE BANNERS NOW -- the mid-screen box is deleted
--======================================================================
-- This used to be its own ScreenGui ("DinoRealmMsg") holding a 540x72 label at y 0.42 -- the middle of the
-- screen, which is where this game puts nothing else. It was shown by flipping `Visible` and hidden by an
-- UNGUARDED `task.delay`, with `traveling` doing double duty as both the touch debounce and part of the
-- hide condition. Two statuses arriving close together and the older timer hides the newer message; an
-- error between the show and the hide and the box stays up, because ResetOnSpawn = false means it outlives
-- the character that was standing on the portal.
--
-- All three of these are the same class of message as the wormhole's "land on an island first": a short
-- answer to something the player just tried to do. They belong in the hero lane with every other answer --
-- same card, same size, same place, same priority order -- not in a private box in the middle of the
-- screen with its own colours and its own fragile timer.
--
-- EVENT priority: a travel refusal must not shove an island landing off the screen, and it queues behind
-- the garden watering directions and any exclusive tutorial/achievement moment rather than talking over
-- them. NotifyCenter owns the hide, so there is no timer here left to strand anything.
local DINO_GREEN = Color3.fromRGB(90, 200, 90)

local function showMsg(t, seconds)
	local NC = _G.NotifyCenter
	if NC and NC.push then
		pcall(NC.push, {
			text     = t,
			color    = DINO_GREEN,
			priority = (NC.PRIORITY and NC.PRIORITY.EVENT) or 80,
			duration = seconds or 2.5,
		})
		return
	end
	warn("[DinoPortal] " .. t .. "  (NotifyCenter unavailable -- message not shown on screen)")
end

-- SWEEP THE OLD BOX. ResetOnSpawn = false meant one built by a previous session, or by a stale copy of this
-- script baked into the place, hangs around with nothing left to hide it.
task.spawn(function()
	for _ = 1, 5 do
		local old = playerGui:FindFirstChild("DinoRealmMsg")
		if old then
			old:Destroy()
			print("[DinoPortal] removed a leftover DinoRealmMsg box -- realm-travel status is a banner now")
		end
		task.wait(2)
	end
end)

-- ---- the remote ----
local enterEvent = ReplicatedStorage:WaitForChild("DinoRealmEnterEvent", 30)
if not enterEvent then
	warn("[DinoPortal] DinoRealmEnterEvent missing -- is DinoRealmTeleport.server.lua running?")
	return
end

local traveling = false -- local debounce (one touch -> one intent)

-- The SERVER decides what we show. We just render the string it hands us.
enterEvent.OnClientEvent:Connect(function(status)
	-- The banner hides itself, so the only thing these timers still do is release the touch debounce.
	-- That is the whole reason the old code was fragile: `traveling` was tangled up with hiding a box, so a
	-- missed hide and a stuck debounce were the same bug. They are separate concerns now.
	if status == "traveling" then
		showMsg("\xF0\x9F\xA6\x96 Traveling to the Dino Realm...", 5)
		-- FAILSAFE: if the teleport never lands (Studio, or a TeleportAsync error), let them try again.
		task.delay(5, function() traveling = false end)
	elseif status == "locked" then
		showMsg("\xF0\x9F\x94\x92 Dino Realm \xE2\x80\x94 Coming soon!")
		task.delay(2.5, function() traveling = false end)
	elseif status == "error" then
		showMsg("Couldn't travel right now, try again")
		task.delay(2.5, function() traveling = false end)
	end
end)

-- ---- wire the portal's touch ----
local function wire(part)
	part.CanTouch = true
	part.Touched:Connect(function(hit)
		if traveling then return end
		local char = player.Character
		if not (char and hit and hit:IsDescendantOf(char)) then return end -- ONLY the local player's own body
		traveling = true
		pcall(function() enterEvent:FireServer() end) -- INTENT ONLY. No arguments. The server gates + teleports.
	end)
end

local function findPortal()
	local p = Workspace:FindFirstChild("DinoPortal", true)
	if not p then return nil end
	if p:IsA("BasePart") then return { p } end
	if p:IsA("Model") then
		local parts = {}
		for _, d in ipairs(p:GetDescendants()) do
			if d:IsA("BasePart") then parts[#parts + 1] = d end
		end
		return parts
	end
	return nil
end

task.spawn(function()
	local parts, waited = findPortal(), 0
	while not parts and waited < 30 do -- the portal may stream/build in after us
		task.wait(0.5); waited = waited + 0.5; parts = findPortal()
	end
	if not parts then
		warn("[DinoPortal] no Part/Model named 'DinoPortal' found in Workspace -- nothing to touch")
		return
	end
	for _, p in ipairs(parts) do wire(p) end
	print("[DinoPortal] ready -- wired " .. #parts .. " part(s) of 'DinoPortal'")
end)
