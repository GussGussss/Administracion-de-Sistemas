# ============================================================
# ssl_funciones.ps1
# Funciones SSL/TLS para Windows - Practica 7
# Cubre: IIS (HTTPS), Apache (HTTPS), Nginx (HTTPS), IIS-FTP (FTPS)
# Ejecutar como Administrador
# ============================================================

# ------------------------------------------------------------
# Variables globales SSL
# ------------------------------------------------------------
$global:SSL_DOMAIN   = "www.reprobados.com"
$global:SSL_CERT_DIR = "C:\SSL_Certs"
$global:SSL_DAYS     = 365

# ------------------------------------------------------------
# Funcion: crear carpeta de certificados
# ------------------------------------------------------------
function Inicializar-DirectorioSSL {
    if (-not (Test-Path $global:SSL_CERT_DIR)) {
        New-Item -ItemType Directory -Path $global:SSL_CERT_DIR -Force | Out-Null
    }
    Write-Host "Directorio SSL: $global:SSL_CERT_DIR" -ForegroundColor Gray
}

# ============================================================
# GENERACION DE CERTIFICADOS
# ============================================================

# ------------------------------------------------------------
# Funcion: generar certificado autofirmado con PowerShell
# Retorna el thumbprint del certificado generado
# ------------------------------------------------------------
function Generar-Certificado {
    param(
        [string]$Servicio,
        [string]$Dominio = $global:SSL_DOMAIN
    )

    Inicializar-DirectorioSSL

    Write-Host ""
    Write-Host "Generando certificado autofirmado para $Servicio..." -ForegroundColor Cyan
    Write-Host "  Dominio : $Dominio" -ForegroundColor Gray
    Write-Host "  Validez : $global:SSL_DAYS dias" -ForegroundColor Gray

    # Eliminar certificado anterior del mismo dominio si existe
    Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -like "*$Dominio*" -and $_.FriendlyName -like "*$Servicio*" } |
        Remove-Item -ErrorAction SilentlyContinue

    # Generar nuevo certificado en el almacen de Windows
    $cert = New-SelfSignedCertificate `
        -DnsName $Dominio `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddDays($global:SSL_DAYS) `
        -FriendlyName "P7-SSL-$Servicio" `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256

    if (-not $cert) {
        Write-Host "ERROR: No se pudo generar el certificado." -ForegroundColor Red
        return $null
    }

    Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray

    # Exportar a archivos .pfx, .cer y .key para Apache/Nginx
    $pfxPath = "$global:SSL_CERT_DIR\$Servicio.pfx"
    $cerPath = "$global:SSL_CERT_DIR\$Servicio.cer"
    $crtPath = "$global:SSL_CERT_DIR\$Servicio.crt"
    $keyPath = "$global:SSL_CERT_DIR\$Servicio.key"

    # Exportar PFX (con clave privada, para IIS y FTP)
    $pfxPassword = ConvertTo-SecureString "P7reprobados2024!" -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pfxPassword | Out-Null

    # Exportar CER (solo clave publica, para referencia)
    Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null

    # Exportar CRT y KEY legibles por Apache/Nginx usando openssl si esta disponible
    $opensslPath = Buscar-OpenSSL
    if ($opensslPath) {
        $pfxPasswordPlain = "P7reprobados2024!"

        # Exportar certificado en PEM (crt)
        & $opensslPath pkcs12 -in $pfxPath -clcerts -nokeys -out $crtPath `
            -passin "pass:$pfxPasswordPlain" 2>$null

        # Exportar clave privada en PEM (key)
        & $opensslPath pkcs12 -in $pfxPath -nocerts -nodes -out $keyPath `
            -passin "pass:$pfxPasswordPlain" 2>$null

        Write-Host "  Archivos exportados: .pfx / .cer / .crt / .key" -ForegroundColor Gray
    } else {
        Write-Host "  OpenSSL no encontrado. Solo se exportaron .pfx y .cer" -ForegroundColor Yellow
        Write-Host "  Apache y Nginx usaran el .pfx convertido manualmente." -ForegroundColor Yellow
    }

    Write-Host "Certificado generado correctamente." -ForegroundColor Green
    return $cert.Thumbprint
}

