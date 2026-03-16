# ============================================================
# practica7.ps1
# Orquestador de Instalacion Hibrida + SSL/TLS - Practica 7
# Windows Server 2019 Core (sin GUI) - PowerShell
# Ejecutar como Administrador
# ============================================================
#
# Archivos requeridos en la misma carpeta:
#   ssl_funciones.ps1        <- funciones SSL/TLS (P7)
#   http_functions.ps1       <- funciones HTTP: IIS, Apache, Nginx (P6)
#   ftp_admin.ps1            <- funciones FTP: IIS-FTP (P5)
#   Preparar-Repositorio.ps1 <- prepara repositorio FTP (P7)
#
# Ejecutar primero: .\Preparar-Repositorio.ps1
# ============================================================

# ------------------------------------------------------------
# Verificar Administrador
# ------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecutar este script como Administrador." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# Cargar scripts de practicas anteriores
#
# NOTA IMPORTANTE sobre ftp_admin.ps1:
#   Ese script tiene una llamada a Menu() al final de su codigo.
#   Si hacemos dot-source directamente, abriria el menu del FTP
#   en medio de P7. La solucion es definir una funcion Menu()
#   vacia ANTES de cargarlo, para que esa llamada no haga nada.
#   Luego P7 define su propio Menu() que sobreescribe esa version
#   vacia y es el que realmente se ejecuta al final.
#
# NOTA sobre main.ps1 del HTTP:
#   No se carga porque tiene un bucle while propio que tomaria
#   el control. Solo se necesita http_functions.ps1.
# ------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Neutralizar Menu() antes de cargar ftp_admin.ps1
function Menu { }

# Cargar funciones HTTP (P6)
$rutaHTTP = "$scriptDir\http_functions.ps1"
if (Test-Path $rutaHTTP) {
    . $rutaHTTP
    Write-Host "Cargado: http_functions.ps1" -ForegroundColor Gray
} else {
    Write-Host "ADVERTENCIA: http_functions.ps1 no encontrado." -ForegroundColor Yellow
}

# Cargar funciones FTP (P5) - Menu() ya esta neutralizado
$rutaFTP = "$scriptDir\ftp_admin.ps1"
if (Test-Path $rutaFTP) {
    . $rutaFTP
    Write-Host "Cargado: ftp_admin.ps1" -ForegroundColor Gray
} else {
    Write-Host "ADVERTENCIA: ftp_admin.ps1 no encontrado." -ForegroundColor Yellow
}

# Cargar funciones SSL (P7)
$rutaSSL = "$scriptDir\ssl_funciones.ps1"
if (Test-Path $rutaSSL) {
    . $rutaSSL
    Write-Host "Cargado: ssl_funciones.ps1" -ForegroundColor Gray
} else {
    Write-Host "ADVERTENCIA: ssl_funciones.ps1 no encontrado." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Variables globales de P7
# ------------------------------------------------------------
$global:FTP_HOST = "127.0.0.1"
$global:FTP_PORT = 21
$global:FTP_USER = ""
$global:FTP_PASS = ""
$global:FTP_REPO = "/http/Windows"
$global:LOG_FILE = "C:\FTP_Data\practica7_log.txt"
$global:REPORTE  = @{}

# ------------------------------------------------------------
# Log
# ------------------------------------------------------------
function Log7 {
    param($msg)
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $linea = "$fecha - $msg"
    Add-Content $global:LOG_FILE $linea -ErrorAction SilentlyContinue
    Write-Host $linea -ForegroundColor DarkGray
}

# ============================================================
# BLOQUE 1: CLIENTE FTP DINAMICO
# ============================================================

# ------------------------------------------------------------
# Pedir credenciales FTP al usuario
# ------------------------------------------------------------
function Pedir-Credenciales-FTP {
    Write-Host ""
    Write-Host "--- Credenciales del servidor FTP ---" -ForegroundColor Cyan
    Write-Host "Servidor : $global:FTP_HOST"
    Write-Host "Puerto   : $global:FTP_PORT"
    Write-Host ""
    $global:FTP_USER = Read-Host "Usuario FTP"
    $passSegura      = Read-Host "Contrasena FTP" -AsSecureString
    $global:FTP_PASS = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passSegura)
    )
}

