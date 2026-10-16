--!strict
--[[
    MathUtils.luau
    Funciones matemáticas y de interpolación para control analógico, deadzones y físicas arcade.
    Cubre: HU-01.3, HU-02.1, HU-02.2.
]]

local MathUtils = {}

-- Calibra zonas muertas (deadzones) para sticks analógicos de Gamepad (HU-01.3)
function MathUtils.ApplyDeadzone(inputVal: number, deadzone: number): number
    local absVal = math.abs(inputVal)
    if absVal <= deadzone then
        return 0
    end
    -- Normaliza el recorrido restante entre deadzone y 1.0 para mantener linealidad suave
    local sign = math.sign(inputVal)
    local normalized = (absVal - deadzone) / (1 - deadzone)
    return sign * math.clamp(normalized, 0, 1)
end

-- Calibra zona muerta para un Vector2 analógico (Stick de dirección)
function MathUtils.ApplyVector2Deadzone(inputVec: Vector2, deadzone: number): Vector2
    local magnitude = inputVec.Magnitude
    if magnitude <= deadzone then
        return Vector2.zero
    end
    local normalized = (magnitude - deadzone) / (1 - deadzone)
    local scaledMagnitude = math.clamp(normalized, 0, 1)
    return inputVec.Unit * scaledMagnitude
end

-- Interpolación lineal básica
function MathUtils.Lerp(a: number, b: number, t: number): number
    return a + (b - a) * math.clamp(t, 0, 1)
end

-- Interpolación lineal con amortiguamiento exponencial independiente de framerate
function MathUtils.ExpDecay(a: number, b: number, decay: number, dt: number): number
    return b + (a - b) * math.exp(-decay * dt)
end

-- Interpolación exponencial para CFrame
function MathUtils.LerpCFrame(a: CFrame, b: CFrame, t: number): CFrame
    return a:Lerp(b, math.clamp(t, 0, 1))
end

-- Proyecta un vector sobre un plano dado por su normal (útil para alineación con pendientes de pista)
function MathUtils.ProjectOnPlane(vector: Vector3, planeNormal: Vector3): Vector3
    local normal = planeNormal.Unit
    return vector - normal * vector:Dot(normal)
end

return MathUtils
