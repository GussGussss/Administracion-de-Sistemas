# ============================================================
# main_p7.ps1
# Practica 7: Infraestructura de Despliegue Seguro e Instalacion Hibrida
# Windows Server 2019 Core (sin GUI) - PowerShell
# Ejecutar como Administrador
#
# Integra:
#   - Practica 5: Servidor FTP (IIS-FTP) como fuente de binarios
#   - Practica 6: Instalacion de servidores HTTP (IIS, Apache, Nginx)
#   - Nuevo P7:   SSL/TLS en 4 servicios + FTPS + Hash SHA256
# ============================================================

# ── Verificar ejecucion como Administrador ────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecutar este script como Administrador." -ForegroundColor Red
    exit 1
}

# ── Cargar funciones P7 y P6 ──────────────────────────────────────────────────
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

if (Test-Path "$scriptDir\funciones_p7.ps1") {
    . "$scriptDir\funciones_p7.ps1"
} else {
    Write-Host "ERROR: No se encuentra funciones_p7.ps1 en $scriptDir" -ForegroundColor Red
    exit 1
}

# Cargar funciones de P6 si estan disponibles (Instalar-IIS, Instalar-Apache, Instalar-Nginx)
$funcionesP6 = "$scriptDir\funciones.ps1"
if (Test-Path $funcionesP6) {
    . $funcionesP6
    Write-Host "Funciones P6 cargadas correctamente." -ForegroundColor Gray
} else {
    Write-Host "ADVERTENCIA: funciones.ps1 (P6) no encontrado. Instalacion WEB no disponible." -ForegroundColor Yellow
}

# ============================================================
# FUNCION: Flujo completo para un servicio HTTP
# 1) Elige fuente (Web/FTP)
# 2) Instala
# 3) Pregunta SSL
# ============================================================
function Flujo-Servicio-HTTP {
    param([string]$Servicio)

    $fuente = Menu-Fuente-Instalacion -Servicio $Servicio

    if ($fuente -eq "1") {
        # ── WEB: Delegar a funciones de P6 ───────────────────────────────────
        Write-Host ""
        Write-Host "Instalacion WEB seleccionada para $Servicio." -ForegroundColor Cyan

        switch ($Servicio) {
            "IIS" {
                if (Get-Command Listar-Versiones-IIS -ErrorAction SilentlyContinue) {
                    Listar-Versiones-IIS
                    $verNum  = Leer-Opcion -Prompt "Seleccione version [1-2]: " -Validas @("1","2")
                    $version = "10.0"
                    $puerto  = Leer-Puerto-P7
                    Instalar-IIS -Version $version -Puerto $puerto
                    Log-Resumen -Servicio "IIS" -Accion "Instalacion-WEB" -Estado "OK" -Detalle "v$version puerto $puerto"
                } else {
                    Write-Host "Funcion Instalar-IIS no disponible (requiere funciones.ps1 de P6)." -ForegroundColor Red
                    Log-Resumen -Servicio "IIS" -Accion "Instalacion-WEB" -Estado "ERROR" -Detalle "P6 no cargado"
                }
            }
            "Apache" {
                if (Get-Command Listar-Versiones-Apache -ErrorAction SilentlyContinue) {
                    Listar-Versiones-Apache
                    $verNum  = Leer-Opcion -Prompt "Seleccione version [1-3]: " -Validas @("1","2","3")
                    $version = switch ($verNum) {
                        "1" { $global:APACHE_LATEST }
                        "2" { $global:APACHE_LTS }
                        "3" { $global:APACHE_OLDEST }
                    }
                    $puerto = Leer-Puerto-P7
                    Instalar-Apache -Version $version -Puerto $puerto
                    Log-Resumen -Servicio "Apache" -Accion "Instalacion-WEB" -Estado "OK" -Detalle "v$version puerto $puerto"
                } else {
                    Write-Host "Funcion Instalar-Apache no disponible (requiere funciones.ps1 de P6)." -ForegroundColor Red
                    Log-Resumen -Servicio "Apache" -Accion "Instalacion-WEB" -Estado "ERROR" -Detalle "P6 no cargado"
                }
            }
            "Nginx" {
                if (Get-Command Listar-Versiones-Nginx -ErrorAction SilentlyContinue) {
                    Listar-Versiones-Nginx
                    $verNum  = Leer-Opcion -Prompt "Seleccione version [1-3]: " -Validas @("1","2","3")
                    $version = switch ($verNum) {
                        "1" { $global:NGINX_LATEST }
                        "2" { $global:NGINX_LTS }
                        "3" { $global:NGINX_OLDEST }
                    }
                    $puerto = Leer-Puerto-P7
                    Instalar-Nginx -Version $version -Puerto $puerto
                    Log-Resumen -Servicio "Nginx" -Accion "Instalacion-WEB" -Estado "OK" -Detalle "v$version puerto $puerto"
                } else {
                    Write-Host "Funcion Instalar-Nginx no disponible (requiere funciones.ps1 de P6)." -ForegroundColor Red
                    Log-Resumen -Servicio "Nginx" -Accion "Instalacion-WEB" -Estado "ERROR" -Detalle "P6 no cargado"
                }
            }
        }
    }
    else {
        # ── FTP: Navegacion dinamica del repositorio privado ─────────────────
        Instalar-Desde-FTP -Servicio $Servicio
    }

    # ── Preguntar SSL para este servicio ─────────────────────────────────────
    if (Preguntar-SSL -Servicio $Servicio) {
        switch ($Servicio) {
            "IIS"    { Activar-SSL-IIS    }
            "Apache" { Activar-SSL-Apache }
            "Nginx"  { Activar-SSL-Nginx  }
        }
    }
}