# ------------------------------------------------------------
# Listar contenido de una carpeta en el servidor FTP
# Retorna array de nombres
# ------------------------------------------------------------
function Listar-FTP {
    param([string]$Ruta)

    $url  = "ftp://$($global:FTP_HOST):$($global:FTP_PORT)$Ruta"
    $cred = New-Object System.Net.NetworkCredential($global:FTP_USER, $global:FTP_PASS)

    try {
        $request             = [System.Net.FtpWebRequest]::Create($url)
        $request.Method      = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $request.Credentials = $cred
        $request.UsePassive  = $true
        $request.UseBinary   = $true
        $request.KeepAlive   = $false
        $request.Timeout     = 10000

        $response  = $request.GetResponse()
        $stream    = $response.GetResponseStream()
        $reader    = New-Object System.IO.StreamReader($stream)
        $contenido = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()

        $items = $contenido.Split("`n") |
                 ForEach-Object { $_.Trim() } |
                 Where-Object   { $_ -ne "" }
        return $items

    } catch {
        Write-Host "ERROR al listar FTP ($Ruta): $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# ------------------------------------------------------------
# Descargar un archivo desde el servidor FTP
# Retorna $true si tuvo exito
# ------------------------------------------------------------
function Descargar-FTP {
    param(
        [string]$RutaRemota,
        [string]$RutaLocal
    )

    $url  = "ftp://$($global:FTP_HOST):$($global:FTP_PORT)$RutaRemota"
    $cred = New-Object System.Net.NetworkCredential($global:FTP_USER, $global:FTP_PASS)

    try {
        Write-Host "  Descargando : $RutaRemota" -ForegroundColor Gray
        Write-Host "  Destino     : $RutaLocal"  -ForegroundColor Gray

        $request             = [System.Net.FtpWebRequest]::Create($url)
        $request.Method      = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $request.Credentials = $cred
        $request.UsePassive  = $true
        $request.UseBinary   = $true
        $request.KeepAlive   = $false
        $request.Timeout     = 60000

        $response   = $request.GetResponse()
        $stream     = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($RutaLocal)
        $stream.CopyTo($fileStream)
        $fileStream.Close()
        $response.Close()

        $tamano = (Get-Item $RutaLocal).Length
        Write-Host "  Descargado  : $("{0:N0}" -f $tamano) bytes" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "ERROR al descargar ($RutaRemota): $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ------------------------------------------------------------
# Navegar el repositorio FTP paso a paso:
#   1. Lista servicios disponibles en /http/Windows/
#   2. Usuario elige servicio
#   3. Lista instaladores dentro de esa carpeta
#   4. Usuario elige archivo
#   5. Descarga instalador y su .sha256
# Retorna hashtable con info del archivo, o $null si cancela
# ------------------------------------------------------------
function Navegar-Repositorio-FTP {

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " REPOSITORIO FTP PRIVADO" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Conectando a $($global:FTP_HOST):$($global:FTP_PORT)$($global:FTP_REPO) ..." -ForegroundColor Gray

    # Paso 1: listar servicios disponibles
    $servicios = Listar-FTP -Ruta $global:FTP_REPO

    if ($servicios.Count -eq 0) {
        Write-Host "No se encontraron servicios en el repositorio." -ForegroundColor Red
        Write-Host "Verifica que el servidor FTP este corriendo y el repositorio preparado." -ForegroundColor Yellow
        return $null
    }

    Write-Host ""
    Write-Host "Servicios disponibles:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $servicios.Count; $i++) {
        Write-Host "  $($i + 1)) $($servicios[$i])"
    }
    Write-Host "  0) Cancelar"

    do {
        $selSvc = Read-Host "Seleccione servicio"
        if ($selSvc -eq "0") { return $null }
        $idxSvc = [int]$selSvc - 1
    } while ($idxSvc -lt 0 -or $idxSvc -ge $servicios.Count)

    $servicioElegido = $servicios[$idxSvc]
    $rutaServicio    = "$($global:FTP_REPO)/$servicioElegido"

    # Paso 2: listar archivos del servicio elegido
    Write-Host ""
    Write-Host "Archivos en $servicioElegido :" -ForegroundColor Yellow

    $archivos = Listar-FTP -Ruta $rutaServicio

    # Mostrar solo instaladores, excluir .sha256 e index.txt
    $instaladores = $archivos | Where-Object {
        $_ -match "\.(zip|msi|exe|deb|tar\.gz)$"
    }

    if ($instaladores.Count -eq 0) {
        Write-Host "No se encontraron instaladores en $rutaServicio" -ForegroundColor Red
        return $null
    }

    for ($i = 0; $i -lt $instaladores.Count; $i++) {
        Write-Host "  $($i + 1)) $($instaladores[$i])"
    }
    Write-Host "  0) Cancelar"

    do {
        $selArch = Read-Host "Seleccione instalador"
        if ($selArch -eq "0") { return $null }
        $idxArch = [int]$selArch - 1
    } while ($idxArch -lt 0 -or $idxArch -ge $instaladores.Count)

    $archivoElegido = $instaladores[$idxArch]
    $rutaRemota     = "$rutaServicio/$archivoElegido"
    $rutaHashRemota = "$rutaRemota.sha256"
    $destino        = "$env:TEMP\$archivoElegido"
    $destinoHash    = "$destino.sha256"

    # Paso 3: descargar instalador
    Write-Host ""
    Write-Host "Descargando instalador..." -ForegroundColor Cyan
    $ok = Descargar-FTP -RutaRemota $rutaRemota -RutaLocal $destino
    if (-not $ok) { return $null }

    # Paso 4: descargar .sha256
    Write-Host "Descargando hash de verificacion..." -ForegroundColor Cyan
    $okHash = Descargar-FTP -RutaRemota $rutaHashRemota -RutaLocal $destinoHash
    if (-not $okHash) {
        Write-Host "ADVERTENCIA: No se pudo descargar el .sha256. Se omitira verificacion." -ForegroundColor Yellow
    }

    return @{
        ArchivoLocal   = $destino
        HashLocal      = $destinoHash
        Servicio       = $servicioElegido
        Archivo        = $archivoElegido
        HashDescargado = $okHash
    }
}

# ============================================================
# BLOQUE 2: VERIFICACION DE INTEGRIDAD
# ============================================================

function Verificar-Hash {
    param(
        [string]$ArchivoLocal,
        [string]$ArchivoHash
    )

    Write-Host ""
    Write-Host "--- Verificacion de integridad SHA256 ---" -ForegroundColor Cyan

    if (-not (Test-Path $ArchivoLocal)) {
        Write-Host "ERROR: Archivo no encontrado: $ArchivoLocal" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $ArchivoHash)) {
        Write-Host "ADVERTENCIA: Archivo .sha256 no encontrado. Omitiendo verificacion." -ForegroundColor Yellow
        return $true
    }

    Write-Host "  Calculando SHA256..." -ForegroundColor Gray
    $hashCalculado = (Get-FileHash -Path $ArchivoLocal -Algorithm SHA256).Hash.ToLower()

    # Formato esperado en el .sha256: "<hash>  <nombre_archivo>"
    $contenidoHash = Get-Content $ArchivoHash -Raw
    $hashEsperado  = ($contenidoHash.Trim().Split(" ") | Select-Object -First 1).ToLower()
    $nombre        = Split-Path $ArchivoLocal -Leaf

    Write-Host "  Archivo        : $nombre"                              -ForegroundColor Gray
    Write-Host "  Hash esperado  : $($hashEsperado.Substring(0,16))..."  -ForegroundColor Gray
    Write-Host "  Hash calculado : $($hashCalculado.Substring(0,16))..." -ForegroundColor Gray

    if ($hashCalculado -eq $hashEsperado) {
        Write-Host "  OK: Integridad verificada. El archivo no fue corrompido." -ForegroundColor Green
        Log7 "Hash OK: $nombre"
        return $true
    } else {
        Write-Host "  FALLO: Los hashes NO coinciden. Archivo posiblemente corrompido." -ForegroundColor Red
        Write-Host "  Esperado  : $hashEsperado"  -ForegroundColor Red
        Write-Host "  Calculado : $hashCalculado" -ForegroundColor Red
        Log7 "Hash FALLO: $nombre"
        return $false
    }
}

# ============================================================
# BLOQUE 3: INSTALACION HIBRIDA
# ============================================================

# ------------------------------------------------------------
# Instalar desde WEB usando las funciones de http_functions.ps1
# ------------------------------------------------------------
function Instalar-Desde-Web {
    param([string]$Servicio)

    Write-Host ""
    Write-Host "Instalando $Servicio desde repositorio WEB..." -ForegroundColor Cyan

    switch ($Servicio.ToUpper()) {

        "IIS" {
            Listar-Versiones-IIS
            $ver    = Read-Host "Seleccione version [1-2]"
            $puerto = Leer-Puerto-P7
            Instalar-IIS -Version "10.0" -Puerto $puerto
        }

        "APACHE" {
            Listar-Versiones-Apache
            $ver    = Read-Host "Seleccione version [1-3]"
            $puerto = Leer-Puerto-P7
            $version = switch ($ver) {
                "1" { $global:APACHE_LATEST }
                "2" { $global:APACHE_LTS    }
                "3" { $global:APACHE_OLDEST }
                default { $global:APACHE_LTS }
            }
            Instalar-Apache -Version $version -Puerto $puerto
        }

        "NGINX" {
            Listar-Versiones-Nginx
            $ver    = Read-Host "Seleccione version [1-3]"
            $puerto = Leer-Puerto-P7
            $version = switch ($ver) {
                "1" { $global:NGINX_LATEST }
                "2" { $global:NGINX_LTS    }
                "3" { $global:NGINX_OLDEST }
                default { $global:NGINX_LTS }
            }
            Instalar-Nginx -Version $version -Puerto $puerto
        }

        "FTP" {
            # Reutiliza directamente las funciones de ftp_admin.ps1 (P5)
            Write-Host "Instalando IIS-FTP usando funciones de P5..." -ForegroundColor Cyan
            Instalar-FTP
            Configurar-Firewall
            Crear-Grupos
            Crear-Estructura
            Permisos
            Configurar-FTP
            Write-Host "IIS-FTP instalado y configurado." -ForegroundColor Green
        }

        default {
            Write-Host "Servicio '$Servicio' no reconocido." -ForegroundColor Red
        }
    }
}

# ------------------------------------------------------------
# Instalar desde FTP privado: navegar, verificar hash e instalar
# ------------------------------------------------------------
function Instalar-Desde-FTP {
    param([string]$Servicio)

    Write-Host ""
    Write-Host "Instalando $Servicio desde repositorio FTP privado..." -ForegroundColor Cyan

    Pedir-Credenciales-FTP

    $resultado = Navegar-Repositorio-FTP
    if (-not $resultado) {
        Write-Host "Instalacion cancelada." -ForegroundColor Yellow
        return $false
    }

    # Verificar integridad antes de instalar
    if ($resultado.HashDescargado) {
        $hashOk = Verificar-Hash `
            -ArchivoLocal $resultado.ArchivoLocal `
            -ArchivoHash  $resultado.HashLocal

        if (-not $hashOk) {
            Write-Host ""
            Write-Host "Instalacion cancelada: el archivo no paso la verificacion de integridad." -ForegroundColor Red
            Log7 "Instalacion cancelada por hash invalido: $($resultado.Archivo)"
            return $false
        }
    }

    # Instalar segun extension
    $archivo = $resultado.ArchivoLocal
    $ext     = [System.IO.Path]::GetExtension($archivo).ToLower()

    Write-Host ""
    Write-Host "Instalando $($resultado.Servicio) ($ext)..." -ForegroundColor Cyan

    switch ($ext) {
        ".msi" {
            $proc = Start-Process msiexec.exe `
                -ArgumentList "/i `"$archivo`" /quiet /norestart" `
                -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Host "Instalacion MSI completada." -ForegroundColor Green
            } else {
                Write-Host "Error instalacion MSI (codigo: $($proc.ExitCode))" -ForegroundColor Red
                return $false
            }
        }
        ".zip" {
            $destDir = "C:\$($resultado.Servicio)"
            Expand-Archive -Path $archivo -DestinationPath $destDir -Force
            Write-Host "Extraido en: $destDir" -ForegroundColor Green
            Write-Host "NOTA: Puede requerirse configuracion manual adicional." -ForegroundColor Yellow
        }
        ".exe" {
            $proc = Start-Process $archivo `
                -ArgumentList "/S /quiet" `
                -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Host "Instalacion EXE completada." -ForegroundColor Green
            } else {
                Write-Host "Error instalacion EXE (codigo: $($proc.ExitCode))" -ForegroundColor Red
                return $false
            }
        }
        default {
            Write-Host "Extension '$ext' no tiene instalacion automatica." -ForegroundColor Yellow
            Write-Host "Archivo guardado en: $archivo" -ForegroundColor Yellow
        }
    }

    Log7 "Instalacion FTP OK: $($resultado.Servicio) - $($resultado.Archivo)"
    return $true
}

