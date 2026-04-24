# ============================================================
#  main_p8.ps1 - Menu principal de la Practica 8
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
# ============================================================

. "$PSScriptRoot\funciones_p8.ps1"

if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  ERROR: Debes ejecutar este script como Administrador." -ForegroundColor Red
    exit 1
}

do {
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |        PRACTICA 8 - ACTIVE DIRECTORY     |" -ForegroundColor Cyan
    Write-Host "  |        practica8.local | 192.168.1.202   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  1. Instalar dependencias                |" -ForegroundColor White
    Write-Host "  |  2. Promover servidor a Domain Controller|" -ForegroundColor White
    Write-Host "  |  3. Crear OUs y usuarios desde CSV       |" -ForegroundColor White
    Write-Host "  |  4. Configurar horarios de acceso        |" -ForegroundColor White
    Write-Host "  |  5. Configurar perfiles moviles y FSRM   |" -ForegroundColor White
    Write-Host "  |  6. Configurar apantallamiento FSRM      |" -ForegroundColor White
    Write-Host "  |  7. Configurar AppLocker                 |" -ForegroundColor White
    Write-Host "  |  8. Crear usuario dinamicamente          |" -ForegroundColor White
    Write-Host "  |  9. Verificar perfiles almacenados       |" -ForegroundColor White
    Write-Host "  |  10. Perfiles Moviles (menu completo)    |" -ForegroundColor Cyan
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  0. Salir / Volver al menu anterior      |" -ForegroundColor Yellow
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    $opcion = Read-Host "  Selecciona una opcion"

    switch ($opcion) {
        "1"  { Instalar-Dependencias }
        "2"  { Promover-DomainController }
        "3"  { Crear-OUsYUsuarios }
        "4"  { Configurar-Horarios }
        "5"  { Configurar-PerfilesYFSRM }
        "6"  { Configurar-Apantallamiento }
        "7"  { Configurar-AppLocker }
        "8"  { Crear-UsuarioDinamico }
        "9"  { Ver-PerfilesAlmacenados }
        "10" {
            # Llamar al script de perfiles moviles que SI funciono
            $scriptPerfiles = "$PSScriptRoot\perfiles_moviles_p8.ps1"
            if (Test-Path $scriptPerfiles) {
                Write-Host "`n  [INFO] Abriendo menu de Perfiles Moviles...`n" -ForegroundColor Cyan
                & $scriptPerfiles
            } else {
                Write-Host ""
                Write-Host "  [ERROR] No se encontro perfiles_moviles_p8.ps1 en:" -ForegroundColor Red
                Write-Host "  $PSScriptRoot" -ForegroundColor Red
                Write-Host "  Asegurate de que el archivo este en la misma carpeta." -ForegroundColor Yellow
                Write-Host ""
                Start-Sleep -Seconds 3
            }
        }
        "0"  { Write-Host "`n  Saliendo / Volviendo al menu anterior...`n" -ForegroundColor Yellow }
        default { Write-Host "`n  Opcion invalida." -ForegroundColor Red; pause }
    }

} while ($opcion -ne "0")
