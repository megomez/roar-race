--!strict
--[[
MountConfig.luau
Configuraciones de físicas base y habilidades pasivas por especie de montura.
Cubre: RF-02, RF-03, HU-02.1, HU-03.
]]

local MountTypes = require(script.Parent:WaitForChild("MountTypes") :: ModuleScript)

type MountStats = MountTypes.MountStats

local MountConfig = {}

local SPECIES_CATALOG: { [string]: MountStats } = {
    ["Capibara"] = {
        MaxSpeed = 70,
        Acceleration = 35,
        BrakingDeceleration = 50,
        TurnSpeed = 3.2,
        Traction = 0.88,
        DriftFriction = 0.55,
        DriftTurnBoost = 1.25,
        JumpForce = 55,
        Weight = 1.1,
        Passive = {
            Type = "ImmunityWaterMudDeceleration",
            DisplayName = "Navegante Anfibio",
            Description = "Inmune a penalizaciones de velocidad al transitar sobre agua o barro.",
            ValueModifier = 1.0, -- Inmunidad al 100% de la ralentización por terreno
        },
    },
    
    ["Avestruz"] = {
        MaxSpeed = 78,
        Acceleration = 46, -- Alta aceleración base
        BrakingDeceleration = 55,
        TurnSpeed = 3.6,
        Traction = 0.82,
        DriftFriction = 0.45,
        DriftTurnBoost = 1.35,
        JumpForce = 65,
        Weight = 0.85,
        Passive = {
            Type = "InitialAccelerationBoost",
            DisplayName = "Arranque Relámpago",
            Description = "Otorga +15% de aceleración durante los primeros 4 segundos tras la salida o re-spawn.",
            ValueModifier = 0.15,
        },
    },
    
    ["Caballo"] = {
        MaxSpeed = 82, -- Mayor velocidad punta en rectas
        Acceleration = 38,
        BrakingDeceleration = 45,
        TurnSpeed = 2.9,
        Traction = 0.85,
        DriftFriction = 0.50,
        DriftTurnBoost = 1.15,
        JumpForce = 60,
        Weight = 1.0,
        Passive = {
            Type = "StraightLineTopSpeed",
            DisplayName = "Galope Infinito",
            Description = "Aumenta la velocidad máxima en un 10% cuando se conduce en línea recta continua.",
            ValueModifier = 0.10,
        },
    },
    
    ["Dragon"] = {
        MaxSpeed = 75,
        Acceleration = 40,
        BrakingDeceleration = 48,
        TurnSpeed = 3.1,
        Traction = 0.86,
        DriftFriction = 0.52,
        DriftTurnBoost = 1.20,
        JumpForce = 70,
        Weight = 1.25,
        Passive = {
            Type = "StunDurationReduction",
            DisplayName = "Escamas Ancestrales",
            Description = "Reduce en un 20% la duración de cualquier efecto de aturdimiento recibido.",
            ValueModifier = 0.20,
        },
    },
    
    ["Leon"] = {
        MaxSpeed = 77,
        Acceleration = 42,
        BrakingDeceleration = 52,
        TurnSpeed = 3.3,
        Traction = 0.87,
        DriftFriction = 0.50,
        DriftTurnBoost = 1.30,
        JumpForce = 58,
        Weight = 1.15,
        Passive = {
            Type = "DraftingSpeedBonus",
            DisplayName = "Instinto Cazador",
            Description = "Gana +5% de velocidad punta al mantenerse dentro de la estela de un rival por más de 1.5s.",
            ValueModifier = 0.05,
        },
    },
    
    ["Tiburon"] = {
        MaxSpeed = 76,
        Acceleration = 39,
        BrakingDeceleration = 47,
        TurnSpeed = 3.5,
        Traction = 0.90,
        DriftFriction = 0.60,
        DriftTurnBoost = 1.40,
        JumpForce = 50,
        Weight = 1.2,
        Passive = {
            Type = "WetTractionMaster",
            DisplayName = "Tracción Hidrodinámica",
            Description = "Agarre óptimo y sin deslizamientos descontrolados en tramos de lluvia o hielo.",
            ValueModifier = 0.25,
        },
    },
    
    ["Gorila"] = {
        MaxSpeed = 73,
        Acceleration = 36,
        BrakingDeceleration = 60,
        TurnSpeed = 2.8,
        Traction = 0.92,
        DriftFriction = 0.65,
        DriftTurnBoost = 1.10,
        JumpForce = 62,
        Weight = 1.4,
        Passive = {
            Type = "ImpactResistance",
            DisplayName = "Poder Titánico",
            Description = "Alta estabilidad; minimiza el desplazamiento y pérdida de control tras choques.",
            ValueModifier = 0.35,
        },
    },
    
    ["Panda"] = {
        MaxSpeed = 74,
        Acceleration = 37,
        BrakingDeceleration = 49,
        TurnSpeed = 3.0,
        Traction = 0.86,
        DriftFriction = 0.53,
        DriftTurnBoost = 1.20,
        JumpForce = 54,
        Weight = 1.1,
        Passive = {
            Type = "NitroEfficiencyBonus",
            DisplayName = "Propulsión Cohete",
            Description = "Extiende la duración de los turbos y boosts en un 10%.",
            ValueModifier = 0.10,
        },
    },
    
    ["Tigre"] = {
        MaxSpeed = 79,
        Acceleration = 44,
        BrakingDeceleration = 50,
        TurnSpeed = 3.4,
        Traction = 0.84,
        DriftFriction = 0.48,
        DriftTurnBoost = 1.32,
        JumpForce = 64,
        Weight = 1.05,
        Passive = {
            Type = "StraightLineTopSpeed",
            DisplayName = "Zarpazo Veloz",
            Description = "Mayor respuesta y aceleración en la salida de las curvas cerradas.",
            ValueModifier = 0.08,
        },
    },
    
    ["Cocodrilo"] = {
        MaxSpeed = 72,
        Acceleration = 38,
        BrakingDeceleration = 56,
        TurnSpeed = 2.9,
        Traction = 0.91,
        DriftFriction = 0.62,
        DriftTurnBoost = 1.18,
        JumpForce = 48,
        Weight = 1.3,
        Passive = {
            Type = "ImmunityWaterMudDeceleration",
            DisplayName = "Acorazado del Pantano",
            Description = "Inmune a la desaceleración sobre superficies acuáticas y lodosas.",
            ValueModifier = 1.0,
        },
    },
    
    ["Zorro"] = {
        MaxSpeed = 76,
        Acceleration = 45,
        BrakingDeceleration = 54,
        TurnSpeed = 3.8,
        Traction = 0.83,
        DriftFriction = 0.46,
        DriftTurnBoost = 1.45,
        JumpForce = 66,
        Weight = 0.8,
        Passive = {
            Type = "InitialAccelerationBoost",
            DisplayName = "Agilidad Escurridiza",
            Description = "Excelente maniobrabilidad en curvas y rápida recuperación de tracción tras derrapes.",
            ValueModifier = 0.12,
        },
    },
}

function MountConfig.GetSpeciesStats(speciesName: string): MountStats?
    return SPECIES_CATALOG[speciesName]
end

function MountConfig.GetDefaultSpecies(): string
    return "Caballo"
end

function MountConfig.GetAllSpeciesNames(): { string }
    local names = {}
    for name in pairs(SPECIES_CATALOG) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

return MountConfig
