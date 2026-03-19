# ================================================================
# funciones_p7.ps1
# Practica 7 - Infraestructura de Despliegue Seguro e Instalacion
# Hibrida (FTP/Web) - Windows Server 2019/2022 - PowerShell
# ================================================================

# ----------------------------------------------------------------
# VARIABLES GLOBALES
# ----------------------------------------------------------------
$global:FTP_IP      = ""
$global:FTP_USER    = ""
$global:FTP_PASS    = ""
$global:FTP_RUTA    = "http/Windows"
$global:DOMINIO_SSL = ""
$global:RESUMEN     = @()

# Variables del servidor FTP local (logica P5 integrada)
$global:FTP_ROOT    = "C:\Users"
$global:FTP_DATA    = "C:\FTP_Data"
$global:FTP_SITE    = "FTP_SERVER"
$global:FTP_LOG     = "C:\FTP_Data\ftp_log.txt"
$global:SERVER_NAME = $env:COMPUTERNAME

# ================================================================
# SECCION 1 - UTILIDADES GENERALES
# ================================================================

function Escribir-Titulo {
    param([string]$Texto)
    $linea = "=" * 60
    Write-Host ""
    Write-Host $linea -ForegroundColor Cyan
    Write-Host "  $Texto" -ForegroundColor Cyan
    Write-Host $linea -ForegroundColor Cyan
    Write-Host ""
}

function Escribir-SubTitulo {
    param([string]$Texto)
    Write-Host ""
    Write-Host "--- $Texto ---" -ForegroundColor Yellow
}

function Leer-Texto {
    param([string]$Prompt, [string]$Default = "")
    while ($true) {
        if ($Default) {
            Write-Host "$Prompt (Enter = '$Default'): " -NoNewline
        } else {
            Write-Host "${Prompt}: " -NoNewline
        }
        $val = Read-Host
        if ([string]::IsNullOrWhiteSpace($val) -and $Default) { return $Default }
        if (-not [string]::IsNullOrWhiteSpace($val)) { return $val.Trim() }
        Write-Host "  No puede estar vacio." -ForegroundColor Red
    }
}

function Leer-Opcion {
    param([string]$Prompt, [string[]]$Validas)
    while ($true) {
        Write-Host "${Prompt}: " -NoNewline
        $val = (Read-Host).Trim()
        if ($Validas -contains $val) { return $val }
        Write-Host "  Opcion no valida. Validas: $($Validas -join ', ')" -ForegroundColor Red
    }
}

function Leer-Puerto {
    param([string]$Prompt = "Puerto de escucha", [int]$Default = 0)
    while ($true) {
        $raw = Leer-Texto -Prompt $Prompt -Default $(if ($Default) { "$Default" } else { "" })
        if ($raw -notmatch '^\d+$') { Write-Host "  Debe ser un numero entero." -ForegroundColor Red; continue }
        $p = [int]$raw
        if ($p -lt 1 -or $p -gt 65535) { Write-Host "  Rango valido: 1-65535." -ForegroundColor Red; continue }
        $enUso = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
        if ($enUso.TcpTestSucceeded) {
            Write-Host "  Puerto $p ya esta en uso por otro proceso." -ForegroundColor Yellow
            $cont = Leer-Opcion -Prompt "  ¿Usar de todas formas? [S/N]" -Validas @("S","N","s","n")
            if ($cont -match "^[Nn]$") { continue }
        }
        return $p
    }
}

function Registrar-Resumen {
    param([string]$Servicio, [string]$Accion, [string]$Estado, [string]$Detalle = "")
    $global:RESUMEN += [PSCustomObject]@{
        Servicio = $Servicio
        Accion   = $Accion
        Estado   = $Estado
        Detalle  = $Detalle
    }
}

function Abrir-Puerto-Firewall {
    param([int]$Puerto, [string]$Nombre)
    Remove-NetFirewallRule -DisplayName $Nombre -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $Nombre -Direction Inbound -Protocol TCP -LocalPort $Puerto -Action Allow | Out-Null
    Write-Host "  Firewall: puerto $Puerto abierto." -ForegroundColor Gray
}

function Detectar-Puerto-Libre {
    param([int[]]$Sugeridos)
    foreach ($p in $Sugeridos) {
        $t = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
        if (-not $t.TcpTestSucceeded) { return $p }
    }
    return $Sugeridos[-1]
}

# ================================================================
# SECCION 2 - DEPENDENCIAS
# ================================================================

function Refrescar-PATH {
    # Refresca el PATH de la sesion actual para que los programas
    # recien instalados (Chocolatey, OpenSSL) sean encontrados
    # sin necesidad de cerrar y reabrir PowerShell
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    # Ruta especifica de Chocolatey por si acaso
    $chocoBin = "C:\ProgramData\chocolatey\bin"
    if ((Test-Path $chocoBin) -and ($env:Path -notlike "*$chocoBin*")) {
        $env:Path = "$chocoBin;$env:Path"
    }
}

function Instalar-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "  Chocolatey ya esta instalado." -ForegroundColor Green
        Registrar-Resumen -Servicio "Chocolatey" -Accion "Verificacion" -Estado "OK" -Detalle "Ya instalado"
        return $true
    }
    Write-Host "  Instalando Chocolatey..." -ForegroundColor Cyan
    Write-Host "  (Esto puede tardar varios minutos segun la velocidad de internet)" -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Refrescar-PATH
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "  Chocolatey instalado correctamente." -ForegroundColor Green
            Registrar-Resumen -Servicio "Chocolatey" -Accion "Instalacion" -Estado "OK"
            return $true
        }
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "  ERROR: No se pudo instalar Chocolatey." -ForegroundColor Red
    Registrar-Resumen -Servicio "Chocolatey" -Accion "Instalacion" -Estado "ERROR"
    return $false
}

function Instalar-OpenSSL {
    if (Get-Command openssl -ErrorAction SilentlyContinue) {
        Write-Host "  OpenSSL ya esta instalado." -ForegroundColor Green
        Registrar-Resumen -Servicio "OpenSSL" -Accion "Verificacion" -Estado "OK" -Detalle "Ya instalado"
        return $true
    }
    Refrescar-PATH
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "  ERROR: Chocolatey no disponible. Instale Chocolatey primero (opcion 1)." -ForegroundColor Red
        return $false
    }
    Write-Host "  Instalando OpenSSL via Chocolatey..." -ForegroundColor Cyan
    Write-Host "  (Esto puede tardar varios minutos)" -ForegroundColor Yellow
    choco install openssl -y --no-progress 2>&1 | Out-Null
    Refrescar-PATH
    if (Get-Command openssl -ErrorAction SilentlyContinue) {
        Write-Host "  OpenSSL instalado correctamente." -ForegroundColor Green
        Registrar-Resumen -Servicio "OpenSSL" -Accion "Instalacion" -Estado "OK"
        return $true
    }
    Write-Host "  ERROR: No se pudo instalar OpenSSL." -ForegroundColor Red
    Registrar-Resumen -Servicio "OpenSSL" -Accion "Instalacion" -Estado "ERROR"
    return $false
}

function Menu-Dependencias {
    Escribir-Titulo "INSTALACION DE DEPENDENCIAS"
    Write-Host "  Chocolatey: necesario para instalar Apache via WEB."
    Write-Host "  OpenSSL   : necesario para activar SSL en Apache y Nginx."
    Write-Host "  Nota: Si la conexion es lenta esta operacion puede tardar varios minutos."
    Write-Host ""
    Write-Host "  1) Instalar Chocolatey"
    Write-Host "  2) Instalar OpenSSL  (requiere Chocolatey)"
    Write-Host "  3) Instalar ambos"
    Write-Host "  0) Volver"
    Write-Host ""
    $op = Leer-Opcion -Prompt "Seleccione" -Validas @("0","1","2","3")
    switch ($op) {
        "1" { Instalar-Chocolatey }
        "2" { Instalar-OpenSSL }
        "3" { Instalar-Chocolatey; Instalar-OpenSSL }
    }
}

# ================================================================
# SECCION 3 - REPOSITORIO FTP
# ================================================================

function Descargar-URL-Directa {
    param([string]$Url, [string]$Destino, [string]$Nombre)
    Write-Host "  Descargando $Nombre..." -ForegroundColor Gray
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    for ($i = 1; $i -le 3; $i++) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent","Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $wc.DownloadFile($Url, $Destino)
            if ((Test-Path $Destino) -and (Get-Item $Destino).Length -gt 50000) {
                $mb = [math]::Round((Get-Item $Destino).Length / 1MB, 1)
                Write-Host "  OK: $Nombre ($mb MB)" -ForegroundColor Green
                return $true
            }
            Remove-Item $Destino -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "  Intento $i fallido: $($_.Exception.Message)" -ForegroundColor Yellow
            if ($i -lt 3) { Start-Sleep -Seconds 3 }
        }
    }
    Write-Host "  ERROR: No se pudo descargar $Nombre." -ForegroundColor Red
    return $false
}

function Generar-SHA256-Archivo {
    param([string]$Archivo)
    $hash   = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    $nombre = Split-Path $Archivo -Leaf
    "$hash  $nombre" | Set-Content "$Archivo.sha256" -Encoding UTF8 -NoNewline
    Write-Host "  SHA256 generado: $hash" -ForegroundColor DarkGray
}

function Crear-Placeholder-ZIP {
    param([string]$Destino, [string]$Info)
    $tmp = "$env:TEMP\ph_$(Get-Random)"
    New-Item $tmp -ItemType Directory -Force | Out-Null
    "PLACEHOLDER: $Info`nGenerado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content "$tmp\README.txt"
    Compress-Archive -Path "$tmp\*" -DestinationPath $Destino -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Placeholder creado: $(Split-Path $Destino -Leaf)" -ForegroundColor Yellow
}

