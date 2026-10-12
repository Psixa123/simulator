--!nonstrict
-- Shared table that lets services reference each other at runtime without circular requires.
-- Main.server.luau fills it in before any service is initialised.

return {}