# ------------------------------------------------------------
# Funcion: buscar openssl en rutas comunes de Windows
# ------------------------------------------------------------
function Buscar-OpenSSL {
    $rutas = @(
        "C:\Program Files\OpenSSL-Win64\bin\openssl.exe",
        "C:\Program Files\OpenSSL\bin\openssl.exe",
        "C:\OpenSSL-Win64\bin\openssl.exe",
        "C:\Tools\OpenSSL\bin\openssl.exe"
    )

    foreach ($ruta in $rutas) {
        if (Test-Path $ruta) { return $ruta }
    }

    # Buscar en PATH
    $enPath = Get-Command openssl -ErrorAction SilentlyContinue
    if ($enPath) { return $enPath.Source }

    # Buscar con Chocolatey
    $chocoOpenSSL = "C:\ProgramData\chocolatey\lib\openssl\tools\openssl.exe"
    if (Test-Path $chocoOpenSSL) { return $chocoOpenSSL }

    return $null
}

# ------------------------------------------------------------
# Funcion: instalar OpenSSL si no esta disponible
# ------------------------------------------------------------
function Instalar-OpenSSL {
    Write-Host "Instalando OpenSSL via Chocolatey..." -ForegroundColor Cyan

    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Chocolatey no disponible. No se puede instalar OpenSSL automaticamente." -ForegroundColor Yellow
        Write-Host "Descargalo manualmente desde: https://slproweb.com/products/Win32OpenSSL.html" -ForegroundColor Yellow
        return $false
    }

    choco install openssl --yes --no-progress 2>&1 | Out-Null
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    if (Buscar-OpenSSL) {
        Write-Host "OpenSSL instalado correctamente." -ForegroundColor Green
        return $true
    }

    Write-Host "No se pudo verificar la instalacion de OpenSSL." -ForegroundColor Yellow
    return $false
}

# ============================================================
# SSL PARA IIS (HTTPS)
# ============================================================

# ------------------------------------------------------------
# Funcion: configurar HTTPS en IIS
# - Genera certificado
# - Agrega binding en puerto 443
# - Configura redireccion HTTP -> HTTPS
# ------------------------------------------------------------
function Configurar-SSL-IIS {

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $siteName = "Default Web Site"

    Write-Host ""
    Write-Host "=== Configurando SSL en IIS ===" -ForegroundColor Cyan

    # Verificar que IIS esta instalado
    if (-not (Get-WindowsFeature Web-Server -ErrorAction SilentlyContinue).Installed) {
        Write-Host "ERROR: IIS no esta instalado." -ForegroundColor Red
        return $false
    }

    # Instalar modulo de reescritura si no esta (necesario para redireccion)
    Instalar-URLRewrite

    # Generar certificado
    $thumbprint = Generar-Certificado -Servicio "IIS"
    if (-not $thumbprint) { return $false }

    # Eliminar binding HTTPS anterior si existe
    Get-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue |
        Remove-WebBinding -ErrorAction SilentlyContinue

    # Agregar binding HTTPS en puerto 443
    New-WebBinding `
        -Name $siteName `
        -Protocol "https" `
        -Port 443 `
        -IPAddress "*" `
        -SslFlags 0 | Out-Null

    # Asociar el certificado al binding
    $binding = Get-WebBinding -Name $siteName -Protocol "https"
    $binding.AddSslCertificate($thumbprint, "My")

    # Configurar redireccion HTTP -> HTTPS en web.config
    Configurar-Redireccion-IIS -SiteName $siteName

    # Abrir puerto 443 en firewall
    Remove-NetFirewallRule -DisplayName "HTTPS-443-IIS" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "HTTPS-443-IIS" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 443 `
        -Action Allow | Out-Null

    iisreset /restart | Out-Null

    Write-Host "SSL configurado en IIS." -ForegroundColor Green
    Write-Host "  HTTP  -> redirige a HTTPS" -ForegroundColor Gray
    Write-Host "  HTTPS -> https://$global:SSL_DOMAIN" -ForegroundColor Gray
    return $true
}