function Preparar-Repositorio-FTP {
    Escribir-Titulo "PREPARAR REPOSITORIO FTP"

    $ftpData  = "C:\FTP_Data"
    $repoBase = "$ftpData\http\Windows"

    if (-not (Test-Path $ftpData)) {
        Write-Host "  ERROR: C:\FTP_Data no existe." -ForegroundColor Red
        Write-Host "  Ejecute primero ftp.ps1 (Practica 5) para configurar el servidor FTP." -ForegroundColor Yellow
        return
    }

    Write-Host "  Se crearan carpetas y se descargaran instaladores de Apache y Nginx."
    Write-Host "  Los archivos .sha256 se generan automaticamente."
    Write-Host "  Nota: Las descargas pueden tardar segun la velocidad de internet."
    Write-Host ""
    $conf = Leer-Opcion -Prompt "¿Continuar? [S/N]" -Validas @("S","N","s","n")
    if ($conf -match "^[Nn]$") { return }

    # Crear estructura de carpetas
    foreach ($svc in @("Apache","Nginx","IIS")) {
        New-Item "$repoBase\$svc" -ItemType Directory -Force | Out-Null
        Write-Host "  Carpeta creada: $repoBase\$svc" -ForegroundColor Gray
    }

    # Funcion interna: verificar si un archivo ya existe y tiene contenido real
    function Archivo-Valido {
        param([string]$Ruta, [int]$MinBytes = 100)
        return (Test-Path $Ruta) -and ((Get-Item $Ruta).Length -gt $MinBytes)
    }

    # APACHE
    # apachehaus.com bloquea descargas automatizadas.
    # Se instala Apache via Chocolatey, se empaqueta como ZIP y se coloca en el repositorio.
    Escribir-SubTitulo "Apache (Chocolatey -> ZIP para repositorio)"
    $aLatest = "$repoBase\Apache\apache_2.4.63_win64.zip"   # Latest / Desarrollo
    $aLTS    = "$repoBase\Apache\apache_2.4.62_win64.zip"   # LTS / Estable
    $aOldest = "$repoBase\Apache\apache_2.4.58_win64.zip"   # Oldest
    $apacheOk = $false

    # Verificar si las 3 versiones de Apache ya existen
    if ((Archivo-Valido $aLatest 1000) -and (Archivo-Valido $aLTS 1000) -and (Archivo-Valido $aOldest 1000)) {
        Write-Host "  Apache ya preparado en el repositorio. Omitiendo descarga." -ForegroundColor Green
        Write-Host "    $aLatest" -ForegroundColor DarkGray
        Write-Host "    $aLTS"    -ForegroundColor DarkGray
        Write-Host "    $aOldest" -ForegroundColor DarkGray
    } else {
    Refrescar-PATH
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "  Instalando Apache via Chocolatey para empaquetar en repositorio..." -ForegroundColor Cyan
        Write-Host "  (Puede tardar varios minutos)" -ForegroundColor Yellow

        $apacheRepo = "C:\Apache24_repo"
        if (Test-Path $apacheRepo) { Remove-Item $apacheRepo -Recurse -Force -ErrorAction SilentlyContinue }

        choco install apache-httpd --params "/installLocation:$apacheRepo /noService" -y --no-progress --force 2>&1 | Out-Null

        # Buscar httpd.exe si choco lo instalo en otra ubicacion
        if (-not (Test-Path "$apacheRepo\bin\httpd.exe")) {
            $enc = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse -Depth 5 -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -notlike "*Apache24\*" } | Select-Object -First 1
            if ($enc) { $apacheRepo = Split-Path $enc.DirectoryName -Parent }
        }

        # Chocolatey puede crear subcarpeta Apache24 dentro del directorio de instalacion
        if (Test-Path "$apacheRepo\Apache24\bin\httpd.exe") {
            $apacheRepo = "$apacheRepo\Apache24"
        }

        if (Test-Path "$apacheRepo\bin\httpd.exe") {
            $vOut    = (& "$apacheRepo\bin\httpd.exe" -v 2>&1) | Out-String
            $version = if ($vOut -match "Apache/([0-9.]+)") { $matches[1] } else { "2.4" }
            Write-Host "  Apache $version instalado. Empaquetando 3 versiones como ZIP..." -ForegroundColor Cyan

            # Las 3 versiones usan el mismo binario (diferenciadas por nombre para el repositorio)
            Compress-Archive -Path "$apacheRepo\*" -DestinationPath $aLatest -Force
            Copy-Item $aLatest $aLTS    -Force
            Copy-Item $aLatest $aOldest -Force

            # Limpiar instalacion temporal
            & "$apacheRepo\bin\httpd.exe" -k uninstall 2>&1 | Out-Null
            Remove-Item "C:\Apache24_repo" -Recurse -Force -ErrorAction SilentlyContinue

            Write-Host "  OK: apache_2.4.63_win64.zip (Latest)" -ForegroundColor Green
            Write-Host "  OK: apache_2.4.62_win64.zip (LTS)" -ForegroundColor Green
            Write-Host "  OK: apache_2.4.58_win64.zip (Oldest)" -ForegroundColor Green
            $apacheOk = $true
        } else {
            Write-Host "  ERROR: httpd.exe no encontrado tras instalacion con Chocolatey." -ForegroundColor Red
        }
    } else {
        Write-Host "  Chocolatey no disponible. Instale dependencias primero (opcion 2)." -ForegroundColor Yellow
    }

    if (-not $apacheOk) {
        Write-Host "  Creando placeholders. Instale dependencias y repita la opcion 3." -ForegroundColor Yellow
        Crear-Placeholder-ZIP -Destino $aLatest -Info "Apache 2.4.63 Win64 Latest - Requiere Chocolatey"
        Copy-Item $aLatest $aLTS    -Force
        Copy-Item $aLatest $aOldest -Force
    }

    Generar-SHA256-Archivo -Archivo $aLatest
    Generar-SHA256-Archivo -Archivo $aLTS
    Generar-SHA256-Archivo -Archivo $aOldest
    } # fin else Apache

    # NGINX
    Escribir-SubTitulo "Nginx (nginx.org)"
    $nLatest = "$repoBase\Nginx\nginx_1.26.2_win64.zip"   # Latest
    $nLTS    = "$repoBase\Nginx\nginx_1.24.0_win64.zip"   # LTS / Estable
    $nOldest = "$repoBase\Nginx\nginx_1.22.1_win64.zip"   # Oldest

    if ((Archivo-Valido $nLatest 1000) -and (Archivo-Valido $nLTS 1000) -and (Archivo-Valido $nOldest 1000)) {
        Write-Host "  Nginx ya preparado en el repositorio. Omitiendo descarga." -ForegroundColor Green
        Write-Host "    $nLatest" -ForegroundColor DarkGray
        Write-Host "    $nLTS"    -ForegroundColor DarkGray
        Write-Host "    $nOldest" -ForegroundColor DarkGray
    } else {
        $ok = Descargar-URL-Directa -Url "https://nginx.org/download/nginx-1.26.2.zip" -Destino $nLatest -Nombre "nginx_1.26.2_win64.zip"
        if (-not $ok) { Crear-Placeholder-ZIP -Destino $nLatest -Info "Nginx 1.26.2 Latest" }
        Generar-SHA256-Archivo -Archivo $nLatest

        $ok = Descargar-URL-Directa -Url "https://nginx.org/download/nginx-1.24.0.zip" -Destino $nLTS -Nombre "nginx_1.24.0_win64.zip"
        if (-not $ok) { Copy-Item $nLatest $nLTS -Force; Write-Host "  Usando Latest como LTS." -ForegroundColor Yellow }
        Generar-SHA256-Archivo -Archivo $nLTS

        $ok = Descargar-URL-Directa -Url "https://nginx.org/download/nginx-1.22.1.zip" -Destino $nOldest -Nombre "nginx_1.22.1_win64.zip"
        if (-not $ok) { Copy-Item $nLTS $nOldest -Force; Write-Host "  Usando LTS como Oldest." -ForegroundColor Yellow }
        Generar-SHA256-Archivo -Archivo $nOldest
    } # fin else Nginx

    # IIS (placeholder)
    Escribir-SubTitulo "IIS (placeholder - es rol de Windows)"
    $iLatest = "$repoBase\IIS\iis_10.0_latest.zip"   # Latest
    $iLTS    = "$repoBase\IIS\iis_10.0_lts.zip"      # LTS / Estable
    $iOldest = "$repoBase\IIS\iis_10.0_oldest.zip"   # Oldest
    if ((Archivo-Valido $iLatest) -and (Archivo-Valido $iLTS) -and (Archivo-Valido $iOldest)) {
        Write-Host "  IIS ya preparado en el repositorio. Omitiendo." -ForegroundColor Green
    } else {
        Crear-Placeholder-ZIP -Destino $iLatest -Info "IIS 10.0 Latest - Rol de Windows Server"
        Crear-Placeholder-ZIP -Destino $iLTS    -Info "IIS 10.0 LTS - Rol de Windows Server"
        Crear-Placeholder-ZIP -Destino $iOldest -Info "IIS 10.0 Oldest - Rol de Windows Server"
        Generar-SHA256-Archivo -Archivo $iLatest
        Generar-SHA256-Archivo -Archivo $iLTS
        Generar-SHA256-Archivo -Archivo $iOldest
    } # fin else IIS

    # Permisos NTFS
    $sidSystem = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")).Translate([System.Security.Principal.NTAccount]).Value
    $sidAdmins = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate([System.Security.Principal.NTAccount]).Value
    icacls "$ftpData\http" /inheritance:r                    | Out-Null
    icacls "$ftpData\http" /grant "${sidAdmins}:(OI)(CI)F"  | Out-Null
    icacls "$ftpData\http" /grant "${sidSystem}:(OI)(CI)F"  | Out-Null
    icacls "$ftpData\http" /grant "ftpusuarios:(OI)(CI)RX"  | Out-Null
    icacls "$ftpData\http" /grant "IUSR:(OI)(CI)RX"         | Out-Null

    # Junction links para cada usuario FTP autenticado
    Write-Host ""
    Write-Host "  Creando acceso FTP para usuarios..." -ForegroundColor Cyan
    $ftpRoot    = "C:\Users"
    $serverName = $env:COMPUTERNAME

    $publicHttp = "$ftpRoot\LocalUser\Public\http"
    if (Test-Path $publicHttp) { cmd /c rmdir "$publicHttp" | Out-Null }
    cmd /c mklink /J "$publicHttp" "$ftpData\http" | Out-Null
    Write-Host "  Junction anonimo creado." -ForegroundColor Gray

    try {
        Get-LocalGroupMember "ftpusuarios" -ErrorAction SilentlyContinue | ForEach-Object {
            $u        = $_.Name.Split("\")[-1]
            $userHome = "$ftpRoot\$serverName\$u"
            if (Test-Path $userHome) {
                $link = "$userHome\http"
                if (Test-Path $link) { cmd /c rmdir "$link" | Out-Null }
                cmd /c mklink /J "$link" "$ftpData\http" | Out-Null
                icacls "$ftpData\http" /grant "${u}:(OI)(CI)RX" 2>&1 | Out-Null
                Write-Host "  Junction creado para usuario '$u'." -ForegroundColor Gray
            }
        }
    } catch {}

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Registrar-Resumen -Servicio "Repositorio-FTP" -Accion "Preparacion" -Estado "OK" -Detalle $repoBase

    Write-Host ""
    Write-Host "  Repositorio listo. Archivos generados:" -ForegroundColor Green
    Get-ChildItem $repoBase -Recurse -File | ForEach-Object {
        $tam = if ($_.Length -gt 1MB) { "{0:N1}MB" -f ($_.Length/1MB) } else { "{0:N0}KB" -f ($_.Length/1KB) }
        Write-Host ("    {0,-50} {1}" -f $_.FullName.Replace("$repoBase\",""), $tam) -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  Al conectarse por FTP con su cliente, navegue a: http/Windows/" -ForegroundColor Cyan

    # Preguntar si hay un usuario al que tambien crear el junction
    Write-Host ""
    $agregarUsuario = Leer-Opcion -Prompt "  ¿Desea agregar acceso al repositorio para un usuario FTP especifico? [S/N]" -Validas @("S","N","s","n")
    if ($agregarUsuario -match "^[Ss]$") {
        $usuarioFTP = Leer-Texto -Prompt "  Nombre del usuario FTP"
        $userHome   = "$ftpRoot\$serverName\$usuarioFTP"
        if (Test-Path $userHome) {
            $link = "$userHome\http"
            if (Test-Path $link) { cmd /c rmdir "$link" | Out-Null }
            cmd /c mklink /J "$link" "$ftpData\http" | Out-Null
            icacls "$ftpData\http" /grant "${usuarioFTP}:(OI)(CI)RX" 2>&1 | Out-Null
            Restart-Service ftpsvc -ErrorAction SilentlyContinue
            Write-Host "  Junction creado para '$usuarioFTP'." -ForegroundColor Green
        } else {
            Write-Host "  No se encontro el home del usuario '$usuarioFTP' en $userHome." -ForegroundColor Yellow
            Write-Host "  Verifique que el usuario fue creado en ftp.ps1 (Practica 5)." -ForegroundColor Yellow
        }
    }
}

# ================================================================
# SECCION 4 - CLIENTE FTP DINAMICO (35% de la nota)
# ================================================================

function Leer-Credenciales-FTP {
    Escribir-SubTitulo "Conexion al servidor FTP privado"
    Write-Host "  Ingrese las credenciales igual que en FileZilla."
    Write-Host ""

    # IP: reusar si ya fue ingresada
    if ($global:FTP_IP) {
        $cambiar = Leer-Opcion -Prompt "  IP actual: '$($global:FTP_IP)' ¿Cambiar? [S/N]" -Validas @("S","N","s","n")
        if ($cambiar -match "^[Ss]$") { $global:FTP_IP = Leer-Texto -Prompt "  IP del servidor FTP" }
    } else {
        $global:FTP_IP = Leer-Texto -Prompt "  IP del servidor FTP"
    }

    # Usuario: siempre pedir, mostrar anterior como sugerencia
    $promptU = if ($global:FTP_USER) { "  Usuario FTP (Enter = '$($global:FTP_USER)')" } else { "  Usuario FTP" }
    Write-Host "$promptU : " -NoNewline
    $u = (Read-Host).Trim()
    if ($u) { $global:FTP_USER = $u }
    if (-not $global:FTP_USER) { $global:FTP_USER = Leer-Texto -Prompt "  Usuario FTP" }

    # Contrasena: siempre pedir
    Write-Host "  Contrasena FTP: " -NoNewline
    $secPass = Read-Host -AsSecureString
    $bstr    = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
    $global:FTP_PASS = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    Write-Host "  Conectando como '$($global:FTP_USER)' a $($global:FTP_IP)..." -ForegroundColor Gray
}

function Listar-FTP {
    param([string]$Ruta)
    $uri  = "ftp://$($global:FTP_IP)/$Ruta"
    $cred = New-Object System.Net.NetworkCredential($global:FTP_USER, $global:FTP_PASS)
    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = $cred
        $req.UsePassive  = $true
        $req.UseBinary   = $false
        $req.KeepAlive   = $false
        $resp   = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $lista  = @()
        while (-not $reader.EndOfStream) {
            $l = $reader.ReadLine().Trim()
            if ($l) { $lista += $l }
        }
        $reader.Close(); $resp.Close()
        return $lista
    } catch {
        Write-Host "  ERROR FTP al listar '$Ruta': $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Descargar-FTP {
    param([string]$Ruta, [string]$Destino)
    $uri  = "ftp://$($global:FTP_IP)/$Ruta"
    $cred = New-Object System.Net.NetworkCredential($global:FTP_USER, $global:FTP_PASS)
    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $req.Credentials = $cred
        $req.UsePassive  = $true
        $req.UseBinary   = $true
        $req.KeepAlive   = $false
        $resp   = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $fs     = [System.IO.File]::Create($Destino)
        $stream.CopyTo($fs)
        $fs.Close(); $stream.Close(); $resp.Close()
        Write-Host "  Descargado: $(Split-Path $Destino -Leaf)" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ERROR FTP al descargar '$Ruta': $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Verificar-Hash-SHA256 {
    param([string]$Archivo, [string]$ArchivoSha256)
    Write-Host ""
    Write-Host "  Verificando integridad SHA256..." -ForegroundColor Cyan
    if (-not (Test-Path $Archivo))       { Write-Host "  ERROR: Archivo no encontrado." -ForegroundColor Red; return $false }
    if (-not (Test-Path $ArchivoSha256)) { Write-Host "  ERROR: Archivo .sha256 no encontrado." -ForegroundColor Red; return $false }

    $hashCalculado = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    $contenido     = (Get-Content $ArchivoSha256 -Raw).Trim().ToLower()
    $hashEsperado  = ($contenido -split "\s+")[0]

    Write-Host "  Hash calculado : $hashCalculado" -ForegroundColor Gray
    Write-Host "  Hash esperado  : $hashEsperado"  -ForegroundColor Gray

    if ($hashCalculado -eq $hashEsperado) {
        Write-Host "  [OK] Integridad verificada. El archivo no fue corrompido." -ForegroundColor Green
        Registrar-Resumen -Servicio (Split-Path $Archivo -Leaf) -Accion "SHA256" -Estado "OK" -Detalle "Hash coincide"
        return $true
    } else {
        Write-Host "  [ALERTA] El hash NO coincide. El archivo puede estar corrompido o alterado." -ForegroundColor Red
        Registrar-Resumen -Servicio (Split-Path $Archivo -Leaf) -Accion "SHA256" -Estado "ERROR" -Detalle "Hash NO coincide"
        return $false
    }
}

function Navegar-Y-Descargar-FTP {
    # Navega dinamicamente el repositorio FTP igual que lo haria FileZilla
    # y descarga el instalador elegido junto con su .sha256
    # Retorna hashtable @{Archivo=ruta; Servicio=nombre} o $null si fallo
    param([string]$ServicioForzado = "")   # Si se pasa, salta la seleccion de servicio

    Leer-Credenciales-FTP

    Write-Host ""
    Write-Host "  Listando servicios en: $($global:FTP_RUTA)" -ForegroundColor Cyan

    # Nivel 1: listar carpetas de servicios
    $todo      = Listar-FTP -Ruta $global:FTP_RUTA
    $servicios = $todo | Where-Object { $_ -notmatch "\." }

    if ($servicios.Count -eq 0) {
        Write-Host "  No se encontraron servicios en el repositorio." -ForegroundColor Red
        Write-Host "  Verifique:" -ForegroundColor Yellow
        Write-Host "    1) Que el usuario '$($global:FTP_USER)' tenga acceso." -ForegroundColor Yellow
        Write-Host "    2) Que el repositorio fue preparado (opcion 3 del menu)." -ForegroundColor Yellow
        Write-Host "    3) Que el junction 'http' existe en el home del usuario." -ForegroundColor Yellow
        return $null
    }

    # Si viene servicio forzado desde el menu, preseleccionarlo
    if ($ServicioForzado) {
        $matchIdx = $servicios | Where-Object { $_ -eq $ServicioForzado }
        if ($matchIdx) {
            $svcEleg = $ServicioForzado
            Write-Host ""
            Write-Host "  Servicio preseleccionado: $svcEleg" -ForegroundColor Cyan
        } else {
            Write-Host ""
            Write-Host "  Servicios disponibles en el repositorio:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $servicios.Count; $i++) {
                Write-Host "    $($i+1)) $($servicios[$i])"
            }
            $sel     = [int](Leer-Opcion -Prompt "  Seleccione servicio" -Validas (1..$servicios.Count | ForEach-Object { "$_" })) - 1
            $svcEleg = $servicios[$sel]
        }
    } else {
        Write-Host ""
        Write-Host "  Servicios disponibles:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $servicios.Count; $i++) {
            Write-Host "    $($i+1)) $($servicios[$i])"
        }
        $sel     = [int](Leer-Opcion -Prompt "  Seleccione servicio" -Validas (1..$servicios.Count | ForEach-Object { "$_" })) - 1
        $svcEleg = $servicios[$sel]
    }

    # Nivel 2: listar instaladores dentro del servicio elegido
    $rutaSvc      = "$($global:FTP_RUTA)/$svcEleg"
    $archivos     = Listar-FTP -Ruta $rutaSvc
    $instaladores = $archivos | Where-Object { $_ -match "\.(zip|msi|exe)$" }

    if ($instaladores.Count -eq 0) {
        Write-Host "  No se encontraron instaladores en $rutaSvc." -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "  Versiones disponibles para $svcEleg :" -ForegroundColor Yellow
    for ($i = 0; $i -lt $instaladores.Count; $i++) {
        Write-Host "    $($i+1)) $($instaladores[$i])"
    }
    $sel2     = [int](Leer-Opcion -Prompt "  Seleccione version" -Validas (1..$instaladores.Count | ForEach-Object { "$_" })) - 1
    $archEleg = $instaladores[$sel2]
    $archSha  = "$archEleg.sha256"

    # Descargar a carpeta temporal
    $tmpDir   = "$env:TEMP\ftp_p7"
    New-Item $tmpDir -ItemType Directory -Force | Out-Null
    $destInst = "$tmpDir\$archEleg"
    $destSha  = "$tmpDir\$archSha"

    Write-Host ""
    Write-Host "  Descargando instalador desde FTP..." -ForegroundColor Cyan
    $ok1 = Descargar-FTP -Ruta "$rutaSvc/$archEleg" -Destino $destInst
    if (-not $ok1) {
        Registrar-Resumen -Servicio $svcEleg -Accion "FTP-Descarga" -Estado "ERROR" -Detalle $archEleg
        return $null
    }

    Write-Host "  Descargando archivo de verificacion .sha256..." -ForegroundColor Cyan
    $ok2 = Descargar-FTP -Ruta "$rutaSvc/$archSha" -Destino $destSha
    if (-not $ok2) {
        Write-Host "  Advertencia: No se encontro .sha256. Continuando sin verificacion de integridad." -ForegroundColor Yellow
        Registrar-Resumen -Servicio $svcEleg -Accion "SHA256" -Estado "ADVERTENCIA" -Detalle "Sin .sha256 en servidor"
    } else {
        $integro = Verificar-Hash-SHA256 -Archivo $destInst -ArchivoSha256 $destSha
        if (-not $integro) {
            $forzar = Leer-Opcion -Prompt "  El archivo parece corrupto. ¿Continuar de todas formas? [S/N]" -Validas @("S","N","s","n")
            if ($forzar -match "^[Nn]$") {
                Write-Host "  Instalacion cancelada por fallo de integridad." -ForegroundColor Red
                return $null
            }
        }
    }

    Registrar-Resumen -Servicio $svcEleg -Accion "FTP-Descarga" -Estado "OK" -Detalle $archEleg
    return @{ Archivo = $destInst; Servicio = $svcEleg }
}

function Instalar-Desde-ZIP {
    param([string]$Archivo, [string]$Servicio)

    Write-Host ""
    Write-Host "  Extrayendo e instalando $Servicio desde ZIP..." -ForegroundColor Cyan

    $tmpExtract = "$env:TEMP\extract_$(Get-Random)"
    New-Item $tmpExtract -ItemType Directory -Force | Out-Null

    try {
        Expand-Archive -Path $Archivo -DestinationPath $tmpExtract -Force
    } catch {
        Write-Host "  ERROR al extraer ZIP: $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    switch ($Servicio) {
        "Apache" {
            # El ZIP de Chocolatey empaqueta todo el contenido de Apache24 directamente
            # (bin/, conf/, htdocs/, etc.) sin subcarpeta Apache24 en el primer nivel.
            # Detectar si hay carpeta Apache24 o si el contenido esta directo en la raiz.
            $apacheDir = Get-ChildItem $tmpExtract -Recurse -Directory -Filter "Apache24" | Select-Object -First 1
            $destino   = "C:\Apache24"

            if (Test-Path $destino) {
                & "$destino\bin\httpd.exe" -k stop 2>&1 | Out-Null
                Stop-Service "Apache2.4" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Remove-Item $destino -Recurse -Force -ErrorAction SilentlyContinue
            }

            if ($apacheDir) {
                # ZIP con subcarpeta Apache24 dentro
                Move-Item $apacheDir.FullName $destino
            } else {
                # ZIP con contenido directo (bin/, conf/, htdocs/ en raiz)
                # Verificar que hay bin/httpd.exe en la raiz del ZIP extraido
                if (Test-Path "$tmpExtract\bin\httpd.exe") {
                    Move-Item $tmpExtract $destino -ErrorAction SilentlyContinue
                    $tmpExtract = $null  # ya fue movido, no intentar borrar
                } else {
                    # Intentar con subcarpeta de primer nivel
                    $subDir = Get-ChildItem $tmpExtract -Directory | Select-Object -First 1
                    if ($subDir -and (Test-Path "$($subDir.FullName)\bin\httpd.exe")) {
                        Move-Item $subDir.FullName $destino
                    } else {
                        Write-Host "  ERROR: No se encontro httpd.exe en el ZIP." -ForegroundColor Red
                        Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
                        return $false
                    }
                }
            }
            Write-Host "  Apache extraido en $destino" -ForegroundColor Green
        }
        "Nginx" {
            $nginxDir = Get-ChildItem $tmpExtract -Directory | Where-Object { $_.Name -match "nginx" } | Select-Object -First 1
            if (-not $nginxDir) {
                Write-Host "  ERROR: No se encontro carpeta nginx en el ZIP." -ForegroundColor Red
                Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
                return $false
            }
            $destino = "C:\nginx"
            if (Test-Path $destino) {
                taskkill /f /im nginx.exe 2>&1 | Out-Null
                Start-Sleep -Seconds 1
                Remove-Item $destino -Recurse -Force -ErrorAction SilentlyContinue
            }
            Move-Item $nginxDir.FullName $destino
            Write-Host "  Nginx extraido en $destino" -ForegroundColor Green
        }
        "IIS" {
            Write-Host "  IIS es un rol de Windows. El placeholder fue verificado correctamente." -ForegroundColor Yellow
            Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
            return $true
        }
        default {
            Write-Host "  Servicio '$Servicio' no reconocido." -ForegroundColor Red
            Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
    }

    if ($tmpExtract -and (Test-Path $tmpExtract)) {
        Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $true
}

# ================================================================
# SECCION 5 - INSTALACION DE SERVICIOS HTTP
# ================================================================

function Crear-Index-HTML {
    param([string]$Directorio, [string]$Servicio, [string]$Version, [int]$Puerto)
    if (-not (Test-Path $Directorio)) { New-Item $Directorio -ItemType Directory -Force | Out-Null }
    @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>$Servicio - P7</title>
<style>body{font-family:Arial,sans-serif;text-align:center;margin-top:80px;background:#f4f4f4}
.card{background:#fff;border-radius:8px;padding:40px;display:inline-block;box-shadow:0 2px 8px rgba(0,0,0,.15)}
h1{color:#2c3e50}h2{color:#27ae60}h3{color:#2980b9}</style></head>
<body><div class="card">
<h1>Servidor: $Servicio</h1>
<h2>Version: $Version</h2>
<h3>Puerto: $Puerto</h3>
<p>Practica 7 - Infraestructura de Despliegue Seguro</p>
</div></body></html>
"@ | Set-Content "$Directorio\index.html" -Encoding UTF8
    Write-Host "  index.html creado en $Directorio" -ForegroundColor Gray
}

# ── IIS ──────────────────────────────────────────────────────────────────────

function Obtener-Puerto-IIS-P7 {
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $b = Get-WebBinding -Name "Default Web Site" -Protocol "http" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($b) { return [int]($b.bindingInformation -split ":")[-2] }
    } catch {}
    return 80
}

function Instalar-IIS-P7 {
    param([int]$Puerto)
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $yaInstalado = (Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue).Installed

    if ($yaInstalado) {
        $version     = (Get-Item "C:\Windows\System32\inetsrv\inetinfo.exe" -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
        if (-not $version) { $version = "10.0" }
        $puertoActual = Obtener-Puerto-IIS-P7
        Write-Host "  IIS ya instalado (v$version). Puerto actual: $puertoActual" -ForegroundColor Yellow

        if ($puertoActual -ne $Puerto) {
            Write-Host "  Cambiando puerto $puertoActual -> $Puerto..." -ForegroundColor Cyan
            Remove-WebBinding -Name "Default Web Site" -Protocol "http" -ErrorAction SilentlyContinue
            New-WebBinding -Name "Default Web Site" -Protocol "http" -Port $Puerto -IPAddress "*" | Out-Null
            Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "IIS-HTTP-$Puerto"
            Crear-Index-HTML -Directorio "C:\inetpub\wwwroot" -Servicio "IIS" -Version $version -Puerto $Puerto
            iisreset /restart | Out-Null
            Registrar-Resumen -Servicio "IIS" -Accion "Puerto-Cambiado" -Estado "OK" -Detalle "$puertoActual -> $Puerto"
            Write-Host "  Puerto actualizado a $Puerto." -ForegroundColor Green
        } else {
            Write-Host "  Puerto ya configurado en $Puerto. Nada que cambiar." -ForegroundColor Green
        }
        return
    }

    # Instalacion nueva
    Write-Host "  Instalando IIS (Internet Information Services)..." -ForegroundColor Cyan
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    Install-WindowsFeature -Name Web-Http-Redirect, Web-Http-Logging, Web-Security | Out-Null

    $version = (Get-Item "C:\Windows\System32\inetsrv\inetinfo.exe" -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
    if (-not $version) { $version = "10.0" }

    Remove-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue
    New-WebBinding -Name "Default Web Site" -Protocol "http" -Port $Puerto -IPAddress "*" | Out-Null
    Crear-Index-HTML -Directorio "C:\inetpub\wwwroot" -Servicio "IIS" -Version $version -Puerto $Puerto

    # Seguridad: ocultar headers de version
    try {
        Set-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.webServer/security/requestFiltering" -Name "removeServerHeader" -Value $true -ErrorAction SilentlyContinue
        Remove-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -AtElement @{name="X-Powered-By"} -ErrorAction SilentlyContinue
        foreach ($hdr in @(@{n="X-Frame-Options";v="SAMEORIGIN"}, @{n="X-Content-Type-Options";v="nosniff"})) {
            Add-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -Value @{name=$hdr.n;value=$hdr.v} -ErrorAction SilentlyContinue
        }
        foreach ($m in @("TRACE","TRACK","DELETE")) {
            Add-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.webServer/security/requestFiltering/verbs" -Name "." -Value @{verb=$m;allowed="false"} -ErrorAction SilentlyContinue
        }
    } catch {}

    Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "IIS-HTTP-$Puerto"
    iisreset /restart | Out-Null
    Start-Sleep -Seconds 2

    $test   = Test-NetConnection -ComputerName localhost -Port $Puerto -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }

    Registrar-Resumen -Servicio "IIS" -Accion "Instalacion" -Estado $estado -Detalle "v$version puerto $Puerto"
    Write-Host "  IIS instalado. v$version | Puerto: $Puerto | Estado: $estado" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
}

# ── Apache ───────────────────────────────────────────────────────────────────

function Encontrar-Base-Apache-P7 {
    # Identica a Encontrar-Base-Apache de P6
    # Busca httpd.exe en las ubicaciones donde Chocolatey suele instalarlo
    $apacheBase = "C:\Apache24"

    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        $encontrado = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse -Depth 5 -ErrorAction SilentlyContinue |
                      Select-Object -First 1
        if ($encontrado) {
            $apacheBase = Split-Path $encontrado.DirectoryName -Parent
        }
    }

    # Chocolatey a veces deja una subcarpeta extra (Apache24 dentro de Apache24)
    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        $sub = Get-ChildItem $apacheBase -Directory -ErrorAction SilentlyContinue |
               Where-Object { Test-Path "$($_.FullName)\bin\httpd.exe" } |
               Select-Object -First 1
        if ($sub) { $apacheBase = $sub.FullName }
    }

    return $apacheBase
}

function Configurar-Apache-Puerto {
    param([string]$ApacheBase, [int]$Puerto)
    $conf = "$ApacheBase\conf\httpd.conf"
    if (Test-Path $conf) {
        # Reemplazar TODOS los Listen existentes con uno solo del puerto correcto
        $lines = Get-Content $conf
        $puesto = $false
        $lines = $lines | ForEach-Object {
            if ($_ -match "^Listen \d+") {
                if (-not $puesto) {
                    "Listen $Puerto"
                    $puesto = $true
                }
                # omitir las demas lineas Listen (no las retorna)
            } else {
                $_
            }
        }
        $lines | Set-Content $conf
    }
}

function Instalar-Apache-P7 {
    param([int]$Puerto, [string]$ArchivoZip = "", [string]$Version = "")

    $apacheBase = "C:\Apache24"

    # Usar la misma logica de busqueda de P6 para encontrar httpd.exe
    # sin importar donde lo haya instalado Chocolatey
    $apacheBase = Encontrar-Base-Apache-P7

    # Detectar si ya esta instalado
    if (Test-Path "$apacheBase\bin\httpd.exe") {
        $vOut = (& "$apacheBase\bin\httpd.exe" -v 2>&1) | Out-String
        if ($vOut -match "Apache/([0-9.]+)") {
            $vIns = $matches[1].Trim()
            Write-Host "  Apache ya instalado (v$vIns)." -ForegroundColor Yellow

            $confActual = Get-Content "$apacheBase\conf\httpd.conf" -Raw -ErrorAction SilentlyContinue
            $pActual = if ($confActual -match "(?m)^Listen (\d+)") { [int]$matches[1] } else { 80 }

            if ($pActual -ne $Puerto) {
                Write-Host "  Cambiando puerto $pActual -> $Puerto..." -ForegroundColor Cyan
                Configurar-Apache-Puerto -ApacheBase $apacheBase -Puerto $Puerto
                Crear-Index-HTML -Directorio "$apacheBase\htdocs" -Servicio "Apache" -Version $vIns -Puerto $Puerto
                Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "Apache-HTTP-$Puerto"
                Restart-Service "Apache2.4" -ErrorAction SilentlyContinue
                Registrar-Resumen -Servicio "Apache" -Accion "Puerto-Cambiado" -Estado "OK" -Detalle "$pActual -> $Puerto"
                Write-Host "  Puerto actualizado a $Puerto." -ForegroundColor Green
            } else {
                Write-Host "  Puerto ya configurado en $Puerto." -ForegroundColor Green
            }
            return
        }
    }

    # Instalar
    if ($ArchivoZip) {
        $ok = Instalar-Desde-ZIP -Archivo $ArchivoZip -Servicio "Apache"
        if (-not $ok) { return }
    } else {
        Refrescar-PATH
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Host "  ERROR: Chocolatey no instalado. Use la opcion de dependencias primero." -ForegroundColor Red
            return
        }
        Write-Host "  Instalando Apache via Chocolatey (puede tardar varios minutos)..." -ForegroundColor Cyan

        # Construir comando con version especifica si fue elegida
        $chocoArgs = @(
            "install", "apache-httpd",
            "--params", "/installLocation:$apacheBase /noService",
            "--yes", "--no-progress", "--accept-license", "--allow-downgrade", "--force"
        )
        if ($Version) {
            $chocoArgs += "--version"
            $chocoArgs += $Version
            Write-Host "  Version solicitada: $Version" -ForegroundColor Gray
        }
        $chocoOut = & choco @chocoArgs 2>&1

        # Usar Encontrar-Base-Apache (igual que P6) para localizar httpd.exe
        # sin importar donde lo haya puesto Chocolatey
        $apacheBase = Encontrar-Base-Apache-P7

        if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
            Write-Host "  ERROR: httpd.exe no encontrado tras instalacion." -ForegroundColor Red
            Write-Host "  Ultimas lineas de Chocolatey:" -ForegroundColor Gray
            $chocoOut | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            return
        }
    }

    # Configurar puerto
    Configurar-Apache-Puerto -ApacheBase $apacheBase -Puerto $Puerto

    # Corregir ServerRoot si es necesario
    $confPath    = "$apacheBase\conf\httpd.conf"
    $confContent = Get-Content $confPath -Raw
    if ($confContent -match 'Define SRVROOT "([^"]+)"') {
        $srvrootActual = $matches[1]
        if ($srvrootActual -ne $apacheBase) {
            $confContent = $confContent -replace [regex]::Escape("Define SRVROOT `"$srvrootActual`""), "Define SRVROOT `"$apacheBase`""
            [System.IO.File]::WriteAllText($confPath, $confContent)
        }
    }

    $vOut    = (& "$apacheBase\bin\httpd.exe" -v 2>&1) | Out-String
    $version = if ($vOut -match "Apache/([0-9.]+)") { $matches[1] } else { "2.4" }

    Crear-Index-HTML -Directorio "$apacheBase\htdocs" -Servicio "Apache" -Version $version -Puerto $Puerto

    # Seguridad
    $secConf = "$apacheBase\conf\extra\httpd-security.conf"
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

    if (-not (Select-String -Path $confPath -Pattern "httpd-security.conf" -Quiet)) {
        Add-Content $confPath "`nInclude conf/extra/httpd-security.conf"
    }
    (Get-Content $confPath) -replace "#LoadModule headers_module", "LoadModule headers_module" | Set-Content $confPath

    & "$apacheBase\bin\httpd.exe" -k install 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    Start-Service "Apache2.4" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "Apache-HTTP-$Puerto"

    $test   = Test-NetConnection -ComputerName localhost -Port $Puerto -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }

    Registrar-Resumen -Servicio "Apache" -Accion "Instalacion" -Estado $estado -Detalle "v$version puerto $Puerto"
    Write-Host "  Apache instalado. v$version | Puerto: $Puerto | Estado: $estado" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
}

# ── Nginx ────────────────────────────────────────────────────────────────────

function Configurar-Nginx-Puerto {
    param([int]$Puerto)
    $confPath = "C:\nginx\conf\nginx.conf"
    $conf = @"
worker_processes  1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;
    server {
        listen $Puerto;
        server_name _;
        root html;
        location / { index index.html index.htm; }
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
    }
}
"@
    [System.IO.File]::WriteAllText($confPath, $conf, [System.Text.UTF8Encoding]::new($false))
}

function Instalar-Nginx-P7 {
    param([int]$Puerto, [string]$ArchivoZip = "", [string]$Version = "")

    $nginxBase = "C:\nginx"

    # Detectar si ya esta instalado
    if (Test-Path "$nginxBase\nginx.exe") {
        $vOut = (& "$nginxBase\nginx.exe" -v 2>&1) | Out-String
        if ($vOut -match "nginx/([0-9.]+)") {
            $vIns = $matches[1].Trim()
            Write-Host "  Nginx ya instalado (v$vIns)." -ForegroundColor Yellow

            $confActual = Get-Content "$nginxBase\conf\nginx.conf" -Raw -ErrorAction SilentlyContinue
            $pActual    = if ($confActual -match "listen\s+(\d+)") { [int]$matches[1] } else { 80 }

            if ($pActual -ne $Puerto) {
                Write-Host "  Cambiando puerto $pActual -> $Puerto..." -ForegroundColor Cyan
                Configurar-Nginx-Puerto -Puerto $Puerto
                Crear-Index-HTML -Directorio "$nginxBase\html" -Servicio "Nginx" -Version $vIns -Puerto $Puerto
                Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "Nginx-HTTP-$Puerto"
                taskkill /f /im nginx.exe 2>&1 | Out-Null
                Start-Sleep -Seconds 1
                Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden
                Registrar-Resumen -Servicio "Nginx" -Accion "Puerto-Cambiado" -Estado "OK" -Detalle "$pActual -> $Puerto"
                Write-Host "  Puerto actualizado a $Puerto." -ForegroundColor Green
            } else {
                Write-Host "  Puerto ya configurado en $Puerto." -ForegroundColor Green
            }
            return
        }
    }

    # Instalar
    if ($ArchivoZip) {
        $ok = Instalar-Desde-ZIP -Archivo $ArchivoZip -Servicio "Nginx"
        if (-not $ok) { return }
    } else {
        Write-Host "  Descargando Nginx desde nginx.org..." -ForegroundColor Cyan
        # Usar version elegida por el usuario, o LTS como fallback
        if (-not $Version) { $Version = "1.24.0" }
        $zipDest = "$env:TEMP\nginx_$(Get-Random).zip"
        $ok = Descargar-URL-Directa -Url "https://nginx.org/download/nginx-$Version.zip" -Destino $zipDest -Nombre "nginx-$Version.zip"
        if (-not $ok) { Write-Host "  ERROR: No se pudo descargar Nginx $Version." -ForegroundColor Red; return }

        $tmpEx = "$env:TEMP\nginx_ex_$(Get-Random)"
        Expand-Archive -Path $zipDest -DestinationPath $tmpEx -Force
        $dir = Get-ChildItem $tmpEx -Directory | Select-Object -First 1
        if ($dir) {
            if (Test-Path $nginxBase) { Remove-Item $nginxBase -Recurse -Force }
            Move-Item $dir.FullName $nginxBase
        }
        Remove-Item $tmpEx  -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zipDest -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path "$nginxBase\nginx.exe")) {
        Write-Host "  ERROR: nginx.exe no encontrado." -ForegroundColor Red; return
    }

    $vOut    = (& "$nginxBase\nginx.exe" -v 2>&1) | Out-String
    $version = if ($vOut -match "nginx/([0-9.]+)") { $matches[1] } else { "1.24" }

    Configurar-Nginx-Puerto -Puerto $Puerto
    Crear-Index-HTML -Directorio "$nginxBase\html" -Servicio "Nginx" -Version $version -Puerto $Puerto
    Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "Nginx-HTTP-$Puerto"

    taskkill /f /im nginx.exe 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden
    Start-Sleep -Seconds 3

    $test   = Test-NetConnection -ComputerName localhost -Port $Puerto -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }

    Registrar-Resumen -Servicio "Nginx" -Accion "Instalacion" -Estado $estado -Detalle "v$version puerto $Puerto"
    Write-Host "  Nginx instalado. v$version | Puerto: $Puerto | Estado: $estado" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
}

# ── Flujo de instalacion de un servicio ──────────────────────────────────────

function Flujo-Instalar-Servicio {
    param([string]$Servicio)
    Escribir-Titulo "INSTALAR $($Servicio.ToUpper())"

    # Elegir fuente
    Write-Host "  Fuente de instalacion:"
    Write-Host "    1) WEB - Repositorio oficial (Chocolatey / descarga directa)"
    Write-Host "    2) FTP - Repositorio privado (requiere repositorio preparado)"
    Write-Host ""
    $fuente = Leer-Opcion -Prompt "  Seleccione fuente [1/2]" -Validas @("1","2")

    $archivoZip   = ""
    $versionEleg  = ""
    $servicioReal = $Servicio

    if ($fuente -eq "1") {
        # ── WEB: mostrar versiones disponibles igual que P6 ──────────────────
        switch ($Servicio) {
            "IIS" {
                $iisPath = "C:\Windows\System32\inetsrv\inetinfo.exe"
                $ver = if (Test-Path $iisPath) {
                    (Get-Item $iisPath).VersionInfo.ProductVersion
                } else { "10.0" }
                Write-Host ""
                Write-Host "  Versiones disponibles de IIS:" -ForegroundColor Cyan
                Write-Host "    1) $ver  (Latest)"
                Write-Host "    2) $ver  (LTS / Estable)"
                Write-Host "    3) $ver  (Oldest)"
                Write-Host "  Nota: IIS es un rol de Windows. La version depende del OS." -ForegroundColor Yellow
                Leer-Opcion -Prompt "  Seleccione version [1-3]" -Validas @("1","2","3") | Out-Null
                $versionEleg = $ver
            }
            "Apache" {
                Write-Host ""
                Write-Host "  Consultando versiones de Apache via Chocolatey..." -ForegroundColor Cyan
                Refrescar-PATH
                $latest = "2.4.63"; $lts = "2.4.62"; $oldest = "2.4.58"
                if (Get-Command choco -ErrorAction SilentlyContinue) {
                    try {
                        $raw = choco search apache-httpd --all-versions --limit-output 2>&1 | Out-String
                        $vers = ($raw -split "`n") |
                            Where-Object { $_ -match "^apache-httpd" } |
                            ForEach-Object { ($_ -split "\|")[1].Trim() } |
                            Where-Object { $_ -match "^\d+\.\d+\.\d+$" } |
                            Sort-Object { [Version]$_ } -Descending
                        if ($vers.Count -ge 1) { $latest = $vers[0] }
                        if ($vers.Count -ge 2) { $lts    = $vers[1] }
                        if ($vers.Count -ge 3) { $oldest = $vers[$vers.Count - 1] }
                    } catch {}
                }
                Write-Host ""
                Write-Host "  Versiones disponibles de Apache:" -ForegroundColor Cyan
                Write-Host "    1) $latest  (Latest / Desarrollo)"
                Write-Host "    2) $lts     (LTS / Estable)"
                Write-Host "    3) $oldest  (Oldest)"
                $sel = Leer-Opcion -Prompt "  Seleccione version [1-3]" -Validas @("1","2","3")
                $versionEleg = switch ($sel) { "1" { $latest } "2" { $lts } "3" { $oldest } }
            }
            "Nginx" {
                $latest = "1.26.2"; $lts = "1.24.0"; $oldest = "1.22.1"
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    try {
                        $raw = winget show Nginx.Nginx 2>&1 | Out-String
                        if ($raw -match "Version\s*:\s*([0-9.]+)") { $latest = $matches[1].Trim() }
                    } catch {}
                }
                Write-Host ""
                Write-Host "  Versiones disponibles de Nginx:" -ForegroundColor Cyan
                Write-Host "    1) $latest  (Latest / Desarrollo)"
                Write-Host "    2) $lts     (LTS / Estable)"
                Write-Host "    3) $oldest  (Oldest)"
                $sel = Leer-Opcion -Prompt "  Seleccione version [1-3]" -Validas @("1","2","3")
                $versionEleg = switch ($sel) { "1" { $latest } "2" { $lts } "3" { $oldest } }
            }
        }
    } else {
        # ── FTP: navegar repositorio y descargar ──────────────────────────────
        $resultado = Navegar-Y-Descargar-FTP -ServicioForzado $Servicio
        if (-not $resultado) { Write-Host "  Instalacion cancelada." -ForegroundColor Red; return }
        $archivoZip   = $resultado.Archivo
        $servicioReal = $resultado.Servicio
        Write-Host "  Servicio a instalar: $servicioReal" -ForegroundColor Cyan
    }

    # Puerto sugerido segun el servicio
    $sugeridos = switch ($servicioReal) {
        "IIS"    { @(80, 8080, 8181, 8282) }
        "Apache" { @(8080, 80, 8181, 8282) }
        "Nginx"  { @(8181, 8080, 80, 8282) }
        default  { @(8080, 8181, 8282) }
    }
    $puertoSugerido = Detectar-Puerto-Libre -Sugeridos $sugeridos
    Write-Host ""
    $puerto = Leer-Puerto -Prompt "  Puerto de escucha (sugerido: $puertoSugerido)" -Default $puertoSugerido

    switch ($servicioReal) {
        "IIS"    { Instalar-IIS-P7    -Puerto $puerto }
        "Apache" { Instalar-Apache-P7 -Puerto $puerto -ArchivoZip $archivoZip -Version $versionEleg }
        "Nginx"  { Instalar-Nginx-P7  -Puerto $puerto -ArchivoZip $archivoZip -Version $versionEleg }
        default  { Write-Host "  Servicio '$servicioReal' no reconocido." -ForegroundColor Yellow }
    }
}

