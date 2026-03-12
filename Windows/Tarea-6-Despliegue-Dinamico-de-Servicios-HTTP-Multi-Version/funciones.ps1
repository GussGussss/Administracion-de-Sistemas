# ============================================================
#  http_functions_v4.ps1  —  Funciones HTTP para Windows Server
#  Cambios v4: Apache usa Chocolatey como gestor de paquetes
#              (segun recomendacion de la tarea)
# ============================================================

# ─────────────────────────────────────────────────────────────
# UTILIDADES COMUNES
# ─────────────────────────────────────────────────────────────

function Validar-Puerto {
    param([string]$Puerto)

    if ($Puerto -notmatch '^\d+$') {
        Write-Host "Error: El puerto debe ser un numero." -ForegroundColor Red
        return $false
    }

    $p = [int]$Puerto
    if ($p -lt 1 -or $p -gt 65535) {
        Write-Host "Error: Puerto fuera de rango (1-65535)." -ForegroundColor Red
        return $false
    }

    $reservados = @(22, 25, 53, 135, 139, 445, 3389)
    if ($reservados -contains $p) {
        Write-Host "Error: Puerto $p reservado por el sistema." -ForegroundColor Red
        return $false
    }

    $enUso = Test-NetConnection -ComputerName "127.0.0.1" -Port $p -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ($enUso.TcpTestSucceeded) {
        Write-Host "Advertencia: El puerto $p ya esta en uso." -ForegroundColor Yellow
    }

    return $true
}

