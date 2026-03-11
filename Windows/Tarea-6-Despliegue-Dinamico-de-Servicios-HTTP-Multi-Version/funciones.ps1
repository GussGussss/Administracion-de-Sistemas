# ============================================================
# http_functions.ps1
# Funciones para despliegue de servidores HTTP en Windows
# Windows Server 2019 Core (sin GUI) - PowerShell
# ============================================================

# ============================================================
# Validar puerto
# ============================================================
function Validar-Puerto {
    param([string]$Puerto)

    if ($Puerto -notmatch '^\d+$') {
        Write-Host "Error: El puerto debe ser un numero entero." -ForegroundColor Red
        return $false
    }

    $p = [int]$Puerto

    if ($p -lt 1 -or $p -gt 65535) {
        Write-Host "Error: Puerto fuera de rango (1-65535)." -ForegroundColor Red
        return $false
    }

    # Puertos reservados del sistema
    $reservados = @(22, 25, 53, 3389, 445, 135, 139)
    if ($reservados -contains $p) {
        Write-Host "Error: Puerto $p reservado por el sistema." -ForegroundColor Red
        return $false
    }

    # Verificar si el puerto esta en uso
    $enUso = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
    if ($enUso.TcpTestSucceeded) {
        Write-Host "Error: El puerto $p ya esta en uso." -ForegroundColor Red
        return $false
    }

    return $true
}

# ============================================================
# Abrir puerto en firewall y cerrar puertos por defecto libres
# ============================================================
function Gestionar-Firewall {
    param([int]$Puerto)

    Write-Host "Configurando firewall para puerto $Puerto..." -ForegroundColor Cyan

    # Eliminar regla previa si existe
    Remove-NetFirewallRule -DisplayName "HTTP-Custom" -ErrorAction SilentlyContinue

    # Crear nueva regla
    New-NetFirewallRule `
        -DisplayName "HTTP-Custom" `
        -Direction Inbound `
        -LocalPort $Puerto `
        -Protocol TCP `
        -Action Allow `
        | Out-Null

    # Si el puerto no es 80, bloquear el 80 si no esta en uso
    if ($Puerto -ne 80) {
        $puerto80 = Test-NetConnection -ComputerName localhost -Port 80 -WarningAction SilentlyContinue
        if (-not $puerto80.TcpTestSucceeded) {
            Remove-NetFirewallRule -DisplayName "HTTP-Default-80" -ErrorAction SilentlyContinue
            New-NetFirewallRule `
                -DisplayName "HTTP-Default-80" `
                -Direction Inbound `
                -LocalPort 80 `
                -Protocol TCP `
                -Action Block `
                | Out-Null
            Write-Host "Puerto 80 bloqueado (no en uso)." -ForegroundColor Yellow
        }
    }

    Write-Host "Firewall configurado." -ForegroundColor Green
}

# ============================================================
# Verificar e instalar winget si no esta disponible
# ============================================================
function Verificar-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }

    Write-Host "winget no encontrado. Intentando instalar dependencias..." -ForegroundColor Yellow

    try {
        $vcLibUrl  = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $vcLibDest = "$env:TEMP\VCLibs.appx"
        Invoke-WebRequest -Uri $vcLibUrl -OutFile $vcLibDest -UseBasicParsing -ErrorAction Stop
        Add-AppxPackage -Path $vcLibDest -ErrorAction SilentlyContinue

        $wingetUrl  = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $wingetDest = "$env:TEMP\winget.msixbundle"
        Invoke-WebRequest -Uri $wingetUrl -OutFile $wingetDest -UseBasicParsing -ErrorAction Stop
        Add-AppxPackage -Path $wingetDest -ErrorAction SilentlyContinue

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "winget instalado correctamente." -ForegroundColor Green
            return $true
        }
    } catch {
        # Fallo de red o instalacion — se usaran versiones predefinidas
    }

    Write-Host "Se usaran versiones predefinidas (winget no disponible)." -ForegroundColor Yellow
    return $false
}

