--!strict
--[[
MountPhysicsController.luau
Simulación física arcade en cliente con predicción local, escalado de montañas,
y movimiento parabólico dinámico al salir despedido por bordes/acantilados.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local sharedMounts = ReplicatedStorage:WaitForChild("Mounts")
local sharedNetwork = ReplicatedStorage:WaitForChild("Network")
local sharedUtils = ReplicatedStorage:WaitForChild("Utils")

local MountTypes = require(sharedMounts:WaitForChild("MountTypes") :: ModuleScript)
local MountConfig = require(sharedMounts:WaitForChild("MountConfig") :: ModuleScript)
local MountRemotes = require(sharedNetwork:WaitForChild("MountRemotes") :: ModuleScript)
local MathUtils = require(sharedUtils:WaitForChild("MathUtils") :: ModuleScript)
local InputController = require(script.Parent:WaitForChild("InputController") :: ModuleScript)

type DriverInput = MountTypes.DriverInput
type MountStats = MountTypes.MountStats
type MountMovementState = MountTypes.MountMovementState
type MountSyncPacket = MountTypes.MountSyncPacket

local MountPhysicsController = {}

local currentMountModel: Model? = nil
local currentStats: MountStats? = nil
local isMounted = false

-- Parámetros dinámicos de movimiento
local forwardSpeed = 0
local lateralVelocity = 0
local verticalVelocity = 0 -- Velocidad Y para trayectorias parabólicas en el aire
local yawAngle = 0
local isCurrentlyDrifting = false
local currentState: MountMovementState = "Idle"
local sequenceNumber = 0
local smoothedGroundY: number? = nil
local currentNormal = Vector3.new(0, 1, 0)

-- Desfase dinámico desde el PrimaryPart hasta la base real del modelo
local mountBottomOffset = 0
local HOVER_HEIGHT = 0.15

-- Configuración de gravedad y pendientes (Permite subir colinas de hasta 72°)
local GRAVITY = 45.0 -- Aceleración de gravedad arcade (studs/s²)
local MAX_SLOPE_ANGLE = 72
local MIN_NORMAL_Y = math.cos(math.rad(MAX_SLOPE_ANGLE)) -- ~0.309

-- Temporizadores de red
local lastSyncTime = 0
local SYNC_INTERVAL = 1 / 20 -- 20 Hz

-- Raycasting hacia la pista
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

-- Corrección del servidor
local serverCorrectionTarget: Vector3? = nil

local function CalculateBottomOffset(model: Model, primaryPart: BasePart): number
    local modelCFrame, modelSize = model:GetBoundingBox()
    local modelBottomY = modelCFrame.Position.Y - (modelSize.Y * 0.5)
    return math.max(0, primaryPart.Position.Y - modelBottomY)
end

local function UpdateRaycastFilter()
    local filterList: {Instance} = {}
    
    if currentMountModel then
        table.insert(filterList, currentMountModel)
    end
    
    local localPlayer = Players.LocalPlayer
    if localPlayer and localPlayer.Character then
        table.insert(filterList, localPlayer.Character)
    end
    
    raycastParams.FilterDescendantsInstances = filterList
end

function MountPhysicsController.Init()
    local correctionRemote = MountRemotes.GetRemote(MountRemotes.Names.ServerCorrection)
    correctionRemote.OnClientEvent:Connect(function(data: any)
        if data and data.AuthorizedPosition then
            serverCorrectionTarget = data.AuthorizedPosition
        end
    end)
    
    RunService.RenderStepped:Connect(function(dt: number)
        if isMounted and currentMountModel and currentStats then
            MountPhysicsController.Update(dt)
        end
    end)
end

function MountPhysicsController.SetMount(mountModel: Model, speciesName: string)
    currentMountModel = mountModel
    currentStats = MountConfig.GetSpeciesStats(speciesName) or MountConfig.GetSpeciesStats(MountConfig.GetDefaultSpecies())
    isMounted = true
    smoothedGroundY = nil
    currentNormal = Vector3.new(0, 1, 0)
    verticalVelocity = 0
    
    local primaryPart = mountModel.PrimaryPart or mountModel:WaitForChild("MountRoot", 3) :: BasePart?
    if primaryPart then
        if not mountModel.PrimaryPart then
            mountModel.PrimaryPart = primaryPart
        end
        
        yawAngle = math.atan2(-primaryPart.CFrame.LookVector.X, -primaryPart.CFrame.LookVector.Z)
        forwardSpeed = 0
        lateralVelocity = 0
        
        mountBottomOffset = CalculateBottomOffset(mountModel, primaryPart)
        
        for _, descendant in mountModel:GetDescendants() do
            if descendant:IsA("BasePart") then
                descendant.CanCollide = false
                descendant.Massless = true
            end
        end
        
        UpdateRaycastFilter()
    end
end

function MountPhysicsController.Dismount()
    isMounted = false
    currentMountModel = nil
    currentStats = nil
    forwardSpeed = 0
    lateralVelocity = 0
    verticalVelocity = 0
    smoothedGroundY = nil
    mountBottomOffset = 0
    currentNormal = Vector3.new(0, 1, 0)
end

function MountPhysicsController.Update(dt: number)
    local mount = currentMountModel
    local stats = currentStats
    if not mount or not stats or not mount.PrimaryPart then return end
    
    local primaryPart = mount.PrimaryPart
    local input = InputController.GetDriverInput()
    
    UpdateRaycastFilter()
    
    -- 1. Aceleración y Frenado
    if input.Throttle > 0 then
        forwardSpeed = math.min(stats.MaxSpeed, forwardSpeed + (stats.Acceleration * input.Throttle * dt))
        if currentState ~= "Airborne" then currentState = "Accelerating" end
    elseif input.Throttle < 0 then
        forwardSpeed = math.max(-stats.MaxSpeed * 0.4, forwardSpeed - (stats.BrakingDeceleration * math.abs(input.Throttle) * dt))
        if currentState ~= "Airborne" then currentState = "Braking" end
    else
        local dragRate = stats.BrakingDeceleration * 0.35
        if forwardSpeed > 0 then
            forwardSpeed = math.max(0, forwardSpeed - (dragRate * dt))
        elseif forwardSpeed < 0 then
            forwardSpeed = math.min(0, forwardSpeed + (dragRate * dt))
        end
        if math.abs(forwardSpeed) < 0.1 and currentState ~= "Airborne" then
            currentState = "Idle"
        end
    end
    
    -- 2. Derrape (Drift)
    local wantsDrift = input.IsDrifting and math.abs(input.Steer) > 0.1 and forwardSpeed > (stats.MaxSpeed * 0.3)
    isCurrentlyDrifting = wantsDrift and currentState ~= "Airborne"
    
    local effectiveTurnSpeed = stats.TurnSpeed
    local effectiveTraction = stats.Traction
    
    if isCurrentlyDrifting then
        currentState = "Drifting"
        effectiveTurnSpeed = stats.TurnSpeed * stats.DriftTurnBoost
        effectiveTraction = stats.DriftFriction
        
        local slipDirection = math.sign(input.Steer)
        lateralVelocity = MathUtils.ExpDecay(lateralVelocity, slipDirection * (forwardSpeed * 0.45), 4.0, dt)
    else
        lateralVelocity = MathUtils.ExpDecay(lateralVelocity, 0, 12.0 * effectiveTraction, dt)
    end
    
    -- 3. Giro angular (Yaw)
    local turnFactor = if stats.MaxSpeed > 0 then (forwardSpeed / stats.MaxSpeed) else 0.5
        yawAngle += -input.Steer * effectiveTurnSpeed * math.clamp(turnFactor, 0.25, 1.0) * dt
        
        -- 4. Detección de Suelo y Terreno con Raycast
        local currentPos = primaryPart.Position
        local rayOrigin = currentPos + Vector3.new(0, 2.5, 0)
        local rayDirection = Vector3.new(0, -7.5, 0) -- Rango corto para saber si tocamos tierra firme
        local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
        
        local targetNormal = Vector3.new(0, 1, 0)
        local groundY = currentPos.Y
        
        if raycastResult and raycastResult.Normal.Y >= MIN_NORMAL_Y then
            local targetGroundY = raycastResult.Position.Y + mountBottomOffset + HOVER_HEIGHT
            
            -- Si estábamos en el aire y caemos sobre el terreno -> Aterrizaje
            if currentState == "Airborne" then
                if currentPos.Y <= targetGroundY + 0.3 then
                    currentState = "Idle"
                    verticalVelocity = 0
                    smoothedGroundY = targetGroundY
                    groundY = targetGroundY
                    targetNormal = raycastResult.Normal
                else
                    -- Todavía volando por encima del suelo en la parábola
                    verticalVelocity -= GRAVITY * dt
                    groundY = currentPos.Y + (verticalVelocity * dt)
                    targetNormal = Vector3.new(0, 1, 0)
                end
            else
                -- Conducción normal / Escalado de montañas
                targetNormal = raycastResult.Normal
                
                -- Detectar si el terreno cayó bruscamente bajo nuestros pies (Borde de un precipicio)
                local dropDistance = if smoothedGroundY then (smoothedGroundY - targetGroundY) else 0
                    
                    if dropDistance > 3.0 and forwardSpeed > (stats.MaxSpeed * 0.3) then
                        -- ¡DESPEGUE PARABÓLICO! Inicia caída libre por inercia
                        currentState = "Airborne"
                        smoothedGroundY = nil
                        verticalVelocity = 0.0 -- Empieza cayendo mientras avanza hacia adelante
                        groundY = currentPos.Y + (verticalVelocity * dt)
                    else
                        -- Terreno continuo (Cuestas arriba o abajo)
                        if not smoothedGroundY then
                            smoothedGroundY = targetGroundY
                        else
                            -- Si sube (Cuesta arriba o bultos): Reacción inmediata (100.0) para jamás atrancarse
                            -- Si baja: Suavizado continuo (25.0)
                            local decaySpeed = if targetGroundY > smoothedGroundY then 100.0 else 25.0
                                smoothedGroundY = MathUtils.ExpDecay(smoothedGroundY, targetGroundY, decaySpeed, dt)
                            end
                            groundY = smoothedGroundY
                        end
                    end
                else
                    -- Sin suelo bajo los pies -> Caída libre parabólica
                    currentState = "Airborne"
                    smoothedGroundY = nil
                    verticalVelocity -= GRAVITY * dt
                    groundY = currentPos.Y + (verticalVelocity * dt)
                    targetNormal = Vector3.new(0, 1, 0)
                end
                
                -- Interpolación suave de la inclinación del chasis según el terreno
                currentNormal = currentNormal:Lerp(targetNormal, math.clamp(18.0 * dt, 0, 1))
                
                -- 5. Cálculo del Vector de Movimiento Resultante
                local headingCFrame = CFrame.Angles(0, yawAngle, 0)
                local forwardVector = headingCFrame.LookVector
                local rightVector = headingCFrame.RightVector
                
                local projectedForward = MathUtils.ProjectOnPlane(forwardVector, currentNormal)
                local surfaceForward = if projectedForward.Magnitude > 0.001 then projectedForward.Unit else forwardVector
                    local projectedRight = MathUtils.ProjectOnPlane(rightVector, currentNormal)
                    local surfaceRight = if projectedRight.Magnitude > 0.001 then projectedRight.Unit else rightVector
                        
                        -- Avance horizontal + Inercia en el aire
                        local newVelocity = (surfaceForward * forwardSpeed) + (surfaceRight * lateralVelocity)
                        local newPosition = currentPos + (newVelocity * dt)
                        newPosition = Vector3.new(newPosition.X, groundY, newPosition.Z)
                        
                        if serverCorrectionTarget then
                            newPosition = newPosition:Lerp(serverCorrectionTarget, 0.2)
                            if (newPosition - serverCorrectionTarget).Magnitude < 0.5 then
                                serverCorrectionTarget = nil
                            end
                        end
                        
                        local rollAngle = 0
                        if isCurrentlyDrifting then
                            rollAngle = -math.sign(input.Steer) * math.rad(12)
                        else
                            rollAngle = -input.Steer * math.rad(6)
                        end
                        
                        local lookTarget = newPosition + surfaceForward
                        local finalOrientation: CFrame
                        if (lookTarget - newPosition).Magnitude > 0.001 then
                            finalOrientation = CFrame.lookAt(newPosition, lookTarget, currentNormal) * CFrame.Angles(0, 0, rollAngle)
                        else
                            finalOrientation = primaryPart.CFrame
                        end
                        
                        primaryPart.CFrame = finalOrientation
                        
                        -- Anular velocidades del solver físico para evitar temblores
                        primaryPart.AssemblyLinearVelocity = Vector3.zero
                        primaryPart.AssemblyAngularVelocity = Vector3.zero
                        
                        -- 6. Sincronización al Servidor (20 Hz)
                        local now = os.clock()
                        if now - lastSyncTime >= SYNC_INTERVAL then
                            lastSyncTime = now
                            sequenceNumber += 1
                            
                            local syncPacket: MountSyncPacket = {
                                Position = newPosition,
                                Velocity = newVelocity,
                                Orientation = finalOrientation,
                                Input = input,
                                State = currentState,
                                SequenceNumber = sequenceNumber,
                            }
                            
                            local syncRemote = MountRemotes.GetRemote(MountRemotes.Names.SyncMovement)
                            syncRemote:FireServer(syncPacket)
                        end
                    end
                    
                    function MountPhysicsController.GetCurrentState(): MountMovementState
                        return currentState
                    end
                    
                    function MountPhysicsController.GetSpeed(): number
                        return forwardSpeed
                    end
                    
                    function MountPhysicsController.IsDrifting(): boolean
                        return isCurrentlyDrifting
                    end
                    
                    return MountPhysicsController