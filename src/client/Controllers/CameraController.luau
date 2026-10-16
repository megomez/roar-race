--!strict
--[[
CameraController.luau
Cámara arcade en tercera persona para carreras con auto-seguimiento,
soporte de mouse, gamepad y FLECHAS del teclado.
Cubre: Épica 1, RF-01, RNF-08, RNF-09.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local CameraController = {}

local camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera
local currentMountModel: Model? = nil
local isTracking = false

-- Parámetros de configuración de cámara
local BASE_DISTANCE = 14.0       -- Distancia por defecto detrás de la montura
local MIN_DISTANCE = 8.0         -- Distancia mínima (zoom cercano)
local MAX_DISTANCE = 24.0        -- Distancia máxima (zoom lejano)
local CAMERA_HEIGHT = 2.8        -- Altura sobre la montura
local BASE_FOV = 70.0            -- FOV base
local MAX_FOV = 82.0             -- FOV a alta velocidad
local ROTATION_LERP_SPEED = 10.0 -- Velocidad de seguimiento angular de la montura
local POSITION_SMOOTH_SPEED = 20.0 -- Suavizado de posición anti-temblor
local ARROW_KEY_SPEED = 2.2      -- Velocidad de rotación con flechas del teclado

local currentCamDistance = BASE_DISTANCE
local currentYaw = 0
local currentPitch = math.rad(-10) -- Leve inclinación hacia abajo mirando a la pista

-- Posición suavizada de la cámara
local smoothedCamPos: Vector3? = nil

-- Control orbital (Mouse, Gamepad y Flechas)
local userYawOffset = 0
local userPitchOffset = 0
local isRightMouseDown = false
local lastUserActivityTime = 0
local AUTO_CENTER_DELAY = 1.0

-- Raycast anti-oclusión para no atravesar muros
local cameraRaycastParams = RaycastParams.new()
cameraRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function UpdateRaycastFilter()
    local filterList: {Instance} = {}
    if currentMountModel then
        table.insert(filterList, currentMountModel)
    end
    local localPlayer = Players.LocalPlayer
    if localPlayer and localPlayer.Character then
        table.insert(filterList, localPlayer.Character)
    end
    cameraRaycastParams.FilterDescendantsInstances = filterList
end

function CameraController.Init()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton1 then
            isRightMouseDown = true
            lastUserActivityTime = os.clock()
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton1 then
            isRightMouseDown = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input, gameProcessed)
        if not isTracking then return end
        
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            if isRightMouseDown or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
                userYawOffset -= input.Delta.X * 0.005
                userPitchOffset = math.clamp(userPitchOffset - (input.Delta.Y * 0.005), math.rad(-35), math.rad(45))
                lastUserActivityTime = os.clock()
            end
        elseif input.UserInputType == Enum.UserInputType.MouseWheel then
            currentCamDistance = math.clamp(currentCamDistance - (input.Position.Z * 2.0), MIN_DISTANCE, MAX_DISTANCE)
        elseif input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick2 then
            if math.abs(input.Position.X) > 0.15 or math.abs(input.Position.Y) > 0.15 then
                userYawOffset -= input.Position.X * 0.04
                userPitchOffset = math.clamp(userPitchOffset + (input.Position.Y * 0.03), math.rad(-35), math.rad(45))
                lastUserActivityTime = os.clock()
            end
        end
    end)
end

function CameraController.Enable(mountModel: Model)
    currentMountModel = mountModel
    isTracking = true
    userYawOffset = 0
    userPitchOffset = 0
    smoothedCamPos = nil
    
    UpdateRaycastFilter()
    
    camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera
    camera.CameraType = Enum.CameraType.Scriptable
    
    -- Posicionamiento instantáneo en el fotograma 1
    if mountModel.PrimaryPart then
        local root = mountModel.PrimaryPart
        local look = root.CFrame.LookVector
        currentYaw = math.atan2(-look.X, -look.Z)
        
        local focusCenter = root.Position + Vector3.new(0, CAMERA_HEIGHT, 0)
        local rotationCFrame = CFrame.Angles(0, currentYaw, 0) * CFrame.Angles(currentPitch, 0, 0)
        local targetPos = focusCenter - (rotationCFrame.LookVector * currentCamDistance)
        
        smoothedCamPos = targetPos
        camera.CFrame = CFrame.lookAt(targetPos, focusCenter)
    end
    
    RunService:BindToRenderStep("MountRacingCamera", Enum.RenderPriority.Camera.Value, CameraController.Update)