# ============================================================
# IIS: Listar versiones (IIS es del sistema, version fija)
# ============================================================
function Listar-Versiones-IIS {
    Write-Host ""
    Write-Host "Versiones disponibles de IIS:" -ForegroundColor Cyan
    Write-Host ""

    # IIS en Windows Server 2019 = IIS 10.0
    # Obtener version real si ya esta instalado
    $iisPath = "C:\Windows\System32\inetsrv\inetinfo.exe"
    if (Test-Path $iisPath) {
        $ver = (Get-Item $iisPath).VersionInfo.ProductVersion
    } else {
        $ver = "10.0 (Windows Server 2019)"
    }

    Write-Host "1) $ver  (Estable - incluida en Windows Server 2019)"
    Write-Host "2) $ver  (LTS - misma version de sistema)"
    Write-Host ""
    Write-Host "Nota: IIS se instala desde roles de Windows. La version depende del OS." -ForegroundColor Yellow
}

# ============================================================
# IIS: Instalar y configurar
# ============================================================
function Instalar-IIS {
    param(
        [string]$Version,
        [int]$Puerto
    )

    Write-Host "Instalando IIS (Internet Information Services)..." -ForegroundColor Cyan

    # Instalar rol IIS silenciosamente
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    Install-WindowsFeature -Name Web-Http-Redirect, Web-Http-Logging, Web-Security | Out-Null

    # Obtener version real instalada
    $iisPath = "C:\Windows\System32\inetsrv\inetinfo.exe"
    $Version = (Get-Item $iisPath -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
    if (-not $Version) { $Version = "10.0" }

    Write-Host "Configurando puerto $Puerto..." -ForegroundColor Cyan

    # Importar modulo WebAdministration
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Cambiar binding del sitio por defecto
    $siteName = "Default Web Site"
    Remove-WebBinding -Name $siteName -ErrorAction SilentlyContinue
    New-WebBinding -Name $siteName -Protocol "http" -Port $Puerto -IPAddress "*" | Out-Null

    # Crear index.html personalizado
    Crear-Index -Servicio "IIS" -Version $Version -Puerto $Puerto -Directorio "C:\inetpub\wwwroot"

    # Configurar seguridad IIS
    Configurar-Seguridad-IIS

    # Crear usuario restringido
    Crear-Usuario-Restringido -Servicio "IIS" -Directorio "C:\inetpub\wwwroot"

    # Reiniciar IIS
    iisreset /restart | Out-Null

    # Gestionar firewall
    Gestionar-Firewall -Puerto $Puerto

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " INSTALACION COMPLETADA              " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Servidor : IIS"
    Write-Host "Version  : $Version"
    Write-Host "Puerto   : $Puerto"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Seguridad IIS
# ============================================================
function Configurar-Seguridad-IIS {

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Eliminar encabezado X-Powered-By
    try {
        Remove-WebConfigurationProperty `
            -PSPath "IIS:\" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." `
            -AtElement @{name="X-Powered-By"} `
            -ErrorAction SilentlyContinue
    } catch {}

    # Agregar encabezados de seguridad
    $headers = @{
        "X-Frame-Options"        = "SAMEORIGIN"
        "X-Content-Type-Options" = "nosniff"
    }

    foreach ($h in $headers.GetEnumerator()) {
        try {
            Remove-WebConfigurationProperty `
                -PSPath "IIS:\" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." `
                -AtElement @{name=$h.Key} `
                -ErrorAction SilentlyContinue

            Add-WebConfigurationProperty `
                -PSPath "IIS:\" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." `
                -Value @{name=$h.Key; value=$h.Value}
        } catch {
            Write-Host "Advertencia: No se pudo agregar header $($h.Key)" -ForegroundColor Yellow
        }
    }

    # Ocultar version del servidor via urlScan / requestFiltering
    try {
        Set-WebConfigurationProperty `
            -PSPath "IIS:\" `
            -Filter "system.webServer/security/requestFiltering" `
            -Name "removeServerHeader" `
            -Value $true `
            -ErrorAction SilentlyContinue
    } catch {}

    # Deshabilitar metodos TRACE y TRACK
    $metodosBloquear = @("TRACE","TRACK","DELETE")
    foreach ($metodo in $metodosBloquear) {
        try {
            Add-WebConfigurationProperty `
                -PSPath "IIS:\" `
                -Filter "system.webServer/security/requestFiltering/verbs" `
                -Name "." `
                -Value @{verb=$metodo; allowed="false"} `
                -ErrorAction SilentlyContinue
        } catch {}
    }

    Write-Host "Seguridad IIS configurada." -ForegroundColor Green
}

# ============================================================
# Apache Win64: Listar versiones via winget
# ============================================================
function Listar-Versiones-Apache {

    Write-Host ""
    Write-Host "Consultando versiones disponibles de Apache..." -ForegroundColor Cyan

    $latest = ""

    # Intentar con winget si esta disponible
    $wingetOk = Verificar-Winget
    if ($wingetOk) {
        try {
            $raw = winget show Apache.ApacheHTTPServer 2>&1 | Out-String
            $versionLine = ($raw -split "`n") | Where-Object { $_ -match "Version\s*:" } | Select-Object -First 1
            if ($versionLine -match ":\s*(.+)") { $latest = $matches[1].Trim() }
        } catch {}
    }

    # Versiones predefinidas como fallback
    if (-not $latest) { $latest = "2.4.62" }
    $lts    = "2.4.58"
    $oldest = "2.4.54"

    Write-Host ""
    Write-Host "Versiones disponibles de Apache HTTP Server:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) $latest  (Latest / Desarrollo)"
    Write-Host "2) $lts     (LTS / Estable)"
    Write-Host "3) $oldest  (Oldest)"

    $global:APACHE_LATEST = $latest
    $global:APACHE_LTS    = $lts
    $global:APACHE_OLDEST = $oldest
}

