-- Day 1 placeholder: lock the local camera onto the BobaDropScene play column.
-- Producer-owned; lives alongside Game Engineer's InputHandler in StarterPlayerScripts.
-- When Day 3 brings real per-side camera rigging, this can be replaced or extended.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants
do
    local ok, mod = pcall(require, ReplicatedStorage.Shared.Logic.Constants)
    Constants = ok and mod or { BOARD_TOTAL_HEIGHT = 14 }
end

local scene = Workspace:WaitForChild("BobaDropScene", 10)
if not scene then
    warn("[SceneCamera] BobaDropScene not found in Workspace; leaving default camera")
    return
end

local camera = Workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable

local boardCenterY = Constants.BOARD_TOTAL_HEIGHT * 0.5
local lookAt = Vector3.new(0, boardCenterY, 0)
local position = Vector3.new(0, boardCenterY + 1, 18)

camera.CFrame = CFrame.lookAt(position, lookAt)
camera.FieldOfView = 45