# ============================================================
# LEER PUERTO (wrapper local para no depender de P6)
# ============================================================
function Leer-Puerto-P7 {
    while ($true) {
        Write-Host "Puerto de escucha: " -NoNewline
        $val = Read-Host
        if ($val -notmatch '^\d+$') { Write-Host "Debe ser un numero." -ForegroundColor Red; continue }
        $p = [int]$val
        if ($p -lt 1 -or $p -gt 65535) { Write-Host "Rango valido: 1-65535" -ForegroundColor Red; continue }
        $reservados = @(22,25,53,445,135,139,3389)
        if ($reservados -contains $p) { Write-Host "Puerto $p reservado por el sistema." -ForegroundColor Red; continue }
        return $p
    }
}

# ============================================================
# MENU PRINCIPAL
# ============================================================
while ($true) {

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "     PRACTICA 7 - Despliegue Seguro e Instalacion Hibrida      " -ForegroundColor Cyan
    Write-Host "           Windows Server 2019 | FTP + HTTP + SSL/TLS          " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "--- INSTALACION HIBRIDA (WEB o FTP) + SSL/TLS ---" -ForegroundColor Yellow
    Write-Host "  1) IIS    (Internet Information Services)"
    Write-Host "  2) Apache (Win64)"
    Write-Host "  3) Nginx  (Windows)"
    Write-Host ""
    Write-Host "--- SSL/TLS INDEPENDIENTE (sin reinstalar) ---" -ForegroundColor Yellow
    Write-Host "  4) Activar SSL en IIS"
    Write-Host "  5) Activar SSL en Apache"
    Write-Host "  6) Activar SSL en Nginx"
    Write-Host "  7) Activar FTPS en IIS-FTP (Practica 5)"
    Write-Host ""
    Write-Host "--- UTILIDADES ---" -ForegroundColor Yellow
    Write-Host "  8) Verificar todos los servicios (puertos)"
    Write-Host "  9) Mostrar resumen final"
    Write-Host "  0) Salir"
    Write-Host ""

    $op = Leer-Opcion -Prompt "Seleccione opcion [0-9]: " -Validas @("0","1","2","3","4","5","6","7","8","9")

    switch ($op) {

        "1" { Flujo-Servicio-HTTP -Servicio "IIS"    }
        "2" { Flujo-Servicio-HTTP -Servicio "Apache" }
        "3" { Flujo-Servicio-HTTP -Servicio "Nginx"  }

        "4" { Activar-SSL-IIS    }
        "5" { Activar-SSL-Apache }
        "6" { Activar-SSL-Nginx  }
        "7" {
            Write-Host ""
            $dominioFTP = Leer-Texto -Prompt "Dominio para el certificado FTPS (Enter = www.reprobados.com): "
            if ([string]::IsNullOrWhiteSpace($dominioFTP)) { $dominioFTP = "www.reprobados.com" }
            Activar-SSL-FTP-IIS -Dominio $dominioFTP
        }

        "8" { Verificar-Todos-Los-Servicios }
        "9" { Mostrar-Resumen }

        "0" {
            Write-Host ""
            Write-Host "Generando resumen final antes de salir..." -ForegroundColor Cyan
            Verificar-Todos-Los-Servicios
            Mostrar-Resumen
            Write-Host "Saliendo de Practica 7." -ForegroundColor Yellow
            exit 0
        }
    }
}
