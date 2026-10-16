--!strict
--[[
    MountServerService.luau
    Servicio central de Server Authority, validación de movimiento, anti-exploits y pasivas.
    Cubre: RF-01, RF-02, RF-03, RNF-04, RNF-05, HU-01.4, HU-03, HU-04.2.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local sharedMounts = ReplicatedStorage:WaitForChild("Mounts")
local sharedNetwork = ReplicatedStorage:WaitForChild("Network")

local MountTypes = require(sharedMounts:WaitForChild("MountTypes") :: ModuleScript)
local MountConfig = require(sharedMounts:WaitForChild("MountConfig") :: ModuleScript)
local MountRemotes = require(sharedNetwork:WaitForChild("MountRemotes") :: ModuleScript)
local MountRiggingService = require(script.Parent:WaitForChild("MountRiggingService") :: ModuleScript)

type DriverInput = MountTypes.DriverInput
type MountSyncPacket = MountTypes.MountSyncPacket
type MountStats = MountTypes.MountStats

type PlayerMountSession = {
    SpeciesName: string,
    Stats: MountStats,
    MountModel: Model,
    LastValidPosition: Vector3,
    LastValidVelocity: Vector3,
    LastTimestamp: number,
    SpawnTimestamp: number,
    LastSequenceNumber: number,
    IsStunned: boolean,
    StunEndTime: number,
    StraightLineTime: number,
}

local MountServerService = {}
local activeSessions: { [Player]: PlayerMountSession } = {}

-- Busca dinámicamente el modelo 3D de la montura en los contenedores de Assets de Studio
local function FindMountModelTemplate(speciesName: string): Model?
    local lowerName = string.lower(speciesName)

    local candidateContainers = {
        ReplicatedStorage:FindFirstChild("Assets"),
        ReplicatedStorage:FindFirstChild("StudioAssets"),
        ReplicatedStorage:FindFirstChild("Models"),
        ReplicatedStorage:FindFirstChild("Mounts"),
        ReplicatedStorage,
        ServerStorage:FindFirstChild("Assets"),
        ServerStorage:FindFirstChild("Models"),
        ServerStorage,
        workspace:FindFirstChild("Assets"),
        workspace:FindFirstChild("Models"),
    }

    for _, container in ipairs(candidateContainers) do
        if container then
            local direct = container:FindFirstChild(speciesName)
            if direct and direct:IsA("Model") then
                return direct
            end
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") and string.lower(child.Name) == lowerName then
                    return child
                end
            end
        end
    end

    for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
        if desc:IsA("Model") and string.lower(desc.Name) == lowerName then
            return desc
        end
    end

    return nil
end

function MountServerService.Init()
    local syncRemote = MountRemotes.GetRemote(MountRemotes.Names.SyncMovement)
    local requestMountRemote = MountRemotes.GetRemote(MountRemotes.Names.RequestMount)
    local dismountRemote = MountRemotes.GetRemote(MountRemotes.Names.Dismount)

    syncRemote.OnServerEvent:Connect(function(player: Player, rawPacket: any)
        MountServerService.OnClientSyncPacket(player, rawPacket)
    end)

    requestMountRemote.OnServerEvent:Connect(function(player: Player, speciesName: any)
        local targetSpecies = if type(speciesName) == "string" then speciesName else MountConfig.GetDefaultSpecies()
        MountServerService.SpawnMountForPlayer(player, targetSpecies)
    end)

    dismountRemote.OnServerEvent:Connect(function(player: Player)
        MountServerService.DeseatPlayer(player)
    end)

    local function HandleCharacter(player: Player, character: Model)
        task.wait(0.2)
        if player.Parent and character.Parent then
            MountServerService.SpawnMountForPlayer(player, MountConfig.GetDefaultSpecies())
        end
    end

    Players.PlayerAdded:Connect(function(player: Player)
        player.CharacterAdded:Connect(function(character: Model)
            HandleCharacter(player, character)
        end)
        if player.Character then
            HandleCharacter(player, player.Character)
        end
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            task.spawn(HandleCharacter, player, player.Character)
        end
        player.CharacterAdded:Connect(function(character: Model)
            HandleCharacter(player, character)
        end)
    end

    Players.PlayerRemoving:Connect(function(player: Player)
        MountServerService.CleanupSession(player)
    end)
end

-- Instancia y configura el modelo de la montura respetando su jerarquía visual y articulaciones
function MountServerService.SpawnMountForPlayer(player: Player, speciesName: string): boolean
    local stats = MountConfig.GetSpeciesStats(speciesName)
    if not stats then
        speciesName = MountConfig.GetDefaultSpecies()
        local fallbackStats = MountConfig.GetSpeciesStats(speciesName)
        assert(fallbackStats, string.format("[MountServerService] Especie %s no encontrada", speciesName))
        stats = fallbackStats
    end

    local character = player.Character
    if not character then return false end
    local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return false end

    -- Limpiar montura previa si existía
    MountServerService.CleanupSession(player)

    local template = FindMountModelTemplate(speciesName)
    local mountModel: Model
    local mountRoot: BasePart

    if template then
        print(string.format("[MountServerService] Clonando modelo de '%s' desde: %s", speciesName, template:GetFullName()))
        mountModel = template:Clone()
        mountModel.Name = string.format("Mount_%s_%s", speciesName, player.Name)
        mountModel:SetAttribute("Species", speciesName)
        mountModel:SetAttribute("OwnerUserId", player.UserId)

        -- 1. Determinar o crear el MountRoot
        local existingRoot = mountModel.PrimaryPart
            or mountModel:FindFirstChild("MountRoot") :: BasePart?
            or mountModel:FindFirstChild("HumanoidRootPart") :: BasePart?
            or mountModel:FindFirstChild("Root") :: BasePart?

        if existingRoot then
            mountRoot = existingRoot
            mountModel.PrimaryPart = mountRoot
        else
            -- Si no tiene un root asignado, crear un MountRoot invisible centrado en el modelo
            local modelCFrame, modelSize = mountModel:GetBoundingBox()
            mountRoot = Instance.new("Part")
            mountRoot.Name = "MountRoot"
            mountRoot.Size = Vector3.new(modelSize.X, math.max(2, modelSize.Y * 0.8), modelSize.Z)
            mountRoot.CFrame = modelCFrame
            mountRoot.Transparency = 1 -- SIEMPRE invisible para no mostrar bloques grises
            mountRoot.CanCollide = true
            mountRoot.Parent = mountModel
            mountModel.PrimaryPart = mountRoot
        end

        -- 2. Asegurar que cualquier caja de colisión o HumanoidRootPart sea invisible
        for _, part in ipairs(mountModel:GetDescendants()) do
            if part:IsA("BasePart") then
                if part.Name == "HumanoidRootPart" or part.Name == "MountRoot" or part.Name == "RootPart" or part.Name == "Hitbox" then
                    part.Transparency = 1
                end
            end
        end

        -- 3. Si el modelo incluye un Humanoid interno, deshabilitar su simulación para que no interfiera
        local internalHumanoid = mountModel:FindFirstChildOfClass("Humanoid")
        if internalHumanoid then
            internalHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            internalHumanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
            internalHumanoid.NameDisplayDistance = 0
            internalHumanoid.PlatformStand = true
            internalHumanoid.EvaluateStateMachine = false
        end

        -- 4. Posicionar todo el modelo como una unidad completa usando PivotTo (evita que la cabeza se desfase)
        mountModel:PivotTo(hrp.CFrame)

        -- 5. Desanclar partes y unir solo aquellas que no formen parte del ensamble
        for _, part in ipairs(mountModel:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = false
                if part ~= mountRoot then
                    part.CanCollide = false
                    part.Massless = true

                    -- Solo soldar si la parte está suelta y no comparte ensamble con mountRoot
                    if part.AssemblyRootPart ~= mountRoot then
                        local weld = Instance.new("WeldConstraint")
                        weld.Name = "AutoWeld_" .. part.Name
                        weld.Part0 = mountRoot
                        weld.Part1 = part
                        weld.Parent = mountRoot
                    end
                end
            end
        end
    else
        warn(string.format("[MountServerService] ⚠️ No se encontró modelo 3D para '%s'. Usando bloque provisional.", speciesName))
        mountModel = Instance.new("Model")
        mountModel.Name = string.format("Mount_%s_%s", speciesName, player.Name)
        mountModel:SetAttribute("Species", speciesName)
        mountModel:SetAttribute("OwnerUserId", player.UserId)

        mountRoot = Instance.new("Part")
        mountRoot.Name = "MountRoot"
        mountRoot.Size = Vector3.new(3.5, 2.5, 5.5)
        mountRoot.Color = Color3.fromRGB(150, 100, 60)
        mountRoot.Material = Enum.Material.SmoothPlastic
        mountRoot.Parent = mountModel
        mountModel.PrimaryPart = mountRoot

        mountModel:PivotTo(hrp.CFrame)
    end

    -- Configuración física del chasis principal
    mountRoot.Anchored = false
    mountRoot.CanCollide = true
    mountRoot.Massless = false
    mountRoot.CustomPhysicalProperties = PhysicalProperties.new(
        stats.Weight * 1.5,
        stats.Traction,
        0.1,
        1.0,
        stats.Traction
    )

    -- Silla de montar (SaddleAttachment)
    if not mountRoot:FindFirstChild("SaddleAttachment") then
        local saddle = Instance.new("Attachment")
        saddle.Name = "SaddleAttachment"
        saddle.Position = Vector3.new(0, (mountRoot.Size.Y * 0.5) + 0.4, -0.2)
        saddle.Parent = mountRoot
    end

    mountModel.Parent = workspace

    -- Otorgar Network Ownership al jugador
    pcall(function()
        mountRoot:SetNetworkOwner(player)
    end)

    -- Anclar Avatar R15
    local attached = MountRiggingService.AttachCharacterToMount(player, mountModel)
    if not attached then
        mountModel:Destroy()
        return false
    end

    local now = os.clock()
    activeSessions[player] = {
        SpeciesName = speciesName,
        Stats = stats,
        MountModel = mountModel,
        LastValidPosition = mountRoot.Position,
        LastValidVelocity = Vector3.zero,
        LastTimestamp = now,
        SpawnTimestamp = now,
        LastSequenceNumber = 0,
        IsStunned = false,
        StunEndTime = 0,
        StraightLineTime = 0,
    }

    -- Notificar al cliente
    local mountAssignedRemote = MountRemotes.GetRemote(MountRemotes.Names.MountAssigned)
    mountAssignedRemote:FireClient(player, mountModel, speciesName)

    return true
end

function MountServerService.DeseatPlayer(player: Player)
    MountRiggingService.DetachCharacterFromMount(player)
    MountServerService.CleanupSession(player)
end

function MountServerService.CleanupSession(player: Player)
    local session = activeSessions[player]
    if session then
        if session.MountModel and session.MountModel.Parent then
            session.MountModel:Destroy()
        end
        activeSessions[player] = nil
    end
end

function MountServerService.OnClientSyncPacket(player: Player, rawPacket: any)
    local session = activeSessions[player]
    if not session then return end

    local isValid, packet = MountRemotes.SanitizeSyncPacket(rawPacket)
    if not isValid or not packet then return end

    local now = os.clock()
    local dt = now - session.LastTimestamp
    if dt <= 0 then return end

    if session.IsStunned then
        if now < session.StunEndTime then
            packet.Input.Throttle = 0
            packet.Input.Steer = 0
            packet.Velocity = Vector3.zero
        else
            session.IsStunned = false
        end
    end

    local maxAllowedSpeed = session.Stats.MaxSpeed

    if session.Stats.Passive.Type == "InitialAccelerationBoost" then
        if (now - session.SpawnTimestamp) <= 4.0 then
            maxAllowedSpeed = maxAllowedSpeed * (1 + session.Stats.Passive.ValueModifier)
        end
    end

    if session.Stats.Passive.Type == "StraightLineTopSpeed" then
        if math.abs(packet.Input.Steer) < 0.1 and packet.Input.Throttle > 0.8 then
            session.StraightLineTime += dt
            if session.StraightLineTime >= 2.0 then
                maxAllowedSpeed = maxAllowedSpeed * (1 + session.Stats.Passive.ValueModifier)
            end
        else
            session.StraightLineTime = 0
        end
    end

    local maxAllowedDistance = (maxAllowedSpeed * 1.25 * dt) + 4.0
    local distance = (packet.Position - session.LastValidPosition).Magnitude

    if distance > maxAllowedDistance then
        warn(string.format("[Anti-Exploit] Movimiento anómalo detectado para %s! Distancia: %.2f studs en %.3fs (Máx permitido: %.2f)", 
            player.Name, distance, dt, maxAllowedDistance))

        local correctionRemote = MountRemotes.GetRemote(MountRemotes.Names.ServerCorrection)
        correctionRemote:FireClient(player, {
            AuthorizedPosition = session.LastValidPosition,
            AuthorizedVelocity = session.LastValidVelocity,
            Timestamp = now,
        })
        return
    end

    session.LastValidPosition = packet.Position
    session.LastValidVelocity = packet.Velocity
    session.LastTimestamp = now
    session.LastSequenceNumber = packet.SequenceNumber
end

function MountServerService.ApplyStunToPlayer(player: Player, baseDuration: number)
    local session = activeSessions[player]
    if not session then return end

    local finalDuration = baseDuration
    if session.Stats.Passive.Type == "StunDurationReduction" then
        finalDuration = baseDuration * (1 - session.Stats.Passive.ValueModifier)
    end

    session.IsStunned = true
    session.StunEndTime = os.clock() + finalDuration

    local stateRemote = MountRemotes.GetRemote(MountRemotes.Names.StateUpdate)
    stateRemote:FireClient(player, {
        State = "Stunned",
        Duration = finalDuration,
    })
end

return MountServerService
