--======================================================================
-- TopCenterStack.client.luau  (LocalScript)
--======================================================================
-- PORTED FROM THE FIRST REALM (src/client/TopCenterStack.client.luau). Same problem
-- here, same shape of fix.
--
-- SIX scripts park a banner at the top-centre of the screen and none of them knows the
-- others exist. Every one is anchored (0.5, 0) and rests at roughly the same Y:
--
--     MonsoonUI       (MonsoonRain)    the storm banner
--     WindstormUI     (Windstorm)      "WINDSTORM: 12s"
--     IceAgeEventUI   (IceAgeUI)       the Ice Age banner
--     PurchaseBanner  (PurchaseBanner) a real Robux purchase went through
--     ServerEventUI   (ServerEvents)   COIN RUSH / POWER SURGE / ...
--     IslandBanner    (Bootstrap)      the persistent objective card
--
-- The moment two fire together they draw straight through each other and you read
-- neither -- and they DO fire together, because a server event landing mid-storm is a
-- completely ordinary thing to happen. This stacks them instead: still top-centre, each
-- visible banner below the visible ones above it, in a fixed priority order, and the
-- stack compacts as banners come and go.
--
-- ===== HOW IT AVOIDS FIGHTING THEIR OWN ANIMATIONS =====
-- Several of these tween their own Position to slide in. If this script wrote Position
-- every frame it would be in a tug-of-war with those tweens and the result would jitter.
--
-- So it never touches the banners. Each is REPARENTED into a full-screen transparent
-- CONTAINER inside its own ScreenGui, and the CONTAINER is what moves. The banner keeps
-- animating inside its container exactly as its author wrote it; the container only
-- decides where "home" is. Every slide-in still works, untouched.
--
-- Stacking uses AbsoluteSize, never an authored height, so it stays correct under the
-- responsive HUD scaler -- a hard-coded 65px would leave a growing gap on a phone.
--
-- ===== TWO DIFFERENCES FROM THE FIRST REALM'S COPY =====
--   1. The child is named EXPLICITLY per GUI rather than "first Frame child". This
--      realm's banners are TextLabels, not Frames, and ServerEventUI also parents
--      full-screen screenFlash frames into the same ScreenGui -- "first child" would
--      sooner or later adopt a lightning flash instead of the banner.
--   2. MonsoonUI owns the top slot by request: when the weather turns, the storm is the
--      loudest thing happening and should not be the third row.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local TOP_MARGIN = 8   -- px from the top of the screen to the first banner
local GAP        = 8   -- px between stacked banners

-- Priority = stacking order, top to bottom. `child` is the banner INSIDE that ScreenGui;
-- nil means "first GuiObject that isn't our own container".
local ORDER = {
	-- NotifyHero (NotifyCenter.luau) is the first realm's top lane: rewards, gifts, crate pulls, purchases --
	-- the one transient card. Its root is named "Hero" and toggles Visible, so it stacks like the rest.
	{ gui = "NotifyHero",     child = "Hero"   },
	-- The island coming apart under your feet outranks the weather. Built only when the
	-- volcano finale fires, so it arrives via the ChildAdded hook below, not the boot sweep.
	{ gui = "GeyserEruptionWarning", child = "Banner" },
	{ gui = "MonsoonUI",      child = "Banner" },  -- the storm outranks everything
	{ gui = "WindstormUI",    child = "Banner" },
	{ gui = "IceAgeEventUI",  child = "Banner" },
	{ gui = "PurchaseBanner", child = nil      },  -- real money -- never swallowed
	{ gui = "ServerEventUI",  child = "Banner" },
	{ gui = "IslandBanner",   child = "Holder" },  -- the persistent objective card, last
}

local tracked = {}  -- [guiName] = { frame = <the banner>, box = <its container> }

local function findBanner(sg, childName)
	if childName then
		local c = sg:FindFirstChild(childName)
		if c and c:IsA("GuiObject") then return c end
		return nil   -- named but not there yet: wait rather than grab the wrong thing
	end
	for _, c in ipairs(sg:GetChildren()) do
		if c:IsA("GuiObject") and c.Name ~= "StackBox" then return c end
	end
	return nil
end

-- Wrap a banner in a container we own. The container is full-screen and transparent, so
-- the banner's own (0.5, 0) anchor still centres it and its own tween still runs inside.
local function adopt(entry)
	if tracked[entry.gui] then return end
	local sg = PlayerGui:FindFirstChild(entry.gui)
	if not (sg and sg:IsA("ScreenGui")) then return end

	local frame = findBanner(sg, entry.child)
	if not frame then return end

	local box = Instance.new("Frame")
	box.Name = "StackBox"
	box.Size = UDim2.new(1, 0, 1, 0)     -- full-screen, so the HUD scaler treats it as a
	box.Position = UDim2.new(0, 0, 0, 0) -- cover and recurses INTO it -- the banner keeps
	box.BackgroundTransparency = 1       -- its UIScale exactly as before
	box.ZIndex = frame.ZIndex
	box.Parent = sg
	frame.Parent = box

	tracked[entry.gui] = { frame = frame, box = box }
	print("[TopCenterStack] adopted " .. entry.gui)
end

-- These are built by different scripts at different times (and some only when their event
-- first fires), so keep looking rather than assuming they all exist at boot.
task.spawn(function()
	for _ = 1, 60 do
		for _, e in ipairs(ORDER) do adopt(e) end
		task.wait(0.5)
	end
end)
PlayerGui.ChildAdded:Connect(function(sg)
	task.defer(function()
		for _, e in ipairs(ORDER) do
			if sg.Name == e.gui then adopt(e) end
		end
	end)
end)

RunService.Heartbeat:Connect(function()
	local y = TOP_MARGIN
	for _, e in ipairs(ORDER) do
		local t = tracked[e.gui]
		-- FORGET A DESTROYED BANNER. Some of these are one-shots that Debris cleans up (the
		-- eruption warning lasts one fuse), and a stale entry here would block the lane from
		-- ever being re-adopted if the event fired a second time -- after a rebirth, say.
		if t and not t.frame.Parent then tracked[e.gui] = nil; t = nil end
		if t then
			if t.frame.Visible then
				-- Offset the CONTAINER by however much stack sits above it. The banner's
				-- own resting Y still applies inside the container, so this only ever ADDS
				-- clearance -- it can never pull a banner up into the one above it.
				t.box.Position = UDim2.new(0, 0, 0, y)
				local h = t.frame.AbsoluteSize.Y   -- LIVE height: includes the HUD scaler
				if h > 1 then y = y + h + GAP end
			else
				t.box.Position = UDim2.new(0, 0, 0, 0)  -- hidden: adds nothing to the stack
			end
		end
	end
end)

print("[TopCenterStack] ready -- top-centre banners stack instead of overlapping ("
	.. #ORDER .. " lanes, priority: MonsoonUI > WindstormUI > IceAgeEventUI > PurchaseBanner > ServerEventUI > IslandBanner)")
