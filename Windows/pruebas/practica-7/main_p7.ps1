# ================================================================
# main_p7.ps1
# Practica 7 - Infraestructura de Despliegue Seguro e Instalacion
# Hibrida (FTP/Web) - Windows Server 2019/2022 - PowerShell
#
# Uso: Ejecutar como Administrador
# Estructura:
#   main_p7.ps1      <- este archivo (solo el menu)
#   funciones_p7.ps1 <- toda la logica
#   ftp.ps1          <- Practica 5 (debe ejecutarse antes para tener FTP)
# ================================================================

# Verificar Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecutar este script como Administrador." -ForegroundColor Red
    exit 1
}

# Cargar funciones
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rutaFunciones = "$scriptDir\funciones_p7.ps1"

if (-not (Test-Path $rutaFunciones)) {
    Write-Host "ERROR: No se encuentra funciones_p7.ps1 en $scriptDir" -ForegroundColor Red
    exit 1
}
. $rutaFunciones

# ================================================================
# MENU PRINCIPAL
# ================================================================
while ($true) {

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  PRACTICA 7 - Despliegue Seguro e Instalacion Hibrida         " -ForegroundColor Cyan
    Write-Host "  Windows Server 2019/2022 | FTP + HTTP + SSL/TLS              " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  -- SERVIDOR FTP LOCAL --" -ForegroundColor Yellow
    Write-Host "  1) Administrar servidor FTP"
    Write-Host "     (Instalar, configurar, crear usuarios, grupos)"
    Write-Host ""
    Write-Host "  -- DEPENDENCIAS --" -ForegroundColor Yellow
    Write-Host "  2) Instalar dependencias (Chocolatey / OpenSSL)"
    Write-Host ""
    Write-Host "  -- REPOSITORIO FTP --" -ForegroundColor Yellow
    Write-Host "  3) Preparar repositorio FTP"
    Write-Host "     (Descarga ZIPs de Apache/Nginx y genera .sha256)"
    Write-Host ""
    Write-Host "  -- INSTALACION HIBRIDA (WEB o FTP) --" -ForegroundColor Yellow
    Write-Host "  4) Instalar IIS"
    Write-Host "  5) Instalar Apache"
    Write-Host "  6) Instalar Nginx"
    Write-Host ""
    Write-Host "  -- SSL/TLS --" -ForegroundColor Yellow
    Write-Host "  7) Activar SSL en IIS    (HTTPS puerto 443)"
    Write-Host "  8) Activar SSL en Apache (HTTPS puerto 443 + redireccion)"
    Write-Host "  9) Activar SSL en Nginx  (HTTPS puerto 443 + redireccion)"
    Write-Host " 10) Activar FTPS en IIS-FTP"
    Write-Host ""
    Write-Host "  -- UTILIDADES --" -ForegroundColor Yellow
    Write-Host " 11) Ver estado de todos los servicios"
    Write-Host " 12) Mostrar resumen final (evidencias)"
    Write-Host " 13) Iniciar / Detener servicios"
    Write-Host "  0) Salir"
    Write-Host ""

    $op = Leer-Opcion -Prompt "Seleccione opcion" -Validas @("0","1","2","3","4","5","6","7","8","9","10","11","12","13")

    switch ($op) {
        "1"  { Menu-Administrar-FTP }
        "2"  { Menu-Dependencias }
        "3"  { Preparar-Repositorio-FTP }
        "4"  { Flujo-Instalar-Servicio -Servicio "IIS" }
        "5"  { Flujo-Instalar-Servicio -Servicio "Apache" }
        "6"  { Flujo-Instalar-Servicio -Servicio "Nginx" }
        "7"  { Activar-SSL-IIS }
        "8"  { Activar-SSL-Apache }
        "9"  { Activar-SSL-Nginx }
        "10" { Activar-FTPS-IIS }
        "11" { Ver-Estado-Servicios }
        "12" { Mostrar-Resumen-Final }
        "13" { Gestionar-Servicios-HTTP }
        "0"  {
            Write-Host ""
            Write-Host "Generando resumen antes de salir..." -ForegroundColor Cyan
            Mostrar-Resumen-Final
            Write-Host "Saliendo." -ForegroundColor Yellow
            exit 0
        }
    }
}