# ------------------------------------------------------------
# Funcion: configurar redireccion HTTP->HTTPS en IIS via web.config
# ------------------------------------------------------------
function Configurar-Redireccion-IIS {
    param([string]$SiteName)

    $webRoot    = "C:\inetpub\wwwroot"
    $webConfig  = "$webRoot\web.config"

    $contenido = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="HTTP a HTTPS" stopProcessing="true">
          <match url="(.*)" />
          <conditions>
            <add input="{HTTPS}" pattern="^OFF$" />
          </conditions>
          <action type="Redirect" url="https://{HTTP_HOST}/{R:1}"
                  redirectType="Permanent" />
        </rule>
      </rules>
    </rewrite>
    <httpProtocol>
      <customHeaders>
        <add name="Strict-Transport-Security" value="max-age=31536000" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@

    [System.IO.File]::WriteAllText($webConfig, $contenido, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Redireccion HTTP->HTTPS configurada en web.config" -ForegroundColor Gray
}

# ------------------------------------------------------------
# Funcion: instalar modulo URL Rewrite para IIS
# ------------------------------------------------------------
function Instalar-URLRewrite {
    $rewriteKey = "HKLM:\SOFTWARE\Microsoft\IIS Extensions\URL Rewrite"
    if (Test-Path $rewriteKey) {
        Write-Host "  URL Rewrite ya instalado." -ForegroundColor Gray
        return
    }

    Write-Host "  Instalando URL Rewrite para IIS..." -ForegroundColor Yellow

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install urlrewrite --yes --no-progress 2>&1 | Out-Null
        Write-Host "  URL Rewrite instalado via Chocolatey." -ForegroundColor Green
    } else {
        Write-Host "  URL Rewrite no encontrado. Descargalo desde:" -ForegroundColor Yellow
        Write-Host "  https://www.iis.net/downloads/microsoft/url-rewrite" -ForegroundColor Yellow
    }
}

# ============================================================
# SSL PARA APACHE (HTTPS)
# ============================================================