# ------------------------------------------------------------
# Orquestador principal: pregunta WEB o FTP, instala y ofrece SSL
# ------------------------------------------------------------
function Orquestar-Instalacion {
    param([string]$Servicio)

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " INSTALACION: $($Servicio.ToUpper())" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Fuente de instalacion:"
    Write-Host "  1) WEB - repositorio oficial (gestor de paquetes)"
    Write-Host "  2) FTP - repositorio privado (este servidor)"
    Write-Host "  0) Omitir"
    Write-Host ""

    do {
        $fuente = Read-Host "Seleccione [0-2]"
    } while ($fuente -notin @("0","1","2"))

    switch ($fuente) {
        "0" {
            Write-Host "Instalacion de $Servicio omitida." -ForegroundColor Yellow
            $global:REPORTE[$Servicio] = @{ Instalacion = "Omitida"; SSL = "N/A" }
            return
        }
        "1" {
            Instalar-Desde-Web -Servicio $Servicio
            $global:REPORTE[$Servicio] = @{ Instalacion = "WEB"; SSL = "Pendiente" }
        }
        "2" {
            $ok = Instalar-Desde-FTP -Servicio $Servicio
            $global:REPORTE[$Servicio] = @{
                Instalacion = if ($ok) { "FTP-OK" } else { "FTP-ERROR" }
                SSL         = "Pendiente"
            }
        }
    }

    # Ofrecer SSL inmediatamente despues de instalar
    Preguntar-SSL -Servicio $Servicio
}