end

function CameraController.Disable()
    isTracking = false
    currentMountModel = nil
    smoothedCamPos = nil
    
    RunService:UnbindFromRenderStep("MountRacingCamera")
    
    camera = Workspace.CurrentCamera
    if camera then
        camera.CameraType = Enum.CameraType.Custom
        camera.FieldOfView = BASE_FOV
    end
end

function CameraController.Update(dt: number)
    if not isTracking or not currentMountModel or not currentMountModel.PrimaryPart then
        return
    end
    
    camera = Workspace.CurrentCamera or camera
    local mountRoot = currentMountModel.PrimaryPart
    local rootPosition = mountRoot.Position
    local rootCFrame = mountRoot.CFrame
    
    UpdateRaycastFilter()
    
    -- 1. Captura continua de Flechas del Teclado
    local arrowX = 0
    local arrowY = 0
    if UserInputService:IsKeyDown(Enum.KeyCode.Left) then arrowX += 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.Right) then arrowX -= 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.Up) then arrowY += 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.Down) then arrowY -= 1 end
    
    if arrowX ~= 0 or arrowY ~= 0 then
        userYawOffset += arrowX * ARROW_KEY_SPEED * dt
        userPitchOffset = math.clamp(userPitchOffset + (arrowY * ARROW_KEY_SPEED * dt), math.rad(-35), math.rad(45))
        lastUserActivityTime = os.clock()
    end
    
    -- 2. Auto-centrado suave si el usuario no opera controles
    local now = os.clock()
    if not isRightMouseDown and arrowX == 0 and arrowY == 0 and (now - lastUserActivityTime) > AUTO_CENTER_DELAY then
        userYawOffset *= math.exp(-3.5 * dt)
        userPitchOffset *= math.exp(-3.5 * dt)
        if math.abs(userYawOffset) < 0.005 then userYawOffset = 0 end
        if math.abs(userPitchOffset) < 0.005 then userPitchOffset = 0 end
    end
    
    -- 3. Seguimiento angular base de la montura
    local mountLook = rootCFrame.LookVector
    local mountTargetYaw = math.atan2(-mountLook.X, -mountLook.Z)
    
    local angleDiff = (mountTargetYaw - currentYaw)
    angleDiff = math.atan2(math.sin(angleDiff), math.cos(angleDiff))
    currentYaw += angleDiff * (1 - math.exp(-ROTATION_LERP_SPEED * dt))
    
    local totalYaw = currentYaw + userYawOffset
    local totalPitch = currentPitch + userPitchOffset
    
    -- 4. Geometría Orbital Limpia (El punto focal es el centro exacto de la montura)
    local focusCenter = rootPosition + Vector3.new(0, CAMERA_HEIGHT, 0)
    local cameraRotation = CFrame.Angles(0, totalYaw, 0) * CFrame.Angles(totalPitch, 0, 0)
    local camLookVector = cameraRotation.LookVector
    
    local targetCameraPos = focusCenter - (camLookVector * currentCamDistance)
    
    -- 5. Raycast anti-oclusión (Muros)
    local rayDir = targetCameraPos - focusCenter
    local rayResult = Workspace:Raycast(focusCenter, rayDir, cameraRaycastParams)
    
    if rayResult and rayResult.Distance > 2.0 then
        targetCameraPos = rayResult.Position + (rayResult.Normal * 0.7)
    end
    
    -- 6. Suavizado vectorial de posición
    if not smoothedCamPos then
        smoothedCamPos = targetCameraPos
    else
        smoothedCamPos = smoothedCamPos:Lerp(targetCameraPos, 1 - math.exp(-POSITION_SMOOTH_SPEED * dt))
    end
    
    -- Mirar directamente al centro orbital (Garantiza que la montura nunca quede de lado)
    camera.CFrame = CFrame.lookAt(smoothedCamPos :: Vector3, focusCenter)
    
    -- FOV Dinámico según velocidad
    local speed = mountRoot.AssemblyLinearVelocity.Magnitude
    local speedRatio = math.clamp(speed / 75, 0, 1)
    local targetFOV = BASE_FOV + ((MAX_FOV - BASE_FOV) * speedRatio)
    camera.FieldOfView += (targetFOV - camera.FieldOfView) * (1 - math.exp(-5.0 * dt))
end

return CameraController