# ============================================================
# http_installer.ps1
# Instalacion de servidores HTTP desde repositorios WEB
# Practica 07
# ============================================================

# ------------------------------------------------------------
# MENU HTTP
# ------------------------------------------------------------

function Instalar-HTTP-Web {

    while ($true) {

        Write-Host ""
        Write-Host "====================================" -ForegroundColor Cyan
        Write-Host " INSTALACION DE SERVIDORES HTTP" -ForegroundColor Cyan
        Write-Host "====================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "1) IIS"
        Write-Host "2) Apache HTTP Server"
        Write-Host "3) Nginx"
        Write-Host "4) Volver"
        Write-Host ""

        $op = Read-Host "Seleccione servidor"

        switch ($op) {

            "1" { Instalar-IIS-Web }

            "2" { Instalar-Apache-Web }

            "3" { Instalar-Nginx-Web }

            "4" { return }

            default {
                Write-Host "Opcion invalida." -ForegroundColor Red
            }
        }
    }
}

# ------------------------------------------------------------
# INSTALAR IIS
# ------------------------------------------------------------

function Instalar-IIS-Web {

    Write-Host ""
    Write-Host "Instalando IIS..." -ForegroundColor Yellow

    Install-WindowsFeature `
        -Name Web-Server `
        -IncludeManagementTools

    Start-Service W3SVC

    Write-Host "IIS instalado correctamente." -ForegroundColor Green
}

# ------------------------------------------------------------
# INSTALAR APACHE
# ------------------------------------------------------------

function Instalar-Apache-Web {

    Write-Host ""
    Write-Host "Instalando Apache HTTP Server..." -ForegroundColor Yellow

    $version = "2.4.58"

    $url = "https://www.apachelounge.com/download/VS17/binaries/httpd-$version-win64-VS17.zip"

    $dest = "$env:TEMP\apache.zip"

    Invoke-WebRequest `
        -Uri $url `
        -OutFile $dest

    Expand-Archive `
        -Path $dest `
        -DestinationPath "C:\"

    Rename-Item `
        "C:\Apache24" `
        -NewName "Apache24"

    Write-Host "Apache instalado en C:\Apache24" -ForegroundColor Green
}

# ------------------------------------------------------------
# INSTALAR NGINX
# ------------------------------------------------------------

function Instalar-Nginx-Web {

    Write-Host ""
    Write-Host "Instalando Nginx..." -ForegroundColor Yellow

    $version = "1.26.0"

    $url = "https://nginx.org/download/nginx-$version.zip"

    $dest = "$env:TEMP\nginx.zip"

    Invoke-WebRequest `
        -Uri $url `
        -OutFile $dest

    Expand-Archive `
        -Path $dest `
        -DestinationPath "C:\"

    Rename-Item `
        "C:\nginx-$version" `
        -NewName "nginx"

    Write-Host "Nginx instalado en C:\nginx" -ForegroundColor Green
}
