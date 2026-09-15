--======================================================================
-- SecurityWatchdog.server.luau  --  farttofloatdinosaurrealm
--======================================================================
-- GENERATED alongside tools/BackdoorScan.studio.luau. Regenerate both together:
-- they share the MANIFEST, and a stale one here reports your own new scripts as
-- intruders every boot until you notice.
--
-- WHAT THIS CAN AND CANNOT DO -- READ THIS BEFORE TRUSTING IT
--
-- It CANNOT read code. `.Source` requires plugin security; a script running
-- inside a live game is forbidden from reading another script's source, and
-- there is no workaround. So every "does this code call require(assetId)"
-- question belongs to the Studio scanner, not here.
--
-- It also CANNOT reliably stop a backdoor that is already in the place. Scripts
-- start in no guaranteed order, so a hostile Script in Workspace may well have
-- already run by the time this executes. Setting Disabled = true afterwards does
-- not kill a thread that is running -- Disabled stops a script from STARTING.
--
-- So what is it for? Two things it genuinely does well:
--
--   1. A BOOT AUDIT. It lists every script in the live place and compares that
--      to the manifest. Anything unexpected gets printed loudly at every server
--      start, so an injected script cannot sit there quietly for weeks. This is
--      the same check as the Studio scanner's strongest rule, running where you
--      will actually see it -- in server logs, on the live game, after publish.
--
--   2. INJECTION AT RUNTIME. This is the part the Studio scan structurally
--      cannot cover. A require(assetId) backdoor's whole point is that its
--      payload arrives from the internet AFTER you last looked, and the usual
--      next move is to create new scripts, or a new RemoteEvent to take orders
--      through. Those appear after boot, and this sees them appear.
--
-- TREAT ITS OUTPUT AS AN ALARM, NOT A FIX. When it fires, go and clean the place
-- in Studio and republish. DESTROY_UNKNOWN below is a containment measure, not a
-- defence -- see the comment on it.
--======================================================================

-- Log only (false), or also remove what it finds (true).
--
-- Default is FALSE, deliberately. Destroying scripts on a live server based on a
-- name-and-location guess can break your own game if the manifest is stale or a
-- legitimate model ships a script -- and it destroys the evidence you would use
-- to work out what happened. Turn it on once the log has been quiet for a while
-- and you trust the manifest.
local DESTROY_UNKNOWN = false

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local SSS     = game:GetService("ServerScriptService")
local SP      = game:GetService("StarterPlayer")
local SG      = game:GetService("StarterGui")
local RF      = game:GetService("ReplicatedFirst")

local IGNORED_ROOTS = {
	"CoreGui", "CorePackages", "Chat", "TextChatService",
	"StarterPlayer.StarterCharacterScripts",
}

-- Reviewed and accepted. Same idea as the scanner's ALLOWLIST; keep them in step.
local ALLOWLIST = {
}

