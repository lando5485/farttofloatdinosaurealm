--======================================================================
-- Music.client.luau  (LocalScript)
--======================================================================
-- Background music for the realm. Five tracks, shuffled, looping forever.
--
-- ===== SHUFFLED, NOT RANDOM =====
-- Picking a random track each time sounds like the obvious answer and is the wrong one: with
-- five tracks, pure random repeats the same one back to back 20% of the time, and it is
-- perfectly capable of not playing one of them for half an hour. This walks a SHUFFLED
-- playlist instead -- every track plays once before any plays twice -- and reshuffles at the
-- end, re-drawing if the new order would repeat the track that just finished. So it stays
-- unpredictable without ever sounding broken.
--
-- ===== IT LIVES IN SoundService =====
-- Not in the character, not in a part. Music is 2D -- no position, no rolloff, no falloff as
-- you fly 80,000 studs up the tower -- and SoundService survives respawns, so dying mid-track
-- does not restart the playlist. This script runs once per player from StarterPlayerScripts
-- and never needs to re-run.
--
-- ===== A BAD ASSET MUST NOT STALL THE PLAYLIST =====
-- If an id fails to load or gets moderated, Ended never fires, and a loop that simply waits
-- for Ended would sit there in silence forever. Every wait below is bounded: the track gets
-- LOAD_TIMEOUT to report a length, and if it never does, the playlist moves on and warns
-- with the id that failed so it can be replaced.
--======================================================================

local SoundService = game:GetService("SoundService")

--======================================================================
-- TUNING
--======================================================================
-- Background music should sit UNDER everything -- the fart flight, the geysers, the volcano
-- finale. If it competes with the eruption it is too loud, however good it sounds on an
-- empty island.
local VOLUME       = 0.22

local GAP          = 2.0    -- seconds of quiet between tracks, so they do not butt together
local LOAD_TIMEOUT = 10     -- seconds to wait for a track to report a length before skipping
local MAX_TRACK    = 15 * 60 -- hard ceiling on any one track, in case Ended never fires

local TRACKS = {
	"rbxassetid://105454447704286",
	"rbxassetid://114592407140048",
	"rbxassetid://125883204432628",
	"rbxassetid://139447453530529",
	"rbxassetid://135055193420375",
}

--======================================================================
local sound = Instance.new("Sound")
sound.Name = "RealmMusic"
sound.Looped = false          -- Ended never fires on a looped Sound, and Ended drives the playlist
sound.Volume = VOLUME
sound.Parent = SoundService

-- Fisher-Yates. table.sort with a random comparator is the usual shortcut here and it is not
-- a shuffle -- it biases the order and can error outright on an inconsistent comparator.
local function shuffled(list, avoidFirst)
	local out = {}
	for _, v in ipairs(list) do table.insert(out, v) end
	for i = #out, 2, -1 do
		local j = math.random(i)
		out[i], out[j] = out[j], out[i]
	end
	-- Never open a new pass with the track that just closed the last one. Swapping with the
	-- SECOND entry rather than re-rolling keeps this O(1) and cannot loop forever.
	if avoidFirst and #out > 1 and out[1] == avoidFirst then
		out[1], out[2] = out[2], out[1]
	end
	return out
end

local queue, lastPlayed = {}, nil

local function nextTrack()
	if #queue == 0 then
		queue = shuffled(TRACKS, lastPlayed)
	end
	local id = table.remove(queue, 1)
	lastPlayed = id
	return id
end

task.spawn(function()
	-- A short settle before the first track -- the player is still loading in.
	task.wait(3)

	-- HOLD FOR THE INTRO CINEMATIC. Intro.client sets _G.introPlaying while the first-join
	-- descent runs, and that sequence has its own rising wind bed pinned to six hard cuts.
	-- Dropping a music track over it would fight the one piece of audio doing the work, so
	-- the playlist waits its turn. Returning players never set the flag, so for them this
	-- falls straight through.
	--
	-- BOUNDED, because a flag that never clears -- a cinematic erroring out partway -- would
	-- otherwise mean no music for the whole session.
	local waited = 0
	while _G.introPlaying and waited < 120 do
		task.wait(0.5)
		waited += 0.5
	end

	while true do
		local id = nextTrack()
		sound.SoundId = id
		sound.TimePosition = 0

		local playing = pcall(function() sound:Play() end)

		if playing then
			-- Wait for a length to appear. TimeLength stays 0 until the asset is loaded, so
			-- this doubles as the load check -- and it is bounded, so a dead id costs ten
			-- seconds once rather than killing the playlist.
			local t0 = os.clock()
			while sound.TimeLength <= 0 and os.clock() - t0 < LOAD_TIMEOUT do
				task.wait(0.2)
			end

			if sound.TimeLength <= 0 then
				warn(("[Music] %s never loaded (moderated, deleted, or not a sound?) -- skipping"):format(id))
				pcall(function() sound:Stop() end)
			else
				-- Ended is the real signal; the deadline is only a backstop for the case
				-- where it never arrives.
				local finished = false
				local conn = sound.Ended:Connect(function() finished = true end)
				local deadline = os.clock() + math.min(sound.TimeLength + 5, MAX_TRACK)
				while not finished and os.clock() < deadline do
					task.wait(0.25)
				end
				conn:Disconnect()
				pcall(function() sound:Stop() end)
			end
		else
			warn(("[Music] could not play %s"):format(id))
		end

		task.wait(GAP)
	end
end)

print(("[Music] ready -- %d tracks, shuffled, volume %.2f"):format(#TRACKS, VOLUME))
