# ============================================================
#  main_p9.ps1 - Menu principal de la Practica 09
#  Enfoque  : Hardening, RBAC, FGPP y MFA
# ============================================================

# Importar todas las funciones
. "$PSScriptRoot\funciones_p9.ps1"

# Verificar que el script se ejecuta como Administrador
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n  ERROR: Debes ejecutar este script como Administrador.`n" -ForegroundColor Red
    exit 1
}

# Bucle principal del menu
do {
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |        PRACTICA 09 - HARDENING AD        |" -ForegroundColor Cyan
    Write-Host "  |        RBAC, FGPP, Auditoria y MFA       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  1. Preparar Entorno y Descargar MFA     |" -ForegroundColor White
    Write-Host "  |  2. Crear Usuarios de Administracion     |" -ForegroundColor White
    Write-Host "  |  3. Aplicar Permisos RBAC                |" -ForegroundColor White
    Write-Host "  |  4. Configurar FGPP                      |" -ForegroundColor White
    Write-Host "  |  5. Configurar Auditoria                 |" -ForegroundColor White
    Write-Host "  |  6. Instalar y Activar MFA               |" -ForegroundColor White
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  |  0. Salir                                |" -ForegroundColor Yellow
    Write-Host "  |                                          |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

   $opcion = Read-Host "  Selecciona una opcion"

    switch ($opcion) {
        "1" { Preparar-EntornoMFA }
        "2" { Crear-UsuariosAdmin }
        "3" { Aplicar-PermisosRBAC }
        "4" { Configurar-FGPP }
        "5" { Configurar-Auditoria }
        "6" { Instalar-MFA }
        "0" { Write-Host "`n  Saliendo...`n" -ForegroundColor Yellow }
        default { Write-Host "`n  Opcion invalida, intenta de nuevo." -ForegroundColor Red; pause }
    }
} while ($opcion -ne "0")