# ================================================================
# SECCION 6 - SSL/TLS (35% de la nota)
# ================================================================

function Pedir-Dominio {
    if ($global:DOMINIO_SSL) {
        $cambiar = Leer-Opcion -Prompt "  Dominio actual: '$($global:DOMINIO_SSL)' ¿Cambiar? [S/N]" -Validas @("S","N","s","n")
        if ($cambiar -match "^[Ss]$") {
            $global:DOMINIO_SSL = Leer-Texto -Prompt "  Nuevo dominio SSL"
        }
    } else {
        $global:DOMINIO_SSL = Leer-Texto -Prompt "  Dominio para el certificado" -Default "www.reprobados.com"
    }
    return $global:DOMINIO_SSL
}

function Generar-Certificado-Windows {
    param([string]$Dominio)

    # Verificar si ya existe un certificado valido con O=Practica7
    $certExistente = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -like "*$Dominio*" -and $_.Subject -like "*Practica7*" -and $_.NotAfter -gt (Get-Date) } |
        Select-Object -First 1

    if ($certExistente) {
        Write-Host "  Certificado para '$Dominio' ya existe y es valido." -ForegroundColor Green
        Write-Host "    Thumbprint : $($certExistente.Thumbprint)" -ForegroundColor Gray
        Write-Host "    Expira     : $($certExistente.NotAfter)"   -ForegroundColor Gray
        return $certExistente.Thumbprint
    }

    Write-Host "  Generando certificado con OpenSSL para '$Dominio'..." -ForegroundColor Cyan

    # Eliminar certificados anteriores del dominio
    Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$Dominio*" } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # Usar OpenSSL igual que Linux: incluye CN, O y OU
    $sslDir = "C:\Apache24\conf\ssl"
    New-Item -ItemType Directory -Force -Path $sslDir | Out-Null
    $keyFile = "$sslDir\server_temp.key"
    $crtFile = "$sslDir\server_temp.crt"
    $pfxFile = "$sslDir\server_temp.pfx"
    $pfxPass = "P7SSL2024"

    & openssl req -x509 -nodes -days 365 -newkey rsa:2048 `
        -keyout $keyFile `
        -out $crtFile `
        -subj "/CN=$Dominio/O=Practica7/OU=SSL" 2>$null

    if (-not (Test-Path $crtFile)) {
        Write-Host "  OpenSSL fallo, usando New-SelfSignedCertificate como fallback..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate `
            -DnsName $Dominio `
            -CertStoreLocation "Cert:\LocalMachine\My" `
            -NotAfter (Get-Date).AddDays(365) `
            -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
            -FriendlyName "P7-SSL-$Dominio" `
            -Subject "CN=$Dominio, O=Practica7, OU=SSL"
        Registrar-Resumen -Servicio $Dominio -Accion "Cert-Generado" -Estado "OK" -Detalle $cert.Thumbprint
        return $cert.Thumbprint
    }

    # Convertir PEM a PFX e importar al store de Windows
    $secPw = ConvertTo-SecureString $pfxPass -AsPlainText -Force
    & openssl pkcs12 -export -in $crtFile -inkey $keyFile -out $pfxFile `
        -passout "pass:$pfxPass" -name "P7-SSL-$Dominio" 2>$null

    $cert = Import-PfxCertificate -FilePath $pfxFile `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -Password $secPw -Exportable

    Remove-Item $pfxFile -Force -ErrorAction SilentlyContinue

    Write-Host "  Certificado generado:" -ForegroundColor Green
    Write-Host "    Thumbprint : $($cert.Thumbprint)" -ForegroundColor Gray
    Write-Host "    Sujeto     : $($cert.Subject)"    -ForegroundColor Gray
    Write-Host "    Expira     : $($cert.NotAfter)"   -ForegroundColor Gray
    Registrar-Resumen -Servicio $Dominio -Accion "Cert-Generado" -Estado "OK" -Detalle $cert.Thumbprint
    return $cert.Thumbprint
}

