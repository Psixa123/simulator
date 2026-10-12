--!nonstrict
-- Sound effects and music.
-- Upload the files in assets/audio (Creator Hub -> Development Items -> Audio, or Studio's
-- Asset Manager -> Bulk Import) and paste each asset ID into `Id`.
-- While an Id is 0 the Fallback (a sound built into Roblox) is used, or the sound is skipped.

return {
	Click = { Id = 0, Fallback = "rbxasset://sounds/volume_slider.ogg", Volume = 0.55, File = "click.wav" },
	Error = { Id = 0, Volume = 0.5, File = "error.wav" },
	Sell = { Id = 0, Volume = 0.6, File = "sell.wav" },
	Success = { Id = 0, Volume = 0.6, File = "success.wav" },
	Hatch = { Id = 0, Volume = 0.7, File = "hatch.wav" },
	Pop = { Id = 0, Volume = 0.45, File = "pop.wav" },
	Alarm = { Id = 0, Volume = 0.5, File = "alarm.wav" },
	Vacuum = { Id = 0, Volume = 0.3, Looped = true, File = "vacuum_loop.wav" },
	Music = { Id = 0, Volume = 0.22, Looped = true, File = "music_loop.wav" },
	Thunder = { Id = 0, Fallback = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.25, PlaybackSpeed = 0.55 },
}
