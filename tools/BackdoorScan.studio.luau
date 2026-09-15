--[[
================================================================================
 BACKDOOR SCANNER  --  farttofloatdinosaurrealm  --  RUN IN STUDIO'S COMMAND BAR
================================================================================
 GENERATED. Regenerate after adding or removing scripts, or the manifest below
 goes stale and your own new files start showing up as intruders.

 HOW TO RUN
   1. Open the farttofloatdinosaurrealm place in Studio.
   2. View -> Command Bar.  (View -> Output too, that is where the report goes.)
   3. Open this file, select all, copy, paste into the command bar, Enter.

 Nothing is deleted. Set QUARANTINE = true and re-run to disable offenders and
 move them to ServerStorage.BACKDOOR_QUARANTINE, where you can read them before
 deciding. Each one is tagged with the path it came from so it can be put back.

 WHY THE COMMAND BAR AND NOT A SCRIPT INSIDE THE GAME
 Reading another script's code (.Source) requires PLUGIN security. The command
 bar has it; a Script running inside your running game does NOT -- at runtime a
 server script can see another script's name, class and location but is forbidden
 from reading a single character of its code. That is a Roblox restriction with
 no workaround. So the half that can actually read what a script DOES can only
 ever be an edit-time tool. The runtime half is SecurityWatchdog.server.luau,
 and it is deliberately limited to what it genuinely can see.

 WHAT THE MANIFEST IS, AND WHY IT IS THE STRONGEST RULE HERE
 This place is built by Rojo from farttofloatdinosaurrealm's src/. The MANIFEST below is the exact
 list of script instances that produces -- 162 of them. So any script in the
 place that is NOT in that list did not come from the repo. It came attached to a
 free model, a toolbox asset, or a plugin.

 That rule does not care what the code looks like, which is the point: pattern
 matching only catches hostile code that resembles hostile code you have already
 seen. The manifest catches a backdoor written this morning in a style nobody has
 catalogued, because it is not on the list. The pattern rules below are the second
 line of defence, for hostile code that landed INSIDE your folders.

 EXPECT SOME LEGITIMATE HITS THE FIRST TIME. Animation scripts inside imported
 models, leftovers from an old kit, things you added by hand in Studio. Review
 each one, then put the ones you trust in ALLOWLIST so the next scan is quiet.
 Resist the urge to allowlist in bulk -- a quiet scan you stopped reading is
 worth nothing.
================================================================================
]]

local QUARANTINE = false -- true = disable + move offenders instead of only reporting

-- Paths you have reviewed and accepted. Exact full paths, e.g.
--     ["Workspace.island3.Model.AnimateSpin"] = true,
local ALLOWLIST = {
}

-- Where Roblox itself puts scripts. Kept SHORT: every entry is a hole in the manifest rule.
local IGNORED_ROOTS = {
	"CoreGui", "CorePackages", "Chat", "TextChatService",
	"StarterPlayer.StarterCharacterScripts", -- Animate, Health: Roblox defaults
}

