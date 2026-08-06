--======================================================================
-- PetCommand.client.luau  (LocalScript)
--======================================================================
-- Chat command "/pet <name>" -> grants that pet the SAME way the island quests do:
-- it fires the pet's server "Hatched" event, so the server marks it OWNED + EQUIPPED,
-- refreshes the Pet Hub, and broadcasts it so OTHER players see it (RemotePets). It
-- also spawns the follower next to you right away. Handy for testing / as a cheat.
--
--   /pet raptor      (aliases: velociraptor)
--   /pet stego       (aliases: stegosaurus)
--   /pet shark       (aliases: megalodon)
--   /pet trike       (aliases: triceratops)
--   /pet spino       (aliases: spinosaurus)
--   /pet trex        (aliases: tyrannosaurus, t-rex)
--   /pet all         -> grant every pet
--   /pet list        -> print the available names
--
--   /giveallpets     -> grant every pet (same as "/pet all", just a friendlier name)
--   /upgrade         -> level the EQUIPPED pet up by 1
--   /upgrade <n>     -> level it up n times
--   /upgrade max     -> take it straight to level 25 (gold + shimmer + every accessory)
--
-- Mirrors MonsoonCommand / IslandTeleport (TextChatService.SendingMessage).
--======================================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer

-- name (+ aliases) -> server hatch event, and the follower spawner (_G fn set by PetFollow)
local PETS = {
	raptor       = { hatch = "RaptorHatched",        spawn = "SpawnRaptorFollower" },
	velociraptor = { hatch = "RaptorHatched",        spawn = "SpawnRaptorFollower" },
	stego        = { hatch = "StegoHatched",         spawn = "SpawnStegoFollower" },
	stegosaurus  = { hatch = "StegoHatched",         spawn = "SpawnStegoFollower" },
	shark        = { hatch = "SharkHatched",         spawn = "SpawnSharkFollower" },
	megalodon    = { hatch = "SharkHatched",         spawn = "SpawnSharkFollower" },
	trike        = { hatch = "TriceratopsHatched",   spawn = "SpawnTriceratopsFollower" },
	triceratops  = { hatch = "TriceratopsHatched",   spawn = "SpawnTriceratopsFollower" },
	spino        = { hatch = "SpinosaurusHatched",   spawn = "SpawnSpinosaurusFollower" },
	spinosaurus  = { hatch = "SpinosaurusHatched",   spawn = "SpawnSpinosaurusFollower" },
	trex         = { hatch = "TyrannosaurusHatched", spawn = "SpawnTyrannosaurusFollower" },
	tyrannosaurus= { hatch = "TyrannosaurusHatched", spawn = "SpawnTyrannosaurusFollower" },
	["t-rex"]    = { hatch = "TyrannosaurusHatched", spawn = "SpawnTyrannosaurusFollower" },
}
local ALL = { "raptor", "stego", "shark", "trike", "spino", "trex" }
local NAMES = table.concat(ALL, ", ")

local function grantPet(key)
	local def = PETS[key]
	if not def then return false end
	-- SERVER grant: fire the pet's hatch event -> server owns + equips it, refreshes the Pet Hub,
	-- and broadcasts it so OTHER players see it (RemotePets). Same path the island quests use.
	local ev = RS:FindFirstChild(def.hatch)
	if ev then pcall(function() ev:FireServer() end) end
	-- spawn the follower next to you right away (client visual)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local at = hrp and (hrp.CFrame * CFrame.new(4, 2, 0)) or CFrame.new(0, 8, 0)
	local spawner = _G[def.spawn]
	if spawner then pcall(function() spawner(at) end) end
	return true
end

local function grantAllPets()
	for _, k in ipairs(ALL) do grantPet(k) end
	print("[PetCommand] granted ALL pets: " .. NAMES)
end