# ------------------------------------------------------------
# Funcion: configurar HTTPS en Apache
# - Activa mod_ssl
# - Escribe VirtualHost en puerto 443
# - Configura redireccion HTTP -> HTTPS
# ------------------------------------------------------------
function Configurar-SSL-Apache {

    # Localizar Apache
    $scriptDir  = Split-Path -Parent $MyInvocation.ScriptName
    if (Get-Command Encontrar-Base-Apache -ErrorAction SilentlyContinue) {
        $apacheBase = Encontrar-Base-Apache
    } else {
        $apacheBase = "C:\Apache24"
    }

    $apacheExe  = "$apacheBase\bin\httpd.exe"
    $confPath   = "$apacheBase\conf\httpd.conf"
    $sslConf    = "$apacheBase\conf\extra\httpd-ssl.conf"
    $crtPath    = "$global:SSL_CERT_DIR\Apache.crt"
    $keyPath    = "$global:SSL_CERT_DIR\Apache.key"
    $pfxPath    = "$global:SSL_CERT_DIR\Apache.pfx"

    Write-Host ""
    Write-Host "=== Configurando SSL en Apache ===" -ForegroundColor Cyan

    if (-not (Test-Path $apacheExe)) {
        Write-Host "ERROR: Apache no encontrado en $apacheBase" -ForegroundColor Red
        return $false
    }

    # Generar certificado
    $thumbprint = Generar-Certificado -Servicio "Apache"
    if (-not $thumbprint) { return $false }

    # Verificar que tenemos los archivos .crt y .key
    # Si OpenSSL no estaba disponible, intentar convertir ahora
    if (-not (Test-Path $crtPath) -or -not (Test-Path $keyPath)) {
        $opensslPath = Buscar-OpenSSL
        if (-not $opensslPath) {
            Write-Host "OpenSSL no encontrado. Intentando instalar..." -ForegroundColor Yellow
            Instalar-OpenSSL | Out-Null
            $opensslPath = Buscar-OpenSSL
        }

        if ($opensslPath -and (Test-Path $pfxPath)) {
            $pfxPass = "P7reprobados2024!"
            & $opensslPath pkcs12 -in $pfxPath -clcerts -nokeys -out $crtPath -passin "pass:$pfxPass" 2>$null
            & $opensslPath pkcs12 -in $pfxPath -nocerts -nodes  -out $keyPath -passin "pass:$pfxPass" 2>$null
        }
    }

    if (-not (Test-Path $crtPath) -or -not (Test-Path $keyPath)) {
        Write-Host "ERROR: No se encontraron $crtPath o $keyPath" -ForegroundColor Red
        Write-Host "Asegurate de tener OpenSSL instalado y vuelve a intentarlo." -ForegroundColor Yellow
        return $false
    }

    # Activar mod_ssl en httpd.conf
    $conf = Get-Content $confPath -Raw
    $conf = $conf -replace "#LoadModule ssl_module",      "LoadModule ssl_module"
    $conf = $conf -replace "#LoadModule socache_shmcb",   "LoadModule socache_shmcb"
    $conf = $conf -replace "#Include conf/extra/httpd-ssl.conf", "Include conf/extra/httpd-ssl.conf"
    [System.IO.File]::WriteAllText($confPath, $conf, [System.Text.UTF8Encoding]::new($false))

    # Obtener puerto HTTP actual de Apache
    $puertHttp = 80
    if ($conf -match "Listen (\d+)") { $puertHttp = [int]$matches[1] }

    # Escribir configuracion SSL
    $sslConfContent = @"
Listen 443

SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLProxyCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLProtocol all -SSLv3
SSLProxyProtocol all -SSLv3
SSLPassPhraseDialog builtin
SSLSessionCache shmcb:logs/ssl_scache(512000)
SSLSessionCacheTimeout 300

<VirtualHost *:443>
    DocumentRoot "${apacheBase}/htdocs"
    ServerName $global:SSL_DOMAIN

    SSLEngine on
    SSLCertificateFile    "$crtPath"
    SSLCertificateKeyFile "$keyPath"

    <FilesMatch "\.(cgi|shtml|phtml|php)$">
        SSLOptions +StdEnvVars
    </FilesMatch>

    Header always set Strict-Transport-Security "max-age=31536000"

    ErrorLog  "logs/ssl_error.log"
    CustomLog "logs/ssl_access.log" common
</VirtualHost>
"@
    [System.IO.File]::WriteAllText($sslConf, $sslConfContent, [System.Text.UTF8Encoding]::new($false))

    # Configurar redireccion HTTP -> HTTPS en httpd.conf
    Configurar-Redireccion-Apache -ApacheBase $apacheBase -PuertoHTTP $puertHttp

    # Abrir puerto 443 en firewall
    Remove-NetFirewallRule -DisplayName "HTTPS-443-Apache" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "HTTPS-443-Apache" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 443 `
        -Action Allow | Out-Null

    # Reiniciar Apache
    Stop-Service -Name "Apache2.4" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service -Name "Apache2.4" -ErrorAction SilentlyContinue

    Write-Host "SSL configurado en Apache." -ForegroundColor Green
    Write-Host "  HTTP  -> redirige a HTTPS" -ForegroundColor Gray
    Write-Host "  HTTPS -> https://$global:SSL_DOMAIN" -ForegroundColor Gray
    return $true
}

# ------------------------------------------------------------
# Funcion: configurar redireccion HTTP->HTTPS en Apache
# ------------------------------------------------------------
function Configurar-Redireccion-Apache {
    param(
        [string]$ApacheBase,
        [int]$PuertoHTTP
    )

    $confPath = "$ApacheBase\conf\httpd.conf"
    $conf     = Get-Content $confPath -Raw

    # Activar mod_rewrite si no esta activo
    $conf = $conf -replace "#LoadModule rewrite_module", "LoadModule rewrite_module"
    $conf = $conf -replace "#LoadModule headers_module", "LoadModule headers_module"

    # Agregar bloque de redireccion si no existe
    if ($conf -notmatch "RewriteEngine On") {
        $bloque = @"

<VirtualHost *:$PuertoHTTP>
    ServerName $global:SSL_DOMAIN
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>
"@
        $conf += $bloque
    }

    [System.IO.File]::WriteAllText($confPath, $conf, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Redireccion HTTP->HTTPS configurada en httpd.conf" -ForegroundColor Gray
}

# ============================================================
# SSL PARA NGINX (HTTPS)
# ============================================================

# ------------------------------------------------------------
# Funcion: configurar HTTPS en Nginx
# - Escribe bloque server en puerto 443
# - Configura redireccion HTTP -> HTTPS
# ------------------------------------------------------------
function Configurar-SSL-Nginx {

    $nginxBase = "C:\nginx"
    $confPath  = "$nginxBase\conf\nginx.conf"
    $crtPath   = "$global:SSL_CERT_DIR\Nginx.crt"
    $keyPath   = "$global:SSL_CERT_DIR\Nginx.key"
    $pfxPath   = "$global:SSL_CERT_DIR\Nginx.pfx"

    Write-Host ""
    Write-Host "=== Configurando SSL en Nginx ===" -ForegroundColor Cyan

    if (-not (Test-Path "$nginxBase\nginx.exe")) {
        Write-Host "ERROR: Nginx no encontrado en $nginxBase" -ForegroundColor Red
        return $false
    }

    # Generar certificado
    $thumbprint = Generar-Certificado -Servicio "Nginx"
    if (-not $thumbprint) { return $false }

    # Convertir PFX a CRT+KEY si es necesario
    if (-not (Test-Path $crtPath) -or -not (Test-Path $keyPath)) {
        $opensslPath = Buscar-OpenSSL
        if (-not $opensslPath) {
            Instalar-OpenSSL | Out-Null
            $opensslPath = Buscar-OpenSSL
        }

        if ($opensslPath -and (Test-Path $pfxPath)) {
            $pfxPass = "P7reprobados2024!"
            & $opensslPath pkcs12 -in $pfxPath -clcerts -nokeys -out $crtPath -passin "pass:$pfxPass" 2>$null
            & $opensslPath pkcs12 -in $pfxPath -nocerts -nodes  -out $keyPath -passin "pass:$pfxPass" 2>$null
        }
    }

    if (-not (Test-Path $crtPath) -or -not (Test-Path $keyPath)) {
        Write-Host "ERROR: Archivos de certificado no disponibles para Nginx." -ForegroundColor Red
        return $false
    }

    # Obtener puerto HTTP actual de Nginx
    $puertoHttp = 80
    if (Test-Path $confPath) {
        $confActual = Get-Content $confPath -Raw
        if ($confActual -match "listen\s+(\d+);") { $puertoHttp = [int]$matches[1] }
    }

    # Escribir nginx.conf con HTTP + HTTPS
    $crtPathNorm = $crtPath.Replace("\", "/")
    $keyPathNorm = $keyPath.Replace("\", "/")

    $nginxConf = @"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server_tokens off;

    server {
        listen       $puertoHttp;
        server_name  $global:SSL_DOMAIN;

        return 301 https://`$host`$request_uri;
    }

    server {
        listen       443 ssl;
        server_name  $global:SSL_DOMAIN;
        root         html;

        ssl_certificate     $crtPathNorm;
        ssl_certificate_key $keyPathNorm;

        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 10m;

        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";

        location / {
            index  index.html index.htm;
        }
    }
}
"@

    [System.IO.File]::WriteAllText($confPath, $nginxConf, [System.Text.UTF8Encoding]::new($false))

    # Abrir puerto 443 en firewall
    Remove-NetFirewallRule -DisplayName "HTTPS-443-Nginx" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "HTTPS-443-Nginx" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 443 `
        -Action Allow | Out-Null

    # Reiniciar Nginx
    taskkill /f /im nginx.exe 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden
    Start-Sleep -Seconds 2

    Write-Host "SSL configurado en Nginx." -ForegroundColor Green
    Write-Host "  HTTP  -> redirige a HTTPS" -ForegroundColor Gray
    Write-Host "  HTTPS -> https://$global:SSL_DOMAIN" -ForegroundColor Gray
    return $true
}

