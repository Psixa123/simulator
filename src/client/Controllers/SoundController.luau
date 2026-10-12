--!nonstrict
-- Plays interface/gameplay sound effects, the vacuum loop and background music.
-- Sounds whose Id isn't uploaded yet use a built-in fallback (see Shared/Config/Sounds).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)

local Registry = require(script.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI.UI)

local SoundController = {}

local folder: Folder
local templates = {} -- [name] = Sound
local music: Sound?
local vacuum: Sound?

local function sfxEnabled(): boolean
	local settings = Registry.DataController.Get("Settings")
	return settings == nil or settings.Sfx ~= false
end

function SoundController.Play(name: string, pitch: number?, volumeScale: number?)
	if not sfxEnabled() then
		return
	end
	local template = templates[name]
	if not template then
		return
	end
	local sound = template:Clone()
	sound.PlaybackSpeed = template.PlaybackSpeed * (pitch or 1)
	sound.Volume = template.Volume * (volumeScale or 1)
	sound.Parent = folder
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, 12)
end

-- Plays a sound from a position in the world (3D)
function SoundController.PlayAt(name: string, position: Vector3, pitch: number?)
	if not sfxEnabled() then
		return
	end
	local template = templates[name]
	if not template then
		return
	end
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	local sound = template:Clone()
	sound.PlaybackSpeed = template.PlaybackSpeed * (pitch or 1)
	sound.RollOffMaxDistance = 160
	sound.RollOffMinDistance = 12
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 6)
end

function SoundController.SetVacuum(active: boolean)
	if not vacuum then
		return
	end
	if active and sfxEnabled() then
		if not vacuum.IsPlaying then
			vacuum:Play()
		end
	elseif vacuum.IsPlaying then
		vacuum:Stop()
	end
end

function SoundController.Init()
	folder = Instance.new("Folder")
	folder.Name = "GameSounds"
	folder.Parent = SoundService

	local missing = {} -- sounds with a file in assets/audio that hasn't been uploaded yet
	for name, def in Sounds do
		local uploaded = def.Id ~= nil and def.Id ~= 0
		local soundId = if uploaded then "rbxassetid://" .. tostring(def.Id) else def.Fallback
		if def.File and not uploaded then
			table.insert(missing, if soundId then name else name .. " (silent)")
		end
		if soundId then
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = soundId
			-- The built-in stand-ins get their own pitch/volume so they don't affect the real upload
			sound.Volume = (if uploaded then nil else def.FallbackVolume) or def.Volume or 0.5
			sound.Looped = def.Looped == true
			sound.PlaybackSpeed = (if uploaded then nil else def.FallbackSpeed) or def.PlaybackSpeed or 1
			sound.Parent = folder
			templates[name] = sound
		end
	end
	music = templates.Music
	vacuum = templates.Vacuum

	if #missing > 0 and RunService:IsStudio() then
		table.sort(missing)
		warn(
			"🔇 These sounds still need an uploaded asset Id in src/shared/Config/Sounds.luau: "
				.. table.concat(missing, ", ")
				.. ". Built-in Roblox stand-ins play until then. See README -> \"Sounds and music\"."
		)
	end

	UI.ClickHook = function()
		SoundController.Play("Click")
	end
end

function SoundController.Start()
	Registry.DataController.Observe("Settings", function(settings)
		if not settings then
			return
		end
		if music then
			if settings.Music then
				if not music.IsPlaying then
					music:Play()
				end
			else
				music:Stop()
			end
		end
		if not settings.Sfx and vacuum then
			vacuum:Stop()
		end
	end)
end

return SoundController
