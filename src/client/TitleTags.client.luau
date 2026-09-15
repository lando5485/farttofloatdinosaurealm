-- ============================================================================================
-- TITLE TAGS (client) -- renders the floating TITLE above every player's head.
--
-- A title is a pure BRAG REWARD: it is not buyable, not earnable by playtime, and grants no gameplay
-- advantage whatsoever. It is granted by the server (currently only by Pet Hub collection milestones --
-- see COLLECTION_MILESTONES in PetSystem) and stored as the player attribute "Title".
--
-- THE VIP BADGE IS THE ONE EXCEPTION and it is deliberately separate from the title, not a title itself:
--   * a TITLE is earned and cannot be bought
--   * the VIP badge IS bought and cannot be earned
-- Writing VIP into the Title attribute would have collapsed those two into one slot, so a VIP would have
-- overwritten (or been overwritten by) a title someone actually played for. They render as two lines instead,
-- and a player with both keeps both.
--
-- VIP still costs no remotes: HasVIP is a player attribute set by PlayerStats, and attributes replicate to
-- every client automatically -- exactly the property this file was already built on.
--
-- WHY AN ATTRIBUTE: player attributes replicate to EVERY client automatically, so this script needs no
-- remotes at all -- each client simply watches every player's "Title" attribute and draws a billboard.
-- The server sets it once; everyone sees it, including late joiners, with no sync code.
--
-- Cosmetic only. Never touches flight, gas, coins, or any stat.
-- ============================================================================================

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

-- ===== PORTABLE GAMEPASS LOOKUP (this file is shared by every realm) =====
-- The three places mount their shared folder somewhere different -- Food at RS.Shared, Dino at
-- RS.DinosaurRealm, Space at the RS root -- and the Dino Realm has no Gamepasses module at all. A
-- hard-coded require would therefore work in exactly one place and ERROR OUT in the others, taking the
-- titles down with it: the VIP badge is a bonus LINE on this billboard, not the reason it exists.
-- So it is searched for by name and treated as optional. Found -> VIP badges render. Not found ->
-- titles render alone, which is exactly right in a realm that sells no VIP pass.
local Gamepasses
do
	local deadline = os.clock() + 10 -- the module replicates with everything else; do not race it
	repeat
		for _, d in ipairs(RS:GetDescendants()) do
			if d:IsA("ModuleScript") and d.Name == "Gamepasses" then
				local ok, mod = pcall(require, d)
				if ok and type(mod) == "table" and type(mod.owns) == "function" then Gamepasses = mod end
				break
			end
		end
		if not Gamepasses then task.wait(0.5) end
	until Gamepasses or os.clock() > deadline
	if not Gamepasses then
		print("[TitleTags] no Gamepasses module in this realm -- earned titles render, VIP badges do not")
	end
end

local TAG_NAME = "PlayerTitleTag"

local LINE_H = 34 -- px per line in the billboard; two lines simply doubles the height

-- Look for the title colour the server picked; fall back to gold. Kept in one place so a new title only
-- needs an entry here to get its own colour (unknown titles still render, just in the default gold).
local TITLE_COLOR = {
	["Pet Collector"] = Color3.fromRGB(80, 220, 140),  -- matches the Collector gut skin (green)
	["Beastmaster"]   = Color3.fromRGB(255, 190, 50),  -- matches the Beastmaster gut skin (gold)
}
local DEFAULT_COLOR = Color3.fromRGB(255, 215, 0)

-- Build (or rebuild) the billboard above one character's head.
local function applyTitle(player, character)
	if not (player and character) then return end
	local head = character:FindFirstChild("Head")
	if not head then return end

	local old = head:FindFirstChild(TAG_NAME)
	if old then old:Destroy() end

	-- Collect the lines to draw, TOP-FIRST. VIP sits above the earned title so the paid badge never pushes a
	-- title out of the way -- both are always fully visible when a player has both.
	local lines = {}
	if Gamepasses and Gamepasses.owns(player, "VIP") then
		lines[#lines + 1] = { text = Gamepasses.VIP_TAG_TEXT, color = Gamepasses.VIP_TAG_COLOR }
	end

	local title = player:GetAttribute("Title")
	if type(title) == "string" and title ~= "" then
		lines[#lines + 1] = { text = title, color = TITLE_COLOR[title] or DEFAULT_COLOR }
	end

	if #lines == 0 then return end -- no VIP, no title -> nothing to draw

	local bb = Instance.new("BillboardGui")
	bb.Name = TAG_NAME
	bb.Adornee = head
	bb.Size = UDim2.new(0, 200, 0, LINE_H * #lines)
	-- The offset GROWS with the line count so the bottom line always sits just above the Roblox nametag --
	-- a fixed offset would let a two-line tag hang down over the player's own name.
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.6 + (#lines - 1) * 0.7, 0)
	bb.AlwaysOnTop = false                            -- respects walls; a title shouldn't shine through terrain
	bb.MaxDistance = 120
	bb.LightInfluence = 0
	bb.Parent = head

	for i, line in ipairs(lines) do
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, LINE_H)
		lbl.Position = UDim2.new(0, 0, 0, (i - 1) * LINE_H)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextColor3 = line.color
		lbl.Text = line.text
		lbl.Parent = bb

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 2
		stroke.Parent = lbl
	end

	local shown = {}
	for _, line in ipairs(lines) do shown[#shown + 1] = line.text end
	print("[TitleTags] rendered '" .. table.concat(shown, " / ") .. "' above " .. player.Name)
end

-- Watch ONE player: draw their title now, redraw it whenever it changes, and re-draw on every respawn
-- (a fresh character = a fresh Head, so the old billboard is gone with the old body).
local function watch(player)
	if player.Character then applyTitle(player, player.Character) end
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Head", 10)
		applyTitle(player, char)
	end)
	player:GetAttributeChangedSignal("Title"):Connect(function()
		applyTitle(player, player.Character) -- title earned/changed mid-session -> appears immediately, no rejoin
	end)
	-- Same for VIP. Ownership resolves asynchronously on join (PlayerStats does a UserOwnsGamePassAsync round
	-- trip) and can also land mid-session on a purchase, so without this a brand-new VIP would see no badge
	-- until they respawned.
	if Gamepasses and Gamepasses.ATTR and Gamepasses.ATTR.VIP then
		player:GetAttributeChangedSignal(Gamepasses.ATTR.VIP):Connect(function()
			applyTitle(player, player.Character)
		end)
	end
end

for _, p in ipairs(Players:GetPlayers()) do watch(p) end -- players already here when this script starts
Players.PlayerAdded:Connect(watch)

print("[TitleTags] ready -- titles render above every player's head (attribute-driven, no remotes)")
