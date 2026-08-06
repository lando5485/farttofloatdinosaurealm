--======================================================================
-- SkinCrateBridge.client.luau  (LocalScript)
--======================================================================
-- Supplies _G.petBuildModel for the skin crate panel.
--
-- The crate reel and the inventory grid render "pet wearing skin" thumbnails, which
-- means they need a MODEL of each pet. The bundle's client gets that from its own
-- PetSystem; here it comes from the templates this realm already publishes to
-- ReplicatedStorage (StegosaurusTemplate, VelociraptorTemplate, ...).
--
-- The panel guards the call (`if not _G.petBuildModel then return nil end`), so
-- without this file the crates still open and skins still grant -- the thumbnails
-- just come back blank. That is the only thing this file changes.
--======================================================================
local RS = game:GetService("ReplicatedStorage")

-- PetUpgrades keys everything by these ids; the templates are named differently, so
-- the mapping has to be explicit. PetFollow.client.luau carries the same table for
-- spawning followers -- if a pet is ever added, both need the new row.
local TEMPLATE_FOR = {
	StegoPet         = "StegosaurusTemplate",
	RaptorPet        = "VelociraptorTemplate",
	SharkPet         = "SharkTemplate",
	TriceratopsPet   = "TriceratopsTemplate",
	SpinosaurusPet   = "SpinosaurusTemplate",
	TyrannosaurusPet = "TyrannosaurusTemplate",
}

-- Built models are cached per pet id: the reel asks for the same handful of pets
-- repeatedly while it scrolls, and cloning a 40-part rig every frame is not free.
local cache = {}

_G.petBuildModel = _G.petBuildModel or function(petId)
	if type(petId) ~= "string" then return nil end
	if cache[petId] then return cache[petId]:Clone() end

	local name = TEMPLATE_FOR[petId]
	if not name then return nil end
	local template = RS:FindFirstChild(name)
	if not template then
		-- templates are published by the dino builder scripts a moment after join, so a
		-- miss early on is normal -- return nil and let the caller retry next open
		return nil
	end

	local ok, model = pcall(function() return template:Clone() end)
	if not ok or not model then return nil end

	-- a thumbnail is viewport-only: it must never collide with or fall through the world
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end

	cache[petId] = model
	return model:Clone()
end

print("[SkinBridge] client ready -- petBuildModel wired to this realm's pet templates.")
