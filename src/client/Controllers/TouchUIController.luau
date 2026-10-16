--!strict
--[[
    TouchUIController.luau
    Interfaz táctil adaptable (Responsive Touch UI) con joystick virtual y botones de acción para móviles.
    Cubre: RF-01, RNF-08, RNF-09, HU-01.1.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local InputController = require(script.Parent:WaitForChild("InputController") :: ModuleScript)

local TouchUIController = {}

local screenGui: ScreenGui? = nil
local joystickThumb: Frame? = nil
local joystickBase: Frame? = nil

local isJoystickActive = false
local touchOrigin = Vector2.zero
local JOYSTICK_RADIUS = 55

function TouchUIController.Init()
    local localPlayer = Players.LocalPlayer
    local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

    -- Solo instanciar la UI táctil si el dispositivo tiene pantalla táctil activa
    if not UserInputService.TouchEnabled then
        return
    end

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RoarRace_TouchHUD"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 10
    screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- Respetar Safe Area (HU-01.1 Escenario 2)

    -- Contenedor principal responsive
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "TouchControlsContainer"
    mainFrame.Size = UDim2.fromScale(1, 1)
    mainFrame.BackgroundTransparency = 1
    mainFrame.Parent = screenGui

    -- 1. Joystick Virtual de Conducción (Lado Izquierdo)
    local joystickArea = Instance.new("Frame")
    joystickArea.Name = "JoystickArea"
    joystickArea.AnchorPoint = Vector2.new(0, 1)
    joystickArea.Position = UDim2.new(0.04, 0, 0.92, 0)
    joystickArea.Size = UDim2.fromOffset(140, 140)
    joystickArea.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    joystickArea.BackgroundTransparency = 0.5
    joystickArea.Parent = mainFrame

    local baseCorner = Instance.new("UICorner")
    baseCorner.CornerRadius = UDim.new(1, 0)
    baseCorner.Parent = joystickArea
    joystickBase = joystickArea

    local thumb = Instance.new("Frame")
    thumb.Name = "Thumb"
    thumb.AnchorPoint = Vector2.new(0.5, 0.5)
    thumb.Position = UDim2.fromScale(0.5, 0.5)
    thumb.Size = UDim2.fromOffset(50, 50)
    thumb.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
    thumb.BackgroundTransparency = 0.2
    thumb.Parent = joystickArea

    local thumbCorner = Instance.new("UICorner")
    thumbCorner.CornerRadius = UDim.new(1, 0)
    thumbCorner.Parent = thumb
    joystickThumb = thumb

    -- 2. Botón de Derrape / Drift (Lado Derecho)
    local driftButton = Instance.new("TextButton")
    driftButton.Name = "DriftButton"
    driftButton.AnchorPoint = Vector2.new(1, 1)
    driftButton.Position = UDim2.new(0.82, 0, 0.92, 0)
    driftButton.Size = UDim2.fromOffset(68, 68)
    driftButton.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
    driftButton.Text = "DRIFT"
    driftButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    driftButton.TextScaled = true
    driftButton.Font = Enum.Font.FredokaOne
    driftButton.Parent = mainFrame

    local driftCorner = Instance.new("UICorner")
    driftCorner.CornerRadius = UDim.new(1, 0)
    driftCorner.Parent = driftButton

    -- 3. Botón de Salto / Jump (Lado Derecho Superior)
    local jumpButton = Instance.new("TextButton")
    jumpButton.Name = "JumpButton"
    jumpButton.AnchorPoint = Vector2.new(1, 1)
    jumpButton.Position = UDim2.new(0.95, 0, 0.92, 0)
    jumpButton.Size = UDim2.fromOffset(75, 75)
    jumpButton.BackgroundColor3 = Color3.fromRGB(255, 140, 40)
    jumpButton.Text = "JUMP"
    jumpButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    jumpButton.TextScaled = true
    jumpButton.Font = Enum.Font.FredokaOne
    jumpButton.Parent = mainFrame

    local jumpCorner = Instance.new("UICorner")
    jumpCorner.CornerRadius = UDim.new(1, 0)
    jumpCorner.Parent = jumpButton

    -- Eventos táctiles del Joystick virtual
    joystickArea.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            isJoystickActive = true
            touchOrigin = Vector2.new(input.Position.X, input.Position.Y)
        end
    end)

    UserInputService.TouchMoved:Connect(function(input, gameProcessed)
        if isJoystickActive then
            local currentTouch = Vector2.new(input.Position.X, input.Position.Y)
            local delta = currentTouch - touchOrigin
            local distance = delta.Magnitude

            if distance > JOYSTICK_RADIUS then
                delta = delta.Unit * JOYSTICK_RADIUS
            end

            -- Posicionar visualmente el pulgar del stick
            thumb.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)

            -- Normalizar hacia InputController
            local normalizedX = delta.X / JOYSTICK_RADIUS
            local normalizedY = -delta.Y / JOYSTICK_RADIUS

            InputController.SetTouchSteer(normalizedX)
            InputController.SetTouchThrottle(normalizedY)
        end
    end)

    local function ResetJoystick()
        isJoystickActive = false
        thumb.Position = UDim2.fromScale(0.5, 0.5)
        InputController.SetTouchSteer(0)
        InputController.SetTouchThrottle(0)
    end

    joystickArea.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            ResetJoystick()
        end
    end)

    UserInputService.TouchEnded:Connect(function(input)
        if isJoystickActive then
            ResetJoystick()
        end
    end)

    -- Eventos de botones de acción
    driftButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            InputController.SetTouchDrift(true)
        end
    end)

    driftButton.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            InputController.SetTouchDrift(false)
        end
    end)

    jumpButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            InputController.SetTouchJump(true)
        end
    end)

    jumpButton.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            InputController.SetTouchJump(false)
        end
    end)

    screenGui.Parent = playerGui
end

return TouchUIController