-- ============================ GENERATED MANIFEST ============================
-- 138 script instances, from farttofloatdinosaurrealm/default.project.json + src/ on disk.
local MANIFEST = {
	["ReplicatedStorage.DinosaurRealm.ChevronTrail"] = true,
	["ReplicatedStorage.DinosaurRealm.Config"] = true,
	["ReplicatedStorage.DinosaurRealm.Constants"] = true,
	["ReplicatedStorage.DinosaurRealm.CosmeticConfig"] = true,
	["ReplicatedStorage.DinosaurRealm.CosmeticIcon"] = true,
	["ReplicatedStorage.DinosaurRealm.CrateTokens"] = true,
	["ReplicatedStorage.DinosaurRealm.DevAccess"] = true,
	["ReplicatedStorage.DinosaurRealm.DinoCard"] = true,
	["ReplicatedStorage.DinosaurRealm.DoneCommand"] = true,
	["ReplicatedStorage.DinosaurRealm.FlightTuning"] = true,
	["ReplicatedStorage.DinosaurRealm.FoodMenu"] = true,
	["ReplicatedStorage.DinosaurRealm.GutSkins"] = true,
	["ReplicatedStorage.DinosaurRealm.HatchBurst"] = true,
	["ReplicatedStorage.DinosaurRealm.IslandOrder"] = true,
	["ReplicatedStorage.DinosaurRealm.JungleChrome"] = true,
	["ReplicatedStorage.DinosaurRealm.MeteorBreak"] = true,
	["ReplicatedStorage.DinosaurRealm.PetCollection"] = true,
	["ReplicatedStorage.DinosaurRealm.PetFace"] = true,
	["ReplicatedStorage.DinosaurRealm.PetRarity"] = true,
	["ReplicatedStorage.DinosaurRealm.PetSkins"] = true,
	["ReplicatedStorage.DinosaurRealm.PetTier"] = true,
	["ReplicatedStorage.DinosaurRealm.PetTraits"] = true,
	["ReplicatedStorage.DinosaurRealm.PhoneHUD"] = true,
	["ReplicatedStorage.DinosaurRealm.PickupFloor"] = true,
	["ReplicatedStorage.DinosaurRealm.Remotes"] = true,
	["ReplicatedStorage.DinosaurRealm.SkinCrates"] = true,
	["ReplicatedStorage.DinosaurRealm.StomachTiers"] = true,
	["ReplicatedStorage.DinosaurRealm.WarpEffect"] = true,
	["ServerScriptService.DinosaurRealmServer"] = true,
	["ServerScriptService.DinosaurRealmServer.AnchorIslands"] = true,
	["ServerScriptService.DinosaurRealmServer.ArrivalReceiver"] = true,
	["ServerScriptService.DinosaurRealmServer.Blizzard"] = true,
	["ServerScriptService.DinosaurRealmServer.Brachiosaurus"] = true,
	["ServerScriptService.DinosaurRealmServer.DailyRewards_Server"] = true,
	["ServerScriptService.DinosaurRealmServer.FoodPetTemplates"] = true,
	["ServerScriptService.DinosaurRealmServer.FoodStands"] = true,
	["ServerScriptService.DinosaurRealmServer.GasBubble"] = true,
	["ServerScriptService.DinosaurRealmServer.GoIsland"] = true,
	["ServerScriptService.DinosaurRealmServer.HideMarkers"] = true,
	["ServerScriptService.DinosaurRealmServer.IceMeteor"] = true,
	["ServerScriptService.DinosaurRealmServer.IcePhysics"] = true,
	["ServerScriptService.DinosaurRealmServer.IceVFX"] = true,
	["ServerScriptService.DinosaurRealmServer.Intro"] = true,
	["ServerScriptService.DinosaurRealmServer.Island1Anchor"] = true,
	["ServerScriptService.DinosaurRealmServer.IslandLayout"] = true,
	["ServerScriptService.DinosaurRealmServer.IslandSurfaceReport"] = true,
	["ServerScriptService.DinosaurRealmServer.IslandTeleport"] = true,
	["ServerScriptService.DinosaurRealmServer.MeteoriteExplosion"] = true,
	["ServerScriptService.DinosaurRealmServer.Monsoon"] = true,
	["ServerScriptService.DinosaurRealmServer.NestingNook_NPCs"] = true,
	["ServerScriptService.DinosaurRealmServer.NestingNook_Setup"] = true,
	["ServerScriptService.DinosaurRealmServer.PetUpgrades"] = true,
	["ServerScriptService.DinosaurRealmServer.PetXPHooks"] = true,
	["ServerScriptService.DinosaurRealmServer.PurchaseBanner"] = true,
	["ServerScriptService.DinosaurRealmServer.PurchaseReceipts"] = true,
	["ServerScriptService.DinosaurRealmServer.Rebirth"] = true,
	["ServerScriptService.DinosaurRealmServer.RedwoodRaptor"] = true,
	["ServerScriptService.DinosaurRealmServer.RemoveInvisibleWalls"] = true,
	["ServerScriptService.DinosaurRealmServer.ReturnIsland"] = true,
	["ServerScriptService.DinosaurRealmServer.SeasonPass"] = true,
	["ServerScriptService.DinosaurRealmServer.SecurityWatchdog"] = true,
	["ServerScriptService.DinosaurRealmServer.ServerEvents"] = true,
	["ServerScriptService.DinosaurRealmServer.Shark"] = true,
	["ServerScriptService.DinosaurRealmServer.Shop"] = true,
	["ServerScriptService.DinosaurRealmServer.SkinCrateBridge"] = true,
	["ServerScriptService.DinosaurRealmServer.SkinCrateService"] = true,
	["ServerScriptService.DinosaurRealmServer.SocialRewards"] = true,
	["ServerScriptService.DinosaurRealmServer.DailyCrateService"] = true,
	["ServerScriptService.DinosaurRealmServer.DailyStreak"] = true,
	["ServerScriptService.DinosaurRealmServer.UniverseBoosts"] = true,
	["ServerScriptService.DinosaurRealmServer.SessionRewards"] = true,
	["ServerScriptService.DinosaurRealmServer.RewardsHubCap"] = true,
	["ServerScriptService.DinosaurRealmServer.Gifting"] = true,
	["ServerScriptService.DinosaurRealmServer.BigEventScheduler"] = true,
	["ServerScriptService.DinosaurRealmServer.SpacePetTemplates"] = true,
	["ServerScriptService.DinosaurRealmServer.Spinosaurus"] = true,
	["ServerScriptService.DinosaurRealmServer.Stegosaurus"] = true,
	["ServerScriptService.DinosaurRealmServer.Therizinosaurus"] = true,
	["ServerScriptService.DinosaurRealmServer.Triceratops"] = true,
	["ServerScriptService.DinosaurRealmServer.Tyrannosaurus"] = true,
	["ServerScriptService.DinosaurRealmServer.Velociraptor"] = true,
	["ServerScriptService.DinosaurRealmServer.VolcanoFireballs"] = true,
	["ServerScriptService.DinosaurRealmServer.WeatherManager"] = true,
	["ServerScriptService.DinosaurRealmServer.Windstorm"] = true,
	["ServerScriptService.DinosaurRealmServer.WormholeService"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.AmbientWildlife"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.ArrivalCinematic"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.BalanceDebug"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Bootstrap"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.DailyStreak"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.GiftingClient"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.GroupBannerClient"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.MenuBackButton"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NotifyBridge"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NotifyCenter"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.BottomHUD"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Bubbles"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.CurrencyCapsule"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.DinoIslandArrow"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.FartTrail"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.FernThief"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.FishingQuest"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.GeyserQuest"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.GoIsland"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.GutGrowCinematic"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.IceAgeCommand"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.IceAgeUI"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Intro"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.IslandAmbience"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.IslandTeleport"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.JungleTheme"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.LandingImpact"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.LandingStabilizer"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.LivingFossil"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.MeteoriteExplosion"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.MonsoonCommand"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.MonsoonRain"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.MosquitoQuest"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Music"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NPCGuide"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NPCWaypointArrow"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NestingNookEggs"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NpcLife"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.PetCommand"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.PetDiff"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.PetFollow"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.PetHub"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.PetHubTabs"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.PetSkinLook"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Pterodactyls"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.PurchaseBanner"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.QuestGate"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.RaptorNestQuest"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Rebirth"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.RedwoodRaptor"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.RemotePets"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.ResponsiveUI"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.ReturnIsland"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.SeasonPass"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.ServerEvents"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Shop"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.ShopGlue"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.ShopKit"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.SkinCrateBridge"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.SkinCrateClient"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.SocialRewards"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.SpawnCamera"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.TestPetPreview"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.TopCenterStack"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.TriceratopsQuest"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.VolcanoFireballs"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Windstorm"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.WormholeClient"] = true,
}
-- ============================================================================

