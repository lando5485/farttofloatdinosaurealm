# -*- coding: utf-8 -*-
"""
Emit the two-part security system into every realm folder.

  <realm>/tools/BackdoorScan.studio.luau   edit-time scanner (reads code; command bar)
  <realm>/src/server/SecurityWatchdog.server.luau   runtime watchdog (cannot read code)

Both carry a MANIFEST of the exact script instance paths that realm's Rojo project
creates, derived from default.project.json + the files on disk. Anything else that
turns up in the place is, by construction, not from the repo.
"""
import json, os, sys

# ---------------------------------------------------------------- manifest ---
def script_name(fn):
    for suf in (".server.luau", ".server.lua", ".client.luau", ".client.lua", ".luau", ".lua"):
        if fn.endswith(suf):
            return fn[: -len(suf)]
    return None

def walk_path(disk, inst_path, out):
    if os.path.isfile(disk):
        if script_name(os.path.basename(disk)) is not None:
            out.add(inst_path)
        return
    if not os.path.isdir(disk):
        return
    for entry in sorted(os.listdir(disk)):
        full = os.path.join(disk, entry)
        if os.path.isdir(full):
            walk_path(full, inst_path + "." + entry, out)
        else:
            n = script_name(entry)
            if n is None:
                continue
            out.add(inst_path if n == "init" else inst_path + "." + n)

def collect(pdir, node, path, out):
    for k, v in node.items():
        if k == "$path":
            walk_path(os.path.join(pdir, v.replace("/", os.sep)), ".".join(path), out)
        elif k.startswith("$"):
            continue
        elif isinstance(v, dict):
            collect(pdir, v, path + [k], out)

def manifest_for(pdir):
    with open(os.path.join(pdir, "default.project.json"), encoding="utf-8") as f:
        d = json.load(f)
    out = set()
    collect(pdir, d.get("tree", {}), [], out)
    return d.get("name", "unknown"), sorted(out)

def lua_manifest(paths):
    return "\n".join('\t["%s"] = true,' % p for p in paths)

# ----------------------------------------------------------------- scanner ---
SCANNER = r'''--[[
================================================================================
 BACKDOOR SCANNER  --  %(NAME)s  --  RUN IN STUDIO'S COMMAND BAR
================================================================================
 GENERATED. Regenerate after adding or removing scripts, or the manifest below
 goes stale and your own new files start showing up as intruders.

 HOW TO RUN
   1. Open the %(NAME)s place in Studio.
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
 This place is built by Rojo from %(NAME)s's src/. The MANIFEST below is the exact
 list of script instances that produces -- %(COUNT)d of them. So any script in the
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
-- %(COUNT)d script instances, from %(NAME)s/default.project.json + src/ on disk.
local MANIFEST = {
%(MANIFEST)s
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
		if b > 127 then table.insert(bad, string.format("pos %%d=0x%%02X", i, b)) end
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
		local m = s:match("require%%s*%%(%%s*%%d%%d%%d%%d+") or s:match("require%%s*%%(%%s*tonumber")
			or s:match("require%%s*%%(%%s*[%%w_]+%%s*%%+%%s*%%d")
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
			if s:match("HttpService[^\n]-:%%s*" .. c) then return "HttpService:" .. c end
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
		local m = s:match("script%%s*:%%s*Destroy") or s:match("script%%.Parent%%s*=%%s*nil")
		return m and "removes itself at runtime" or nil
	  end },
	{ id = "owner-targeting", sev = "HIGH",
	  why = "Code singling out one UserId is how a backdoor gives its author admin in your game while behaving normally for everyone else.",
	  test = function(s)
		local id = s:match("UserId%%s*==%%s*(%%d%%d%%d+)")
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
		for _ in s:gmatch("\\%%d%%d%%d") do n = n + 1 end
		return (n >= 40) and (n .. " decimal escapes") or nil
	  end },
	{ id = "obfuscated-names", sev = "MEDIUM",
	  why = "Machine-mangled identifiers. Real code does not name things like this; obfuscators do.",
	  test = function(s)
		local n = 0
		for _ in s:gmatch("_0x%%x%%x%%x+") do n = n + 1 end
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

print(("\n========== BACKDOOR SCAN -- %(NAME)s ==========\n%%d scripts scanned against a %(COUNT)d-entry manifest, %%d findings")
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
		print(("\n[%%s] %%s"):format(byPath[path][1].sev, path))
		for _, g in ipairs(byPath[path]) do
			print(("    %%-18s %%s"):format(g.rule, g.detail))
			print(("      -> %%s"):format(g.why))
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
		print(("\nQUARANTINED %%d script(s) -> ServerStorage.BACKDOOR_QUARANTINE"):format(moved))
		print("Each carries an OriginalPath value, so a false positive can be put back.")
	else
		print("\nNothing was changed. Set QUARANTINE = true at the top and re-run to disable and\n"
			.. "move these into ServerStorage.BACKDOOR_QUARANTINE for inspection.")
	end
end

print("\nAFTER CLEANING: save the place, then REPUBLISH. Deleting a backdoor in Studio does\n"
	.. "nothing to the version your players are on until you publish over it.\n"
	.. "================================================\n")
'''

