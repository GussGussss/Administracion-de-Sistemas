# ============================================================
# http_functions.ps1
# Funciones para despliegue de servidores HTTP en Windows
# Windows Server 2019 Core (sin GUI)
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

    $reservados = @(22, 25, 53, 3389, 445, 135, 139)
    if ($reservados -contains $p) {
        Write-Host "Error: Puerto $p reservado por el sistema." -ForegroundColor Red
        return $false
    }

    $enUso = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
    if ($enUso.TcpTestSucceeded) {
        Write-Host "Error: El puerto $p ya esta en uso." -ForegroundColor Red
        return $false
    }

    Write-Host "Puerto $p valido." -ForegroundColor Green
    return $true
}


# ============================================================
# Gestionar puerto (validar + abrir firewall)
# Mirrors: gestionar_puerto() del script Linux
# ============================================================
function Gestionar-Puerto {
    param([int]$Puerto)

    if (-not (Validar-Puerto -Puerto $Puerto)) {
        Write-Host "Error: puerto invalido o en uso." -ForegroundColor Red
        return $false
    }

    Gestionar-Firewall -Puerto $Puerto
    return $true
}


# ============================================================
# Abrir puerto en firewall y bloquear puertos por defecto libres
# ============================================================
function Gestionar-Firewall {
    param([int]$Puerto)

    Write-Host "Configurando firewall para el puerto $Puerto..." -ForegroundColor Cyan

    Remove-NetFirewallRule -DisplayName "HTTP-Custom" -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName "HTTP-Custom" `
        -Direction Inbound `
        -LocalPort $Puerto `
        -Protocol TCP `
        -Action Allow `
        | Out-Null

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
# Cerrar puerto anterior en firewall
# Mirrors: cerrar_puerto_firewall() del script Linux
# ============================================================
function Cerrar-Puerto-Firewall {
    param([int]$Puerto)

    Write-Host "Cerrando puerto anterior $Puerto en firewall..." -ForegroundColor Yellow
    Remove-NetFirewallRule -DisplayName "HTTP-Custom-$Puerto" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "HTTP-Custom"         -ErrorAction SilentlyContinue
}


# ============================================================
# Detener servicios HTTP para evitar conflictos
# Mirrors: detener_servicios_http() del script Linux
# ============================================================
function Detener-Servicios-HTTP {

    Write-Host "Deteniendo servicios HTTP existentes para evitar conflictos..." -ForegroundColor Cyan

    $servicios = @("W3SVC", "Apache2.4", "Apache", "nginx")
    foreach ($svc in $servicios) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Host "$svc detenido." -ForegroundColor Yellow
        } else {
            Write-Host "$svc no estaba activo." -ForegroundColor Gray
        }
    }

    Get-Process -Name "httpd","nginx" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
}


# ============================================================
# Verificar winget (sin intentar instalarlo en Server Core)
# ============================================================
function Verificar-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    return $false
}


# ============================================================
# Obtener puerto actual de IIS
# Mirrors: obtener_puerto_apache() / obtener_puerto_nginx() del script Linux
# ============================================================
function Obtener-Puerto-IIS {
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $binding = Get-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue |
                   Select-Object -First 1
        if ($binding) {
            return [int]($binding.bindingInformation -split ":")[-2]
        }
    } catch {}
    return 0
}


# ============================================================
# Obtener puerto actual de Apache
# ============================================================
function Obtener-Puerto-Apache {
    $confPath = "C:\Apache24\conf\httpd.conf"
    if (Test-Path $confPath) {
        $line = Select-String -Path $confPath -Pattern "^Listen \d+" | Select-Object -First 1
        if ($line) {
            return [int]($line.Line -split " ")[-1]
        }
    }
    return 0
}


# ============================================================
# Obtener puerto actual de Nginx
# ============================================================
function Obtener-Puerto-Nginx {
    $confPath = "C:\nginx\conf\nginx.conf"
    if (Test-Path $confPath) {
        $line = Select-String -Path $confPath -Pattern "listen\s+\d+" | Select-Object -First 1
        if ($line) {
            if ($line.Line -match "listen\s+(\d+)") { return [int]$matches[1] }
        }
    }
    return 0
}


# ============================================================
# Cambiar puerto IIS (sin reinstalar)
# Mirrors: cambiar_puerto_apache() del script Linux
# ============================================================
function Cambiar-Puerto-IIS {
    param([int]$PuertoNuevo)

    $puertoViejo = Obtener-Puerto-IIS
    Write-Host "Cambiando puerto IIS: $puertoViejo -> $PuertoNuevo" -ForegroundColor Cyan

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $siteName = "Default Web Site"
    Remove-WebBinding -Name $siteName -ErrorAction SilentlyContinue
    New-WebBinding -Name $siteName -Protocol "http" -Port $PuertoNuevo -IPAddress "*" | Out-Null

    if ($puertoViejo -gt 0) { Cerrar-Puerto-Firewall -Puerto $puertoViejo }
    Gestionar-Firewall -Puerto $PuertoNuevo

    Write-Host "Reiniciando IIS..." -ForegroundColor Cyan
    iisreset /restart | Out-Null
    Write-Host "Puerto IIS actualizado a $PuertoNuevo." -ForegroundColor Green
}


# ============================================================
# Cambiar puerto Apache (sin reinstalar)
# Mirrors: cambiar_puerto_apache() del script Linux
# ============================================================
function Cambiar-Puerto-Apache {
    param([int]$PuertoNuevo)

    $apacheBase  = Encontrar-Base-Apache
    $puertoViejo = Obtener-Puerto-Apache

    Write-Host "Cambiando puerto Apache: $puertoViejo -> $PuertoNuevo" -ForegroundColor Cyan

    $confPath = "$apacheBase\conf\httpd.conf"
    (Get-Content $confPath) -replace "Listen \d+", "Listen $PuertoNuevo" | Set-Content $confPath

    if ($puertoViejo -gt 0) { Cerrar-Puerto-Firewall -Puerto $puertoViejo }
    Gestionar-Firewall -Puerto $PuertoNuevo

    Write-Host "Reiniciando Apache..." -ForegroundColor Cyan
    Restart-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    Write-Host "Puerto Apache actualizado a $PuertoNuevo." -ForegroundColor Green
}


# ============================================================
# Cambiar puerto Nginx (sin reinstalar)
# Mirrors: cambiar_puerto_nginx() del script Linux
# ============================================================
function Cambiar-Puerto-Nginx {
    param([int]$PuertoNuevo)

    $puertoViejo = Obtener-Puerto-Nginx
    Write-Host "Cambiando puerto Nginx: $puertoViejo -> $PuertoNuevo" -ForegroundColor Cyan

    Configurar-Conf-Nginx -Puerto $PuertoNuevo

    if ($puertoViejo -gt 0) { Cerrar-Puerto-Firewall -Puerto $puertoViejo }
    Gestionar-Firewall -Puerto $PuertoNuevo

    Write-Host "Reiniciando Nginx..." -ForegroundColor Cyan
    $nginxBase = "C:\nginx"
    taskkill /f /im nginx.exe 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden
    Write-Host "Puerto Nginx actualizado a $PuertoNuevo." -ForegroundColor Green
}


# ============================================================
# Encontrar directorio base de Apache
# ============================================================
function Encontrar-Base-Apache {
    $apacheBase = "C:\Apache24"

    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        $encontrado = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                      Select-Object -First 1
        if ($encontrado) {
            $apacheBase = Split-Path $encontrado.DirectoryName -Parent
        }
    }

    # Doble verificacion: subcarpeta extra que deja Chocolatey a veces
    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        $sub = Get-ChildItem $apacheBase -Directory -ErrorAction SilentlyContinue |
               Where-Object { Test-Path "$($_.FullName)\bin\httpd.exe" } |
               Select-Object -First 1
        if ($sub) { $apacheBase = $sub.FullName }
    }

    return $apacheBase
}


# ============================================================
# IIS: Listar versiones
# ============================================================
function Listar-Versiones-IIS {
    Write-Host ""
    Write-Host "Versiones disponibles de IIS:" -ForegroundColor Cyan
    Write-Host ""

    $iisPath = "C:\Windows\System32\inetsrv\inetinfo.exe"
    if (Test-Path $iisPath) {
        $ver = (Get-Item $iisPath).VersionInfo.ProductVersion
    } else {
        $ver = "10.0 (Windows Server 2019)"
    }

    Write-Host "1) $ver  (Estable - incluida en Windows Server 2019)"
    Write-Host "2) $ver  (LTS - misma version del sistema)"
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

    # ── Detectar si IIS ya esta instalado ─────────────────────────────────────
    $iisInstalado = (Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue).Installed

    if ($iisInstalado) {
        $iisPath = "C:\Windows\System32\inetsrv\inetinfo.exe"
        $versionInstalada = (Get-Item $iisPath -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
        if (-not $versionInstalada) { $versionInstalada = "10.0" }

        Write-Host ""
        Write-Host "IIS ya esta instalado (version $versionInstalada)." -ForegroundColor Yellow

        $puertoActual = Obtener-Puerto-IIS
        if ($puertoActual -eq $Puerto) {
            Write-Host "Misma version y puerto solicitados. Nada que hacer." -ForegroundColor Green
            return
        }

        Write-Host "Misma version solicitada. Solo se actualizara el puerto a $Puerto."
        if (-not (Gestionar-Puerto -Puerto $Puerto)) { return }
        Cambiar-Puerto-IIS -PuertoNuevo $Puerto

        Crear-Index -Servicio "IIS" -Version $versionInstalada -Puerto $Puerto -Directorio "C:\inetpub\wwwroot"

        Write-Host ""
        Write-Host "=====================================" -ForegroundColor Green
        Write-Host " PUERTO ACTUALIZADO                  " -ForegroundColor Green
        Write-Host "=====================================" -ForegroundColor Green
        Write-Host "Servidor : IIS"
        Write-Host "Version  : $versionInstalada"
        Write-Host "Puerto   : $Puerto"
        Write-Host "=====================================" -ForegroundColor Green
        return
    }

    # ── Instalacion nueva ─────────────────────────────────────────────────────
    Detener-Servicios-HTTP

    if (-not (Gestionar-Puerto -Puerto $Puerto)) { return }

    Write-Host "Instalando IIS (Internet Information Services)..." -ForegroundColor Cyan

    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    Install-WindowsFeature -Name Web-Http-Redirect, Web-Http-Logging, Web-Security | Out-Null

    $iisPath = "C:\Windows\System32\inetsrv\inetinfo.exe"
    $Version = (Get-Item $iisPath -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
    if (-not $Version) { $Version = "10.0" }

    Write-Host "Configurando puerto $Puerto..." -ForegroundColor Cyan

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $siteName = "Default Web Site"
    Remove-WebBinding -Name $siteName -ErrorAction SilentlyContinue
    New-WebBinding -Name $siteName -Protocol "http" -Port $Puerto -IPAddress "*" | Out-Null

    Crear-Index -Servicio "IIS" -Version $Version -Puerto $Puerto -Directorio "C:\inetpub\wwwroot"

    Configurar-Seguridad-IIS

    Crear-Usuario-Restringido -Servicio "IIS" -Directorio "C:\inetpub\wwwroot"

    iisreset /restart | Out-Null

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

    try {
        Remove-WebConfigurationProperty `
            -PSPath "IIS:\" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." `
            -AtElement @{name="X-Powered-By"} `
            -ErrorAction SilentlyContinue
    } catch {}

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
            Write-Host "Advertencia: No se pudo agregar el header $($h.Key)" -ForegroundColor Yellow
        }
    }

    try {
        Set-WebConfigurationProperty `
            -PSPath "IIS:\" `
            -Filter "system.webServer/security/requestFiltering" `
            -Name "removeServerHeader" `
            -Value $true `
            -ErrorAction SilentlyContinue
    } catch {}

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
# Apache Win64: Listar versiones
# ============================================================
function Listar-Versiones-Apache {

    Write-Host ""
    Write-Host "Consultando versiones disponibles de Apache..." -ForegroundColor Cyan

    # Instalar Chocolatey si no esta presente (gestor de paquetes para Windows Server 2019)
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Instalando Chocolatey (gestor de paquetes)..." -ForegroundColor Yellow
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Set-ExecutionPolicy Bypass -Scope Process -Force
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Host "Chocolatey instalado correctamente." -ForegroundColor Green
        } catch {
            Write-Host "No se pudo instalar Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    $latest = ""
    $lts    = ""
    $oldest = ""

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            Write-Host "Consultando repositorio de Chocolatey..." -ForegroundColor Gray
            $raw = choco search apache-httpd --all-versions --limit-output 2>&1 | Out-String
            $versiones = ($raw -split "`n") |
                Where-Object { $_ -match "^apache-httpd" } |
                ForEach-Object { ($_ -split "[|]")[1].Trim() } |
                Where-Object { $_ -match "^\d+\.\d+\.\d+$" } |
                Sort-Object { [Version]$_ } -Descending

            if ($versiones.Count -ge 1) { $latest = $versiones[0] }
            if ($versiones.Count -ge 2) { $lts    = $versiones[1] }
            if ($versiones.Count -ge 3) { $oldest = $versiones[$versiones.Count - 1] }
        } catch {
            Write-Host "Chocolatey no pudo listar versiones: $($_.Exception.Message)" -ForegroundColor Gray
        }
    }

    # Fallback con versiones conocidas
    if (-not $latest) { $latest = "2.4.55" }
    if (-not $lts)    { $lts    = "2.4.54" }
    if (-not $oldest) { $oldest = "2.4.52" }

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
    param([string]$Version, [int]$Puerto)

    # ── Detectar si Apache ya esta instalado ──────────────────────────────────
    $apacheBase       = Encontrar-Base-Apache
    $versionInstalada = ""

    if (Test-Path "$apacheBase\bin\httpd.exe") {
        $vOut = (& "$apacheBase\bin\httpd.exe" -v 2>&1) | Out-String
        if ($vOut -match "Apache/([0-9]+\.[0-9]+\.[0-9]+)") {
            $versionInstalada = $matches[1].Trim()
        }
    }

    if ($versionInstalada) {
        Write-Host ""
        Write-Host "Apache ya esta instalado (version $versionInstalada)." -ForegroundColor Yellow

        if ($versionInstalada -ne $Version) {
            Write-Host "Version solicitada ($Version) difiere de la instalada ($versionInstalada)." -ForegroundColor Yellow
            Write-Host "Se reinstalara Apache con la version $Version..." -ForegroundColor Cyan
            Stop-Service -Name "Apache2.4" -Force -ErrorAction SilentlyContinue
            Stop-Service -Name "Apache"    -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            choco uninstall apache-httpd --yes --no-progress 2>&1 | Out-Null
            Remove-Item $apacheBase -Recurse -Force -ErrorAction SilentlyContinue
            # Continua hacia instalacion nueva abajo
        } else {
            Write-Host "Misma version solicitada. Solo se actualizara el puerto a $Puerto."
            if (-not (Gestionar-Puerto -Puerto $Puerto)) { return }
            Cambiar-Puerto-Apache -PuertoNuevo $Puerto

            $webRoot = "$apacheBase\htdocs"
            Crear-Index -Servicio "Apache" -Version $versionInstalada -Puerto $Puerto -Directorio $webRoot

            Write-Host ""
            Write-Host "=====================================" -ForegroundColor Green
            Write-Host " PUERTO ACTUALIZADO                  " -ForegroundColor Green
            Write-Host "=====================================" -ForegroundColor Green
            Write-Host "Servidor : Apache HTTP Server"
            Write-Host "Version  : $versionInstalada"
            Write-Host "Puerto   : $Puerto"
            Write-Host "=====================================" -ForegroundColor Green
            return
        }
    }

    # ── Instalacion nueva (o reinstalacion) ───────────────────────────────────
    Detener-Servicios-HTTP

    if (-not (Gestionar-Puerto -Puerto $Puerto)) { return }

    Write-Host ""
    Write-Host "Instalando Apache HTTP Server $Version via Chocolatey..." -ForegroundColor Cyan

    $apacheBase = "C:\Apache24"

    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Error: Chocolatey no disponible. Ejecute primero la opcion de listar versiones." -ForegroundColor Red
        return
    }

    Write-Host "Descargando e instalando Apache $Version (puede tardar unos minutos)..." -ForegroundColor Cyan
    $chocoOut = choco install apache-httpd `
        --version $Version `
        --params "/installLocation:$apacheBase /noService" `
        --yes `
        --no-progress `
        --accept-license `
        --allow-downgrade `
        --force `
        2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Chocolatey fallo al instalar Apache $Version." -ForegroundColor Red
        Write-Host ($chocoOut | Select-Object -Last 5 | Out-String) -ForegroundColor Gray
        return
    }

    # Reubicar si httpd.exe no esta donde se espera
    $apacheBase = Encontrar-Base-Apache

    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        Write-Host "Error: httpd.exe no encontrado tras la instalacion." -ForegroundColor Red
        return
    }

    $apacheExe   = "$apacheBase\bin\httpd.exe"
    $versionReal = (& $apacheExe -v 2>&1) | Select-String "Apache/" |
                   ForEach-Object { ($_.ToString() -split "/")[1] -split " " | Select-Object -First 1 }
    if ($versionReal) { $Version = $versionReal.Trim() }

    $confPath = "$apacheBase\conf\httpd.conf"
    Write-Host "Configurando puerto $Puerto en httpd.conf..." -ForegroundColor Cyan
    (Get-Content $confPath) -replace "Listen \d+", "Listen $Puerto" | Set-Content $confPath

    # Corregir ServerRoot si Chocolatey lo dejo mal
    $confContent = Get-Content $confPath -Raw
    if ($confContent -match 'Define SRVROOT "([^"]+)"') {
        $srvrootActual = $matches[1]
        if ($srvrootActual -ne $apacheBase) {
            Write-Host "Corrigiendo ServerRoot: $srvrootActual -> $apacheBase" -ForegroundColor Yellow
            $confContent = $confContent -replace [regex]::Escape("Define SRVROOT `"$srvrootActual`""), "Define SRVROOT `"$apacheBase`""
            [System.IO.File]::WriteAllText($confPath, $confContent)
        }
    }

    $webRoot = "$apacheBase\htdocs"
    Crear-Index -Servicio "Apache" -Version $Version -Puerto $Puerto -Directorio $webRoot

    Configurar-Seguridad-Apache -ApacheBase $apacheBase

    Crear-Usuario-Restringido -Servicio "Apache" -Directorio $webRoot

    Write-Host "Registrando servicio Apache..." -ForegroundColor Cyan
    & "$apacheBase\bin\httpd.exe" -k install 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    Write-Host "Iniciando servicio Apache..." -ForegroundColor Cyan
    Start-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $escuchando = Test-NetConnection -ComputerName "127.0.0.1" -Port $Puerto -InformationLevel Quiet -ErrorAction SilentlyContinue
    if ($escuchando) {
        Write-Host "Apache escuchando en el puerto $Puerto correctamente." -ForegroundColor Green
    } else {
        Write-Host "ADVERTENCIA: Apache no responde en el puerto $Puerto." -ForegroundColor Yellow
        $errorLog = "$apacheBase\logs\error.log"
        if (Test-Path $errorLog) {
            Write-Host "Revisando error.log..." -ForegroundColor Gray
            Get-Content $errorLog -Tail 8 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        }
        & "$apacheBase\bin\httpd.exe" -k start 2>&1 | Out-Null
        Start-Sleep -Seconds 3
        $escuchando2 = Test-NetConnection -ComputerName "127.0.0.1" -Port $Puerto -InformationLevel Quiet -ErrorAction SilentlyContinue
        if (-not $escuchando2) {
            Write-Host "Error: Apache no pudo iniciar. Revise $errorLog" -ForegroundColor Red
        }
    }

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
# Seguridad Apache
# ============================================================
function Configurar-Seguridad-Apache {
    param([string]$ApacheBase)

    $secConf = "$ApacheBase\conf\extra\httpd-security.conf"

    @"
ServerTokens Prod
ServerSignature Off
TraceEnable Off

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</IfModule>

<Directory "`${SRVROOT}/htdocs">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>
"@ | Set-Content $secConf -Encoding UTF8

    $confPath = "$ApacheBase\conf\httpd.conf"
    if (-not (Select-String -Path $confPath -Pattern "httpd-security.conf" -Quiet)) {
        Add-Content $confPath "`nInclude conf/extra/httpd-security.conf"
    }

    (Get-Content $confPath) -replace "#LoadModule headers_module", "LoadModule headers_module" |
        Set-Content $confPath

    Write-Host "Seguridad Apache configurada." -ForegroundColor Green
}


# ============================================================
# Nginx Windows: Listar versiones
# ============================================================
function Listar-Versiones-Nginx {

    Write-Host ""
    Write-Host "Consultando versiones disponibles de Nginx..." -ForegroundColor Cyan

    $latest = ""

    $wingetOk = Verificar-Winget
    if ($wingetOk) {
        try {
            $raw = winget show Nginx.Nginx 2>&1 | Out-String
            $versionLine = ($raw -split "`n") | Where-Object { $_ -match "Version\s*:" } | Select-Object -First 1
            if ($versionLine -match ":\s*(.+)") { $latest = $matches[1].Trim() }
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


# ============================================================
# Nginx: Escribir nginx.conf con el puerto indicado
# Mirrors: configurar_puerto_nginx() del script Linux
# ============================================================
function Configurar-Conf-Nginx {
    param([int]$Puerto)

    $nginxBase = "C:\nginx"
    $confPath  = "$nginxBase\conf\nginx.conf"

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
    # Sin BOM para que nginx lea el archivo correctamente
    [System.IO.File]::WriteAllText($confPath, $nginxConf, [System.Text.UTF8Encoding]::new($false))
}


# ============================================================
# Nginx Windows: Instalar y configurar
# ============================================================
function Instalar-Nginx {
    param(
        [string]$Version,
        [int]$Puerto
    )

    $nginxBase = "C:\nginx"

    # ── Detectar si Nginx ya esta instalado ───────────────────────────────────
    $versionInstalada = ""
    if (Test-Path "$nginxBase\nginx.exe") {
        $vOut = (& "$nginxBase\nginx.exe" -v 2>&1) | Out-String
        if ($vOut -match "nginx/([0-9]+\.[0-9]+\.[0-9]+)") {
            $versionInstalada = $matches[1].Trim()
        }
    }

    if ($versionInstalada) {
        Write-Host ""
        Write-Host "Nginx ya esta instalado (version $versionInstalada)." -ForegroundColor Yellow

        if ($versionInstalada -ne $Version) {
            Write-Host "Version solicitada ($Version) difiere de la instalada ($versionInstalada)." -ForegroundColor Yellow
            Write-Host "Se reinstalara Nginx con la version $Version..." -ForegroundColor Cyan
            taskkill /f /im nginx.exe 2>&1 | Out-Null
            Start-Sleep -Seconds 1
            Remove-Item $nginxBase -Recurse -Force -ErrorAction SilentlyContinue
            # Continua hacia instalacion nueva abajo
        } else {
            Write-Host "Misma version solicitada. Solo se actualizara el puerto a $Puerto."
            if (-not (Gestionar-Puerto -Puerto $Puerto)) { return }
            Cambiar-Puerto-Nginx -PuertoNuevo $Puerto

            Crear-Index -Servicio "Nginx" -Version $versionInstalada -Puerto $Puerto -Directorio "$nginxBase\html"

            Write-Host ""
            Write-Host "=====================================" -ForegroundColor Green
            Write-Host " PUERTO ACTUALIZADO                  " -ForegroundColor Green
            Write-Host "=====================================" -ForegroundColor Green
            Write-Host "Servidor : Nginx"
            Write-Host "Version  : $versionInstalada"
            Write-Host "Puerto   : $Puerto"
            Write-Host "=====================================" -ForegroundColor Green
            return
        }
    }

    # ── Instalacion nueva (o reinstalacion) ───────────────────────────────────
    Detener-Servicios-HTTP

    if (-not (Gestionar-Puerto -Puerto $Puerto)) { return }

    Write-Host ""
    Write-Host "Instalando Nginx $Version..." -ForegroundColor Cyan

    $zipName = "nginx-$Version.zip"
    $zipUrl  = "https://nginx.org/download/$zipName"
    $zipDest = "$env:TEMP\nginx.zip"

    Write-Host "Descargando Nginx $Version desde nginx.org..." -ForegroundColor Cyan
    Write-Host "(Esto puede tardar unos segundos)" -ForegroundColor Yellow

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        $wc.DownloadFile($zipUrl, $zipDest)
    } catch {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipDest -UseBasicParsing -ErrorAction Stop
    }

    Write-Host "Extrayendo archivos..." -ForegroundColor Cyan
    Expand-Archive -Path $zipDest -DestinationPath "$env:TEMP\nginx_extract" -Force
    Remove-Item $zipDest -Force -ErrorAction SilentlyContinue

    $extractedDir = Get-ChildItem "$env:TEMP\nginx_extract" -Directory | Select-Object -First 1
    if ($extractedDir) {
        if (Test-Path $nginxBase) { Remove-Item $nginxBase -Recurse -Force }
        Move-Item $extractedDir.FullName $nginxBase
    }
    Remove-Item "$env:TEMP\nginx_extract" -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path "$nginxBase\nginx.exe")) {
        Write-Host "Error: nginx.exe no encontrado tras la instalacion." -ForegroundColor Red
        return
    }

    $versionReal = (& "$nginxBase\nginx.exe" -v 2>&1) | ForEach-Object { ($_.ToString() -split "/")[1] }
    if ($versionReal) { $Version = $versionReal.Trim() }

    $webRoot = "$nginxBase\html"

    Write-Host "Configurando puerto $Puerto..." -ForegroundColor Cyan
    Configurar-Conf-Nginx -Puerto $Puerto

    Crear-Index -Servicio "Nginx" -Version $Version -Puerto $Puerto -Directorio $webRoot

    Crear-Usuario-Restringido -Servicio "Nginx" -Directorio $webRoot

    taskkill /f /im nginx.exe 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden
    Start-Sleep -Seconds 3

    $escuchando = Test-NetConnection -ComputerName localhost -Port $Puerto -WarningAction SilentlyContinue
    if ($escuchando.TcpTestSucceeded) {
        Write-Host "Nginx escuchando en el puerto $Puerto." -ForegroundColor Green
    } else {
        Write-Host "Advertencia: Nginx no responde en el puerto $Puerto." -ForegroundColor Yellow
        $logPath = "$nginxBase\logs\error.log"
        if (Test-Path $logPath) {
            Write-Host "Ultimas lineas del log de error:" -ForegroundColor Yellow
            Get-Content $logPath -Tail 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        }
        Write-Host "Reintentando inicio de Nginx..." -ForegroundColor Cyan
        & "$nginxBase\nginx.exe" -p $nginxBase 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    }

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

    $chars    = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%"
    $password = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    $secPwd   = ConvertTo-SecureString $password -AsPlainText -Force

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

    if (Test-Path $Directorio) {
        $acl = Get-Acl $Directorio

        $acl.SetAccessRuleProtection($true, $false)
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

        $hostname     = $env:COMPUTERNAME
        $usuarioLocal = "$hostname\$usuario"

        $reglaServicio = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $usuarioLocal,
            "ReadAndExecute",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )

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
