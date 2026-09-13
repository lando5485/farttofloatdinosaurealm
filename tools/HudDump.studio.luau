--======================================================================
-- HudDump.studio.luau -- print where a HUD panel actually sits, in a form
-- you can paste straight back into a chat and hand to another realm.
--======================================================================
-- HOW TO RUN IT
--   1. Press Play so the HUD is actually built (this reads the LIVE gui, not the source).
--   2. Open the command bar and set the dropdown on its left to  ** Client **.
--      This will not work on Server -- PlayerGui only exists on the client.
--   3. Paste this whole file in and press Enter.
--
-- WHAT IT PRINTS, and why each line is needed to rebuild the layout elsewhere:
--
--   Size / Position / AnchorPoint  -- the AUTHORED values. These are what you copy into
--                                     the other realm's source. Everything else is context
--                                     for checking the copy actually landed right.
--   Absolute pos/size              -- where it ended up in real pixels. Two panels with
--                                     identical Size/Position can still render in different
--                                     places, because of the next two lines.
--   IgnoreGuiInset                 -- if this differs between realms, every Y is off by the
--                                     topbar inset (36px) even though the numbers match.
--   UIScale                        -- a responsive scaler multiplies the whole panel. If one
--                                     realm has one and the other does not, nothing lines up.
--   viewport                       -- absolute pixels mean nothing without it.
--
-- SET `MATCH` to narrow the dump. Empty = every ScreenGui, which is a lot on this realm.
--======================================================================

local MATCH = "stat"   -- case-insensitive substring; try "" for everything, or "right", "panel"
local DEPTH = 2        -- how many levels of children to print under each top-level frame

local Players = game:GetService("Players")
local plr = Players.LocalPlayer
if not plr then warn("[HudDump] no LocalPlayer -- set the command bar dropdown to CLIENT."); return end
local pg = plr:FindFirstChildOfClass("PlayerGui")
if not pg then warn("[HudDump] no PlayerGui yet -- press Play first."); return end

local cam = workspace.CurrentCamera
local vp = cam and cam.ViewportSize or Vector2.new(0, 0)

local function u2(v)
	return ("UDim2.new(%g, %d, %g, %d)"):format(v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
end
local function v2(v) return ("Vector2.new(%g, %g)"):format(v.X, v.Y) end
local function hit(name) return MATCH == "" or name:lower():find(MATCH:lower(), 1, true) ~= nil end

-- A UIScale anywhere ABOVE an element multiplies it, so walk up, not just the element itself.
local function scaleChain(inst)
	local out, n = {}, inst
	while n and n ~= pg do
		local s = n:FindFirstChildOfClass("UIScale")
		if s then out[#out + 1] = ("%s=%.3f"):format(n.Name, s.Scale) end
		n = n.Parent
	end
	return #out > 0 and table.concat(out, " ") or "none"
end

local function dump(g, indent, depth)
	for _, c in ipairs(g:GetChildren()) do
		if c:IsA("GuiObject") then
			print(("%s%s  %s"):format(indent, c.ClassName, c.Name))
			print(("%s    Size        %s"):format(indent, u2(c.Size)))
			print(("%s    Position    %s"):format(indent, u2(c.Position)))
			print(("%s    AnchorPoint %s"):format(indent, v2(c.AnchorPoint)))
			print(("%s    Absolute    pos (%d, %d)  size (%d, %d)  ZIndex %d  Visible %s")
				:format(indent, c.AbsolutePosition.X, c.AbsolutePosition.Y,
					c.AbsoluteSize.X, c.AbsoluteSize.Y, c.ZIndex, tostring(c.Visible)))
			local extra = c:GetAttribute("ResponsiveExtraShrink")
			if extra then print(("%s    ResponsiveExtraShrink  %s"):format(indent, tostring(extra))) end
			if depth > 1 then dump(c, indent .. "    ", depth - 1) end
		end
	end
end

print("")
print("========== HUD PLACEMENT DUMP ==========")
print(("place      %s  (%d)"):format(game.Name, game.PlaceId))
print(("viewport   %d x %d"):format(vp.X, vp.Y))
print(("filter     MATCH = %q   (set MATCH = \"\" to dump everything)"):format(MATCH))
print("")

local found = 0
for _, sg in ipairs(pg:GetChildren()) do
	if sg:IsA("ScreenGui") or sg:IsA("BillboardGui") then
		-- match on the ScreenGui OR on any of its direct children, so a generically named
		-- container (e.g. "MainGui") holding a "StatsPanel" still shows up.
		local show = hit(sg.Name)
		if not show then
			for _, c in ipairs(sg:GetChildren()) do
				if c:IsA("GuiObject") and hit(c.Name) then show = true break end
			end
		end
		if show then
			found += 1
			print(("ScreenGui  %s"):format(sg.Name))
			if sg:IsA("ScreenGui") then
				print(("    IgnoreGuiInset %s   DisplayOrder %d   Enabled %s   ResetOnSpawn %s")
					:format(tostring(sg.IgnoreGuiInset), sg.DisplayOrder,
						tostring(sg.Enabled), tostring(sg.ResetOnSpawn)))
			end
			print(("    UIScale chain  %s"):format(scaleChain(sg)))
			dump(sg, "    ", DEPTH)
			print("")
		end
	end
end

if found == 0 then
	warn(("[HudDump] nothing matched %q. Run again with MATCH = \"\" to list every gui."):format(MATCH))
else
	print(("========== %d gui(s) dumped -- copy everything above =========="):format(found))
end