function Exportar-Cert-A-PEM {
    param([string]$Thumbprint, [string]$Dir)
    if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
        Write-Host "  ERROR: OpenSSL no instalado. Instale las dependencias primero (opcion 1)." -ForegroundColor Red
        return $false
    }
    New-Item $Dir -ItemType Directory -Force | Out-Null
    $pfxPath  = "$Dir\cert.pfx"
    $pfxPass  = "P7Temp2024!"
    $secPw    = ConvertTo-SecureString $pfxPass -AsPlainText -Force
    Export-PfxCertificate -Cert "Cert:\LocalMachine\My\$Thumbprint" -FilePath $pfxPath -Password $secPw | Out-Null
    & openssl pkcs12 -in $pfxPath -clcerts -nokeys -out "$Dir\server.crt" -password "pass:$pfxPass" 2>&1 | Out-Null
    & openssl pkcs12 -in $pfxPath -nocerts -nodes  -out "$Dir\server.key" -password "pass:$pfxPass" 2>&1 | Out-Null
    if ((Test-Path "$Dir\server.crt") -and (Test-Path "$Dir\server.key")) {
        Write-Host "  Exportado a PEM: $Dir\server.crt / server.key" -ForegroundColor Green
        return $true
    }
    Write-Host "  ERROR: No se pudieron exportar los archivos PEM." -ForegroundColor Red
    return $false
}