# ============================================================
# SSL PARA IIS-FTP (FTPS)
# ============================================================

# ------------------------------------------------------------
# Funcion: configurar FTPS en IIS-FTP
# - Genera certificado
# - Configura canal de control y datos con SSL
# - Requiere SSL para ambos canales
# ------------------------------------------------------------
function Configurar-SSL-FTP {

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $ftpSite = "FTP_SERVER"

    Write-Host ""
    Write-Host "=== Configurando FTPS en IIS-FTP ===" -ForegroundColor Cyan

    # Verificar que el sitio FTP existe
    if (-not (Get-WebSite $ftpSite -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: Sitio FTP '$ftpSite' no encontrado." -ForegroundColor Red
        Write-Host "Asegurate de haber ejecutado el script de P5 primero." -ForegroundColor Yellow
        return $false
    }

    # Generar certificado para FTP
    $thumbprint = Generar-Certificado -Servicio "FTP"
    if (-not $thumbprint) { return $false }

    # Abrir puerto 990 (FTPS implicito) en firewall
    Remove-NetFirewallRule -DisplayName "FTPS-990" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "FTPS-990" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 990 `
        -Action Allow | Out-Null

    # Configurar SSL en el sitio FTP via applicationHost.config
    $configPath = "C:\Windows\System32\inetsrv\config\applicationHost.config"
    $utf8NoBOM  = New-Object System.Text.UTF8Encoding $false
    $content    = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)

    # Reemplazar la politica SSL del sitio FTP
    # controlChannelPolicy="SslAllow"  -> SslRequire
    # dataChannelPolicy="SslAllow"     -> SslRequire
    $content = $content -replace `
        'controlChannelPolicy="SslAllow"\s+dataChannelPolicy="SslAllow"', `
        "controlChannelPolicy=`"SslRequire`" dataChannelPolicy=`"SslRequire`" serverCertHash=`"$thumbprint`""

    [System.IO.File]::WriteAllText($configPath, $content, $utf8NoBOM)

    # Asignar el certificado al binding del puerto 21
    $appcmd = "C:\Windows\System32\inetsrv\appcmd.exe"
    & $appcmd set site $ftpSite /ftpServer.security.ssl.serverCertHash:$thumbprint 2>$null

    Restart-Service ftpsvc -ErrorAction SilentlyContinue

    Write-Host "FTPS configurado en IIS-FTP." -ForegroundColor Green
    Write-Host "  Canal de control : SSL requerido" -ForegroundColor Gray
    Write-Host "  Canal de datos   : SSL requerido" -ForegroundColor Gray
    Write-Host "  Certificado      : $($thumbprint.Substring(0,16))..." -ForegroundColor Gray
    return $true
}

# ============================================================
# VERIFICACION DE SSL
# ============================================================

# ------------------------------------------------------------
# Funcion: verificar que un servicio responde en HTTPS/FTPS
# ------------------------------------------------------------
function Verificar-SSL {
    param(
        [string]$Servicio,
        [int]$Puerto,
        [string]$Protocolo = "HTTPS"
    )

    Write-Host "  Verificando $Protocolo en $Servicio (puerto $Puerto)..." -ForegroundColor Gray

    $resultado = Test-NetConnection `
        -ComputerName "127.0.0.1" `
        -Port $Puerto `
        -WarningAction SilentlyContinue

    if ($resultado.TcpTestSucceeded) {
        Write-Host "  OK $Servicio responde en puerto $Puerto ($Protocolo)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  FALLO $Servicio NO responde en puerto $Puerto ($Protocolo)" -ForegroundColor Red
        return $false
    }
}

# ------------------------------------------------------------
# Funcion: verificar certificado instalado en el almacen
# ------------------------------------------------------------
function Verificar-Certificado {
    param([string]$Servicio)

    $cert = Get-ChildItem Cert:\LocalMachine\My |
            Where-Object { $_.FriendlyName -like "*$Servicio*" } |
            Select-Object -First 1

    if ($cert) {
        $diasRestantes = ($cert.NotAfter - (Get-Date)).Days
        Write-Host "  Certificado $Servicio : OK (vence en $diasRestantes dias, dominio: $($cert.Subject))" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  Certificado $Servicio : NO ENCONTRADO" -ForegroundColor Red
        return $false
    }
}

# ------------------------------------------------------------
# Funcion: ejecutar verificacion completa de los 4 servicios
# Retorna hashtable con resultados para el reporte final
# ------------------------------------------------------------
function Verificar-SSL-Completo {

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " VERIFICACION SSL/TLS - RESUMEN" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    $resultados = @{}

    $verificaciones = @(
        @{ Servicio = "IIS";    Puerto = 443; Protocolo = "HTTPS" },
        @{ Servicio = "Apache"; Puerto = 443; Protocolo = "HTTPS" },
        @{ Servicio = "Nginx";  Puerto = 443; Protocolo = "HTTPS" },
        @{ Servicio = "FTP";    Puerto = 21;  Protocolo = "FTPS"  }
    )

    foreach ($v in $verificaciones) {
        Write-Host ""
        Write-Host "[ $($v.Servicio) ]" -ForegroundColor Yellow
        $certOk  = Verificar-Certificado -Servicio $v.Servicio
        $puertoOk = Verificar-SSL -Servicio $v.Servicio -Puerto $v.Puerto -Protocolo $v.Protocolo

        $resultados[$v.Servicio] = @{
            Certificado = $certOk
            Puerto      = $puertoOk
            Estado      = if ($certOk -and $puertoOk) { "OK" } else { "FALLO" }
        }
    }

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " RESULTADO FINAL" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($svc in $resultados.Keys) {
        $estado = $resultados[$svc].Estado
        $color  = if ($estado -eq "OK") { "Green" } else { "Red" }
        Write-Host "  $svc : $estado" -ForegroundColor $color
    }

    Write-Host ""
    return $resultados
}
