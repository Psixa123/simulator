--!nonstrict
-- Shared table so client controllers can reference each other without circular requires.

local Registry: { [string]: any } = {}

return Registry