# ============================================================
# Apache Win64: Instalar y configurar
# ============================================================
function Instalar-Apache {
    param(
        [string]$Version,
        [int]$Puerto
    )

    Write-Host "Instalando Apache HTTP Server $Version via winget..." -ForegroundColor Cyan

    # Detener instancias previas
    Stop-Service -Name "Apache*" -ErrorAction SilentlyContinue
    Stop-Service -Name "httpd*"  -ErrorAction SilentlyContinue

    # Instalar via winget silenciosamente
    winget install --id Apache.ApacheHTTPServer --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null

    # Ruta de instalacion tipica de Apache Win64
    $apacheBase = "C:\Apache24"
    if (-not (Test-Path $apacheBase)) {
        # Buscar en Program Files
        $apacheBase = Get-ChildItem "C:\Program Files" -Filter "Apache*" -Directory -ErrorAction SilentlyContinue |
                      Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $apacheBase -or -not (Test-Path $apacheBase)) {
        Write-Host "Error: No se encontro directorio de Apache tras instalacion." -ForegroundColor Red
        return
    }

    $confPath = "$apacheBase\conf\httpd.conf"

    # Obtener version real instalada
    $apacheExe = "$apacheBase\bin\httpd.exe"
    $versionReal = & $apacheExe -v 2>&1 | Select-String "Apache/" | ForEach-Object { ($_ -split "/")[1] -split " " | Select-Object -First 1 }
    if ($versionReal) { $Version = $versionReal.Trim() }

    Write-Host "Configurando puerto $Puerto en httpd.conf..." -ForegroundColor Cyan

    # Cambiar puerto Listen
    (Get-Content $confPath) -replace "Listen \d+", "Listen $Puerto" | Set-Content $confPath

    # Directorio web
    $webRoot = "$apacheBase\htdocs"
    Crear-Index -Servicio "Apache" -Version $Version -Puerto $Puerto -Directorio $webRoot

    # Seguridad Apache
    Configurar-Seguridad-Apache -ApacheBase $apacheBase

    # Crear usuario restringido
    Crear-Usuario-Restringido -Servicio "Apache" -Directorio $webRoot

    # Registrar e iniciar servicio Windows
    & "$apacheBase\bin\httpd.exe" -k install 2>&1 | Out-Null
    Start-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    if (-not $?) {
        & "$apacheBase\bin\httpd.exe" -k start 2>&1 | Out-Null
    }

    Gestionar-Firewall -Puerto $Puerto

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " INSTALACION COMPLETADA              " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Servidor : Apache HTTP Server"
    Write-Host "Version  : $Version"
    Write-Host "Puerto   : $Puerto"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Seguridad Apache Windows
# ============================================================
function Configurar-Seguridad-Apache {
    param([string]$ApacheBase)

    $secConf = "$ApacheBase\conf\extra\httpd-security.conf"

    # Crear archivo de seguridad
    @"
ServerTokens Prod
ServerSignature Off
TraceEnable Off

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</IfModule>

<LimitExcept GET POST HEAD>
    Deny from all
</LimitExcept>
"@ | Set-Content $secConf -Encoding UTF8

    # Incluir en httpd.conf si no esta incluido
    $confPath = "$ApacheBase\conf\httpd.conf"
    if (-not (Select-String -Path $confPath -Pattern "httpd-security.conf" -Quiet)) {
        Add-Content $confPath "`nInclude conf/extra/httpd-security.conf"
    }

    # Activar mod_headers si esta comentado
    (Get-Content $confPath) -replace "#LoadModule headers_module", "LoadModule headers_module" |
        Set-Content $confPath

    Write-Host "Seguridad Apache configurada." -ForegroundColor Green
}

# ============================================================
# Nginx Windows: Listar versiones via winget
# ============================================================
function Listar-Versiones-Nginx {

    Write-Host ""
    Write-Host "Consultando versiones disponibles de Nginx..." -ForegroundColor Cyan

    $latest = ""

    # Intentar con winget si esta disponible
    $wingetOk = Verificar-Winget
    if ($wingetOk) {
        try {
            $raw = winget show Nginx.Nginx 2>&1 | Out-String
            $versionLine = ($raw -split "`n") | Where-Object { $_ -match "Version\s*:" } | Select-Object -First 1
            if ($versionLine -match ":\s*(.+)") { $latest = $matches[1].Trim() }
        } catch {}
    }

    # Versiones predefinidas como fallback
    if (-not $latest) { $latest = "1.26.2" }
    $lts    = "1.24.0"
    $oldest = "1.22.1"

    Write-Host ""
    Write-Host "Versiones disponibles de Nginx:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) $latest  (Latest / Desarrollo)"
    Write-Host "2) $lts     (LTS / Estable)"
    Write-Host "3) $oldest  (Oldest)"

    $global:NGINX_LATEST = $latest
    $global:NGINX_LTS    = $lts
    $global:NGINX_OLDEST = $oldest
}

# ============================================================
# Nginx Windows: Instalar y configurar
# ============================================================
function Instalar-Nginx {
    param(
        [string]$Version,
        [int]$Puerto
    )

    Write-Host "Instalando Nginx $Version via winget..." -ForegroundColor Cyan

    # Detener instancias previas
    Stop-Service -Name "nginx" -ErrorAction SilentlyContinue
    taskkill /f /im nginx.exe 2>&1 | Out-Null

    winget install --id Nginx.Nginx --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null

    # Buscar directorio nginx
    $nginxBase = "C:\nginx"
    if (-not (Test-Path $nginxBase)) {
        $nginxBase = Get-ChildItem "C:\Program Files" -Filter "nginx*" -Directory -ErrorAction SilentlyContinue |
                     Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $nginxBase -or -not (Test-Path $nginxBase)) {
        Write-Host "Error: No se encontro directorio de Nginx." -ForegroundColor Red
        return
    }

    # Obtener version real
    $nginxExe = "$nginxBase\nginx.exe"
    $versionReal = & $nginxExe -v 2>&1 | ForEach-Object { ($_ -split "/")[1] }
    if ($versionReal) { $Version = $versionReal.Trim() }

    $confPath = "$nginxBase\conf\nginx.conf"
    $webRoot  = "$nginxBase\html"

    Write-Host "Configurando puerto $Puerto..." -ForegroundColor Cyan

    # Reescribir bloque server con puerto correcto
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
        listen       $Puerto;
        server_name  _;
        root         html;

        location / {
            index  index.html index.htm;
        }

        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
    }
}
"@
    $nginxConf | Set-Content $confPath -Encoding UTF8

    Crear-Index -Servicio "Nginx" -Version $Version -Puerto $Puerto -Directorio $webRoot

    Crear-Usuario-Restringido -Servicio "Nginx" -Directorio $webRoot

    # Iniciar nginx
    Start-Process -FilePath $nginxExe -WorkingDirectory $nginxBase -WindowStyle Hidden

    Gestionar-Firewall -Puerto $Puerto

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " INSTALACION COMPLETADA              " -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Servidor : Nginx"
    Write-Host "Version  : $Version"
    Write-Host "Puerto   : $Puerto"
    Write-Host "=====================================" -ForegroundColor Green
}

