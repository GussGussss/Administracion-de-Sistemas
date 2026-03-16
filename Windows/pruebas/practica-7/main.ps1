# ============================================================
# main.ps1
# ORQUESTADOR - Infraestructura de Despliegue Seguro
# Practica 07
# ============================================================

# ------------------------------------------------------------
# Verificar ejecucion como Administrador
# ------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal] `
[Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
[Security.Principal.WindowsBuiltInRole] "Administrator")) {

    Write-Host ""
    Write-Host "ERROR: Ejecutar PowerShell como Administrador." -ForegroundColor Red
    exit
}

# ------------------------------------------------------------
# Cargar modulos del sistema
# ------------------------------------------------------------

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

. "$scriptDir\ftp_client.ps1"
. "$scriptDir\http_installer.ps1"
. "$scriptDir\hash_validator.ps1"
. "$scriptDir\ssl_config.ps1"
. "$scriptDir\verify_installation.ps1"

# ------------------------------------------------------------
# Menu principal
# ------------------------------------------------------------
function Mostrar-Menu {

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  ORQUESTADOR DE DESPLIEGUE SEGURO" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) Instalar servidor HTTP desde WEB"
    Write-Host "2) Instalar servidor HTTP desde FTP"
    Write-Host "3) Configurar SSL/TLS en servicios"
    Write-Host "4) Verificar instalaciones"
    Write-Host "5) Salir"
    Write-Host ""
}

# ------------------------------------------------------------
# Bucle principal
# ------------------------------------------------------------

while ($true) {

    Mostrar-Menu

    $opcion = Read-Host "Seleccione una opcion"

    switch ($opcion) {

        # ----------------------------------------------------
        # Instalacion WEB
        # ----------------------------------------------------
        "1" {

            Write-Host ""
            Write-Host "Instalacion desde repositorio WEB..." -ForegroundColor Yellow

            Instalar-HTTP-Web

        }

        # ----------------------------------------------------
        # Instalacion FTP
        # ----------------------------------------------------
        "2" {

            Write-Host ""
            Write-Host "Instalacion desde repositorio FTP..." -ForegroundColor Yellow

            Instalar-HTTP-FTP

        }

        # ----------------------------------------------------
        # Configurar SSL
        # ----------------------------------------------------
        "3" {

            Write-Host ""
            Write-Host "Configurando SSL/TLS..." -ForegroundColor Yellow

            Configurar-SSL

        }

        # ----------------------------------------------------
        # Verificacion final
        # ----------------------------------------------------
        "4" {

            Write-Host ""
            Write-Host "Verificando servicios..." -ForegroundColor Yellow

            Verificar-Servicios

        }

        # ----------------------------------------------------
        # Salir
        # ----------------------------------------------------
        "5" {

            Write-Host ""
            Write-Host "Saliendo..." -ForegroundColor Yellow
            exit
        }

        default {

            Write-Host ""
            Write-Host "Opcion invalida." -ForegroundColor Red
        }
    }
}
