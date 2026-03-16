# ============================================================
# ssl_config.ps1
# Configuracion SSL/TLS para servidores
# Practica 07
# ============================================================

Import-Module WebAdministration -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# FUNCION PRINCIPAL
# ------------------------------------------------------------

function Configurar-SSL {

    Write-Host ""
    Write-Host "CONFIGURACION SSL/TLS" -ForegroundColor Cyan
    Write-Host ""

    Crear-Certificado
    Configurar-IIS-SSL
    Configurar-Apache-SSL
    Configurar-Nginx-SSL
    Configurar-FTP-SSL

}

# ------------------------------------------------------------
# CREAR CERTIFICADO AUTOFIRMADO
# ------------------------------------------------------------

function Crear-Certificado {

    Write-Host "Generando certificado SSL..." -ForegroundColor Yellow

    $cert = New-SelfSignedCertificate `
        -DnsName "reprobados.com" `
        -CertStoreLocation "Cert:\LocalMachine\My"

    Write-Host "Certificado creado correctamente." -ForegroundColor Green

    return $cert
}

# ------------------------------------------------------------
# CONFIGURAR IIS HTTPS
# ------------------------------------------------------------

function Configurar-IIS-SSL {

    Write-Host ""
    Write-Host "Configurando HTTPS en IIS..." -ForegroundColor Yellow

    try {

        Import-Module WebAdministration

        $site = "Default Web Site"

        New-WebBinding `
            -Name $site `
            -Protocol https `
            -Port 443 `
            -IPAddress "*"

        Write-Host "HTTPS habilitado en IIS." -ForegroundColor Green

    }
    catch {

        Write-Host "IIS no encontrado o no instalado." -ForegroundColor Red

    }
}

# ------------------------------------------------------------
# CONFIGURAR APACHE SSL
# ------------------------------------------------------------

function Configurar-Apache-SSL {

    $apacheConf = "C:\Apache24\conf\httpd.conf"

    if (Test-Path $apacheConf) {

        Write-Host ""
        Write-Host "Configurando SSL en Apache..." -ForegroundColor Yellow

        Add-Content $apacheConf "LoadModule ssl_module modules/mod_ssl.so"
        Add-Content $apacheConf "Listen 443"

        Write-Host "Configuracion SSL agregada a Apache." -ForegroundColor Green
    }
}

# ------------------------------------------------------------
# CONFIGURAR NGINX SSL
# ------------------------------------------------------------

function Configurar-Nginx-SSL {

    $nginxConf = "C:\nginx\conf\nginx.conf"

    if (Test-Path $nginxConf) {

        Write-Host ""
        Write-Host "Configurando SSL en Nginx..." -ForegroundColor Yellow

        Write-Host "Debe agregarse manualmente un bloque SSL en nginx.conf"

        Write-Host "Ejemplo:"
        Write-Host "server {"
        Write-Host " listen 443 ssl;"
        Write-Host " ssl_certificate cert.pem;"
        Write-Host " ssl_certificate_key key.pem;"
        Write-Host "}"

    }
}

# ------------------------------------------------------------
# CONFIGURAR FTPS (IIS FTP)
# ------------------------------------------------------------

function Configurar-FTP-SSL {

    Write-Host ""
    Write-Host "Configurando FTPS..." -ForegroundColor Yellow

    try {

        Set-ItemProperty `
        "IIS:\Sites\FTP_SERVER" `
        -Name ftpServer.security.ssl.controlChannelPolicy `
        -Value "SslAllow"

        Set-ItemProperty `
        "IIS:\Sites\FTP_SERVER" `
        -Name ftpServer.security.ssl.dataChannelPolicy `
        -Value "SslAllow"

        Write-Host "FTPS habilitado." -ForegroundColor Green

    }
    catch {

        Write-Host "FTP IIS no encontrado." -ForegroundColor Red

    }

}
