# ============================================================
#  main_p9.ps1 -- Menu principal Practica 09
#  Hardening AD, RBAC, FGPP, Auditoria y MFA
# ============================================================
. "$PSScriptRoot\funciones_p9.ps1"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n  [ERROR] Ejecuta este script como Administrador.`n" -ForegroundColor Red
    exit 1
}
do {
    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |     PRACTICA 09 - HARDENING AD             |" -ForegroundColor Cyan
    Write-Host "  |     RBAC - FGPP - Auditoria - MFA          |" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |                                            |" -ForegroundColor Cyan
    Write-Host "  |  1. Preparar entorno y descargar MFA       |" -ForegroundColor White
    Write-Host "  |  2. Crear usuarios de administracion       |" -ForegroundColor White
    Write-Host "  |  3. Aplicar permisos RBAC (delegacion)     |" -ForegroundColor White
    Write-Host "  |  4. Configurar FGPP (politicas contrasena) |" -ForegroundColor White
    Write-Host "  |  5. Configurar auditoria y generar reporte |" -ForegroundColor White
    Write-Host "  |  6. Instalar dependencias y motor MFA      |" -ForegroundColor White
    Write-Host "  |  7. Activar MFA y generar clave celular    |" -ForegroundColor White
    Write-Host "  |  8. Ejecutar tests de evaluacion           |" -ForegroundColor Yellow
    Write-Host "  |                                            |" -ForegroundColor Cyan
    Write-Host "  |  9. Ir al menu Practica 08                 |" -ForegroundColor Magenta
    Write-Host "  |     (P08 + Perfiles Moviles)               |" -ForegroundColor DarkMagenta
    Write-Host "  |                                            |" -ForegroundColor Cyan
    Write-Host "  |  0. Salir                                  |" -ForegroundColor Red
    Write-Host "  |                                            |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan
    $opcion = Read-Host "  Selecciona una opcion"
    switch ($opcion) {
        '1' { Preparar-EntornoMFA }
        '2' { Crear-UsuariosAdmin }
        '3' { Aplicar-PermisosRBAC }
        '4' { Configurar-FGPP }
        '5' { Configurar-Auditoria }
        '6' { Instalar-MFA }
        '7' { Activar-MFA }
        '8' { Ejecutar-Tests }
        '9' {
            $scriptP8 = "$PSScriptRoot\main_p8.ps1"
            if (Test-Path $scriptP8) {
                # Detener AppIDSvc antes de ir a P8 para evitar conflictos
                Write-Host "`n  [INFO] Deteniendo AppIDSvc para evitar conflictos..." -ForegroundColor Yellow
                sc.exe stop AppIDSvc 2>$null | Out-Null
                sc.exe config AppIDSvc start= demand 2>$null | Out-Null
                Write-Host "  [OK] AppIDSvc detenido." -ForegroundColor Green
                Write-Host "  [INFO] Abriendo menu Practica 08...`n" -ForegroundColor Cyan
                & $scriptP8
            } else {
                Write-Host "`n  [ERROR] No se encontro main_p8.ps1 en:" -ForegroundColor Red
                Write-Host "  $PSScriptRoot" -ForegroundColor Red
                Write-Host "  Asegurate de que todos los scripts esten en la misma carpeta." -ForegroundColor Yellow
                Start-Sleep -Seconds 3
            }
        }
        '0' { Write-Host "`n  Saliendo. Buen trabajo!" -ForegroundColor Green }
        default {
            Write-Host "`n  [ERROR] Opcion no valida." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($opcion -ne '0')
