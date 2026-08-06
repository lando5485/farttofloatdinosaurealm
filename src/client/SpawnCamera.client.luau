--======================================================================
-- SpawnCamera.client.luau  (LocalScript)
--======================================================================
-- On spawn the character is rotated (e.g. island1 spawns you 90 deg clockwise);
-- this swings the CAMERA to look the SAME way the character faces, so your view
-- matches your body the moment you join / respawn. Done via a brief Scriptable
-- snap, then handed back to the default (Custom) camera which continues from
-- that orientation.
--======================================================================
local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local player    = Players.LocalPlayer

local function faceCamBehindChar(char)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end
	task.wait(0.2) -- let the character + default camera settle first
	-- STAND DOWN DURING THE INTRO. The opening cinematic owns the camera (Scriptable) and
	-- flies it up the tower; snapping it back behind the character here would fight it for
	-- control every frame and shred the shot. Intro.client.luau sets this flag.
	if _G.introPlaying then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then return end
	flat = flat.Unit
	local camPos = hrp.Position - flat * 16 + Vector3.new(0, 6, 0) -- behind + above, looking the way the body faces
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(camPos, hrp.Position + Vector3.new(0, 1.5, 0))
	task.wait() -- one frame holding the new orientation
	cam.CameraType = Enum.CameraType.Custom -- default camera resumes from here, keeping the new yaw
end

player.CharacterAdded:Connect(faceCamBehindChar)
if player.Character then task.spawn(faceCamBehindChar, player.Character) end
print("[SpawnCamera] camera swings to face the character's spawn direction on join/respawn")