-- ============================ GENERATED MANIFEST ============================
-- 162 script instances, from farttofloatdinosaurrealm/default.project.json + src/ on disk.
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
	["ReplicatedStorage.DinosaurRealm.Gamepasses"] = true,
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
	["ServerScriptService.DinosaurRealmServer.BigEventScheduler"] = true,
	["ServerScriptService.DinosaurRealmServer.Blizzard"] = true,
	["ServerScriptService.DinosaurRealmServer.Brachiosaurus"] = true,
	["ServerScriptService.DinosaurRealmServer.DailyCrateService"] = true,
	["ServerScriptService.DinosaurRealmServer.DailyRewards_Server"] = true,
	["ServerScriptService.DinosaurRealmServer.DailyStreak"] = true,
	["ServerScriptService.DinosaurRealmServer.FirstSpawnAnchor"] = true,
	["ServerScriptService.DinosaurRealmServer.FoodPetTemplates"] = true,
	["ServerScriptService.DinosaurRealmServer.FoodStands"] = true,
	["ServerScriptService.DinosaurRealmServer.GasBubble"] = true,
	["ServerScriptService.DinosaurRealmServer.Gifting"] = true,
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
	["ServerScriptService.DinosaurRealmServer.RealmCompletion"] = true,
	["ServerScriptService.DinosaurRealmServer.Rebirth"] = true,
	["ServerScriptService.DinosaurRealmServer.RedwoodRaptor"] = true,
	["ServerScriptService.DinosaurRealmServer.RemoveInvisibleWalls"] = true,
	["ServerScriptService.DinosaurRealmServer.ReturnIsland"] = true,
	["ServerScriptService.DinosaurRealmServer.RewardsHubCap"] = true,
	["ServerScriptService.DinosaurRealmServer.SeasonPass"] = true,
	["ServerScriptService.DinosaurRealmServer.SecurityWatchdog"] = true,
	["ServerScriptService.DinosaurRealmServer.ServerEvents"] = true,
	["ServerScriptService.DinosaurRealmServer.SessionRewards"] = true,
	["ServerScriptService.DinosaurRealmServer.Shark"] = true,
	["ServerScriptService.DinosaurRealmServer.Shop"] = true,
	["ServerScriptService.DinosaurRealmServer.SkinCrateBridge"] = true,
	["ServerScriptService.DinosaurRealmServer.SkinCrateService"] = true,
	["ServerScriptService.DinosaurRealmServer.SocialRewards"] = true,
	["ServerScriptService.DinosaurRealmServer.SpacePetTemplates"] = true,
	["ServerScriptService.DinosaurRealmServer.SpawnProbe"] = true,
	["ServerScriptService.DinosaurRealmServer.Spinosaurus"] = true,
	["ServerScriptService.DinosaurRealmServer.Stegosaurus"] = true,
	["ServerScriptService.DinosaurRealmServer.TRexRoam"] = true,
	["ServerScriptService.DinosaurRealmServer.Therizinosaurus"] = true,
	["ServerScriptService.DinosaurRealmServer.Triceratops"] = true,
	["ServerScriptService.DinosaurRealmServer.Tyrannosaurus"] = true,
	["ServerScriptService.DinosaurRealmServer.UniverseBoosts"] = true,
	["ServerScriptService.DinosaurRealmServer.Velociraptor"] = true,
	["ServerScriptService.DinosaurRealmServer.VolcanoFireballs"] = true,
	["ServerScriptService.DinosaurRealmServer.WeatherManager"] = true,
	["ServerScriptService.DinosaurRealmServer.Windstorm"] = true,
	["ServerScriptService.DinosaurRealmServer.WormholeService"] = true,
	["ServerScriptService.RealmPipelineProbe"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.AmbientWildlife"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.ArrivalCinematic"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.BalanceDebug"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Bootstrap"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.BottomHUD"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Bubbles"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.CurrencyCapsule"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.DailyStreak"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.DinoIslandArrow"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.FartTrail"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.FernThief"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.FishingQuest"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.GeyserQuest"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.GiftingClient"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.GoIsland"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.GroupBannerClient"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.GutGrowCinematic"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Haptics"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.IceAgeCommand"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.IceAgeUI"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Intro"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.IslandAmbience"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.IslandTeleport"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.JungleTheme"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.LandingImpact"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.LandingStabilizer"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.LivingFossil"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.MenuBackButton"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.MeteoriteExplosion"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.MonsoonCommand"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.MonsoonRain"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.MosquitoQuest"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Music"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NPCGuide"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NPCWaypointArrow"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NestingNookEggs"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NotifyBridge"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.NotifyCenter"] = true,
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
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.SpawnCamera"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.TRexRoam"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.TestPetPreview"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.TitleTags"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.TopCenterStack"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.TriceratopsQuest"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.UiHaptics"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.VolcanoFireballs"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.Windstorm"] = true,
	["StarterPlayer.StarterPlayerScripts.DinosaurRealmClient.WormholeClient"] = true,
}
-- ============================================================================

--------------------------------------------------------------------------------
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

