--!strict
--[[
    MountAnimationController.luau
    Máquina de estados de animación para el Avatar R15 montado y sincronización con estados de carrera.
    Cubre: RF-04, RNF-01, HU-04.1, HU-04.2.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedMounts = ReplicatedStorage:WaitForChild("Mounts")
local sharedNetwork = ReplicatedStorage:WaitForChild("Network")

local MountTypes = require(sharedMounts:WaitForChild("MountTypes") :: ModuleScript)
local MountRemotes = require(sharedNetwork:WaitForChild("MountRemotes") :: ModuleScript)
local MountPhysicsController = require(script.Parent:WaitForChild("MountPhysicsController") :: ModuleScript)

type MountMovementState = MountTypes.MountMovementState

local MountAnimationController = {}

-- IDs de animación de ejemplo (pueden ser configuradas o reemplazadas por assets definitivos del juego)
local DEFAULT_ANIM_IDS = {
    RidingIdle = "rbxassetid://10921257404",     -- Postura en reposo sobre montura
    RidingFast = "rbxassetid://10921262864",     -- Conducción a alta velocidad
    DriftLeft = "rbxassetid://10921265842",      -- Inclinación lateral izquierda
    DriftRight = "rbxassetid://10921268153",     -- Inclinación lateral derecha
    Jump = "rbxassetid://10921271254",           -- Suspensión en el aire
    Stunned = "rbxassetid://10921274530",        -- Reacción de impacto / aturdimiento
}

local loadedTracks: { [string]: AnimationTrack } = {}
local currentActiveTrackName: string? = nil
local isStunned = false
local stunEndTime = 0

local function LoadTrack(humanoid: Humanoid, name: string, animId: string): AnimationTrack?
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local animInstance = Instance.new("Animation")
    animInstance.AnimationId = animId

    local success, track = pcall(function()
        return animator:LoadAnimation(animInstance)
    end)

    if success and track then
        track.Priority = Enum.AnimationPriority.Action
        loadedTracks[name] = track
        return track
    end

    return nil
end

function MountAnimationController.Init()
    local stateRemote = MountRemotes.GetRemote(MountRemotes.Names.StateUpdate)
    stateRemote.OnClientEvent:Connect(function(data: any)
        if data and data.State == "Stunned" then
            local duration = tonumber(data.Duration) or 2.0
            MountAnimationController.PlayStunReaction(duration)
        end
    end)
end

function MountAnimationController.SetupAvatarAnimations(character: Model)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    -- Limpiar animaciones previas
    for _, track in pairs(loadedTracks) do
        track:Stop(0.1)
    end
    table.clear(loadedTracks)

    -- Cargar catálogo de animaciones de montura R15
    for name, id in pairs(DEFAULT_ANIM_IDS) do
        LoadTrack(humanoid, name, id)
    end
end

local function CrossFadeTo(trackName: string, fadeDuration: number)
    if currentActiveTrackName == trackName then return end

    local newTrack = loadedTracks[trackName]
    if newTrack then
        if currentActiveTrackName and loadedTracks[currentActiveTrackName] then
            loadedTracks[currentActiveTrackName]:Stop(fadeDuration)
        end
        newTrack:Play(fadeDuration)
        currentActiveTrackName = trackName
    end
end

-- Actualización periódica de la máquina de estados de animación (HU-04.2 Escenario 1)
function MountAnimationController.Update(dt: number)
    if isStunned then
        if os.clock() >= stunEndTime then
            isStunned = false
        else
            CrossFadeTo("Stunned", 0.1)
            return
        end
    end

    local state = MountPhysicsController.GetCurrentState()
    local speed = MountPhysicsController.GetSpeed()

    if state == "Airborne" then
        CrossFadeTo("Jump", 0.15)
    elseif state == "Drifting" then
        -- Selección de inclinación según giro
        CrossFadeTo("DriftLeft", 0.1)
    elseif speed > 35 then
        CrossFadeTo("RidingFast", 0.2)
    else
        CrossFadeTo("RidingIdle", 0.25)
    end
end

-- Ejecuta la reacción de impacto/aturdimiento interrumpiendo el ciclo de conducción (HU-04.2 Escenario 2)
function MountAnimationController.PlayStunReaction(duration: number)
    isStunned = true
    stunEndTime = os.clock() + duration
    CrossFadeTo("Stunned", 0.05)
end

return MountAnimationController