# ---------------------------------------------------------------- watchdog ---
WATCHDOG = r'''--======================================================================
-- SecurityWatchdog.server.luau  --  %(NAME)s
--======================================================================
-- GENERATED alongside tools/BackdoorScan.studio.luau. Regenerate both together:
-- they share the MANIFEST, and a stale one here reports your own new scripts as
-- intruders every boot until you notice.
--
-- WHAT THIS CAN AND CANNOT DO -- READ THIS BEFORE TRUSTING IT
--
-- It CANNOT read code. `.Source` requires plugin security; a script running
-- inside a live game is forbidden from reading another script's source, and
-- there is no workaround. So every "does this code call require(assetId)"
-- question belongs to the Studio scanner, not here.
--
-- It also CANNOT reliably stop a backdoor that is already in the place. Scripts
-- start in no guaranteed order, so a hostile Script in Workspace may well have
-- already run by the time this executes. Setting Disabled = true afterwards does
-- not kill a thread that is running -- Disabled stops a script from STARTING.
--
-- So what is it for? Two things it genuinely does well:
--
--   1. A BOOT AUDIT. It lists every script in the live place and compares that
--      to the manifest. Anything unexpected gets printed loudly at every server
--      start, so an injected script cannot sit there quietly for weeks. This is
--      the same check as the Studio scanner's strongest rule, running where you
--      will actually see it -- in server logs, on the live game, after publish.
--
--   2. INJECTION AT RUNTIME. This is the part the Studio scan structurally
--      cannot cover. A require(assetId) backdoor's whole point is that its
--      payload arrives from the internet AFTER you last looked, and the usual
--      next move is to create new scripts, or a new RemoteEvent to take orders
--      through. Those appear after boot, and this sees them appear.
--
-- TREAT ITS OUTPUT AS AN ALARM, NOT A FIX. When it fires, go and clean the place
-- in Studio and republish. DESTROY_UNKNOWN below is a containment measure, not a
-- defence -- see the comment on it.
--======================================================================

-- Log only (false), or also remove what it finds (true).
--
-- Default is FALSE, deliberately. Destroying scripts on a live server based on a
-- name-and-location guess can break your own game if the manifest is stale or a
-- legitimate model ships a script -- and it destroys the evidence you would use
-- to work out what happened. Turn it on once the log has been quiet for a while
-- and you trust the manifest.
local DESTROY_UNKNOWN = false

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local SSS     = game:GetService("ServerScriptService")
local SP      = game:GetService("StarterPlayer")
local SG      = game:GetService("StarterGui")
local RF      = game:GetService("ReplicatedFirst")

local IGNORED_ROOTS = {
	"CoreGui", "CorePackages", "Chat", "TextChatService",
	"StarterPlayer.StarterCharacterScripts",
}

-- Reviewed and accepted. Same idea as the scanner's ALLOWLIST; keep them in step.
local ALLOWLIST = {
}

-- ============================ GENERATED MANIFEST ============================
-- %(COUNT)d script instances, from %(NAME)s/default.project.json + src/ on disk.
local MANIFEST = {
%(MANIFEST)s
}
-- ============================================================================

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

-- See the long note in the Studio scanner: non-ASCII in a script NAME is a
-- homoglyph disguise, and nothing legitimate here uses it.
local function nonAscii(s)
	for i = 1, #s do
		if s:byte(i) > 127 then return true end
	end
	return false
end

local alerts = 0
local function alert(kind, inst, note)
	alerts = alerts + 1
	local path = (typeof(inst) == "Instance") and fullPath(inst) or tostring(inst)
	warn(("[SECURITY] %%s | %%s | %%s | %%s"):format(kind, path,
		(typeof(inst) == "Instance") and inst.ClassName or "?", note or ""))
end

--======================================================================
-- 1. BOOT AUDIT
--======================================================================
local function auditScript(inst, when)
	local path = fullPath(inst)
	if underAny(path, IGNORED_ROOTS) or ALLOWLIST[path] then return end

	if nonAscii(inst.Name) then
		alert("HOMOGLYPH-NAME", inst, when .. " -- name is not ASCII, deliberate disguise")
	elseif not MANIFEST[path] then
		alert("NOT-IN-MANIFEST", inst, when .. " -- not produced by this realm's Rojo project")
	else
		return -- known good
	end

	if DESTROY_UNKNOWN then
		pcall(function() inst.Disabled = true end) -- stops it STARTING; does not kill a running thread
		pcall(function() inst:Destroy() end)
		warn("[SECURITY]   ^ destroyed (DESTROY_UNKNOWN is on)")
	end
end

do
	local n = 0
	for _, inst in ipairs(game:GetDescendants()) do
		if inst:IsA("LuaSourceContainer") then
			n = n + 1
			auditScript(inst, "at boot")
		end
	end
	print(("[SECURITY] %(NAME)s boot audit: %%d scripts against a %(COUNT)d-entry manifest, %%d alert(s)")
		:format(n, alerts))
	if alerts > 0 then
		warn("[SECURITY] Clean these in Studio with tools/BackdoorScan.studio.luau, then REPUBLISH.")
	end
end

--======================================================================
-- 2. RUNTIME INJECTION
--
-- The part the Studio scan cannot cover: a require(assetId) payload arrives from
-- the internet after you last looked, then creates scripts or opens a remote to
-- take orders through. Both show up as descendants appearing after boot.
--
-- Watched narrowly, on the containers that matter, rather than on game itself --
-- a global DescendantAdded fires for every part, effect and character limb the
-- game creates, which is thousands per minute and would bury the signal.
--======================================================================
local WATCH = {RS, SSS, SP, SG, RF, workspace}

-- Remotes legitimately created after boot by your own code are common, so the
-- first pass is a snapshot: anything present shortly after start is baseline,
-- and only LATER arrivals are reported.
local baselineRemotes = {}
task.delay(10, function()
	for _, svc in ipairs({RS, RF}) do
		for _, d in ipairs(svc:GetDescendants()) do
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") then
				baselineRemotes[d] = true
			end
		end
	end

	for _, svc in ipairs(WATCH) do
		svc.DescendantAdded:Connect(function(d)
			if d:IsA("LuaSourceContainer") then
				alert("SCRIPT-ADDED-AT-RUNTIME", d,
					"a script appeared after the server started -- nothing in this realm does that")
				if DESTROY_UNKNOWN then
					pcall(function() d.Disabled = true end)
					pcall(function() d:Destroy() end)
				end
			elseif (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and not baselineRemotes[d] then
				alert("REMOTE-ADDED-LATE", d,
					"a new remote appeared long after boot -- a common backdoor control channel")
			end
		end)
	end
	print("[SECURITY] runtime injection watch armed")
end)

--======================================================================
-- 3. WHAT IS NOT COVERED HERE, SAID OUT LOUD
--
-- * Exploiters on the CLIENT. Nothing above touches that. Client-side exploits
--   are stopped by the server not trusting client input, remote by remote --
--   a different job from backdoors, and not one a watchdog can do generically.
-- * A hostile edit INSIDE a manifested file. The path is on the list, so this
--   passes it. Your defence there is git: `git status` and `git diff` before you
--   publish will show it, and this file cannot.
-- * Plugins. A malicious Studio plugin edits the place at edit time, before any
--   of this runs. Install plugins as carefully as you install models.
--======================================================================
'''

# --------------------------------------------------------------------- main ---
REALMS = sys.argv[1:]
for pdir in REALMS:
    name, paths = manifest_for(pdir)
    subs = {"NAME": name, "COUNT": len(paths), "MANIFEST": lua_manifest(paths)}

    tools = os.path.join(pdir, "tools")
    os.makedirs(tools, exist_ok=True)
    with open(os.path.join(tools, "BackdoorScan.studio.luau"), "w", encoding="utf-8", newline="\n") as f:
        f.write(SCANNER % subs)

    srv = os.path.join(pdir, "src", "server")
    os.makedirs(srv, exist_ok=True)
    with open(os.path.join(srv, "SecurityWatchdog.server.luau"), "w", encoding="utf-8", newline="\n") as f:
        f.write(WATCHDOG % subs)

    print("%-14s %-46s manifest=%d" % (name, pdir, len(paths)))