function Gestionar-Firewall {
    param([int]$Puerto)

    $ruleName = "HTTP-Custom"
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP `
        -LocalPort $Puerto -Action Allow -Profile Any | Out-Null

    if ($Puerto -ne 80) {
        $uso80 = Test-NetConnection -ComputerName "127.0.0.1" -Port 80 `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if (-not $uso80.TcpTestSucceeded) {
            Remove-NetFirewallRule -DisplayName "HTTP-Port80" -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName "HTTP-Port80" -Direction Inbound `
                -Protocol TCP -LocalPort 80 -Action Block -Profile Any | Out-Null
        }
    }

    Write-Host "Firewall configurado para puerto $Puerto." -ForegroundColor Green
}

function Verificar-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    return $false
}

# ─────────────────────────────────────────────────────────────
# CHOCOLATEY — instalacion automatica si no esta presente
# ─────────────────────────────────────────────────────────────

function Instalar-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "Chocolatey ya esta instalado." -ForegroundColor Green
        return $true
    }

    Write-Host "Instalando Chocolatey (gestor de paquetes)..." -ForegroundColor Cyan
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Set-ExecutionPolicy Bypass -Scope Process -Force
        $script = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
        Invoke-Expression $script
        # Recargar PATH para que choco sea accesible
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "Chocolatey instalado correctamente." -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "Error instalando Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
    }
    return $false
}

# ─────────────────────────────────────────────────────────────
# IIS
# ─────────────────────────────────────────────────────────────

function Listar-Versiones-IIS {
    Write-Host ""
    Write-Host "Consultando version de IIS disponible en Windows Server 2019..." -ForegroundColor Cyan

    $version = "10.0"
    $inetinfo = "C:\Windows\System32\inetsrv\inetinfo.exe"
    if (Test-Path $inetinfo) {
        $v = (Get-Item $inetinfo).VersionInfo.ProductVersion
        if ($v) { $version = $v }
    }

    Write-Host ""
    Write-Host "Versiones disponibles de IIS:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) $version  (Latest — incluido en Windows Server 2019)"
    Write-Host "2) $version  (LTS    — misma version estable)"
    Write-Host "3) $version  (Oldest — version base del sistema)"

    $global:IIS_LATEST = $version
    $global:IIS_LTS    = $version
    $global:IIS_OLDEST = $version
}

function Instalar-IIS {
    param([string]$Version, [int]$Puerto)

    Write-Host ""
    Write-Host "Instalando IIS $Version en puerto $Puerto..." -ForegroundColor Cyan

    $feature = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
    if ($feature -and $feature.Installed) {
        Write-Host "IIS ya esta instalado." -ForegroundColor Green
    } else {
        Write-Host "Habilitando rol Web-Server..." -ForegroundColor Gray
        Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    Write-Host "Configurando puerto $Puerto en IIS..." -ForegroundColor Gray
    Get-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue |
        Remove-WebBinding -ErrorAction SilentlyContinue
    New-WebBinding -Name "Default Web Site" -Protocol "http" -Port $Puerto -IPAddress "*" | Out-Null

    $wwwroot = "C:\inetpub\wwwroot"
    Crear-Index -Directorio $wwwroot -Servidor "IIS" -Version $Version -Puerto $Puerto
    Configurar-Seguridad-IIS
    Crear-Usuario-Restringido -service "iis" -directorio $wwwroot

    iisreset /restart | Out-Null
    Gestionar-Firewall -Puerto $Puerto

    Write-Host ""
    Write-Host "IIS $Version instalado y corriendo en puerto $Puerto." -ForegroundColor Green
    Write-Host "URL: http://localhost:$Puerto" -ForegroundColor Cyan
}

function Configurar-Seguridad-IIS {
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        Remove-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." -AtElement @{name="X-Powered-By"} -ErrorAction SilentlyContinue
        Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." -Value @{name="X-Frame-Options"; value="SAMEORIGIN"} -ErrorAction SilentlyContinue
        Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." -Value @{name="X-Content-Type-Options"; value="nosniff"} -ErrorAction SilentlyContinue
        Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
            -Filter "system.webServer/security/requestFiltering" `
            -Name "removeServerHeader" -Value $true -ErrorAction SilentlyContinue
        $verbFilter = "system.webServer/security/requestFiltering/verbs"
        foreach ($verbo in @("TRACE","TRACK","DELETE")) {
            Add-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
                -Filter $verbFilter -Name "." `
                -Value @{verb=$verbo; allowed="false"} -ErrorAction SilentlyContinue
        }
        Write-Host "Seguridad IIS configurada." -ForegroundColor Green
    } catch {
        Write-Host "Advertencia configurando seguridad IIS: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────
# APACHE  (via Chocolatey)
# ─────────────────────────────────────────────────────────────

function Listar-Versiones-Apache {
    Write-Host ""
    Write-Host "Consultando versiones disponibles de Apache..." -ForegroundColor Cyan

    # Versiones disponibles en el repositorio de Chocolatey
    # choco search muestra versiones; usamos la API publica para listarlas
    $versiones = @()
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $apiUrl = "https://community.chocolatey.org/api/v2/FindPackagesById()?id='apache-httpd'&`$orderby=Version+desc&`$top=20"
        $resp = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
        $versiones = $resp | ForEach-Object { $_.properties.Version } | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Select-Object -Unique | Sort-Object {
            $parts = $_ -split '\.'
            [int]$parts[0]*10000 + [int]$parts[1]*100 + [int]$parts[2]
        } -Descending | Select-Object -First 10
    } catch {
        Write-Host "No se pudo consultar API de Chocolatey, usando versiones conocidas." -ForegroundColor Gray
    }

    # Fallback con versiones conocidas disponibles en Chocolatey
    if (-not $versiones -or $versiones.Count -lt 3) {
        $versiones = @("2.4.55", "2.4.54", "2.4.51", "2.4.49", "2.4.48", "2.4.46")
    }

    $latest = $versiones[0]
    $lts    = $versiones[1]
    $oldest = $versiones[-1]

    Write-Host ""
    Write-Host "Versiones disponibles de Apache HTTP Server (via Chocolatey):" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1) $latest  (Latest / Desarrollo)"
    Write-Host "2) $lts     (LTS / Estable)"
    Write-Host "3) $oldest  (Oldest)"

    $global:APACHE_LATEST = $latest
    $global:APACHE_LTS    = $lts
    $global:APACHE_OLDEST = $oldest
}

function Instalar-Apache {
    param([string]$Version, [int]$Puerto)

    Write-Host ""
    Write-Host "Instalando Apache HTTP Server $Version en puerto $Puerto..." -ForegroundColor Cyan

    # Detener instancias previas
    Get-Service | Where-Object { $_.Name -like "Apache*" } |
        Stop-Service -Force -ErrorAction SilentlyContinue
    Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # ── Instalar o actualizar Chocolatey ──────────────────────
    $chocoOk = Instalar-Chocolatey
    if (-not $chocoOk) {
        Write-Host "Error: No se pudo instalar Chocolatey. Abortando." -ForegroundColor Red
        return
    }

    # ── Desinstalar version anterior si existe ────────────────
    $apacheBase = "C:\Apache24"
    if (Test-Path "$apacheBase\bin\httpd.exe") {
        Write-Host "Eliminando instalacion anterior de Apache..." -ForegroundColor Gray
        & "$apacheBase\bin\httpd.exe" -k uninstall -ErrorAction SilentlyContinue
        Remove-Item $apacheBase -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── Instalar via Chocolatey ───────────────────────────────
    Write-Host "Descargando e instalando Apache $Version via Chocolatey..." -ForegroundColor Cyan
    $chocoParams = "/installLocation:C:\Apache24 /noService"

    & choco install apache-httpd --version $Version --params $chocoParams -y --no-progress 2>&1 |
        ForEach-Object { Write-Host $_ -ForegroundColor Gray }

    # Chocolatey instala en AppData por defecto; buscar httpd.exe donde quedo
    $posiblesPaths = @(
        "C:\Apache24\bin\httpd.exe",
        "$env:APPDATA\Apache24\bin\httpd.exe",
        "C:\tools\Apache24\bin\httpd.exe"
    )

    $httpdExe = $null
    foreach ($p in $posiblesPaths) {
        if (Test-Path $p) { $httpdExe = $p; $apacheBase = Split-Path (Split-Path $p); break }
    }

    # Busqueda exhaustiva si no se encontro
    if (-not $httpdExe) {
        $found = Get-ChildItem -Path "C:\" -Filter "httpd.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $httpdExe = $found.FullName; $apacheBase = Split-Path (Split-Path $httpdExe) }
    }

    if (-not $httpdExe) {
        Write-Host "Error: No se encontro httpd.exe tras la instalacion de Chocolatey." -ForegroundColor Red
        return
    }

    Write-Host "Apache instalado en: $apacheBase" -ForegroundColor Green

    # ── Normalizar ubicacion a C:\Apache24 ────────────────────
    if ($apacheBase -ne "C:\Apache24") {
        Write-Host "Moviendo Apache a C:\Apache24..." -ForegroundColor Gray
        if (Test-Path "C:\Apache24") { Remove-Item "C:\Apache24" -Recurse -Force }
        Move-Item $apacheBase "C:\Apache24" -Force
        $apacheBase = "C:\Apache24"
        $httpdExe   = "C:\Apache24\bin\httpd.exe"
    }

    # ── Configurar puerto en httpd.conf ───────────────────────
    $confFile = "$apacheBase\conf\httpd.conf"
    if (Test-Path $confFile) {
        $conf = Get-Content $confFile -Raw
        $conf = $conf -replace 'Listen \d+', "Listen $Puerto"
        $conf = $conf -replace 'ServerRoot "[^"]*"', "ServerRoot `"$apacheBase`""
        Set-Content $confFile $conf -Encoding UTF8
        Write-Host "Puerto configurado: $Puerto" -ForegroundColor Green
    }

    # ── Index, seguridad, usuario ─────────────────────────────
    $docroot = "$apacheBase\htdocs"
    Crear-Index -Directorio $docroot -Servidor "Apache" -Version $Version -Puerto $Puerto
    Configurar-Seguridad-Apache -apacheBase $apacheBase
    Crear-Usuario-Restringido -service "apache" -directorio $docroot

    # ── Registrar e iniciar servicio Windows ──────────────────
    Write-Host "Registrando servicio Apache..." -ForegroundColor Gray
    & $httpdExe -k install 2>&1 | Out-Null
    Start-Service "Apache2.4" -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 3
    $svc = Get-Service "Apache2.4" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "Apache $Version corriendo en puerto $Puerto." -ForegroundColor Green
    } else {
        Write-Host "Advertencia: Servicio Apache no inicio. Revisando logs..." -ForegroundColor Yellow
        $errorLog = "$apacheBase\logs\error.log"
        if (Test-Path $errorLog) {
            Get-Content $errorLog -Tail 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        }
    }

    Gestionar-Firewall -Puerto $Puerto
    Write-Host ""
    Write-Host "URL: http://localhost:$Puerto" -ForegroundColor Cyan
}

