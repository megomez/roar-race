--!strict
--[[
MountRiggingService.luau
Servicio de anclaje físico y sincronización estructural del Avatar (R15) sobre la montura.
Cubre: RF-04, RNF-01, RNF-02, HU-04.1.
]]

local MountRiggingService = {}

type RigRecord = {
    Mount: Model,
    Joint: Motor6D | WeldConstraint,
    Constraints: { Instance },
    OriginalMassless: { [BasePart]: boolean },
}

local activeRigs: { [Player]: RigRecord } = {}

-- Optimiza colisiones y masa del Avatar R15 para evitar desbalance físico
local function OptimizeAvatarCollisions(character: Model, mountRoot: BasePart): ({ Instance }, { [BasePart]: boolean })
    local createdConstraints = {}
    local originalMassless = {}
    
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            originalMassless[part] = part.Massless
            
            -- Desactiva colisiones del personaje mientras está montado
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            
            -- Avatar se vuelve Massless para no desplazar el centro de masa de la montura
            part.Massless = true
            
            local noCol = Instance.new("NoCollisionConstraint")
            noCol.Name = "MountNoCol_" .. part.Name
            noCol.Part0 = part
            noCol.Part1 = mountRoot
            noCol.Parent = mountRoot
            table.insert(createdConstraints, noCol)
        end
    end
    
    return createdConstraints, originalMassless
end

-- Restablece colisiones y masa normal del personaje al desmontar
local function RestoreAvatarCollisions(character: Model, originalMassless: { [BasePart]: boolean }?)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if part.Name == "HumanoidRootPart" or part.Name == "Head" or part.Name == "UpperTorso" or part.Name == "LowerTorso" then
                part.CanCollide = true
            end
            part.CanTouch = true
            part.CanQuery = true
            
            if originalMassless and originalMassless[part] ~= nil then
                part.Massless = originalMassless[part]
            else
                if not part:IsA("Accessory") and not part.Parent:IsA("Accessory") then
                    part.Massless = false
                end
            end
        end
    end
end

-- Ancla físicamente el personaje R15 al socket de la montura (HU-04.1)
function MountRiggingService.AttachCharacterToMount(player: Player, mountModel: Model): boolean
    local character = player.Character
    if not character then
        return false
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local lowerTorso = character:FindFirstChild("LowerTorso") :: BasePart?
    
    if not humanoid or not hrp or not lowerTorso then
        warn(string.format("[MountRiggingService] Character de %s no tiene Humanoid o RootPart válidos", player.Name))
        return false
    end
    
    local mountRoot = mountModel.PrimaryPart or mountModel:FindFirstChild("MountRoot") :: BasePart?
    if not mountRoot then
        warn("[MountRiggingService] La montura no tiene PrimaryPart ni MountRoot configurado")
        return false
    end
    
    MountRiggingService.DetachCharacterFromMount(player)
    
    -- Configurar Humanoid para modo vehículo y desactivar fuerzas físicas internas
    humanoid.PlatformStand = true
    humanoid.AutoRotate = false
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    
    -- Asignar máxima prioridad a mountRoot como raíz absoluta del ensamblado
    mountRoot.RootPriority = 127
    hrp.RootPriority = 0
    
    -- Asignar la propiedad de red al cliente para eliminar latencia y tirones de física
    pcall(function()
        if not mountRoot.Anchored then
            mountRoot:SetNetworkOwner(player)
        end
    end)
    
    -- Optimizar colisiones del avatar y neutralizar masa
    local constraints, originalMassless = OptimizeAvatarCollisions(character, mountRoot)
    
    -- Buscar Attachment de silla/montura o calcular offset por defecto
    local saddleAttachment = mountRoot:FindFirstChild("SaddleAttachment") :: Attachment?
    local targetCFrame: CFrame
    if saddleAttachment then
        targetCFrame = mountRoot.CFrame * saddleAttachment.CFrame
    else
        targetCFrame = mountRoot.CFrame * CFrame.new(0, (mountRoot.Size.Y * 0.5) + 0.5, 0)
    end
    
    hrp.CFrame = targetCFrame
    
    -- Articulación rígida estructurada (Motor6D)
    local mountJoint = Instance.new("Motor6D")
    mountJoint.Name = "MountAttachmentJoint"
    mountJoint.Part0 = mountRoot
    mountJoint.Part1 = hrp
    mountJoint.C0 = saddleAttachment and saddleAttachment.CFrame or CFrame.new(0, (mountRoot.Size.Y * 0.5) + 0.5, 0)
    mountJoint.C1 = CFrame.new(0, 0, 0)
    mountJoint.Parent = mountRoot
    
    activeRigs[player] = {
        Mount = mountModel,
        Joint = mountJoint,
        Constraints = constraints,
        OriginalMassless = originalMassless,
    }
    
    return true
end

-- Desancla al jugador de la montura
function MountRiggingService.DetachCharacterFromMount(player: Player): boolean
    local record = activeRigs[player]
    if not record then
        return false
    end
    
    if record.Joint and record.Joint.Parent then
        record.Joint:Destroy()
    end
    
    if record.Constraints then
        for _, c in ipairs(record.Constraints) do
            if c and c.Parent then
                c:Destroy()
            end
        end
    end
    
    -- Devolver la propiedad de red de la montura al servidor
    if record.Mount then
        local mountRoot = record.Mount.PrimaryPart or record.Mount:FindFirstChild("MountRoot") :: BasePart?
        if mountRoot and mountRoot:IsDescendantOf(workspace) then
            pcall(function()
                if not mountRoot.Anchored then
                    mountRoot:SetNetworkOwner(nil)
                end
            end)
        end
    end
    
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.PlatformStand = false
            humanoid.AutoRotate = true
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if hrp then
            hrp.RootPriority = 0
        end
        RestoreAvatarCollisions(character, record.OriginalMassless)
    end
    
    activeRigs[player] = nil
    return true
end

function MountRiggingService.GetActiveMount(player: Player): Model?
    local record = activeRigs[player]
    return record and record.Mount or nil
end

return MountRiggingService