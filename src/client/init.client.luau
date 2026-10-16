--!strict
--[[
    Client Entry Point - Roar & Race
    Inicializa los controladores del cliente para el Módulo 1.
    Cubre: HU-01.1, HU-01.2, HU-01.3, HU-02.1, HU-02.2, HU-04.1, HU-04.2.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedNetwork = ReplicatedStorage:WaitForChild("Network")
local MountRemotes = require(sharedNetwork:WaitForChild("MountRemotes") :: ModuleScript)

local controllersFolder = script:WaitForChild("Controllers")
local InputController = require(controllersFolder:WaitForChild("InputController") :: ModuleScript)
local MountPhysicsController = require(controllersFolder:WaitForChild("MountPhysicsController") :: ModuleScript)
local MountAnimationController = require(controllersFolder:WaitForChild("MountAnimationController") :: ModuleScript)
local TouchUIController = require(controllersFolder:WaitForChild("TouchUIController") :: ModuleScript)
local CameraController = require(controllersFolder:WaitForChild("CameraController") :: ModuleScript)

print("[Client] Inicializando sistemas de conducción, cámaras y físicas de Roar & Race...")

InputController.Init()
MountPhysicsController.Init()
MountAnimationController.Init()
TouchUIController.Init()
CameraController.Init()

local localPlayer = Players.LocalPlayer

local function OnCharacterAdded(character: Model)
    MountAnimationController.SetupAvatarAnimations(character)
end

if localPlayer.Character then
    OnCharacterAdded(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(OnCharacterAdded)

RunService.RenderStepped:Connect(function(dt: number)
    MountAnimationController.Update(dt)
end)

local currentBoundMount: Model? = nil
local function BindPlayerMount(mountModel: Model, speciesName: string)
    if currentBoundMount == mountModel then
        return
    end
    currentBoundMount = mountModel

    MountPhysicsController.SetMount(mountModel, speciesName)
    CameraController.Enable(mountModel)
    print(string.format("[Client] Montura vinculada a controles y cámara: %s (%s)", mountModel.Name, speciesName))
end

-- Escuchar evento explícito del servidor cuando se asigna la montura
local mountAssignedRemote = MountRemotes.GetRemote(MountRemotes.Names.MountAssigned)
mountAssignedRemote.OnClientEvent:Connect(function(mountModel: any, speciesName: any)
    if mountModel and mountModel:IsA("Model") then
        local species = if type(speciesName) == "string" then speciesName else "Capibara"
        BindPlayerMount(mountModel, species)
    end
end)

-- Verificación de respaldo si la montura ya existía en Workspace
local function CheckExistingMount(child: Instance)
    if child:IsA("Model") and child.Name:find(string.format("_%s$", localPlayer.Name)) then
        local species = child:GetAttribute("Species")
        local speciesStr = if type(species) == "string" then species else "Capibara"
        BindPlayerMount(child, speciesStr)
    end
end

for _, child in ipairs(workspace:GetChildren()) do
    CheckExistingMount(child)
end
workspace.ChildAdded:Connect(CheckExistingMount)

print("[Client] Módulo 1 (Sistema Core de Conducción, Físicas y Cámara) inicializado correctamente.")