function Configurar-Seguridad-Apache {
    param([string]$apacheBase)

    $secConf = "$apacheBase\conf\extra\httpd-security.conf"
    $contenido = @"
# Seguridad Apache — generado automaticamente
ServerTokens Prod
ServerSignature Off
TraceEnable Off

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header unset X-Powered-By
</IfModule>

<LimitExcept GET POST HEAD>
    deny from all
</LimitExcept>
"@

    Set-Content -Path $secConf -Value $contenido -Encoding UTF8

    $confFile = "$apacheBase\conf\httpd.conf"
    if (Test-Path $confFile) {
        $conf = Get-Content $confFile -Raw
        $includeLinea = "Include conf/extra/httpd-security.conf"
        if ($conf -notmatch [regex]::Escape($includeLinea)) {
            Add-Content -Path $confFile -Value "`n$includeLinea"
        }
        # Descomentar mod_headers si esta comentado
        $conf = $conf -replace '#(LoadModule headers_module)', '$1'
        Set-Content $confFile $conf -Encoding UTF8
    }
    Write-Host "Seguridad Apache configurada." -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────
# NGINX  (descarga directa desde nginx.org — nunca ha bloqueado)
# ─────────────────────────────────────────────────────────────

function Listar-Versiones-Nginx {
    Write-Host ""
    Write-Host "Consultando versiones disponibles de Nginx..." -ForegroundColor Cyan

    $latest = ""; $lts = ""; $oldest = ""
    $wingetOk = Verificar-Winget
    if ($wingetOk) {
        try {
            $raw = winget show Nginx.Nginx 2>&1 | Out-String
            $vline = ($raw -split "`n") | Where-Object { $_ -match "Version\s*:" } | Select-Object -First 1
            if ($vline -match ":\s*(.+)") { $latest = $matches[1].Trim() }
        } catch {}
    }

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

function Instalar-Nginx {
    param([string]$Version, [int]$Puerto)

    Write-Host ""
    Write-Host "Instalando Nginx $Version en puerto $Puerto..." -ForegroundColor Cyan

    # Detener instancias previas
    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    # Verificar si ya esta instalada la version correcta
    $nginxExe = "C:\nginx\nginx.exe"
    if (Test-Path $nginxExe) {
        $verActual = & $nginxExe -v 2>&1 | Out-String
        if ($verActual -match $Version) {
            Write-Host "Nginx $Version ya esta instalado." -ForegroundColor Green
        } else {
            Remove-Item "C:\nginx" -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path $nginxExe)) {
        $url     = "https://nginx.org/download/nginx-$Version.zip"
        $zipDest = "$env:TEMP\nginx.zip"

        Write-Host "Descargando Nginx $Version desde nginx.org..." -ForegroundColor Cyan
        Write-Host "URL: $url" -ForegroundColor Gray

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "PowerShell/WindowsServer")
            $wc.DownloadFile($url, $zipDest)
        } catch {
            Invoke-WebRequest -Uri $url -OutFile $zipDest -UseBasicParsing
        }

        # Validar ZIP
        $bytes = [System.IO.File]::ReadAllBytes($zipDest)
        if ($bytes.Length -lt 100000 -or $bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) {
            Write-Host "Error: ZIP de Nginx invalido." -ForegroundColor Red
            return
        }
        Write-Host "Descarga correcta ($([math]::Round($bytes.Length/1MB,1)) MB)." -ForegroundColor Green

        Expand-Archive -Path $zipDest -DestinationPath "$env:TEMP\nginx_extract" -Force
        $carpeta = Get-ChildItem "$env:TEMP\nginx_extract" | Where-Object { $_.PSIsContainer } | Select-Object -First 1
        Move-Item $carpeta.FullName "C:\nginx" -Force
        Remove-Item "$env:TEMP\nginx_extract" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── Escribir nginx.conf SIN BOM ───────────────────────────
    $nginxConf = @"
worker_processes  1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;
    sendfile      on;
    server {
        listen       $Puerto;
        server_name  localhost;
        root         html;
        index        index.html;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
        location / { try_files `$uri `$uri/ =404; }
    }
}
"@
    $confPath = "C:\nginx\conf\nginx.conf"
    [System.IO.File]::WriteAllText($confPath, $nginxConf, [System.Text.UTF8Encoding]::new($false))

    Crear-Index -Directorio "C:\nginx\html" -Servidor "Nginx" -Version $Version -Puerto $Puerto

    # ── Iniciar Nginx ─────────────────────────────────────────
    Start-Process -FilePath "C:\nginx\nginx.exe" -WorkingDirectory "C:\nginx" -WindowStyle Hidden
    Start-Sleep -Seconds 3

    $test = Test-NetConnection -ComputerName "127.0.0.1" -Port $Puerto -WarningAction SilentlyContinue
    if ($test.TcpTestSucceeded) {
        Write-Host "Nginx $Version corriendo en puerto $Puerto." -ForegroundColor Green
    } else {
        Write-Host "Advertencia: Nginx no responde en puerto $Puerto." -ForegroundColor Yellow
        $errorLog = "C:\nginx\logs\error.log"
        if (Test-Path $errorLog) {
            Get-Content $errorLog -Tail 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        }
    }

    Gestionar-Firewall -Puerto $Puerto
    Write-Host "URL: http://localhost:$Puerto" -ForegroundColor Cyan
}