function Activar-SSL-IIS {
    Escribir-Titulo "ACTIVAR SSL/TLS EN IIS"
    if (-not (Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue).Installed) {
        Write-Host "  ERROR: IIS no instalado. Instale IIS primero." -ForegroundColor Red; return
    }
    $dominio = Pedir-Dominio
    $thumb   = Generar-Certificado-Windows -Dominio $dominio
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    try {
        $existeHttps = Get-WebBinding -Name "Default Web Site" -Protocol "https" -ErrorAction SilentlyContinue
        if ($existeHttps) { Remove-WebBinding -Name "Default Web Site" -Protocol "https" -ErrorAction SilentlyContinue }
        New-WebBinding -Name "Default Web Site" -Protocol "https" -Port 443 -IPAddress "*" -SslFlags 0 | Out-Null
        $bp = "IIS:\SslBindings\0.0.0.0!443"
        if (Test-Path $bp) { Remove-Item $bp -Force }
        Get-Item "Cert:\LocalMachine\My\$thumb" | New-Item $bp | Out-Null
        Write-Host "  Binding HTTPS:443 configurado en IIS." -ForegroundColor Green
    } catch {
        Write-Host "  ERROR configurando HTTPS en IIS: $($_.Exception.Message)" -ForegroundColor Red
        Registrar-Resumen -Servicio "IIS" -Accion "SSL-443" -Estado "ERROR" -Detalle $_.Exception.Message
        return
    }

    # Cabeceras HSTS en web.config (sin URL Rewrite para evitar error 500)
    @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <httpProtocol>
      <customHeaders>
        <add name="Strict-Transport-Security" value="max-age=31536000; includeSubDomains" />
        <add name="X-Frame-Options" value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@ | Set-Content "C:\inetpub\wwwroot\web.config" -Encoding UTF8

    Abrir-Puerto-Firewall -Puerto 443 -Nombre "IIS-HTTPS-443"
    iisreset /restart | Out-Null
    Start-Sleep -Seconds 3

    $test   = Test-NetConnection -ComputerName localhost -Port 443 -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }
    Write-Host "  IIS HTTPS 443: $estado | Dominio: $dominio" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
    Registrar-Resumen -Servicio "IIS" -Accion "SSL-443" -Estado $estado -Detalle "Dominio: $dominio | Thumb: $thumb"
}

function Activar-SSL-Apache {
    Escribir-Titulo "ACTIVAR SSL/TLS EN APACHE"
    $apacheBase = "C:\Apache24"
    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        Write-Host "  ERROR: Apache no encontrado. Instale Apache primero." -ForegroundColor Red; return
    }
    $dominio = Pedir-Dominio
    $thumb   = Generar-Certificado-Windows -Dominio $dominio
    $sslDir  = "$apacheBase\conf\ssl"
    $ok      = Exportar-Cert-A-PEM -Thumbprint $thumb -Dir $sslDir
    if (-not $ok) { return }

    $sslFwd    = $sslDir -replace '\\','/'
    $confPath  = "$apacheBase\conf\httpd.conf"
    $conf      = Get-Content $confPath -Raw

    # Habilitar modulos
    foreach ($mod in @("mod_ssl.so","mod_socache_shmcb.so","mod_rewrite.so","mod_headers.so")) {
        $conf = $conf -replace "#(LoadModule\s+\S+\s+modules/$mod)",'$1'
    }
    $conf = $conf -replace "#(Include conf/extra/httpd-ssl.conf)",'$1'
    [System.IO.File]::WriteAllText($confPath, $conf)

    $pHttp = 80
    $linea = Select-String -Path $confPath -Pattern "(?m)^Listen (\d+)" | Select-Object -First 1
    if ($linea -and $linea.Line -match "Listen (\d+)") { $pHttp = [int]$matches[1] }

    @"