# ============================================================
# BLOQUE 4: SSL/TLS
# ============================================================

function Preguntar-SSL {
    param([string]$Servicio)

    Write-Host ""
    $resp = Read-Host "Desea activar SSL en $Servicio? [S/N]"

    if ($resp.ToUpper() -ne "S") {
        Write-Host "SSL no activado en $Servicio." -ForegroundColor Yellow
        if ($global:REPORTE.ContainsKey($Servicio)) {
            $global:REPORTE[$Servicio].SSL = "No activado"
        }
        return
    }

    $ok = $false
    switch ($Servicio.ToUpper()) {
        "IIS"    { $ok = Configurar-SSL-IIS    }
        "APACHE" { $ok = Configurar-SSL-Apache  }
        "NGINX"  { $ok = Configurar-SSL-Nginx   }
        "FTP"    { $ok = Configurar-SSL-FTP     }
        default  { Write-Host "SSL no implementado para '$Servicio'" -ForegroundColor Yellow }
    }

    if ($global:REPORTE.ContainsKey($Servicio)) {
        $global:REPORTE[$Servicio].SSL = if ($ok) { "Configurado" } else { "Error" }
    }
    Log7 "SSL $Servicio : $(if ($ok) {'OK'} else {'ERROR'})"
}

# ============================================================
# BLOQUE 5: REPORTE FINAL
# ============================================================

