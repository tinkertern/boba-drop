-- src/ServerScriptService/Networking/DisconnectHandler.lua
local Constants = require(game:GetService("ReplicatedStorage").Shared.Logic.Constants)

local DisconnectHandler = {}
DisconnectHandler.__index = DisconnectHandler

function DisconnectHandler.new(roomManager)
    local self = setmetatable({}, DisconnectHandler)
    self._roomManager = roomManager
    -- Disconnect grace and AFK piece-timeout used to share one [pid] slot, so
    -- starting one would silently cancel the other. They're independent timers
    -- with different lifecycles — separate slots make each cancellable on its
    -- own and remove an implicit clobber that masked timing bugs.
    self._disconnectTasks = {} -- playerId → grace-period task handle
    self._afkTasks = {}        -- playerId → per-piece AFK task handle
    return self
end

function DisconnectHandler:onPlayerLeaving(player)
    local pid = player.UserId
    -- A leaving player can't be AFK on the next piece — cancel any pending AFK
    -- timer so it doesn't fire after they're gone.
    if self._afkTasks[pid] then
        task.cancel(self._afkTasks[pid])
        self._afkTasks[pid] = nil
    end

    local room = self._roomManager:roomOf(player)
    if not room then return end

    if room.phase == "playing" then
        -- In-round disconnect: 10s grace period, then forfeit
        self._disconnectTasks[pid] = task.delay(Constants.DISCONNECT_GRACE, function()
            -- After grace, forfeit the round
            if room.gameState and room.gameState:phase() == "playing" then
                room.gameState:forfeitRound(tostring(pid), "disconnect")
            end
            self._disconnectTasks[pid] = nil
        end)
    elseif room.phase == "postMatch" then
        -- Mid-rematch-window disconnect: treat as Leave
        self._roomManager:treatAsLeave(player)
    end
end

-- Per-piece AFK timer (called from RoomManager when a piece spawns).
-- Cleared when the piece locks.
function DisconnectHandler:startAfkTimer(player, onTimeout)
    local pid = player.UserId
    if self._afkTasks[pid] then task.cancel(self._afkTasks[pid]) end
    self._afkTasks[pid] = task.delay(Constants.AFK_PIECE_TIMEOUT, function()
        onTimeout()
        self._afkTasks[pid] = nil
    end)
end

function DisconnectHandler:clearAfkTimer(player)
    local pid = player.UserId
    if self._afkTasks[pid] then
        task.cancel(self._afkTasks[pid])
        self._afkTasks[pid] = nil
    end
end

return DisconnectHandler