--======================================================================
-- /upgrade -- level the EQUIPPED pet.
--======================================================================
-- Fires PetUpgradeEvent once per level. The server (PetUpgrades.server.luau:257)
-- resolves the target itself:
--
--     petId = petId or _G.playerEquippedPet[player]
--     if petId and ownsPet(player, petId) then levelUp(player, petId, "manual") end
--
-- ...so it ALWAYS acts on whatever pet you currently have equipped, and it will not
-- touch a pet you don't own. levelUp() is also hard-capped at PET_MAX_LEVEL (25), so
-- firing extra times is harmless -- the surplus is simply ignored. That's why "max"
-- can just fire 25 times without needing to know the pet's current level.
--
-- Each level-up re-syncs the follower, the Pet Hub card, and the cross-player
-- broadcast, so the new look appears immediately (and to everyone else too).
local PET_MAX_LEVEL = 25

local function upgradeEquipped(times)
	local ev = RS:FindFirstChild("PetUpgradeEvent")
	if not ev then
		warn("[PetCommand] PetUpgradeEvent missing -> cannot upgrade (is PetUpgrades.server.luau running?)")
		return
	end
	for _ = 1, times do
		pcall(function() ev:FireServer() end) -- no petId -> server uses the EQUIPPED pet
		task.wait(0.06) -- let each level-up sync the follower/GUI before the next
	end
end

TextChatService.SendingMessage:Connect(function(message)
	local text = message.Text
	if not text then return end
	local lower = text:lower()

	------------------------------------------------------------------
	-- /giveallpets
	------------------------------------------------------------------
	if lower:match("^%s*/giveallpets%s*$") then
		grantAllPets()
		return
	end

	------------------------------------------------------------------
	-- /upgrade  |  /upgrade <n>  |  /upgrade max
	------------------------------------------------------------------
	if lower:match("^%s*/upgrade") then
		local arg = lower:match("^%s*/upgrade%s+(%S+)%s*$")
		if not arg then
			if not lower:match("^%s*/upgrade%s*$") then return end -- not actually our command
			upgradeEquipped(1)
			print("[PetCommand] /upgrade -> +1 level on the EQUIPPED pet")
			return
		end
		if arg == "max" then
			-- levelUp() caps at 25, so firing the full 25 is safe from any starting level
			upgradeEquipped(PET_MAX_LEVEL)
			print("[PetCommand] /upgrade max -> EQUIPPED pet taken to level " .. PET_MAX_LEVEL
				.. " (gold + shimmer + every accessory)")
			return
		end
		local n = tonumber(arg)
		if not n or n < 1 then
			print("[PetCommand] usage: /upgrade  |  /upgrade <n>  |  /upgrade max")
			return
		end
		n = math.min(math.floor(n), PET_MAX_LEVEL)
		upgradeEquipped(n)
		print(("[PetCommand] /upgrade %d -> +%d level(s) on the EQUIPPED pet"):format(n, n))
		return
	end

	------------------------------------------------------------------
	-- /pet <name> | /pet all | /pet list
	------------------------------------------------------------------
	local arg = lower:match("^%s*/pets?%s+(%S+)%s*$") -- accepts "/pet" and "/pets"
	if not arg then
		if lower:match("^%s*/pets?%s*$") then
			print("[PetCommand] usage: /pet <name>  ->  " .. NAMES .. "   (or /pet all, /pet list)")
		end
		return
	end
	if arg == "list" then
		print("[PetCommand] available pets: " .. NAMES)
		return
	end
	if arg == "all" then
		grantAllPets()
		return
	end
	if grantPet(arg) then
		print("[PetCommand] granted pet: " .. arg)
	else
		print("[PetCommand] unknown pet '" .. arg .. "'. Try: " .. NAMES)
	end
end)

print("[PetCommand] ready -- /pet <name> (" .. NAMES .. ") | /pet all | /giveallpets | "
	.. "/upgrade [n|max]  (upgrade acts on the EQUIPPED pet)")
