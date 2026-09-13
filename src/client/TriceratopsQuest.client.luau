--======================================================================
-- TriceratopsQuest.client.luau  (LocalScript)
--======================================================================
-- Island 2 "Fern Frontier" grant for the Triceratops pet. Mirrors EXACTLY how
-- island3's BurritoDig grants the Raptor: a hatchable EGG with an [E] prompt ->
-- on hatch it spawns the follower, adds the Pet Hub card, and fires the server
-- grant (TriceratopsHatched) so it's equippable like the others.
-- Also exposes _G.GrantTriceratops(cf) + a /trike chat command.
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RS        = game:GetService("ReplicatedStorage")
local TS        = game:GetService("TweenService")
local HatchBurst   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("HatchBurst"))   -- shared cool hatch FX
local ChevronTrail = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("ChevronTrail")) -- shared ground chevron guide
local player    = Players.LocalPlayer

local st = { owns = false, hatching = false }

local function floatText(pos, text)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,240,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=22; lbl.TextColor3=Color3.fromRGB(230,236,196); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	TS:Create(lbl, TweenInfo.new(1.4), {TextTransparency=1}):Play()
	task.delay(1.6, function() a:Destroy() end)
end

-- the GRANT (identical path to BurritoDig -> Raptor)
--
-- ===== FERN FRONTIER HATCHES A STEGOSAURUS NOW, NOT A TRICERATOPS =====
-- The Triceratops moved down to Nesting Nook, where the mother standing over the nest is a
-- Triceratops -- see QuestGate. This end of the swap is just as good a fit: Fern Frontier is
-- fern country, and the Stego is the game's other big plant-eater, so the herbivore is still
-- being earned on the island covered in the thing it eats.
--
-- THE FILE AND THE REMOTES KEEP THEIR OLD NAMES ON PURPOSE. Renaming this script, the
-- _G.GrantTriceratops hook and the marker it reads would touch the PetCommand /trike alias,
-- the island2 quest attribute and the egg placement, all to rename a thing that works. The
-- egg itself is generic, so only the species granted at the end of it changed.
local function grant(cf)
	if st.owns then return end
	st.owns = true
	if _G.SpawnStegoFollower then pcall(function() _G.SpawnStegoFollower(cf) end) end
	if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet("StegoPet", { petId="StegoPet", displayName="Stegosaurus", level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
	do local th = RS:FindFirstChild("StegoHatched"); if th then pcall(function() th:FireServer() end) end end
	print("[Trike] Stegosaurus granted on Fern Frontier (follower + Pet Hub card + server grant)")
end
_G.GrantTriceratops = grant

-- /trike chat command -> grant it in front of you (dev shortcut)
player.Chatted:Connect(function(msg)
	local m = string.gsub(string.lower(msg), "%s", "")
	if m == "/trike" or m == "/triceratops" then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = hrp and (hrp.CFrame * CFrame.new(0,0,-6)) or CFrame.new(0,8,0)
		grant(at); floatText((hrp and hrp.Position or Vector3.zero)+Vector3.new(0,4,0), "Triceratops unlocked! \xF0\x9F\xA6\x95")
	end
end)

-- ===== island2 "Fern Frontier" EGG + Hatch prompt (the assigned grant) =====
--
-- ===== THE EGG IS RETIRED -- ISLAND2'S GRANT IS THE FERN THIEF NOW =====
-- FernThief.client.luau replaced it: you trap the fern-stealing BABY STEGO around the
-- island and BEFRIEND it, and the caught thief becomes the pet. That script fires the
-- exact same grant this egg used (_G.GrantTriceratops above), so the follower, the Pet
-- Hub card and the server StegoHatched event are identical -- only the doorway changed.
-- EVERYTHING ABOVE THIS LINE STAYS LIVE: grant(), /trike and _G.GrantTriceratops are
-- what FernThief (and the dev shortcut) call. Flip EGG_QUEST_ACTIVE back to true to
-- restore the egg (and remove FernThief, or the island grants the same pet twice).
local EGG_QUEST_ACTIVE = false

task.spawn(function()
	if not EGG_QUEST_ACTIVE then
		print("[Trike] island2 egg retired -- the Fern Thief quest (FernThief.client.luau) grants the Stego now")
		return
	end
	local isl = Workspace:FindFirstChild("island2") or Workspace:WaitForChild("island2", 60)
	if not isl then warn("[Trike] island2 not found -> no egg placed (use /trike or _G.GrantTriceratops)"); return end

	-- QUEST GATE -- CURRENTLY OFF. Set REQUIRE_QUEST = true to put it back. That is the
	-- whole switch; nothing else needs touching.
	--
	-- WHEN ON: the egg stays hidden until the FrillRancher gives the quest (talking sets
	-- Island2QuestAccepted, the same handshake every island NPC uses). It exists because the
	-- egg otherwise sits there from join onward next to an NPC still saying "come talk to
	-- me", which reads as a leftover mystery egg.
	--
	-- WHY IT IS OFF: to check the EggPlacement marker without running the quest first. The
	-- FrillRancher is untouched -- he still stands on island2 and still sets the attribute
	-- when talked to; the egg just no longer waits for him before placing itself.
	--
	-- The prints below stay useful either way: this block used to wait SILENTLY, so an egg
	-- that was merely locked looked exactly like an egg that was broken -- no [Trike] line
	-- appeared at all, and the obvious reading was that placement had failed.
	local REQUIRE_QUEST = false
	if REQUIRE_QUEST and player:GetAttribute("Island2QuestAccepted") ~= true then
		print("[Trike] island2: egg is quest-gated -- waiting for Island2QuestAccepted (talk to the FrillRancher)")
		player:GetAttributeChangedSignal("Island2QuestAccepted"):Wait()
		print("[Trike] island2: quest accepted -> placing the egg")
	end
	if not REQUIRE_QUEST then
		print("[Trike] island2: quest gate OFF -- placing the egg immediately (REQUIRE_QUEST = false)")
	end

	-- StreamingEnabled: island2's Model replicates at join, its PARTS do not. This
	-- script used to raycast immediately: with no parts streamed the ray hit nothing
	-- and the fallback pinned the egg to the (partial) bounding-box top -- the
	-- floating egg. Wait for real geometry first (same guard MosquitoQuest uses).
	local function islandHasStreamedIn()
		local ok, _, size = pcall(function() return isl:GetBoundingBox() end)
		return ok and size ~= nil and size.Magnitude > 1
	end
	if not islandHasStreamedIn() then
		print("[Trike] island2 has not streamed in yet -- waiting before placing the egg...")
		while not islandHasStreamedIn() do task.wait(1) end
	end

	local bcf, bsize = isl:GetBoundingBox()
	local center = nil

	-- A HAND-PLACED "EggPlacement" PART WINS. Everything below this is the script GUESSING
	-- where an egg looks right, and a guess is what put it somewhere odd to begin with. Drop
	-- a part named EggPlacement anywhere on island2 and the egg goes exactly there.
	--
	-- Same marker name island1's Lost Eggs already use (see NestingNook_Setup), so this is
	-- the established way to pin an egg by hand rather than a second convention.
	--
	-- MATCHED THE SAME LOOSE WAY NestingNook_Setup MATCHES ITS OWN MARKERS: the name must
	-- merely contain "egg" and "plac". An exact-prefix test was used here first and missed
	-- a part actually named "egg placement" -- the space broke it -- which is precisely the
	-- kind of near-miss a hand-typed marker name produces. Both spellings now work, and both
	-- scripts agree on what a marker is called.
	do
		local marker
		for _, d in ipairs(isl:GetDescendants()) do
			local n = d.Name:lower()
			if d:IsA("BasePart") and n:find("egg", 1, true) and n:find("plac", 1, true) then
				marker = d; break
			end
		end
		if marker then
			-- sit the egg ON the marker's top face. The shell is 4 studs tall and centred on
			-- `center`, so +2 puts its bottom exactly on that surface -- the same offset the
			-- raycast path uses against the ground it hits.
			center = marker.Position + Vector3.new(0, marker.Size.Y * 0.5 + 2.0, 0)
			-- GHOST THE MARKER: it is a position anchor, not scenery. Left visible it is a
			-- block sitting under the egg; left query-able it can swallow the Hatch prompt's
			-- ray. Exactly the treatment the 'Dig' and 'putdino' markers get.
			marker.Transparency = 1; marker.CanCollide = false; marker.CanQuery = false
			print(("[Trike] island2: egg pinned to marker '%s' at (%.0f, %.0f, %.0f)")
				:format(marker.Name, center.X, center.Y, center.Z))
		end
	end

	-- FALLBACK, only when no marker exists. Include-filter the raycast to the ISLAND's own
	-- geometry so it can't land on a pet, an NPC or another player, and try a small ring of
	-- spots -- the bbox centre of an island can be over a hole or open air.
	if not center then
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = { isl }
		local topY = bcf.Position.Y + bsize.Y/2
		for _, off in ipairs({ Vector3.zero, Vector3.new(14,0,0), Vector3.new(-14,0,0), Vector3.new(0,0,14), Vector3.new(0,0,-14), Vector3.new(20,0,20) }) do
			local from = Vector3.new(bcf.Position.X + off.X, topY + 60, bcf.Position.Z + off.Z)
			local hit = Workspace:Raycast(from, Vector3.new(0, -(bsize.Y + 120), 0), rp)
			if hit then center = hit.Position + Vector3.new(0, 2.0, 0); break end
		end
		if not center then
			warn("[Trike] island2: no ground found under any probe -> egg at bbox top (check the island's collision)")
			center = Vector3.new(bcf.Position.X, topY + 2.0, bcf.Position.Z)
		end
		print("[Trike] island2: no 'EggPlacement' part found -> egg positioned by ground probe")
	end

	-- cute egg (cream shell + a few earthy spots)
	local egg = Instance.new("Model"); egg.Name = "TriceratopsEgg"
	local function part(name, sh, sz, col, cf)
		local p = Instance.new("Part"); p.Name=name; p.Shape=sh; p.Size=sz; p.Color=col; p.Material=Enum.Material.SmoothPlastic
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CastShadow=false; p.CFrame=cf; p.Parent=egg; return p
	end
	local shell = part("Shell", Enum.PartType.Ball, Vector3.new(3.0,4.0,3.0), Color3.fromRGB(232,224,190), CFrame.new(center))
	egg.PrimaryPart = shell
	for _, sp in ipairs({ {0.9,0.6,0.7}, {-0.7,-0.4,0.8}, {0.4,-0.9,-0.6}, {-0.5,0.9,-0.4} }) do
		part("Spot", Enum.PartType.Ball, Vector3.new(0.7,0.7,0.7), Color3.fromRGB(150,160,110), CFrame.new(center + Vector3.new(sp[1],sp[2],sp[3])))
	end
	egg.Parent = Workspace

	-- Same green chevron runway island1 / island11 use -> leads the player to the egg.
	-- ChevronTrail.start (not .guideToEgg) on purpose: .guideToEgg also puts a bottom-edge
	-- hint banner on screen, and this island wants the ARROWS ONLY -- no text.
	ChevronTrail.start(
		function() return center end,
		function() return st.owns end -- hatched -> the trail clears itself
	)

	-- NO HIGHLIGHT. There used to be a Highlight adorned to the egg (pale fill + outline),
	-- which is what read as a glowing outline through the scenery. Removed by request -- the
	-- egg is a physical prop sitting on its marker, and the chevron trail below is already
	-- the thing that tells players where it is.
	-- gentle bob
	task.spawn(function() local t = 0 while egg.Parent and not st.owns do t += 0.05; pcall(function() egg:PivotTo(CFrame.new(center + Vector3.new(0, math.sin(t*2)*0.25, 0)) * CFrame.Angles(0, math.sin(t)*0.12, 0)) end); task.wait(0.05) end end)

	local pp = Instance.new("ProximityPrompt"); pp.ActionText = "Hatch"; pp.ObjectText = "Triceratops Egg"
	pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0.4; pp.MaxActivationDistance = 12; pp.RequiresLineOfSight = false; pp.Parent = shell

	-- LOCKED UNTIL THE FRILLRANCHER HANDS THE QUEST OVER.
	--
	-- This is the gate now -- NOT the placement gate above. The two are deliberately split:
	-- the egg is PLACED on its marker the moment you arrive (so it is visible, and so its
	-- position can be checked without running the quest), but it cannot be HATCHED until
	-- Island2QuestAccepted is set. Gating placement instead meant no egg existed at all
	-- until you talked to him, which is what made the marker impossible to verify.
	--
	-- The prompt stays ENABLED while locked and ANSWERS the press, rather than vanishing.
	-- A missing "E" tells the player nothing -- they cannot tell locked from broken, which
	-- is exactly the confusion this quest already caused once. Same rule the geysers use.
	local function questAccepted()
		return player:GetAttribute("Island2QuestAccepted") == true
	end
	player:GetAttributeChangedSignal("Island2QuestAccepted"):Connect(function()
		if questAccepted() then print("[Trike] island2: quest accepted -> egg can now be hatched") end
	end)

	pp.Triggered:Connect(function()
		if not questAccepted() then
			floatText(center + Vector3.new(0, 3, 0), "Talk to the FrillRancher first!", Color3.fromRGB(255, 210, 120))
			return
		end
		if st.owns or st.hatching then return end
		st.hatching = true
		local base = egg:GetPivot()
		-- quick shake then grant
		local t0 = os.clock()
		while os.clock()-t0 < 1.0 and egg.Parent do local p=(os.clock()-t0)/1.0; local amp=0.1+p*0.9
			pcall(function() egg:PivotTo(base * CFrame.new((math.random()-0.5)*amp,0,(math.random()-0.5)*amp) * CFrame.Angles(0, math.rad((math.random()-0.5)*60),0)) end); task.wait() end
		HatchBurst.play(center + Vector3.new(0,1,0), Color3.fromRGB(232,224,190)) -- COOL hatch explosion
		grant(base)
		floatText(center + Vector3.new(0,3,0), "Triceratops hatched! \xF0\x9F\xA6\x95")
		pcall(function() egg:Destroy() end)
	end)
	print(("[Trike] island2 'Fern Frontier' Triceratops egg placed at (%.0f,%.0f,%.0f)"):format(center.X, center.Y, center.Z))
end)