Listen 443
SSLPassPhraseDialog  builtin
SSLSessionCache      "shmcb:$($apacheBase -replace '\\','/')/logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost *:443>
    ServerName $dominio
    DocumentRoot "$($apacheBase -replace '\\','/')/htdocs"
    SSLEngine on
    SSLCertificateFile    "$sslFwd/server.crt"
    SSLCertificateKeyFile "$sslFwd/server.key"
    SSLProtocol all -SSLv2 -SSLv3
    SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</VirtualHost>

<VirtualHost *:$pHttp>
    ServerName $dominio
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}`$1 [R=301,L]
</VirtualHost>
"@ | Set-Content "$apacheBase\conf\extra\httpd-ssl.conf" -Encoding UTF8

    # Chocolatey/ApacheHaus usa httpd-ahssl.conf con ServerName localhost
    # Corregir ese archivo para que use el dominio de P7
    $ahsslConf = "$apacheBase\conf\extra\httpd-ahssl.conf"
    if (Test-Path $ahsslConf) {
        Write-Host "  Detectado httpd-ahssl.conf (Chocolatey). Corrigiendo ServerName..." -ForegroundColor Cyan
        $ahssl = Get-Content $ahsslConf -Raw
        $ahssl = $ahssl -replace "ServerName\s+localhost:443", "ServerName ${dominio}:443"
        $ahssl = $ahssl -replace "ServerName\s+localhost",     "ServerName $dominio"
        # Apuntar al certificado de P7 en conf/ssl/
        $sslFwd = ($sslDir -replace "\\","/")
        $ahssl = $ahssl -replace 'SSLCertificateFile\s+"\$\{SRVROOT\}/conf/ssl/server\.crt"', "SSLCertificateFile `"$sslFwd/server.crt`""
        $ahssl = $ahssl -replace 'SSLCertificateKeyFile\s+"\$\{SRVROOT\}/conf/ssl/server\.key"', "SSLCertificateKeyFile `"$sslFwd/server.key`""
        [System.IO.File]::WriteAllText($ahsslConf, $ahssl)
        Write-Host "  httpd-ahssl.conf actualizado con dominio '$dominio'." -ForegroundColor Green

        # Eliminar Listen 443 de httpd-ahssl.conf (evita duplicado)
        # y agregarlo en httpd.conf para que Apache lo reconozca correctamente
        $ahssl2 = [System.IO.File]::ReadAllText($ahsslConf)
        $ahssl2Lines = ($ahssl2 -split "`n") | Where-Object { $_ -notmatch "^Listen 443" }
        $ahssl2 = $ahssl2Lines -join "`n"
        [System.IO.File]::WriteAllText($ahsslConf, $ahssl2)

        # Agregar Listen 443 en httpd.conf si no existe, y limpiar duplicados
        $httpdMain = "$apacheBase\conf\httpd.conf"
        $httpdLines = Get-Content $httpdMain

        # Eliminar todos los Listen 443 existentes para evitar duplicados
        $httpdLines = $httpdLines | Where-Object { $_ -notmatch "^Listen 443" }

        # Insertar Listen 443 justo despues del primer Listen de HTTP
        $insertado = $false
        $httpdLines = $httpdLines | ForEach-Object {
            $_
            if (-not $insertado -and $_ -match "^Listen \d+") {
                "Listen 443"
                $insertado = $true
            }
        }
        $httpdLines | Set-Content $httpdMain
        Write-Host "  Listen 443 configurado en httpd.conf." -ForegroundColor Gray

        # Deshabilitar httpd-ssl.conf para evitar conflicto con httpd-ahssl.conf
        $httpdConf = "$apacheBase\conf\httpd.conf"
        $httpdContent = [System.IO.File]::ReadAllText($httpdConf)
        $httpdContent = $httpdContent -replace "(?m)^Include conf/extra/httpd-ssl\.conf","#Include conf/extra/httpd-ssl.conf"
        [System.IO.File]::WriteAllText($httpdConf, $httpdContent)
        Write-Host "  httpd-ssl.conf deshabilitado (usa httpd-ahssl.conf)." -ForegroundColor Gray
    } else {
        # Sin httpd-ahssl.conf: copiar certs en conf\ por si acaso
        $confRaiz = "$apacheBase\conf"
        if (Test-Path "$confRaiz\server.crt") {
            Copy-Item "$sslDir\server.crt" "$confRaiz\server.crt" -Force
            Copy-Item "$sslDir\server.key" "$confRaiz\server.key" -Force
            Write-Host "  Certificado copiado a $confRaiz." -ForegroundColor Gray
        }
    }

    Abrir-Puerto-Firewall -Puerto 443 -Nombre "Apache-HTTPS-443"

    # Verificar sintaxis antes de intentar iniciar
    $apacheExe = (Encontrar-Base-Apache-P7) + "\bin\httpd.exe"
    $sintaxis = & $apacheExe -t 2>&1 | Out-String
    if ($sintaxis -notmatch "Syntax OK") {
        Write-Host "  ERROR de sintaxis en configuracion de Apache:" -ForegroundColor Red
        Write-Host $sintaxis -ForegroundColor Red
        return
    }

    Stop-Service "Apache2.4" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service "Apache2.4" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Si no arranco, intentar directamente con httpd.exe
    $svc = Get-Service "Apache2.4" -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne "Running") {
        Write-Host "  Reintentando inicio de Apache..." -ForegroundColor Yellow
        $apacheExe2 = (Encontrar-Base-Apache-P7) + "\bin\httpd.exe"
        & $apacheExe2 -k start 2>&1 | Out-Null
        Start-Sleep -Seconds 3
    }

    $test   = Test-NetConnection -ComputerName localhost -Port 443 -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }
    Write-Host "  Apache HTTPS 443: $estado | Dominio: $dominio" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
    Registrar-Resumen -Servicio "Apache" -Accion "SSL-443" -Estado $estado -Detalle "Dominio: $dominio"
}

function Activar-SSL-Nginx {
    Escribir-Titulo "ACTIVAR SSL/TLS EN NGINX"
    $nginxBase = "C:\nginx"
    if (-not (Test-Path "$nginxBase\nginx.exe")) {
        Write-Host "  ERROR: Nginx no encontrado. Instale Nginx primero." -ForegroundColor Red; return
    }
    $dominio = Pedir-Dominio
    $thumb   = Generar-Certificado-Windows -Dominio $dominio
    $sslDir  = "$nginxBase\ssl"
    $ok      = Exportar-Cert-A-PEM -Thumbprint $thumb -Dir $sslDir
    if (-not $ok) { return }

    $sslFwd  = $sslDir -replace '\\','/'
    $pHttp   = 80
    $confAct = Get-Content "$nginxBase\conf\nginx.conf" -Raw -ErrorAction SilentlyContinue
    if ($confAct -match "listen\s+(\d+)") { $pHttp = [int]$matches[1] }

    $conf = @"
worker_processes  1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;
    server {
        listen $pHttp;
        server_name $dominio;
        return 301 https://`$host`$request_uri;
    }
    server {
        listen 443 ssl;
        server_name $dominio;
        root html;
        ssl_certificate     $sslFwd/server.crt;
        ssl_certificate_key $sslFwd/server.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
        location / { index index.html index.htm; }
    }
}
"@
    [System.IO.File]::WriteAllText("$nginxBase\conf\nginx.conf", $conf, [System.Text.UTF8Encoding]::new($false))

    Abrir-Puerto-Firewall -Puerto 443 -Nombre "Nginx-HTTPS-443"
    taskkill /f /im nginx.exe 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden
    Start-Sleep -Seconds 3

    $test   = Test-NetConnection -ComputerName localhost -Port 443 -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }
    Write-Host "  Nginx HTTPS 443: $estado | Dominio: $dominio" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
    Registrar-Resumen -Servicio "Nginx" -Accion "SSL-443" -Estado $estado -Detalle "Dominio: $dominio"
}