# ============================================================
# Crear pagina index.html personalizada
# ============================================================
function Crear-Index {
    param(
        [string]$Servicio,
        [string]$Version,
        [int]$Puerto,
        [string]$Directorio
    )

    if (-not (Test-Path $Directorio)) {
        New-Item -ItemType Directory -Path $Directorio -Force | Out-Null
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Servidor HTTP</title>
</head>
<body>
<h1>Servidor: $Servicio</h1>
<h2>Version: $Version</h2>
<h3>Puerto: $Puerto</h3>
</body>
</html>
"@

    $html | Set-Content "$Directorio\index.html" -Encoding UTF8
    Write-Host "index.html creado en $Directorio" -ForegroundColor Green
}

# ============================================================
# Crear usuario dedicado con permisos restringidos (NTFS)
# ============================================================
function Crear-Usuario-Restringido {
    param(
        [string]$Servicio,
        [string]$Directorio
    )

    $usuario = "svc_$($Servicio.ToLower())"

    # Generar contraseña aleatoria sin dependencias externas
    $chars   = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%"
    $password = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    $secPwd  = ConvertTo-SecureString $password -AsPlainText -Force

    # Crear usuario local si no existe
    if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
        New-LocalUser `
            -Name $usuario `
            -Password $secPwd `
            -PasswordNeverExpires `
            -UserMayNotChangePassword `
            -Description "Cuenta de servicio para $Servicio" `
            | Out-Null
        Write-Host "Usuario $usuario creado." -ForegroundColor Green
    }

    # Asignar permisos NTFS
    if (Test-Path $Directorio) {
        $acl = Get-Acl $Directorio

        # Deshabilitar herencia y limpiar ACL
        $acl.SetAccessRuleProtection($true, $false)
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

        # Nombre completo del usuario local: HOSTNAME\usuario
        $hostname      = $env:COMPUTERNAME
        $usuarioLocal  = "$hostname\$usuario"

        # Regla para el usuario de servicio (lectura + ejecucion)
        $reglaServicio = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $usuarioLocal,
            "ReadAndExecute",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )

        # Reglas para SYSTEM y Administrators (control total)
        foreach ($cuenta in @("NT AUTHORITY\SYSTEM", "BUILTIN\Administrators")) {
            $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $cuenta,
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.AddAccessRule($regla)
        }

        # IUSR e IIS_IUSRS necesitan lectura para servir contenido anonimo en IIS
        foreach ($cuenta in @("IUSR", "IIS_IUSRS")) {
            try {
                $reglaIIS = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $cuenta,
                    "ReadAndExecute",
                    "ContainerInherit,ObjectInherit",
                    "None",
                    "Allow"
                )
                $acl.AddAccessRule($reglaIIS)
            } catch {
                Write-Host "Advertencia: No se pudo agregar $cuenta a la ACL." -ForegroundColor Yellow
            }
        }

        $acl.AddAccessRule($reglaServicio)
        Set-Acl $Directorio $acl
        Write-Host "Permisos NTFS aplicados en $Directorio para usuario $usuarioLocal." -ForegroundColor Green
    }
}
