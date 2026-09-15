--======================================================================
-- RealmPipelineProbe.server.luau   [TEMPORARY -- DROP IN EACH REALM, THEN DELETE]
--======================================================================
-- PUT THIS IN ServerScriptService IN **EVERY** REALM (Dino, Space, Food, Candy), JOIN EACH
-- ONE, AND COMPARE THE BLOCKS IT PRINTS.
--
-- WHY IT EXISTS
--   Two files in the Dino repo make OPPOSITE claims about the most load-bearing fact in the
--   whole cross-realm design, and both cite the same number:
--
--     CROSS_REALM_PIPELINE.md:8
--       "All three places are in ONE Roblox experience (universe 10236070926)."
--     DailyCrateService.server.luau:27
--       "FOOD REALM -- a DIFFERENT experience (10236070926)"
--
--   Everything in section 3 of the pipeline doc -- the token wallet, the gift mailbox,
--   rebirths, the login streak, the session ladder, the daily ticket cap, the daily crate,
--   and the dinoComplete flag that gates Food's Candy portal -- is a DataStore. DataStores
--   are scoped to the EXPERIENCE (GameId), never to the place. So:
--
--     * same GameId  -> those systems really are shared, and the design works as written
--     * different    -> every one of them is silently per-experience. No error, no warning:
--                       gifts never arrive, the wallet forks, the Candy portal never opens.
--
--   That is not something reading the code can settle. game.GameId can.
--
-- WHAT IT PRINTS
--   1. GameId (the experience) and PlaceId (this place)
--   2. whether DataStores are reachable at all
--   3. a WRITE then READ against the real universe token store key for a fake test user, so
--      you can see the same value from another realm and prove sharing end to end
--   4. whether MessagingService (live gifts) accepts a publish
--
-- HOW TO READ IT
--   Run in Dino, then in Space. If the GameId lines MATCH, the shared stores are real. If the
--   PROBE VALUE written in one realm is visible from the other, it is proven, not assumed.
--======================================================================

local DataStoreService  = game:GetService("DataStoreService")
local MessagingService  = game:GetService("MessagingService")
local RunService        = game:GetService("RunService")

-- A key no player can ever own: userId 0 is not a real account, so this probe can never
-- touch, read or corrupt a live wallet.
local PROBE_KEY  = "u_0_pipeline_probe"
local TOKEN_STORE = "UniverseCrateTokens_v1"

task.spawn(function()
	print("========== REALM PIPELINE PROBE ==========")
	print(("[Probe] GameId  (EXPERIENCE) = %s   <-- compare this number across realms")
		:format(tostring(game.GameId)))
	print(("[Probe] PlaceId (THIS PLACE) = %s"):format(tostring(game.PlaceId)))
	print(("[Probe] running in %s"):format(RunService:IsStudio() and "STUDIO" or "a LIVE server"))

	if RunService:IsStudio() then
		print("[Probe] NOTE: in Studio, DataStores need Game Settings > Security > "
			.. "'Enable Studio Access to API Services'. Without it the store lines below "
			.. "will fail and tell you nothing about the live game.")
	end

	-- ---- 2/3. DataStore reachability + a real cross-realm sharing test ----
	local store
	local okStore = pcall(function() store = DataStoreService:GetDataStore(TOKEN_STORE) end)
	if not okStore or not store then
		warn("[Probe] DataStores UNREACHABLE -- cannot test sharing from here.")
	else
		-- stamp this realm and the time, so the other realm can see WHO wrote last
		local stamp = ("%s@%d"):format(tostring(game.PlaceId), os.time())
		local okW, errW = pcall(function()
			store:UpdateAsync(PROBE_KEY, function(old)
				local rec = (type(old) == "table") and old or {}
				rec.lastWrittenByPlace = stamp
				rec.seenPlaces = rec.seenPlaces or {}
				rec.seenPlaces[tostring(game.PlaceId)] = os.time()
				return rec
			end)
		end)
		print(okW and ("[Probe] WROTE probe stamp: " .. stamp)
		            or ("[Probe] write FAILED: " .. tostring(errW)))

		local okR, rec = pcall(function() return store:GetAsync(PROBE_KEY) end)
		if okR and type(rec) == "table" then
			local seen = {}
			for placeId, at in pairs(rec.seenPlaces or {}) do
				seen[#seen + 1] = ("%s (%ds ago)"):format(placeId, os.time() - (tonumber(at) or 0))
			end
			table.sort(seen)
			print("[Probe] PLACES THAT HAVE EVER WRITTEN THIS STORE: " ..
				(#seen > 0 and table.concat(seen, ", ") or "(none)"))
			print("[Probe]   >>> If a place ID from ANOTHER realm appears in that list, the")
			print("[Probe]   >>> stores ARE shared and the pipeline's section 3 is sound.")
			print("[Probe]   >>> If each realm only ever sees itself, they are separate")
			print("[Probe]   >>> experiences and every shared system is quietly a no-op.")
		else
			warn("[Probe] read FAILED: " .. tostring(rec))
		end
	end

	-- ---- 4. MessagingService (live gift delivery) ----
	local okM, errM = pcall(function()
		MessagingService:PublishAsync("GiftDelivery_v1", { probe = true, place = game.PlaceId })
	end)
	print(okM and "[Probe] MessagingService publish OK (live gifts can leave this realm)"
	            or ("[Probe] MessagingService publish FAILED: " .. tostring(errM)))
	print("[Probe] NOTE: MessagingService is ALSO experience-scoped -- it only reaches")
	print("[Probe] places sharing the GameId printed above.")
	print("========== END REALM PIPELINE PROBE ==========")
end)