-- Any byte above 127 means the name is not plain ASCII, and that is the whole
-- homoglyph trick: Cyrillic "a" (U+0430) is pixel-identical to Latin "a" in the
-- Explorer, so a script called "Pockoge" spelled with Cyrillic letters reads as
-- "Package" to you and sorts next to the real thing, while being a completely
-- different string to Lua. Every legitimate script name in these projects is
-- ASCII, so there is no false positive to trade off against.
local function nonAscii(s)
	local bad = {}
	for i = 1, #s do
		local b = s:byte(i)
		if b > 127 then table.insert(bad, string.format("pos %d=0x%02X", i, b)) end
	end
	return (#bad > 0) and table.concat(bad, " ") or nil
end

--------------------------------------------------------------------------------
-- SOURCE RULES -- command bar only. Ordered by how damning.
--------------------------------------------------------------------------------
local RULES = {
	{ id = "require-asset-id", sev = "CRITICAL",
	  why = "Downloads and runs code from a Roblox asset you do not control. THE standard backdoor: its author can swap the payload at any time, after your review, without ever touching your place.",
	  test = function(s)
		local m = s:match("require%s*%(%s*%d%d%d%d+") or s:match("require%s*%(%s*tonumber")
			or s:match("require%s*%(%s*[%w_]+%s*%+%s*%d")
		return m and ("matched " .. m) or nil
	  end },
	{ id = "loadstring", sev = "CRITICAL",
	  why = "Compiles a string into runnable code. No legitimate use in these projects, and it is how a fetched payload gets executed.",
	  test = function(s) return s:find("loadstring") and "loadstring present" or nil end },
	{ id = "http-exfil", sev = "CRITICAL",
	  why = "Sends data out of the game or pulls code in. HttpService:JSONEncode is fine and is NOT flagged; DataStore:GetAsync is a different service and is NOT flagged.",
	  test = function(s)
		if not s:find("HttpService") then return nil end
		for _, c in ipairs({"GetAsync", "PostAsync", "RequestAsync"}) do
			if s:match("HttpService[^\n]-:%s*" .. c) then return "HttpService:" .. c end
		end
		return nil
	  end },
	{ id = "env-tampering", sev = "CRITICAL",
	  why = "getfenv/setfenv rewrite which globals a chunk sees -- used to hide behaviour from a reader and to defeat sandboxing. Not used anywhere in these codebases.",
	  test = function(s)
		local m = s:match("getfenv") or s:match("setfenv")
		return m and (m .. " present") or nil
	  end },
	{ id = "self-hiding", sev = "HIGH",
	  why = "A script that deletes or unparents itself on run is hiding from exactly this scan.",
	  test = function(s)
		local m = s:match("script%s*:%s*Destroy") or s:match("script%.Parent%s*=%s*nil")
		return m and "removes itself at runtime" or nil
	  end },
	{ id = "owner-targeting", sev = "HIGH",
	  why = "Code singling out one UserId is how a backdoor gives its author admin in your game while behaving normally for everyone else.",
	  test = function(s)
		local id = s:match("UserId%s*==%s*(%d%d%d+)")
		return id and ("hardcoded UserId " .. id) or nil
	  end },
	{ id = "base64-blob", sev = "HIGH",
	  why = "A long unbroken base64-ish literal is an encoded payload far more often than it is data.",
	  test = function(s)
		local b = s:match("[\"']([A-Za-z0-9+/=][A-Za-z0-9+/=][A-Za-z0-9+/=][A-Za-z0-9+/=]+)[\"']")
		return (b and #b >= 200) and ("encoded blob, " .. #b .. " chars") or nil
	  end },
	{ id = "escape-blob", sev = "HIGH",
	  why = "A long run of decimal \\ddd escapes smuggles a payload past a human reading the source. Threshold 40 is measured, not guessed: the worst legitimate file across all four realms is Bubbles.client.luau at 16 (emoji), so this leaves 2.5x headroom. Most emoji here use \\xNN hex, which is not counted at all.",
	  test = function(s)
		local n = 0
		for _ in s:gmatch("\\%d%d%d") do n = n + 1 end
		return (n >= 40) and (n .. " decimal escapes") or nil
	  end },
	{ id = "obfuscated-names", sev = "MEDIUM",
	  why = "Machine-mangled identifiers. Real code does not name things like this; obfuscators do.",
	  test = function(s)
		local n = 0
		for _ in s:gmatch("_0x%x%x%x+") do n = n + 1 end
		return (n >= 3) and (n .. " mangled identifiers") or nil
	  end },
}

--------------------------------------------------------------------------------
local findings, scanned = {}, 0
local function add(sev, rule, inst, path, detail, why)
	table.insert(findings, {sev = sev, rule = rule, inst = inst, path = path, detail = detail, why = why})
end

for _, inst in ipairs(game:GetDescendants()) do
	if inst:IsA("LuaSourceContainer") then
		local path = fullPath(inst)
		if not underAny(path, IGNORED_ROOTS) and not ALLOWLIST[path] then
			scanned = scanned + 1

			if not MANIFEST[path] then
				add("CRITICAL", "not-in-manifest", inst, path, inst.ClassName,
					"Not produced by this realm's Rojo project, so it is not from src/. It arrived with a model, a toolbox asset, or a plugin.")
			end

			local na = nonAscii(inst.Name)
			if na then
				add("CRITICAL", "homoglyph-name", inst, path, na,
					"Name contains non-ASCII characters that look like Latin letters in the Explorer. A deliberate disguise -- there is no innocent reason for it.")
			end

			local ok, src = pcall(function() return inst.Source end)
			if not ok or type(src) ~= "string" then
				add("HIGH", "source-unreadable", inst, path, tostring(src),
					"Could not read this script's code. From the command bar that should not happen -- treat it as hostile until explained.")
			else
				for _, r in ipairs(RULES) do
					local okr, d = pcall(r.test, src)
					if okr and d then add(r.sev, r.id, inst, path, d, r.why) end
				end
			end
		end
	end
end

local ORDER = {CRITICAL = 1, HIGH = 2, MEDIUM = 3}
table.sort(findings, function(a, b)
	if ORDER[a.sev] ~= ORDER[b.sev] then return ORDER[a.sev] < ORDER[b.sev] end
	return a.path < b.path
end)

print(("\n========== BACKDOOR SCAN -- farttofloatdinosaurrealm ==========\n%d scripts scanned against a 162-entry manifest, %d findings")
	:format(scanned, #findings))

if #findings == 0 then
	print("\nNo findings.\n\nWhat that does and does not mean: every script in the place is one this realm's\n"
		.. "Rojo project creates, and none matched a known-hostile pattern. Novel code doing\n"
		.. "something bad in a way no rule here describes, sitting inside a manifested file,\n"
		.. "would still pass. This narrows the risk; it does not prove the place is clean.")
else
	local byPath, order = {}, {}
	for _, f in ipairs(findings) do
		if not byPath[f.path] then byPath[f.path] = {}; table.insert(order, f.path) end
		table.insert(byPath[f.path], f)
	end
	for _, path in ipairs(order) do
		print(("\n[%s] %s"):format(byPath[path][1].sev, path))
		for _, g in ipairs(byPath[path]) do
			print(("    %-18s %s"):format(g.rule, g.detail))
			print(("      -> %s"):format(g.why))
		end
	end

	if QUARANTINE then
		local ss = game:GetService("ServerStorage")
		local folder = ss:FindFirstChild("BACKDOOR_QUARANTINE")
		if not folder then
			folder = Instance.new("Folder"); folder.Name = "BACKDOOR_QUARANTINE"; folder.Parent = ss
		end
		local moved = 0
		for _, path in ipairs(order) do
			local inst = byPath[path][1].inst
			if inst and inst.Parent then
				local tag = Instance.new("StringValue")
				tag.Name = "OriginalPath"; tag.Value = path; tag.Parent = inst
				pcall(function() inst.Disabled = true end) -- Script/LocalScript only; ModuleScript has no Disabled
				inst.Parent = folder
				moved = moved + 1
			end
		end
		print(("\nQUARANTINED %d script(s) -> ServerStorage.BACKDOOR_QUARANTINE"):format(moved))
		print("Each carries an OriginalPath value, so a false positive can be put back.")
	else
		print("\nNothing was changed. Set QUARANTINE = true at the top and re-run to disable and\n"
			.. "move these into ServerStorage.BACKDOOR_QUARANTINE for inspection.")
	end
end

print("\nAFTER CLEANING: save the place, then REPUBLISH. Deleting a backdoor in Studio does\n"
	.. "nothing to the version your players are on until you publish over it.\n"
	.. "================================================\n")
