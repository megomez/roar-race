--!strict
--[[
    MountTypes.luau
    Definiciones de tipos y enumeraciones para el Módulo 1 (Sistema Core de Conducción y Físicas de Montura).
    Cubre: HU-01.1, HU-01.2, HU-01.3, HU-01.4, HU-02.1, HU-02.2, HU-03, HU-04.1, HU-04.2.
]]

export type DeviceType = "Touch" | "KeyboardMouse" | "Gamepad"

export type MountMovementState = "Idle" | "Accelerating" | "Braking" | "Drifting" | "Airborne" | "Stunned"

export type PassiveAbilityType = 
    | "ImmunityWaterMudDeceleration"  -- Capibara: Inmunidad a desaceleración en agua/barro
    | "InitialAccelerationBoost"       -- Avestruz: +15% aceleración inicial
    | "StraightLineTopSpeed"           -- Caballo: +10% velocidad punta en rectas
    | "StunDurationReduction"          -- Dragón: -20% tiempo de aturdimiento
    | "DraftingSpeedBonus"             -- León: +5% velocidad en estela/persecución
    | "WetTractionMaster"              -- Tiburón: Máxima tracción en superficies húmedas
    | "ImpactResistance"               -- Gorila: Mayor estabilidad contra choques
    | "NitroEfficiencyBonus"           -- Panda: +10% duración de turbos

export type PassiveAbilityConfig = {
    Type: PassiveAbilityType,
    DisplayName: string,
    Description: string,
    ValueModifier: number,
}

export type MountStats = {
    MaxSpeed: number,               -- Velocidad máxima en studs/s
    Acceleration: number,           -- Tasa de aceleración (studs/s^2)
    BrakingDeceleration: number,    -- Tasa de frenado (studs/s^2)
    TurnSpeed: number,              -- Velocidad angular de giro (rad/s)
    Traction: number,               -- Nivel de adherencia a la pista (0.0 a 1.0)
    DriftFriction: number,          -- Adherencia lateral durante el derrape (0.0 a 1.0)
    DriftTurnBoost: number,         -- Multiplicador de maniobrabilidad al derrapar
    JumpForce: number,              -- Fuerza de salto de la montura
    Weight: number,                 -- Masa y resistencia a impulsos externos
    Passive: PassiveAbilityConfig,  -- Habilidad pasiva única inmodificable (HU-03)
}

export type DriverInput = {
    Throttle: number,       -- -1 (reversa/freno) a 1 (acelerar a fondo)
    Steer: number,          -- -1 (izquierda) a 1 (derecha)
    IsDrifting: boolean,    -- Comando de derrape activo (HU-02.2)
    IsJumping: boolean,     -- Intento de salto
    Timestamp: number,      -- Marca temporal para cálculo de latencia y predicción
}

export type MountSyncPacket = {
    Position: Vector3,
    Velocity: Vector3,
    Orientation: CFrame,
    Input: DriverInput,
    State: MountMovementState,
    SequenceNumber: number,
}

return {}