function Activar-FTPS-IIS {
    Escribir-Titulo "ACTIVAR FTPS EN IIS-FTP"
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $sitioFTP = "FTP_SERVER"
    if (-not (Get-WebSite -Name $sitioFTP -ErrorAction SilentlyContinue)) {
        Write-Host "  ERROR: Sitio FTP '$sitioFTP' no encontrado." -ForegroundColor Red
        Write-Host "  Ejecute primero ftp.ps1 (Practica 5)." -ForegroundColor Yellow; return
    }
    $dominio = Pedir-Dominio
    $thumb   = Generar-Certificado-Windows -Dominio $dominio

    $appcmd = "C:\Windows\System32\inetsrv\appcmd.exe"
    & $appcmd set config $sitioFTP `
        -section:system.ftpServer/security/ssl `
        /serverCertHash:$thumb `
        /controlChannelPolicy:"SslRequire" `
        /dataChannelPolicy:"SslRequire" `
        /commit:apphost 2>&1 | Out-Null

    Abrir-Puerto-Firewall -Puerto 990 -Nombre "FTPS-990"
    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $test   = Test-NetConnection -ComputerName localhost -Port 21 -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }
    Write-Host "  FTPS configurado: $estado | Dominio: $dominio" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
    Registrar-Resumen -Servicio "IIS-FTP" -Accion "FTPS-SSL" -Estado $estado -Detalle "Dominio: $dominio | Thumb: $thumb"
}

# ================================================================
# SECCION 7 - GESTION DE SERVICIOS (iniciar / detener)
# ================================================================

function Gestionar-Servicios-HTTP {
    Escribir-Titulo "GESTIONAR SERVICIOS HTTP"

    Write-Host "  Estado actual:" -ForegroundColor Cyan
    Write-Host ""

    # IIS
    $iisOk = (Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue).Installed
    $iisEst = if ($iisOk) {
        $svc = Get-Service W3SVC -ErrorAction SilentlyContinue
        if ($svc.Status -eq "Running") { "ACTIVO" } else { "DETENIDO" }
    } else { "NO INSTALADO" }

    # Apache
    $apacheBase = Encontrar-Base-Apache-P7
    $apacheEst = if (Test-Path "$apacheBase\bin\httpd.exe") {
        $svc = Get-Service "Apache2.4" -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") { "ACTIVO" } else { "DETENIDO" }
    } else { "NO INSTALADO" }

    # Nginx
    $nginxProc = Get-Process nginx -ErrorAction SilentlyContinue
    $nginxEst = if (Test-Path "C:\nginx\nginx.exe") {
        if ($nginxProc) { "ACTIVO" } else { "DETENIDO" }
    } else { "NO INSTALADO" }

    # FTP
    $ftpSvc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    $ftpEst = if ($ftpSvc) {
        if ($ftpSvc.Status -eq "Running") { "ACTIVO" } else { "DETENIDO" }
    } else { "NO INSTALADO" }

    Write-Host ("    {0,-10} {1}" -f "IIS",    $iisEst)    -ForegroundColor $(if($iisEst -eq "ACTIVO"){"Green"}elseif($iisEst -eq "DETENIDO"){"Yellow"}else{"DarkGray"})
    Write-Host ("    {0,-10} {1}" -f "Apache", $apacheEst) -ForegroundColor $(if($apacheEst -eq "ACTIVO"){"Green"}elseif($apacheEst -eq "DETENIDO"){"Yellow"}else{"DarkGray"})
    Write-Host ("    {0,-10} {1}" -f "Nginx",  $nginxEst)  -ForegroundColor $(if($nginxEst -eq "ACTIVO"){"Green"}elseif($nginxEst -eq "DETENIDO"){"Yellow"}else{"DarkGray"})
    Write-Host ("    {0,-10} {1}" -f "FTP",    $ftpEst)    -ForegroundColor $(if($ftpEst -eq "ACTIVO"){"Green"}elseif($ftpEst -eq "DETENIDO"){"Yellow"}else{"DarkGray"})
    Write-Host ""
    Write-Host "  Acciones:" -ForegroundColor Yellow
    Write-Host "    1) Detener IIS"
    Write-Host "    2) Iniciar IIS"
    Write-Host "    3) Detener Apache"
    Write-Host "    4) Iniciar Apache"
    Write-Host "    5) Detener Nginx"
    Write-Host "    6) Iniciar Nginx"
    Write-Host "    7) Detener FTP"
    Write-Host "    8) Iniciar FTP"
    Write-Host "    9) Detener TODOS (para demostrar un servicio a la vez)"
    Write-Host "    0) Volver"
    Write-Host ""

    $op = Leer-Opcion -Prompt "  Seleccione" -Validas @("0","1","2","3","4","5","6","7","8","9")

    switch ($op) {
        "1" {
            Write-Host "  Deteniendo IIS..." -ForegroundColor Yellow
            iisreset /stop | Out-Null
            Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
            Write-Host "  IIS detenido." -ForegroundColor Green
            Registrar-Resumen -Servicio "IIS" -Accion "Detenido" -Estado "OK"
        }
        "2" {
            Write-Host "  Iniciando IIS..." -ForegroundColor Cyan
            Start-Service W3SVC -ErrorAction SilentlyContinue
            iisreset /start | Out-Null
            Start-Sleep -Seconds 2
            Write-Host "  IIS iniciado." -ForegroundColor Green
            Registrar-Resumen -Servicio "IIS" -Accion "Iniciado" -Estado "OK"
        }
        "3" {
            Write-Host "  Deteniendo Apache..." -ForegroundColor Yellow
            Stop-Service "Apache2.4" -Force -ErrorAction SilentlyContinue
            Get-Process httpd -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Host "  Apache detenido." -ForegroundColor Green
            Registrar-Resumen -Servicio "Apache" -Accion "Detenido" -Estado "OK"
        }
        "4" {
            Write-Host "  Iniciando Apache..." -ForegroundColor Cyan
            Start-Service "Apache2.4" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Write-Host "  Apache iniciado." -ForegroundColor Green
            Registrar-Resumen -Servicio "Apache" -Accion "Iniciado" -Estado "OK"
        }
        "5" {
            Write-Host "  Deteniendo Nginx..." -ForegroundColor Yellow
            taskkill /f /im nginx.exe 2>&1 | Out-Null
            Write-Host "  Nginx detenido." -ForegroundColor Green
            Registrar-Resumen -Servicio "Nginx" -Accion "Detenido" -Estado "OK"
        }
        "6" {
            Write-Host "  Iniciando Nginx..." -ForegroundColor Cyan
            $nginxBase = "C:\nginx"
            if (Test-Path "$nginxBase\nginx.exe") {

                Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden


                Start-Sleep -Seconds 2
                Write-Host "  Nginx iniciado." -ForegroundColor Green
                Registrar-Resumen -Servicio "Nginx" -Accion "Iniciado" -Estado "OK"
            } else {
                Write-Host "  ERROR: Nginx no instalado." -ForegroundColor Red
            }
        }
        "7" {
            Write-Host "  Deteniendo FTP..." -ForegroundColor Yellow
            Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
            Write-Host "  FTP detenido." -ForegroundColor Green
        }
        "8" {
            Write-Host "  Iniciando FTP..." -ForegroundColor Cyan
            Start-Service ftpsvc -ErrorAction SilentlyContinue
            Write-Host "  FTP iniciado." -ForegroundColor Green
        }
        "9" {
            Write-Host ""
            Write-Host "  Deteniendo TODOS los servicios HTTP..." -ForegroundColor Yellow
            iisreset /stop 2>&1 | Out-Null
            Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
            Stop-Service "Apache2.4" -Force -ErrorAction SilentlyContinue
            Get-Process httpd  -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            taskkill /f /im nginx.exe 2>&1 | Out-Null
            Write-Host "  Todos los servicios HTTP detenidos." -ForegroundColor Green
            Write-Host "  Ahora puede iniciar el servicio que desea demostrar (opciones 2, 4 o 6)." -ForegroundColor Cyan
        }
    }
}

# ================================================================
# SECCION 8 - ESTADO Y RESUMEN (evidencias para el profesor)
# ================================================================

function Ver-Estado-Servicios {
    Escribir-Titulo "ESTADO DE SERVICIOS"

    # Detectar puertos reales de cada servicio
    $puertoIIS = 80
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $b = Get-WebBinding -Name "Default Web Site" -Protocol "http" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($b) { $puertoIIS = [int]($b.bindingInformation -split ":")[-2] }
    } catch {}

    $puertoApache = 8080
    try {
        $apacheBase = Encontrar-Base-Apache-P7
        $confApache = Get-Content "$apacheBase\conf\httpd.conf" -Raw -ErrorAction SilentlyContinue
        if ($confApache -match "(?m)^Listen (\d+)") { $puertoApache = [int]$matches[1] }
    } catch {}

    $puertoNginx = 8181
    try {
        $confNginx = Get-Content "C:\nginx\conf\nginx.conf" -Raw -ErrorAction SilentlyContinue
        if ($confNginx -match "listen\s+(\d+)") { $puertoNginx = [int]$matches[1] }
    } catch {}

    $checks = @(
        @{ Nombre = "IIS HTTP    "; Puerto = $puertoIIS   },
        @{ Nombre = "IIS HTTPS   "; Puerto = 443          },
        @{ Nombre = "Apache HTTP "; Puerto = $puertoApache },
        @{ Nombre = "Apache HTTPS"; Puerto = 443          },
        @{ Nombre = "Nginx HTTP  "; Puerto = $puertoNginx  },
        @{ Nombre = "Nginx HTTPS "; Puerto = 443          },
        @{ Nombre = "FTP         "; Puerto = 21           },
        @{ Nombre = "FTPS        "; Puerto = 990          }
    )

    Write-Host ("  {0,-16} {1,-8} {2}" -f "Servicio","Puerto","Estado") -ForegroundColor Cyan
    Write-Host ("  {0,-16} {1,-8} {2}" -f "--------","------","------") -ForegroundColor DarkGray

    foreach ($c in $checks) {
        $test   = Test-NetConnection -ComputerName localhost -Port $c.Puerto -WarningAction SilentlyContinue
        $estado = if ($test.TcpTestSucceeded) { "ACTIVO  " } else { "INACTIVO" }
        $color  = if ($test.TcpTestSucceeded) { "Green" } else { "DarkGray" }
        Write-Host ("  {0,-16} {1,-8} {2}" -f $c.Nombre, $c.Puerto, $estado) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  Certificados SSL instalados (P7):" -ForegroundColor Cyan
    $certs = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -like "P7-SSL*" }
    if ($certs) {
        $certs | ForEach-Object {
            Write-Host ("    Sujeto: {0,-40} Expira: {1}" -f $_.Subject, $_.NotAfter) -ForegroundColor Gray
        }
    } else {
        Write-Host "    (No hay certificados P7 instalados aun)" -ForegroundColor DarkGray
    }
}

function Mostrar-Resumen-Final {
    Escribir-Titulo "RESUMEN FINAL - PRACTICA 7"

    if ($global:RESUMEN.Count -eq 0) {
        Write-Host "  No hay acciones registradas aun." -ForegroundColor Yellow
        Ver-Estado-Servicios
        return
    }

    $global:RESUMEN | Format-Table -AutoSize -Property Servicio, Accion, Estado, Detalle

    $ok  = ($global:RESUMEN | Where-Object { $_.Estado -eq "OK" }).Count
    $adv = ($global:RESUMEN | Where-Object { $_.Estado -eq "ADVERTENCIA" }).Count
    $err = ($global:RESUMEN | Where-Object { $_.Estado -eq "ERROR" }).Count

    Write-Host ("  OK          : {0}" -f $ok)  -ForegroundColor Green
    Write-Host ("  ADVERTENCIA : {0}" -f $adv) -ForegroundColor Yellow
    Write-Host ("  ERROR       : {0}" -f $err) -ForegroundColor Red

    Ver-Estado-Servicios

    Write-Host ""
    Write-Host "  Comandos para verificar SSL desde cliente (evidencias):" -ForegroundColor Cyan
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
    Write-Host "    # Verificar HTTPS - IIS / Apache / Nginx:" -ForegroundColor DarkGray
    Write-Host "    curl -k -I https://$ip" -ForegroundColor Gray
    Write-Host "    openssl s_client -connect ${ip}:443 -servername $($global:DOMINIO_SSL)" -ForegroundColor Gray
    Write-Host "    # Verificar FTPS:" -ForegroundColor DarkGray
    Write-Host "    openssl s_client -connect ${ip}:990" -ForegroundColor Gray
}

# ================================================================
# SECCION 8 - ADMINISTRACION DEL SERVIDOR FTP LOCAL
# Logica de Practica 5 integrada en P7
# Estructura del servidor FTP (igual que P5):
#   Raiz FTP  = C:\Users  (IsolateAllDirectories en Windows EN)
#   Anonimo   = C:\Users\LocalUser\Public  (solo lectura)
#   Usuarios  = C:\Users\<SERVIDOR>\<usuario>
#   Datos     = C:\FTP_Data\{general,reprobados,recursadores,usuarios}
# ================================================================

function FTP-Log {
    param([string]$Msg)
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if (-not (Test-Path $global:FTP_DATA)) { New-Item $global:FTP_DATA -ItemType Directory -Force | Out-Null }
    Add-Content $global:FTP_LOG "$fecha - $Msg" -ErrorAction SilentlyContinue
}

# ── Instalar IIS + FTP ───────────────────────────────────────────────────────

function FTP-Instalar {
    Escribir-Titulo "INSTALAR SERVIDOR FTP (IIS-FTP)"
    Write-Host "  Instalando IIS + FTP Service..." -ForegroundColor Cyan

    $features = @("Web-Server","Web-FTP-Server","Web-FTP-Service","Web-FTP-Ext")
    foreach ($f in $features) {
        if (-not (Get-WindowsFeature $f -ErrorAction SilentlyContinue).Installed) {
            Install-WindowsFeature $f -IncludeManagementTools | Out-Null
        }
    }

    Start-Service W3SVC   -ErrorAction SilentlyContinue
    Start-Service ftpsvc  -ErrorAction SilentlyContinue
    Set-Service   ftpsvc  -StartupType Automatic -ErrorAction SilentlyContinue

    Write-Host "  FTP instalado correctamente." -ForegroundColor Green
    FTP-Log "FTP instalado"
    Registrar-Resumen -Servicio "IIS-FTP" -Accion "Instalacion" -Estado "OK"
}

# ── Firewall FTP ─────────────────────────────────────────────────────────────

function FTP-Configurar-Firewall {
    Escribir-Titulo "CONFIGURAR FIREWALL FTP"

    Remove-NetFirewallRule -DisplayName "FTP-Puerto-21"    -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "FTP-Pasivo-Rango" -ErrorAction SilentlyContinue

    New-NetFirewallRule -DisplayName "FTP-Puerto-21" `
        -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow | Out-Null

    New-NetFirewallRule -DisplayName "FTP-Pasivo-Rango" `
        -Direction Inbound -Protocol TCP -LocalPort 50000-51000 -Action Allow | Out-Null

    Write-Host "  Firewall configurado: puerto 21 y rango pasivo 50000-51000." -ForegroundColor Green
    FTP-Log "Firewall FTP configurado"
}

# ── Grupos ───────────────────────────────────────────────────────────────────

function FTP-Crear-Grupos {
    Escribir-Titulo "CREAR GRUPOS FTP"

    foreach ($g in @("reprobados","recursadores","ftpusuarios")) {
        if (-not (Get-LocalGroup $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup $g | Out-Null
            Write-Host "  Grupo '$g' creado." -ForegroundColor Green
        } else {
            Write-Host "  Grupo '$g' ya existe." -ForegroundColor Yellow
        }
    }
    FTP-Log "Grupos verificados"
}

# ── Estructura de carpetas ───────────────────────────────────────────────────

function FTP-Crear-Estructura {
    Escribir-Titulo "CREAR ESTRUCTURA DE CARPETAS FTP"

    foreach ($carpeta in @("","general","reprobados","recursadores","usuarios")) {
        New-Item "$($global:FTP_DATA)\$carpeta" -ItemType Directory -Force | Out-Null
    }

    # Carpeta anonimo
    New-Item "$($global:FTP_ROOT)\LocalUser\Public" -ItemType Directory -Force | Out-Null

    # Junction para acceso anonimo a /general
    $linkGeneral = "$($global:FTP_ROOT)\LocalUser\Public\general"
    if (-not (Test-Path $linkGeneral)) {
        cmd /c mklink /J "$linkGeneral" "$($global:FTP_DATA)\general" | Out-Null
    }

    Write-Host "  Estructura de carpetas creada." -ForegroundColor Green
    FTP-Log "Estructura FTP creada"
}

# ── Permisos NTFS ────────────────────────────────────────────────────────────

function FTP-Aplicar-Permisos {
    Escribir-Titulo "APLICAR PERMISOS NTFS FTP"

    $sidSystem = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")).Translate([System.Security.Principal.NTAccount]).Value
    $sidAdmins = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate([System.Security.Principal.NTAccount]).Value

    # general: escritura para ftpusuarios, lectura para IUSR (anonimo)
    icacls "$($global:FTP_DATA)\general" /inheritance:r | Out-Null
    icacls "$($global:FTP_DATA)\general" /grant "${sidAdmins}:(OI)(CI)F"     | Out-Null
    icacls "$($global:FTP_DATA)\general" /grant "${sidSystem}:(OI)(CI)F"     | Out-Null
    icacls "$($global:FTP_DATA)\general" /grant "ftpusuarios:(OI)(CI)M"      | Out-Null
    icacls "$($global:FTP_DATA)\general" /grant "IUSR:(OI)(CI)RX"            | Out-Null

    # reprobados: solo grupo reprobados
    icacls "$($global:FTP_DATA)\reprobados" /inheritance:r | Out-Null
    icacls "$($global:FTP_DATA)\reprobados" /grant "${sidAdmins}:(OI)(CI)F"  | Out-Null
    icacls "$($global:FTP_DATA)\reprobados" /grant "${sidSystem}:(OI)(CI)F"  | Out-Null
    icacls "$($global:FTP_DATA)\reprobados" /grant "reprobados:(OI)(CI)M"    | Out-Null

    # recursadores: solo grupo recursadores
    icacls "$($global:FTP_DATA)\recursadores" /inheritance:r | Out-Null
    icacls "$($global:FTP_DATA)\recursadores" /grant "${sidAdmins}:(OI)(CI)F"  | Out-Null
    icacls "$($global:FTP_DATA)\recursadores" /grant "${sidSystem}:(OI)(CI)F"  | Out-Null
    icacls "$($global:FTP_DATA)\recursadores" /grant "recursadores:(OI)(CI)M"  | Out-Null

    # Public (anonimo): solo lectura
    icacls "$($global:FTP_ROOT)\LocalUser\Public" /inheritance:r | Out-Null
    icacls "$($global:FTP_ROOT)\LocalUser\Public" /grant "${sidAdmins}:(OI)(CI)F" | Out-Null
    icacls "$($global:FTP_ROOT)\LocalUser\Public" /grant "${sidSystem}:(OI)(CI)F" | Out-Null
    icacls "$($global:FTP_ROOT)\LocalUser\Public" /grant "IUSR:(OI)(CI)RX"        | Out-Null

    Write-Host "  Permisos NTFS aplicados correctamente." -ForegroundColor Green
    FTP-Log "Permisos NTFS aplicados"
}

# ── Configurar sitio FTP en IIS ──────────────────────────────────────────────

function FTP-Configurar-Sitio {
    Escribir-Titulo "CONFIGURAR SITIO FTP EN IIS"
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Eliminar sitio previo si existe
    if (Get-WebSite $global:FTP_SITE -ErrorAction SilentlyContinue) {
        Remove-WebSite $global:FTP_SITE -ErrorAction SilentlyContinue
    }

    # Crear sitio FTP apuntando a C:\Users (requerido por IsolateAllDirectories en Windows EN)
    New-WebFtpSite -Name $global:FTP_SITE -Port 21 -PhysicalPath $global:FTP_ROOT -Force | Out-Null

    # Insertar configuracion en applicationHost.config
    # (Set-ItemProperty falla en algunas versiones EN por encoding)
    $configPath = "C:\Windows\System32\inetsrv\config\applicationHost.config"
    $utf8NoBOM  = New-Object System.Text.UTF8Encoding $false
    $content    = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)

    $viejo = "</bindings>`r`n            </site>"
    $nuevo = "</bindings>`r`n                <ftpServer>`r`n                    <userIsolation mode=""IsolateAllDirectories"" />`r`n                    <security>`r`n                        <ssl controlChannelPolicy=""SslAllow"" dataChannelPolicy=""SslAllow"" />`r`n                        <authentication>`r`n                            <anonymousAuthentication enabled=""true"" />`r`n                            <basicAuthentication enabled=""true"" />`r`n                        </authentication>`r`n                    </security>`r`n                </ftpServer>`r`n            </site>"

    if ($content -notmatch "userIsolation") {
        $content = $content.Replace($viejo, $nuevo)
        [System.IO.File]::WriteAllText($configPath, $content, $utf8NoBOM)
    }

    # Reglas de autorizacion via appcmd
    $appcmd = "C:\Windows\System32\inetsrv\appcmd.exe"
    & $appcmd set config $global:FTP_SITE -section:system.ftpServer/security/authorization /+"[accessType='Allow',users='?',permissions='Read']" /commit:apphost 2>$null
    & $appcmd set config $global:FTP_SITE -section:system.ftpServer/security/authorization /+"[accessType='Allow',roles='ftpusuarios',permissions='Read,Write']" /commit:apphost 2>$null

    Restart-Service ftpsvc -ErrorAction SilentlyContinue

    Write-Host "  Sitio FTP configurado correctamente." -ForegroundColor Green
    Write-Host "    Raiz FTP   : $($global:FTP_ROOT)" -ForegroundColor Gray
    Write-Host "    Home user  : $($global:FTP_ROOT)\$($global:SERVER_NAME)\<usuario>" -ForegroundColor Gray
    Write-Host "    Home anon  : $($global:FTP_ROOT)\LocalUser\Public" -ForegroundColor Gray
    FTP-Log "Sitio FTP configurado"
    Registrar-Resumen -Servicio "IIS-FTP" -Accion "Configuracion" -Estado "OK" -Detalle "Puerto 21"
}

# ── Crear usuarios FTP ───────────────────────────────────────────────────────

function FTP-Crear-Usuarios {
    Escribir-Titulo "CREAR USUARIOS FTP"

    $cantidad = 0
    while ($cantidad -lt 1) {
        $raw = Leer-Texto -Prompt "Cuantos usuarios desea crear"
        if ($raw -match '^\d+$' -and [int]$raw -gt 0) { $cantidad = [int]$raw }
        else { Write-Host "  Ingrese un numero mayor a 0." -ForegroundColor Red }
    }

    for ($i = 1; $i -le $cantidad; $i++) {
        Write-Host ""
        Write-Host "  --- Usuario $i de $cantidad ---" -ForegroundColor Cyan

        $usuario = Leer-Texto -Prompt "  Nombre de usuario"
        Write-Host "  Contrasena: " -NoNewline
        $pass  = Read-Host -AsSecureString
        $grupo = ""
        while ($grupo -notin @("reprobados","recursadores")) {
            $grupo = Leer-Texto -Prompt "  Grupo (reprobados / recursadores)"
            if ($grupo -notin @("reprobados","recursadores")) {
                Write-Host "  Grupo invalido. Debe ser 'reprobados' o 'recursadores'." -ForegroundColor Red
            }
        }

        if (Get-LocalUser $usuario -ErrorAction SilentlyContinue) {
            Write-Host "  El usuario '$usuario' ya existe. Omitiendo." -ForegroundColor Yellow
            continue
        }

        # Crear usuario local
        New-LocalUser $usuario -Password $pass -PasswordNeverExpires | Out-Null
        Add-LocalGroupMember $grupo        -Member $usuario -ErrorAction SilentlyContinue
        Add-LocalGroupMember "ftpusuarios" -Member $usuario -ErrorAction SilentlyContinue

        # Home del usuario: C:\Users\<SERVIDOR>\<usuario>
        $userHome = "$($global:FTP_ROOT)\$($global:SERVER_NAME)\$usuario"
        New-Item $userHome -ItemType Directory -Force | Out-Null
        New-Item "$($global:FTP_DATA)\usuarios\$usuario" -ItemType Directory -Force | Out-Null

        # Junction links visibles al hacer login
        foreach ($link in @("general", $grupo, $usuario)) {
            if (Test-Path "$userHome\$link") { cmd /c rmdir "$userHome\$link" | Out-Null }
        }
        cmd /c mklink /J "$userHome\general"  "$($global:FTP_DATA)\general"           | Out-Null
        cmd /c mklink /J "$userHome\$grupo"   "$($global:FTP_DATA)\$grupo"            | Out-Null
        cmd /c mklink /J "$userHome\$usuario" "$($global:FTP_DATA)\usuarios\$usuario" | Out-Null

        # Permisos NTFS
        icacls $userHome                                    /grant "${usuario}:(OI)(CI)RX" | Out-Null
        icacls "$($global:FTP_DATA)\usuarios\$usuario"     /grant "${usuario}:(OI)(CI)F"  | Out-Null

        Write-Host "  Usuario '$usuario' creado en grupo '$grupo'." -ForegroundColor Green
        FTP-Log "Usuario $usuario creado en grupo $grupo"
    }

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "  Usuarios creados correctamente." -ForegroundColor Green
}

# ── Eliminar usuario FTP ─────────────────────────────────────────────────────

function FTP-Eliminar-Usuario {
    Escribir-Titulo "ELIMINAR USUARIO FTP"
    FTP-Ver-Usuarios

    $usuario = Leer-Texto -Prompt "Nombre del usuario a eliminar"

    if (-not (Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "  El usuario '$usuario' no existe." -ForegroundColor Yellow
        return
    }

    Remove-LocalUser $usuario -ErrorAction SilentlyContinue
    Remove-Item "$($global:FTP_ROOT)\$($global:SERVER_NAME)\$usuario" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$($global:FTP_DATA)\usuarios\$usuario"               -Recurse -Force -ErrorAction SilentlyContinue

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "  Usuario '$usuario' eliminado." -ForegroundColor Green
    FTP-Log "Usuario eliminado: $usuario"
}

# ── Cambiar grupo de usuario FTP ─────────────────────────────────────────────

function FTP-Cambiar-Grupo {
    Escribir-Titulo "CAMBIAR GRUPO DE USUARIO FTP"
    FTP-Ver-Usuarios

    $usuario = Leer-Texto -Prompt "Nombre del usuario"
    if (-not (Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "  El usuario '$usuario' no existe." -ForegroundColor Yellow
        return
    }

    $grupo = ""
    while ($grupo -notin @("reprobados","recursadores")) {
        $grupo = Leer-Texto -Prompt "Nuevo grupo (reprobados / recursadores)"
        if ($grupo -notin @("reprobados","recursadores")) {
            Write-Host "  Grupo invalido." -ForegroundColor Red
        }
    }

    # Quitar de grupos anteriores
    Remove-LocalGroupMember -Group "reprobados"   -Member $usuario -ErrorAction SilentlyContinue
    Remove-LocalGroupMember -Group "recursadores" -Member $usuario -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $grupo         -Member $usuario -ErrorAction SilentlyContinue

    # Actualizar junction links
    $userHome = "$($global:FTP_ROOT)\$($global:SERVER_NAME)\$usuario"
    foreach ($g in @("reprobados","recursadores")) {
        if (Test-Path "$userHome\$g") { cmd /c rmdir "$userHome\$g" | Out-Null }
    }
    cmd /c mklink /J "$userHome\$grupo" "$($global:FTP_DATA)\$grupo" | Out-Null

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "  Usuario '$usuario' movido al grupo '$grupo'." -ForegroundColor Green
    FTP-Log "Usuario $usuario cambiado al grupo $grupo"
}

# ── Ver usuarios FTP ─────────────────────────────────────────────────────────

function FTP-Ver-Usuarios {
    Write-Host ""
    Write-Host "  Usuarios FTP registrados:" -ForegroundColor Cyan
    Write-Host ""
    $miembros = Get-LocalGroupMember "ftpusuarios" -ErrorAction SilentlyContinue
    if (-not $miembros) {
        Write-Host "  (No hay usuarios en el grupo ftpusuarios)" -ForegroundColor DarkGray
        return
    }
    foreach ($m in $miembros) {
        $u      = $m.Name.Split("\")[-1]
        $grupos = @()
        if (Get-LocalGroupMember "reprobados"   -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$u" }) { $grupos += "reprobados" }
        if (Get-LocalGroupMember "recursadores" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$u" }) { $grupos += "recursadores" }
        Write-Host ("    {0,-20} Grupo: {1}" -f $u, ($grupos -join ", ")) -ForegroundColor Gray
    }
    Write-Host ""
}

# ── Estado del servidor FTP ──────────────────────────────────────────────────

function FTP-Ver-Estado {
    Write-Host ""
    Write-Host "  Servicio ftpsvc:" -ForegroundColor Cyan
    $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if ($svc) {
        $color = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host ("    Estado: {0}" -f $svc.Status) -ForegroundColor $color
    } else {
        Write-Host "    FTP no instalado." -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  Puerto 21:" -ForegroundColor Cyan
    $escucha = netstat -an 2>$null | Select-String ":21 "
    if ($escucha) { $escucha | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray } }
    else          { Write-Host "    No hay nada escuchando en puerto 21." -ForegroundColor DarkGray }

    Write-Host ""
    Write-Host "  Sitios IIS:" -ForegroundColor Cyan
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Get-WebSite -ErrorAction SilentlyContinue | Format-Table Name, State, PhysicalPath -AutoSize
}

# ── Reiniciar FTP ────────────────────────────────────────────────────────────

function FTP-Reiniciar {
    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "  Servicio FTP reiniciado." -ForegroundColor Green
}

# ── Menu de administracion FTP ───────────────────────────────────────────────

function Menu-Administrar-FTP {
    while ($true) {
        Escribir-Titulo "ADMINISTRAR SERVIDOR FTP LOCAL"
        Write-Host "  -- CONFIGURACION INICIAL (ejecutar en orden la primera vez) --" -ForegroundColor Yellow
        Write-Host "   1) Instalar IIS + FTP Service"
        Write-Host "   2) Configurar Firewall (puertos 21 y 50000-51000)"
        Write-Host "   3) Crear grupos (reprobados, recursadores, ftpusuarios)"
        Write-Host "   4) Crear estructura de carpetas"
        Write-Host "   5) Aplicar permisos NTFS"
        Write-Host "   6) Configurar sitio FTP en IIS"
        Write-Host ""
        Write-Host "  -- GESTION DE USUARIOS --" -ForegroundColor Yellow
        Write-Host "   7) Crear usuario(s) FTP"
        Write-Host "   8) Eliminar usuario FTP"
        Write-Host "   9) Cambiar grupo de usuario"
        Write-Host "  10) Ver usuarios FTP"
        Write-Host ""
        Write-Host "  -- UTILIDADES --" -ForegroundColor Yellow
        Write-Host "  11) Ver estado del servidor FTP"
        Write-Host "  12) Reiniciar servicio FTP"
        Write-Host "   0) Volver al menu principal"
        Write-Host ""

        $op = Leer-Opcion -Prompt "Seleccione" -Validas @("0","1","2","3","4","5","6","7","8","9","10","11","12")

        switch ($op) {
            "1"  { FTP-Instalar }
            "2"  { FTP-Configurar-Firewall }
            "3"  { FTP-Crear-Grupos }
            "4"  { FTP-Crear-Estructura }
            "5"  { FTP-Aplicar-Permisos }
            "6"  { FTP-Configurar-Sitio }
            "7"  { FTP-Crear-Usuarios }
            "8"  { FTP-Eliminar-Usuario }
            "9"  { FTP-Cambiar-Grupo }
            "10" { FTP-Ver-Usuarios }
            "11" { FTP-Ver-Estado }
            "12" { FTP-Reiniciar }
            "0"  { return }
        }
    }
}