function Generar-Reporte-Final {

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " GENERANDO REPORTE FINAL..." -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    $verificacionSSL = $null
    if (Get-Command Verificar-SSL-Completo -ErrorAction SilentlyContinue) {
        $verificacionSSL = Verificar-SSL-Completo
    }

    $lineas = @()
    $lineas += "============================================"
    $lineas += " REPORTE FINAL - PRACTICA 7"
    $lineas += " Fecha    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lineas += " Servidor : $env:COMPUTERNAME"
    $lineas += " Dominio  : $global:SSL_DOMAIN"
    $lineas += "============================================"
    $lineas += ""
    $lineas += "--- INSTALACIONES ---"
    $lineas += ""

    foreach ($svc in $global:REPORTE.Keys) {
        $info = $global:REPORTE[$svc]
        $lineas += "  Servicio    : $svc"
        $lineas += "  Instalacion : $($info.Instalacion)"
        $lineas += "  SSL         : $($info.SSL)"

        if ($verificacionSSL -and $verificacionSSL.ContainsKey($svc)) {
            $v = $verificacionSSL[$svc]
            $lineas += "  Certificado : $(if ($v.Certificado) {'OK'} else {'NO ENCONTRADO'})"
            $lineas += "  Puerto SSL  : $(if ($v.Puerto) {'Respondiendo'} else {'No responde'})"
            $lineas += "  Estado SSL  : $($v.Estado)"
        }
        $lineas += ""
    }

    $lineas += "--- CERTIFICADOS EN EL SISTEMA ---"
    $lineas += ""
    Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.FriendlyName -like "P7-SSL-*" } |
        ForEach-Object {
            $lineas += "  Nombre     : $($_.FriendlyName)"
            $lineas += "  Dominio    : $($_.Subject)"
            $lineas += "  Vence      : $($_.NotAfter.ToString('yyyy-MM-dd'))"
            $lineas += "  Thumbprint : $($_.Thumbprint)"
            $lineas += ""
        }

    $lineas += "--- PUERTOS EN ESCUCHA ---"
    $lineas += ""
    $puertos = netstat -an |
               Select-String ":80 |:443 |:21 |:990 " |
               ForEach-Object { "  $($_.Line.Trim())" }
    $lineas += $puertos

    $lineas += ""
    $lineas += "============================================"
    $lineas += " FIN DEL REPORTE"
    $lineas += "============================================"

    # Guardar en archivo
    $reportePath = "C:\FTP_Data\reporte_practica7.txt"
    $lineas | Set-Content $reportePath -Encoding UTF8
    Log7 "Reporte guardado: $reportePath"

    # Mostrar con colores
    foreach ($linea in $lineas) {
        if      ($linea -match "OK|Configurado|FTP-OK|WEB")              { Write-Host $linea -ForegroundColor Green }
        elseif  ($linea -match "ERROR|FALLO|No responde|NO ENCONTRADO")  { Write-Host $linea -ForegroundColor Red   }
        elseif  ($linea -match "^---|====")                               { Write-Host $linea -ForegroundColor Cyan  }
        else                                                               { Write-Host $linea }
    }

    Write-Host ""
    Write-Host "Reporte guardado en: $reportePath" -ForegroundColor Green
}

