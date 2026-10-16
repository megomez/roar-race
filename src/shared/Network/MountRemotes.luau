--!strict
--[[
    MountRemotes.luau
    Gestión centralizada y sanitización de RemoteEvents para el Módulo 1 de monturas.
    Cubre: RF-01, RNF-04, RNF-05, HU-01.4.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedMounts = ReplicatedStorage:WaitForChild("Mounts")
local MountTypes = require(sharedMounts:WaitForChild("MountTypes") :: ModuleScript)

type DriverInput = MountTypes.DriverInput
type MountSyncPacket = MountTypes.MountSyncPacket

local MountRemotes = {
    Names = {
        SyncMovement = "Mount_SyncMovement",         -- Envío de inputs y posición predicha del cliente
        RequestMount = "Mount_RequestMount",         -- Petición de montar animal
        Dismount = "Mount_Dismount",                 -- Petición de bajar del animal
        StateUpdate = "Mount_StateUpdate",           -- Notificación del servidor (aturdimiento, pasivas)
        ServerCorrection = "Mount_ServerCorrection", -- Corrección forzada de posición/velocidad por anti-exploit
        MountAssigned = "Mount_MountAssigned",       -- Notifica al cliente qué montura y especie le fueron asignadas
    }
}

local remotesFolder: Folder? = nil

function MountRemotes.GetFolder(): Folder
    if remotesFolder then
        return remotesFolder
    end

    if RunService:IsServer() then
        local existing = ReplicatedStorage:FindFirstChild("MountRemotes")
        if existing and existing:IsA("Folder") then
            remotesFolder = existing
            return existing
        end

        local folder = Instance.new("Folder")
        folder.Name = "MountRemotes"

        for _, remoteName in pairs(MountRemotes.Names) do
            local remote = Instance.new("RemoteEvent")
            remote.Name = remoteName
            remote.Parent = folder
        end

        folder.Parent = ReplicatedStorage
        remotesFolder = folder
        return folder
    else
        local folder = ReplicatedStorage:WaitForChild("MountRemotes")
        assert(folder and folder:IsA("Folder"), "[MountRemotes] No se encontró el contenedor MountRemotes en ReplicatedStorage")
        remotesFolder = folder
        return folder
    end
end

-- Inicialización inmediata en el servidor para evitar condiciones de carrera con clientes
if RunService:IsServer() then
    MountRemotes.GetFolder()
end

function MountRemotes.GetRemote(name: string): RemoteEvent
    local folder = MountRemotes.GetFolder()
    local remote = folder:WaitForChild(name)
    assert(remote and remote:IsA("RemoteEvent"), string.format("[MountRemotes] RemoteEvent %s no existe", name))
    return remote
end

-- Sanitización estricta de DriverInput recibida del cliente (RNF-05, HU-01.4)
function MountRemotes.SanitizeDriverInput(input: any): (boolean, DriverInput?)
    if type(input) ~= "table" then
        return false, nil
    end

    local throttle = tonumber(input.Throttle)
    local steer = tonumber(input.Steer)
    local isDrifting = input.IsDrifting == true
    local isJumping = input.IsJumping == true
    local timestamp = tonumber(input.Timestamp)

    if not throttle or not steer or not timestamp then
        return false, nil
    end

    -- Limitar valores dentro de rangos lógicos
    throttle = math.clamp(throttle, -1, 1)
    steer = math.clamp(steer, -1, 1)

    local sanitized: DriverInput = {
        Throttle = throttle,
        Steer = steer,
        IsDrifting = isDrifting,
        IsJumping = isJumping,
        Timestamp = timestamp,
    }

    return true, sanitized
end

-- Sanitización estricta de paquete de sincronización de movimiento
function MountRemotes.SanitizeSyncPacket(packet: any): (boolean, MountSyncPacket?)
    if type(packet) ~= "table" then
        return false, nil
    end

    if typeof(packet.Position) ~= "Vector3" or typeof(packet.Velocity) ~= "Vector3" or typeof(packet.Orientation) ~= "CFrame" then
        return false, nil
    end

    local isInputOk, sanitizedInput = MountRemotes.SanitizeDriverInput(packet.Input)
    if not isInputOk or not sanitizedInput then
        return false, nil
    end

    local seq = tonumber(packet.SequenceNumber) or 0
    local state = packet.State
    if type(state) ~= "string" then
        state = "Idle"
    end

    local sanitized: MountSyncPacket = {
        Position = packet.Position,
        Velocity = packet.Velocity,
        Orientation = packet.Orientation,
        Input = sanitizedInput,
        State = state,
        SequenceNumber = seq,
    }

    return true, sanitized
end

return MountRemotes
