# ============================================================
# ftp_server.ps1
# Instalacion y configuracion del servidor FTP
# Practica 07
# ============================================================

Import-Module ServerManager
Import-Module WebAdministration

$ftpRoot = "C:\FTP_REPOSITORY"
$ftpSite = "FTP_SERVER"

# ------------------------------------------------------------
# INSTALAR SERVICIO FTP
# ------------------------------------------------------------

function Instalar-FTP-Servidor {

    Write-Host ""
    Write-Host "Instalando servidor FTP..." -ForegroundColor Yellow

    $features = @(
        "Web-Server",
        "Web-FTP-Server",
        "Web-FTP-Service",
        "Web-FTP-Ext"
    )

    foreach ($f in $features) {

        if (!(Get-WindowsFeature $f).Installed) {

            Install-WindowsFeature $f -IncludeManagementTools
        }
    }

    Start-Service W3SVC
    Start-Service ftpsvc

    Write-Host "Servicio FTP instalado." -ForegroundColor Green
}

# ------------------------------------------------------------
# CREAR ESTRUCTURA DEL REPOSITORIO
# ------------------------------------------------------------

function Crear-Repositorio-FTP {

    Write-Host ""
    Write-Host "Creando estructura del repositorio..." -ForegroundColor Yellow

    $paths = @(
        "$ftpRoot",
        "$ftpRoot\http",
        "$ftpRoot\http\Windows",
        "$ftpRoot\http\Windows\Apache",
        "$ftpRoot\http\Windows\Nginx",
        "$ftpRoot\http\Windows\Tomcat"
    )

    foreach ($p in $paths) {

        if (-not (Test-Path $p)) {

            New-Item $p -ItemType Directory | Out-Null
        }
    }

    Write-Host "Repositorio creado en $ftpRoot" -ForegroundColor Green
}

# ------------------------------------------------------------
# CONFIGURAR SITIO FTP
# ------------------------------------------------------------

function Configurar-Sitio-FTP {

    Write-Host ""
    Write-Host "Configurando sitio FTP..." -ForegroundColor Yellow

    if (Get-WebSite $ftpSite -ErrorAction SilentlyContinue) {

        Remove-WebSite $ftpSite
    }

    New-WebFtpSite `
        -Name $ftpSite `
        -Port 21 `
        -PhysicalPath $ftpRoot `
        -Force

    Write-Host "Sitio FTP creado." -ForegroundColor Green
}

# ------------------------------------------------------------
# CONFIGURAR FIREWALL
# ------------------------------------------------------------

function Configurar-Firewall-FTP {

    Write-Host ""
    Write-Host "Configurando firewall FTP..." -ForegroundColor Yellow

    Remove-NetFirewallRule -DisplayName "FTP 21" -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName "FTP 21" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 21 `
        -Action Allow

    Write-Host "Puerto 21 abierto." -ForegroundColor Green
}

# ------------------------------------------------------------
# FUNCION PRINCIPAL
# ------------------------------------------------------------

function Preparar-Servidor-FTP {

    Instalar-FTP-Servidor
    Crear-Repositorio-FTP
    Configurar-Sitio-FTP
    Configurar-Firewall-FTP

    Write-Host ""
    Write-Host "Servidor FTP listo para usar como repositorio." -ForegroundColor Green
}
