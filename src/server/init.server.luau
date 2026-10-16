--!strict
--[[
    Server Entry Point - Roar & Race
    Inicializa los servicios del servidor.
]]

local Players = game:GetService("Players")
local mountsFolder = script:WaitForChild("Mounts")
local MountServerService = require(mountsFolder:WaitForChild("MountServerService") :: ModuleScript)

print("[Server] Inicializando servicios de Roar & Race...")

MountServerService.Init()

print("[Server] Módulo 1 (Sistema Core de Conducción y Físicas) inicializado correctamente.")