# ============================================================
# UTILIDAD: leer puerto con validacion basica
# Se llama Leer-Puerto-P7 para no colisionar con funciones
# de los otros scripts cargados.
# ============================================================
function Leer-Puerto-P7 {
    while ($true) {
        $input = Read-Host "Puerto de escucha"
        if ($input -match '^\d+$') {
            $p = [int]$input
            if ($p -ge 1 -and $p -le 65535) { return $p }
        }
        Write-Host "Puerto invalido. Ingrese un numero entre 1 y 65535." -ForegroundColor Red
    }
}

# ============================================================
# MENU PRINCIPAL DE P7
# Esta funcion sobreescribe la Menu() vacia que definimos
# arriba para neutralizar ftp_admin.ps1. Es la que realmente
# se ejecuta cuando llamamos Menu() al final del script.
# ============================================================
function Menu {

    while ($true) {

        Write-Host ""
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host "  PRACTICA 7 - DESPLIEGUE SEGURO           " -ForegroundColor Cyan
        Write-Host "  Instalacion Hibrida + SSL/TLS            " -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  -- Instalacion de servicios --"
        Write-Host "  1) IIS"
        Write-Host "  2) Apache"
        Write-Host "  3) Nginx"
        Write-Host "  4) FTP (IIS-FTP)"
        Write-Host ""
        Write-Host "  -- SSL/TLS (servicio ya instalado) --"
        Write-Host "  5) Activar SSL en IIS"
        Write-Host "  6) Activar SSL en Apache"
        Write-Host "  7) Activar SSL en Nginx"
        Write-Host "  8) Activar FTPS en IIS-FTP"
        Write-Host ""
        Write-Host "  -- Utilidades --"
        Write-Host "  9) Verificar SSL en todos los servicios"
        Write-Host " 10) Generar reporte final"
        Write-Host " 11) Preparar repositorio FTP"
        Write-Host "  0) Salir"
        Write-Host ""

        $op = Read-Host "Opcion"

        switch ($op) {
            "1"  { Orquestar-Instalacion -Servicio "IIS"    }
            "2"  { Orquestar-Instalacion -Servicio "Apache" }
            "3"  { Orquestar-Instalacion -Servicio "Nginx"  }
            "4"  { Orquestar-Instalacion -Servicio "FTP"    }
            "5"  {
                $ok = Configurar-SSL-IIS
                $global:REPORTE["IIS"] = @{ Instalacion = "Existente"; SSL = if ($ok) {"Configurado"} else {"Error"} }
            }
            "6"  {
                $ok = Configurar-SSL-Apache
                $global:REPORTE["Apache"] = @{ Instalacion = "Existente"; SSL = if ($ok) {"Configurado"} else {"Error"} }
            }
            "7"  {
                $ok = Configurar-SSL-Nginx
                $global:REPORTE["Nginx"] = @{ Instalacion = "Existente"; SSL = if ($ok) {"Configurado"} else {"Error"} }
            }
            "8"  {
                $ok = Configurar-SSL-FTP
                $global:REPORTE["FTP"] = @{ Instalacion = "Existente"; SSL = if ($ok) {"Configurado"} else {"Error"} }
            }
            "9"  { Verificar-SSL-Completo  }
            "10" { Generar-Reporte-Final   }
            "11" {
                $prep = "$scriptDir\Preparar-Repositorio.ps1"
                if (Test-Path $prep) { & $prep }
                else { Write-Host "Preparar-Repositorio.ps1 no encontrado." -ForegroundColor Red }
            }
            "0"  { Write-Host "Saliendo..." -ForegroundColor Yellow; exit 0 }
            default { Write-Host "Opcion no valida." -ForegroundColor Red }
        }
    }
}

# ------------------------------------------------------------
# Punto de entrada: lanzar el menu de P7
# ------------------------------------------------------------
Menu