local function fullPath(inst)
	local parts, cur = {}, inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

local function underAny(path, list)
	for _, prefix in ipairs(list) do
		if path == prefix or path:sub(1, #prefix + 1) == prefix .. "." then return true end
	end
	return false
end

-- See the long note in the Studio scanner: non-ASCII in a script NAME is a
-- homoglyph disguise, and nothing legitimate here uses it.
local function nonAscii(s)
	for i = 1, #s do
		if s:byte(i) > 127 then return true end
	end
	return false
end

local alerts = 0
local function alert(kind, inst, note)
	alerts = alerts + 1
	local path = (typeof(inst) == "Instance") and fullPath(inst) or tostring(inst)
	warn(("[SECURITY] %s | %s | %s | %s"):format(kind, path,
		(typeof(inst) == "Instance") and inst.ClassName or "?", note or ""))
end

--======================================================================
-- 1. BOOT AUDIT
--======================================================================
local function auditScript(inst, when)
	local path = fullPath(inst)
	if underAny(path, IGNORED_ROOTS) or ALLOWLIST[path] then return end

	if nonAscii(inst.Name) then
		alert("HOMOGLYPH-NAME", inst, when .. " -- name is not ASCII, deliberate disguise")
	elseif not MANIFEST[path] then
		alert("NOT-IN-MANIFEST", inst, when .. " -- not produced by this realm's Rojo project")
	else
		return -- known good
	end

	if DESTROY_UNKNOWN then
		pcall(function() inst.Disabled = true end) -- stops it STARTING; does not kill a running thread
		pcall(function() inst:Destroy() end)
		warn("[SECURITY]   ^ destroyed (DESTROY_UNKNOWN is on)")
	end
end

do
	local n = 0
	for _, inst in ipairs(game:GetDescendants()) do
		if inst:IsA("LuaSourceContainer") then
			n = n + 1
			auditScript(inst, "at boot")
		end
	end
	print(("[SECURITY] farttofloatdinosaurrealm boot audit: %d scripts against a 138-entry manifest, %d alert(s)")
		:format(n, alerts))
	if alerts > 0 then
		warn("[SECURITY] Clean these in Studio with tools/BackdoorScan.studio.luau, then REPUBLISH.")
	end
end

--======================================================================
-- 2. RUNTIME INJECTION
--
-- The part the Studio scan cannot cover: a require(assetId) payload arrives from
-- the internet after you last looked, then creates scripts or opens a remote to
-- take orders through. Both show up as descendants appearing after boot.
--
-- Watched narrowly, on the containers that matter, rather than on game itself --
-- a global DescendantAdded fires for every part, effect and character limb the
-- game creates, which is thousands per minute and would bury the signal.
--======================================================================
local WATCH = {RS, SSS, SP, SG, RF, workspace}

-- Remotes legitimately created after boot by your own code are common, so the
-- first pass is a snapshot: anything present shortly after start is baseline,
-- and only LATER arrivals are reported.
local baselineRemotes = {}
task.delay(10, function()
	for _, svc in ipairs({RS, RF}) do
		for _, d in ipairs(svc:GetDescendants()) do
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") then
				baselineRemotes[d] = true
			end
		end
	end

	for _, svc in ipairs(WATCH) do
		svc.DescendantAdded:Connect(function(d)
			if d:IsA("LuaSourceContainer") then
				alert("SCRIPT-ADDED-AT-RUNTIME", d,
					"a script appeared after the server started -- nothing in this realm does that")
				if DESTROY_UNKNOWN then
					pcall(function() d.Disabled = true end)
					pcall(function() d:Destroy() end)
				end
			elseif (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and not baselineRemotes[d] then
				alert("REMOTE-ADDED-LATE", d,
					"a new remote appeared long after boot -- a common backdoor control channel")
			end
		end)
	end
	print("[SECURITY] runtime injection watch armed")
end)

--======================================================================
-- 3. WHAT IS NOT COVERED HERE, SAID OUT LOUD
--
-- * Exploiters on the CLIENT. Nothing above touches that. Client-side exploits
--   are stopped by the server not trusting client input, remote by remote --
--   a different job from backdoors, and not one a watchdog can do generically.
-- * A hostile edit INSIDE a manifested file. The path is on the list, so this
--   passes it. Your defence there is git: `git status` and `git diff` before you
--   publish will show it, and this file cannot.
-- * Plugins. A malicious Studio plugin edits the place at edit time, before any
--   of this runs. Install plugins as carefully as you install models.
--======================================================================
