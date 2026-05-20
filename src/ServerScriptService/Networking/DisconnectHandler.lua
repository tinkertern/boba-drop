-- src/ServerScriptService/Networking/DisconnectHandler.lua
local Constants = require(game:GetService("ReplicatedStorage").Shared.Logic.Constants)

local DisconnectHandler = {}
DisconnectHandler.__index = DisconnectHandler

function DisconnectHandler.new(roomManager)
    local self = setmetatable({}, DisconnectHandler)
    self._roomManager = roomManager
    self._graceTasks = {} -- playerId → task handle
    return self
end

function DisconnectHandler:onPlayerLeaving(player)
    local room = self._roomManager:roomOf(player)
    if not room then return end

    if room.phase == "playing" then
        -- In-round disconnect: 10s grace period, then forfeit
        local pid = player.UserId
        self._graceTasks[pid] = task.delay(Constants.DISCONNECT_GRACE, function()
            -- After grace, forfeit the round
            if room.gameState and room.gameState:phase() == "playing" then
                room.gameState:forfeitRound(tostring(pid), "disconnect")
            end
            self._graceTasks[pid] = nil
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
    if self._graceTasks[pid] then task.cancel(self._graceTasks[pid]) end
    self._graceTasks[pid] = task.delay(Constants.AFK_PIECE_TIMEOUT, function()
        onTimeout()
        self._graceTasks[pid] = nil
    end)
end

function DisconnectHandler:clearAfkTimer(player)
    local pid = player.UserId
    if self._graceTasks[pid] then
        task.cancel(self._graceTasks[pid])
        self._graceTasks[pid] = nil
    end
end

return DisconnectHandler
