--!nonstrict
-- Sound effects and music.
-- Upload the files in assets/audio (Creator Hub -> Development Items -> Audio, or Studio's
-- Asset Manager -> Bulk Import) and paste each asset ID into `Id`.
-- While an Id is 0 the Fallback (a sound built into the Roblox client, played with FallbackSpeed /
-- FallbackVolume when given) is used, or the sound is skipped. Music has no built-in stand-in.
-- In Studio the SoundController warns once about every sound that still needs an Id.

return {
	Click = { Id = 0, Fallback = "rbxasset://sounds/volume_slider.ogg", Volume = 0.55, File = "click.wav" },
	Error = { Id = 0, Fallback = "rbxasset://sounds/volume_slider.ogg", FallbackSpeed = 0.5, Volume = 0.5, File = "error.wav" },
	Sell = { Id = 0, Fallback = "rbxasset://sounds/electronicpingshort.wav", FallbackVolume = 0.45, Volume = 0.6, File = "sell.wav" },
	Success = { Id = 0, Fallback = "rbxasset://sounds/electronicpingshort.wav", FallbackSpeed = 1.25, FallbackVolume = 0.45, Volume = 0.6, File = "success.wav" },
	Hatch = { Id = 0, Fallback = "rbxasset://sounds/impact_explosion_03.mp3", FallbackSpeed = 1.8, FallbackVolume = 0.3, Volume = 0.7, File = "hatch.wav" },
	Pop = { Id = 0, Fallback = "rbxasset://sounds/action_jump.mp3", FallbackSpeed = 1.4, Volume = 0.45, File = "pop.wav" },
	Alarm = { Id = 0, Fallback = "rbxasset://sounds/electronicpingshort.wav", FallbackSpeed = 0.75, FallbackVolume = 0.6, Volume = 0.5, File = "alarm.wav" },
	Vacuum = { Id = 0, Fallback = "rbxasset://sounds/action_falling.mp3", FallbackSpeed = 1.3, FallbackVolume = 0.25, Volume = 0.3, Looped = true, File = "vacuum_loop.wav" },
	Music = { Id = 0, Volume = 0.22, Looped = true, File = "music_loop.wav" },
	Thunder = { Id = 0, Fallback = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.25, PlaybackSpeed = 0.55 },
}
