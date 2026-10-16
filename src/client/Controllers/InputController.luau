--!strict
--[[
    InputController.luau
    Controlador multi-dispositivo unificado (Móvil, PC, Consola / Gamepad).
    Cubre: RF-01, RNF-08, RNF-09, HU-01.1, HU-01.2, HU-01.3.
]]

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedMounts = ReplicatedStorage:WaitForChild("Mounts")
local sharedUtils = ReplicatedStorage:WaitForChild("Utils")

local MountTypes = require(sharedMounts:WaitForChild("MountTypes") :: ModuleScript)
local MathUtils = require(sharedUtils:WaitForChild("MathUtils") :: ModuleScript)

type DriverInput = MountTypes.DriverInput
type DeviceType = MountTypes.DeviceType

local InputController = {}

local currentDevice: DeviceType = "KeyboardMouse"
local gamepadDeadzone = 0.18

-- Estado interno de teclas PC
local keysPressed = {
    Forward = false,
    Backward = false,
    Left = false,
    Right = false,
    Drift = false,
    Jump = false,
}

-- Estado táctil / virtual joystick
local touchSteer = 0
local touchThrottle = 0
local touchDrift = false
local touchJump = false

-- Estado analógico de gamepad
local gamepadSteer = 0
local gamepadThrottle = 0
local gamepadDrift = false
local gamepadJump = false

local onDeviceChangedCallbacks: { (DeviceType) -> () } = {}

-- Determina el tipo de dispositivo inicial
local function DetectDeviceType(): DeviceType
    if GuiService:IsTenFootInterface() or UserInputService.GamepadEnabled then
        return "Gamepad"
    elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        return "Touch"
    else
        return "KeyboardMouse"
    end
end

function InputController.Init()
    currentDevice = DetectDeviceType()

    -- Detección dinámica de cambio de periférico
    UserInputService.LastInputTypeChanged:Connect(function(lastInputType)
        local previous = currentDevice
        if lastInputType == Enum.UserInputType.Gamepad1 or lastInputType == Enum.UserInputType.Gamepad2 then
            currentDevice = "Gamepad"
        elseif lastInputType == Enum.UserInputType.Touch then
            currentDevice = "Touch"
        elseif lastInputType == Enum.UserInputType.Keyboard or lastInputType == Enum.UserInputType.MouseButton1 then
            currentDevice = "KeyboardMouse"
        end

        if currentDevice ~= previous then
            for _, callback in ipairs(onDeviceChangedCallbacks) do
                callback(currentDevice)
            end
        end
    end)

    -- Mapeo de entradas para PC (Teclado) (HU-01.2)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
            keysPressed.Forward = true
        elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
            keysPressed.Backward = true
        elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
            keysPressed.Left = true
        elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
            keysPressed.Right = true
        elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
            keysPressed.Drift = true
        elseif input.KeyCode == Enum.KeyCode.Space then
            keysPressed.Jump = true
        end

        -- Mapeo Gamepad (HU-01.3)
        if input.KeyCode == Enum.KeyCode.ButtonA then
            gamepadJump = true
        elseif input.KeyCode == Enum.KeyCode.ButtonX or input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1 then
            gamepadDrift = true
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
            keysPressed.Forward = false
        elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
            keysPressed.Backward = false
        elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
            keysPressed.Left = false
        elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
            keysPressed.Right = false
        elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
            keysPressed.Drift = false
        elseif input.KeyCode == Enum.KeyCode.Space then
            keysPressed.Jump = false
        end

        if input.KeyCode == Enum.KeyCode.ButtonA then
            gamepadJump = false
        elseif input.KeyCode == Enum.KeyCode.ButtonX or input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1 then
            gamepadDrift = false
        end
    end)

    -- Mapeo Analógico Gamepad (Sticks y Gatillos) (HU-01.3)
    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Gamepad1 then
            if input.KeyCode == Enum.KeyCode.Thumbstick1 then
                -- Stick izquierdo para dirección con deadzone calibrada (HU-01.3 Escenario 1)
                local stickPos = Vector2.new(input.Position.X, input.Position.Y)
                local deadzoned = MathUtils.ApplyVector2Deadzone(stickPos, gamepadDeadzone)
                gamepadSteer = deadzoned.X
            elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
                -- Gatillo derecho: Acelerador analógico
                gamepadThrottle = input.Position.Z
            elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
                -- Gatillo izquierdo: Freno / Reversa analógico
                gamepadThrottle = -input.Position.Z
            end
        end
    end)
end

-- Métodos para inyectar entradas táctiles desde la UI de Móvil (HU-01.1)
function InputController.SetTouchSteer(steer: number)
    touchSteer = math.clamp(steer, -1, 1)
end

function InputController.SetTouchThrottle(throttle: number)
    touchThrottle = math.clamp(throttle, -1, 1)
end

function InputController.SetTouchDrift(isDrifting: boolean)
    touchDrift = isDrifting
end

function InputController.SetTouchJump(isJumping: boolean)
    touchJump = isJumping
end

-- Retorna la estructura unificada de entradas DriverInput (RF-01)
function InputController.GetDriverInput(): DriverInput
    local steer = 0
    local throttle = 0
    local isDrifting = false
    local isJumping = false

    if currentDevice == "Gamepad" then
        steer = gamepadSteer
        throttle = gamepadThrottle
        isDrifting = gamepadDrift
        isJumping = gamepadJump
    elseif currentDevice == "Touch" then
        steer = touchSteer
        throttle = touchThrottle
        isDrifting = touchDrift
        isJumping = touchJump
    else -- KeyboardMouse
        if keysPressed.Left then steer -= 1 end
        if keysPressed.Right then steer += 1 end
        if keysPressed.Forward then throttle += 1 end
        if keysPressed.Backward then throttle -= 1 end
        isDrifting = keysPressed.Drift
        isJumping = keysPressed.Jump
    end

    return {
        Throttle = math.clamp(throttle, -1, 1),
        Steer = math.clamp(steer, -1, 1),
        IsDrifting = isDrifting,
        IsJumping = isJumping,
        Timestamp = os.clock(),
    }
end

function InputController.GetCurrentDevice(): DeviceType
    return currentDevice
end

function InputController.OnDeviceChanged(callback: (DeviceType) -> ())
    table.insert(onDeviceChangedCallbacks, callback)
end

return InputController