# ─────────────────────────────────────────────────────────────
# COMPARTIDAS
# ─────────────────────────────────────────────────────────────

function Crear-Index {
    param([string]$Directorio, [string]$Servidor, [string]$Version, [int]$Puerto)

    if (-not (Test-Path $Directorio)) { New-Item -ItemType Directory -Path $Directorio -Force | Out-Null }

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>$Servidor $Version</title>
<style>body{font-family:Arial,sans-serif;background:#1a1a2e;color:#eee;display:flex;justify-content:center;align-items:center;height:100vh;margin:0}
.card{background:#16213e;border-radius:12px;padding:40px;text-align:center;box-shadow:0 4px 20px rgba(0,0,0,.5)}
h1{color:#0f3460;font-size:2em}p{color:#a8b2d8}span{color:#e94560;font-weight:bold}</style></head>
<body><div class="card">
<h1>$Servidor HTTP Server</h1>
<p>Version: <span>$Version</span></p>
<p>Puerto: <span>$Puerto</span></p>
<p>Servidor: <span>Windows Server 2019</span></p>
<p style="color:#4CAF50;margin-top:20px">&#10003; Servicio activo</p>
</div></body></html>
"@
    Set-Content -Path "$Directorio\index.html" -Value $html -Encoding UTF8
}

function Crear-Usuario-Restringido {
    param([string]$service, [string]$directorio)

    $usuario = "svc_$service"
    $chars   = ([char[]]'abcdefghijkmnpqrstuvwxyz') +
               ([char[]]'ABCDEFGHJKLMNPQRSTUVWXYZ') +
               ([char[]]'23456789') +
               ([char[]]'!@#$%')
    $pwd = -join (1..16 | ForEach-Object { $chars | Get-Random })
    $secPwd = ConvertTo-SecureString $pwd -AsPlainText -Force

    # Eliminar si ya existe
    Remove-LocalUser -Name $usuario -ErrorAction SilentlyContinue
    New-LocalUser -Name $usuario -Password $secPwd -PasswordNeverExpires `
        -UserMayNotChangePassword -Description "Cuenta servicio $service" | Out-Null

    # ACL sobre el directorio
    $acl = Get-Acl $directorio -ErrorAction SilentlyContinue
    if ($acl) {
        $acl.SetAccessRuleProtection($true, $false)  # deshabilitar herencia

        $permisos = @(
            @("SYSTEM",                        "FullControl"),
            @("BUILTIN\Administrators",        "FullControl"),
            @("IUSR",                          "ReadAndExecute"),
            @("IIS_IUSRS",                     "ReadAndExecute"),
            @("$env:COMPUTERNAME\$usuario",    "ReadAndExecute")
        )
        foreach ($p in $permisos) {
            try {
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $p[0], $p[1], "ContainerInherit,ObjectInherit", "None", "Allow")
                $acl.AddAccessRule($rule)
            } catch { }
        }
        Set-Acl -Path $directorio -AclObject $acl -ErrorAction SilentlyContinue
    }

    Write-Host "Usuario restringido '$usuario' creado para $service." -ForegroundColor Green
}
