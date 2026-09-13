--!nonstrict
-- Remotes (ReplicatedStorage/Shared/Remotes)
-- Thin shared accessor for the player-state SNAPSHOT stream. The snapshot table carries
-- lastCrateClaim (and is the only thing the crate UI needs from server state).
--
--   getStateChanged() -> RemoteEvent  (server -> client): server pushes a fresh snapshot.
--   getRequestState() -> RemoteEvent  (client -> server): client asks for a fresh snapshot
--                                       (on-ready handshake; reliable on slow clients).
--
-- The server (PlayerState) creates the remotes; the client waits for them. Both sides require
-- this module and call the getters, so neither hard-codes instance paths.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "StateRemotes"
local STATE_CHANGED = "StateChanged"
local REQUEST_STATE = "RequestState"

local isServer = RunService:IsServer()

local function getFolder()
	if isServer then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder
	else
		return ReplicatedStorage:WaitForChild(FOLDER_NAME, 30) or ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
end

local function getRemote(name)
	local folder = getFolder()
	if isServer then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		return remote
	else
		return folder:WaitForChild(name, 30) or folder:WaitForChild(name)
	end
end

function Remotes.getStateChanged()
	return getRemote(STATE_CHANGED)
end

function Remotes.getRequestState()
	return getRemote(REQUEST_STATE)
end

return Remotes
