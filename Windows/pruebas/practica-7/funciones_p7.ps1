# ============================================================
# funciones_p7.ps1
# Funciones para Practica 7: Despliegue Seguro e Instalacion Hibrida
# Windows Server 2019 Core (sin GUI) - PowerShell
# Integra: P5 (FTP/IIS) + P6 (HTTP) + SSL/TLS + Hash
# ============================================================

# ============================================================
# VARIABLES GLOBALES DE ESTADO
# ============================================================
$global:RESUMEN = @()   # Acumula resultados para el resumen final
$global:FTP_IP   = ""
$global:FTP_USER = ""
$global:FTP_PASS = ""

# ============================================================
# LOG HELPER
# ============================================================
function Log-Resumen {
    param([string]$Servicio, [string]$Accion, [string]$Estado, [string]$Detalle = "")
    $global:RESUMEN += [PSCustomObject]@{
        Servicio = $Servicio
        Accion   = $Accion
        Estado   = $Estado
        Detalle  = $Detalle
    }
}

# ============================================================
# MOSTRAR RESUMEN FINAL
# ============================================================
function Mostrar-Resumen {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                  RESUMEN FINAL DE INSTALACION               " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $global:RESUMEN | Format-Table -AutoSize -Property Servicio, Accion, Estado, Detalle

    $ok   = ($global:RESUMEN | Where-Object { $_.Estado -eq "OK" }).Count
    $fail = ($global:RESUMEN | Where-Object { $_.Estado -eq "ERROR" }).Count
    $warn = ($global:RESUMEN | Where-Object { $_.Estado -eq "ADVERTENCIA" }).Count

    Write-Host ""
    Write-Host "  OK          : $ok" -ForegroundColor Green
    Write-Host "  ADVERTENCIA : $warn" -ForegroundColor Yellow
    Write-Host "  ERROR       : $fail" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan
}


# ============================================================
# VALIDAR ENTRADA DE TEXTO (sin caracteres especiales)
# ============================================================
function Leer-Texto {
    param([string]$Prompt, [int]$MaxLen = 100)
    while ($true) {
        Write-Host $Prompt -NoNewline
        $val = Read-Host
        if ([string]::IsNullOrWhiteSpace($val)) {
            Write-Host "No puede estar vacio." -ForegroundColor Red; continue
        }
        if ($val.Length -gt $MaxLen) {
            Write-Host "Demasiado largo (max $MaxLen caracteres)." -ForegroundColor Red; continue
        }
        return $val.Trim()
    }
}

# ============================================================
# LEER OPCION VALIDADA
# ============================================================
function Leer-Opcion {
    param([string]$Prompt, [string[]]$Validas)
    while ($true) {
        Write-Host $Prompt -NoNewline
        $val = Read-Host
        if ([string]::IsNullOrWhiteSpace($val)) {
            Write-Host "Entrada invalida." -ForegroundColor Red; continue
        }
        if ($Validas -and ($Validas -notcontains $val.Trim())) {
            Write-Host "Opcion no valida. Validas: $($Validas -join ', ')" -ForegroundColor Red; continue
        }
        return $val.Trim()
    }
}

# ============================================================
# LEER CREDENCIALES FTP
# ============================================================
function Leer-Credenciales-FTP {
    Write-Host ""
    Write-Host "--- Credenciales del Servidor FTP Privado ---" -ForegroundColor Cyan
    $global:FTP_IP   = Leer-Texto -Prompt "IP del servidor FTP: "
    $global:FTP_USER = Leer-Texto -Prompt "Usuario FTP: "
    Write-Host "Contrasena FTP: " -NoNewline
    $secPass = Read-Host -AsSecureString
    $bstr    = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
    $global:FTP_PASS = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

# ============================================================
# LISTAR DIRECTORIO FTP (devuelve array de nombres)
# ============================================================
function Listar-FTP {
    param([string]$RutaFTP)

    $uri  = "ftp://$($global:FTP_IP)/$RutaFTP"
    $cred = New-Object System.Net.NetworkCredential($global:FTP_USER, $global:FTP_PASS)

    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = $cred
        $req.UsePassive   = $true
        $req.UseBinary    = $false
        $req.KeepAlive    = $false

        $resp   = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $lista  = @()
        while (-not $reader.EndOfStream) {
            $linea = $reader.ReadLine().Trim()
            if ($linea -ne "") { $lista += $linea }
        }
        $reader.Close()
        $resp.Close()
        return $lista
    }
    catch {
        Write-Host "Error al listar FTP: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# ============================================================
# DESCARGAR ARCHIVO FTP
# ============================================================
function Descargar-FTP {
    param([string]$RutaFTP, [string]$Destino)

    $uri  = "ftp://$($global:FTP_IP)/$RutaFTP"
    $cred = New-Object System.Net.NetworkCredential($global:FTP_USER, $global:FTP_PASS)

    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $req.Credentials = $cred
        $req.UsePassive   = $true
        $req.UseBinary    = $true
        $req.KeepAlive    = $false

        $resp       = $req.GetResponse()
        $stream     = $resp.GetResponseStream()
        $fileStream = [System.IO.File]::Create($Destino)
        $stream.CopyTo($fileStream)
        $fileStream.Close()
        $stream.Close()
        $resp.Close()
        Write-Host "Descargado: $Destino" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error al descargar $RutaFTP : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ============================================================
# VERIFICAR INTEGRIDAD SHA256
# ============================================================
function Verificar-Hash {
    param([string]$ArchivoDescargado, [string]$ArchivoSha256)

    Write-Host ""
    Write-Host "Verificando integridad SHA256..." -ForegroundColor Cyan

    if (-not (Test-Path $ArchivoDescargado)) {
        Write-Host "Error: Archivo no encontrado: $ArchivoDescargado" -ForegroundColor Red
        Log-Resumen -Servicio "Hash" -Accion "SHA256" -Estado "ERROR" -Detalle "Archivo no encontrado"
        return $false
    }
    if (-not (Test-Path $ArchivoSha256)) {
        Write-Host "Error: Archivo .sha256 no encontrado: $ArchivoSha256" -ForegroundColor Red
        Log-Resumen -Servicio "Hash" -Accion "SHA256" -Estado "ERROR" -Detalle ".sha256 no encontrado"
        return $false
    }

    # Calcular hash local
    $hashLocal = (Get-FileHash -Path $ArchivoDescargado -Algorithm SHA256).Hash.ToLower()

    # Leer hash esperado (puede ser solo el hash o "hash  nombre_archivo")
    $contenido     = (Get-Content $ArchivoSha256 -Raw).Trim().ToLower()
    $hashEsperado  = ($contenido -split "\s+")[0]

    Write-Host "  Hash calculado : $hashLocal"
    Write-Host "  Hash esperado  : $hashEsperado"

    if ($hashLocal -eq $hashEsperado) {
        Write-Host "Integridad verificada correctamente." -ForegroundColor Green
        Log-Resumen -Servicio (Split-Path $ArchivoDescargado -Leaf) -Accion "SHA256" -Estado "OK" -Detalle "Hash coincide"
        return $true
    }
    else {
        Write-Host "ALERTA: El hash NO coincide. El archivo puede estar corrupto o alterado." -ForegroundColor Red
        Log-Resumen -Servicio (Split-Path $ArchivoDescargado -Leaf) -Accion "SHA256" -Estado "ERROR" -Detalle "Hash NO coincide"
        return $false
    }
}

# ============================================================
# NAVEGACION FTP DINAMICA Y DESCARGA
# Estructura esperada en FTP: /http/Windows/<Servicio>/<archivo>
# ============================================================
function Instalar-Desde-FTP {
    param([string]$Servicio)

    Leer-Credenciales-FTP

    Write-Host ""
    Write-Host "Conectando al repositorio FTP privado..." -ForegroundColor Cyan

    # Nivel 1: listar servicios disponibles en /http/Windows/
    $rutaOS      = "http/Windows"
    $servicios   = Listar-FTP -RutaFTP $rutaOS

    if ($servicios.Count -eq 0) {
        Write-Host "No se encontraron servicios en el repositorio FTP ($rutaOS)." -ForegroundColor Red
        Log-Resumen -Servicio $Servicio -Accion "FTP-Lista" -Estado "ERROR" -Detalle "Directorio vacio o inaccesible"
        return $false
    }

    Write-Host ""
    Write-Host "Servicios disponibles en FTP ($rutaOS):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $servicios.Count; $i++) {
        Write-Host "  $($i+1)) $($servicios[$i])"
    }

    $opciones = 1..$servicios.Count | ForEach-Object { "$_" }
    $selIdx   = [int](Leer-Opcion -Prompt "Seleccione servicio [1-$($servicios.Count)]: " -Validas $opciones) - 1
    $svcElegido = $servicios[$selIdx]

    # Nivel 2: listar archivos dentro del servicio elegido
    $rutaSvc  = "$rutaOS/$svcElegido"
    $archivos = Listar-FTP -RutaFTP $rutaSvc

    # Filtrar solo instaladores (excluir .sha256)
    $instaladores = $archivos | Where-Object { $_ -match "\.(msi|zip|exe|nupkg)$" }

    if ($instaladores.Count -eq 0) {
        Write-Host "No se encontraron instaladores en $rutaSvc" -ForegroundColor Red
        Log-Resumen -Servicio $svcElegido -Accion "FTP-Archivos" -Estado "ERROR" -Detalle "Sin instaladores"
        return $false
    }

    Write-Host ""
    Write-Host "Versiones disponibles para $svcElegido :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $instaladores.Count; $i++) {
        Write-Host "  $($i+1)) $($instaladores[$i])"
    }

    $opciones2   = 1..$instaladores.Count | ForEach-Object { "$_" }
    $selIdx2     = [int](Leer-Opcion -Prompt "Seleccione version [1-$($instaladores.Count)]: " -Validas $opciones2) - 1
    $archivoEleg = $instaladores[$selIdx2]
    $archivSha   = "$archivoEleg.sha256"

    # Descargar instalador y .sha256
    $tmpDir   = "$env:TEMP\ftp_install"
    New-Item $tmpDir -ItemType Directory -Force | Out-Null

    $destInst = "$tmpDir\$archivoEleg"
    $destSha  = "$tmpDir\$archivSha"

    Write-Host ""
    Write-Host "Descargando $archivoEleg ..." -ForegroundColor Cyan
    $ok1 = Descargar-FTP -RutaFTP "$rutaSvc/$archivoEleg" -Destino $destInst
    if (-not $ok1) {
        Log-Resumen -Servicio $svcElegido -Accion "FTP-Descarga" -Estado "ERROR" -Detalle "No se pudo descargar $archivoEleg"
        return $false
    }

    Write-Host "Descargando $archivSha ..." -ForegroundColor Cyan
    $ok2 = Descargar-FTP -RutaFTP "$rutaSvc/$archivSha" -Destino $destSha
    if (-not $ok2) {
        Write-Host "Advertencia: No se encontro el .sha256. Continuando sin verificacion." -ForegroundColor Yellow
        Log-Resumen -Servicio $svcElegido -Accion "FTP-Hash" -Estado "ADVERTENCIA" -Detalle "Sin archivo .sha256"
    }
    else {
        $integro = Verificar-Hash -ArchivoDescargado $destInst -ArchivoSha256 $destSha
        if (-not $integro) {
            $conf = Leer-Opcion -Prompt "El hash no coincide. ¿Continuar de todas formas? [S/N]: " -Validas @("S","N","s","n")
            if ($conf -match "^[Nn]$") {
                Write-Host "Instalacion cancelada por fallo de integridad." -ForegroundColor Red
                return $false
            }
        }
    }

    # Instalar segun extension
    Write-Host ""
    Write-Host "Instalando $archivoEleg ..." -ForegroundColor Cyan
    Instalar-Binario -Archivo $destInst -Servicio $svcElegido

    Log-Resumen -Servicio $svcElegido -Accion "Instalacion-FTP" -Estado "OK" -Detalle $archivoEleg
    return $true
}

# ============================================================
# INSTALAR BINARIO SEGUN EXTENSION
# ============================================================
function Instalar-Binario {
    param([string]$Archivo, [string]$Servicio)

    $ext = [System.IO.Path]::GetExtension($Archivo).ToLower()

    switch ($ext) {
        ".msi" {
            Write-Host "Ejecutando instalacion MSI silenciosa..." -ForegroundColor Cyan
            $args = "/i `"$Archivo`" /quiet /norestart /l*v `"$env:TEMP\install_$Servicio.log`""
            Start-Process msiexec.exe -ArgumentList $args -Wait -NoNewWindow
        }
        ".exe" {
            Write-Host "Ejecutando instalador EXE silencioso..." -ForegroundColor Cyan
            Start-Process $Archivo -ArgumentList "/S /quiet /norestart" -Wait -NoNewWindow
        }
        ".zip" {
            Write-Host "Extrayendo ZIP en C:\$Servicio ..." -ForegroundColor Cyan
            $destDir = "C:\$Servicio"
            Expand-Archive -Path $Archivo -DestinationPath $destDir -Force
            Write-Host "Extraido en $destDir" -ForegroundColor Green
        }
        default {
            Write-Host "Extension '$ext' no reconocida. El archivo queda en: $Archivo" -ForegroundColor Yellow
        }
    }
}


# ============================================================
# GENERAR CERTIFICADO AUTOFIRMADO (OpenSSL no disponible en Server Core;
# usamos New-SelfSignedCertificate nativo de PowerShell)
# ============================================================
function Generar-Certificado {
    param([string]$Dominio = "www.reprobados.com")

    Write-Host ""
    Write-Host "Generando certificado autofirmado para $Dominio ..." -ForegroundColor Cyan

    # Eliminar cert anterior con mismo dominio si existe
    Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -like "*$Dominio*" } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $cert = New-SelfSignedCertificate `
        -DnsName $Dominio `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddDays(365) `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -FriendlyName "SSL $Dominio (P7)"

    Write-Host "Certificado generado." -ForegroundColor Green
    Write-Host "  Thumbprint : $($cert.Thumbprint)"
    Write-Host "  Expira     : $($cert.NotAfter)"

    Log-Resumen -Servicio $Dominio -Accion "Cert-Generado" -Estado "OK" -Detalle $cert.Thumbprint
    return $cert.Thumbprint
}

# ============================================================
# SSL EN IIS (puerto 443 + redireccion HTTP->HTTPS)
# ============================================================
function Activar-SSL-IIS {
    param([string]$Dominio = "www.reprobados.com")

    Write-Host ""
    Write-Host "Activando SSL/TLS en IIS para $Dominio ..." -ForegroundColor Cyan

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $thumb = Generar-Certificado -Dominio $Dominio

    $siteName = "Default Web Site"

    # Agregar binding HTTPS en 443
    try {
        $existeHttps = Get-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue
        if ($existeHttps) {
            Remove-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue
        }

        New-WebBinding -Name $siteName -Protocol "https" -Port 443 -IPAddress "*" -SslFlags 0 | Out-Null

        # Asociar certificado al binding
        $bindingPath = "IIS:\SslBindings\0.0.0.0!443"
        if (Test-Path $bindingPath) { Remove-Item $bindingPath -Force }
        $cert = Get-Item "Cert:\LocalMachine\My\$thumb"
        $cert | New-Item $bindingPath | Out-Null

        Write-Host "Binding HTTPS:443 configurado en IIS." -ForegroundColor Green
    }
    catch {
        Write-Host "Error configurando HTTPS en IIS: $($_.Exception.Message)" -ForegroundColor Red
        Log-Resumen -Servicio "IIS" -Accion "SSL-443" -Estado "ERROR" -Detalle $_.Exception.Message
        return
    }

    # ── Detectar si URL Rewrite esta instalado ───────────────────────────────
    # URL Rewrite registra su modulo en la configuracion global de IIS.
    # Si no esta, el web.config con <rewrite> causa error 500.
    $urlRewriteInstalado = $false
    try {
        $modulosIIS = Get-WebConfiguration -Filter "system.webServer/globalModules/*" -PSPath "IIS:\" -ErrorAction SilentlyContinue
        if ($modulosIIS | Where-Object { $_.Name -like "*RewriteModule*" }) {
            $urlRewriteInstalado = $true
        }
    } catch {}

    # Verificacion alternativa: buscar la DLL del modulo
    if (-not $urlRewriteInstalado) {
        $rewriteDll = "C:\Windows\System32\inetsrv\rewrite.dll"
        if (Test-Path $rewriteDll) { $urlRewriteInstalado = $true }
    }

    $webConfig = "C:\inetpub\wwwroot\web.config"

    if ($urlRewriteInstalado) {
        Write-Host "URL Rewrite detectado. Configurando redireccion HTTP->HTTPS..." -ForegroundColor Cyan
        $contenidoRedir = @"
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
          <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
        </rule>
      </rules>
    </rewrite>
    <httpProtocol>
      <customHeaders>
        <add name="Strict-Transport-Security" value="max-age=31536000; includeSubDomains" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@
        $contenidoRedir | Set-Content $webConfig -Encoding UTF8
    }
    else {
        # Sin URL Rewrite: web.config solo con cabeceras de seguridad (sin <rewrite>)
        # La redireccion se hace a nivel de binding IIS: se elimina el binding HTTP:80
        # para forzar que solo funcione HTTPS:443
        Write-Host "URL Rewrite no instalado. Aplicando redireccion por binding IIS..." -ForegroundColor Yellow

        $contenidoSinRewrite = @"
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
"@
        $contenidoSinRewrite | Set-Content $webConfig -Encoding UTF8

        # Redireccion alternativa: agregar binding en puerto 80 que apunte a HTTPS
        # usando una pagina de redireccion en el directorio raiz
        $redirHtml = @"
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="refresh" content="0; url=https://$Dominio" />
<script>window.location.replace("https://$Dominio" + window.location.pathname);</script>
</head>
<body>Redirigiendo a HTTPS...</body>
</html>
"@
        # Guardar la pagina de redireccion
        $redirHtml | Set-Content "C:\inetpub\wwwroot\redirect.html" -Encoding UTF8

        # Configurar documento de error 403 para redirigir via HTTP
        try {
            Set-WebConfigurationProperty `
                -PSPath "IIS:\" `
                -Filter "system.webServer/defaultDocument/files" `
                -Name "." `
                -Value @{ value = "redirect.html" } `
                -ErrorAction SilentlyContinue
        } catch {}

        Write-Host "Redireccion alternativa configurada (meta-refresh a HTTPS)." -ForegroundColor Green
        Write-Host "NOTA: Para redireccion 301 completa instale URL Rewrite:" -ForegroundColor Yellow
        Write-Host "      choco install urlrewrite  (luego ejecute opcion 4 del menu)" -ForegroundColor Yellow
    }

    iisreset /restart | Out-Null

    # Verificar que 443 responde
    Start-Sleep -Seconds 3
    $verif = Test-NetConnection -ComputerName localhost -Port 443 -WarningAction SilentlyContinue
    $estadoSSL = if ($verif.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }

    Write-Host "IIS SSL en puerto 443: $estadoSSL" -ForegroundColor $(if ($estadoSSL -eq "OK") { "Green" } else { "Yellow" })
    Log-Resumen -Servicio "IIS" -Accion "SSL-443" -Estado $estadoSSL -Detalle "Thumbprint: $thumb"
}

# ============================================================
# SSL EN APACHE (Win64)
# Requiere mod_ssl incluido en la instalacion de Chocolatey
# ============================================================
function Activar-SSL-Apache {
    param([string]$Dominio = "www.reprobados.com")

    Write-Host ""
    Write-Host "Activando SSL/TLS en Apache para $Dominio ..." -ForegroundColor Cyan

    # Localizar Apache
    $apacheBase = "C:\Apache24"
    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        $encontrado = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($encontrado) { $apacheBase = Split-Path $encontrado.DirectoryName -Parent }
    }

    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        Write-Host "Apache no esta instalado. Instale Apache primero." -ForegroundColor Red
        Log-Resumen -Servicio "Apache" -Accion "SSL-443" -Estado "ERROR" -Detalle "Apache no instalado"
        return
    }

    # Generar cert PEM con PowerShell y exportar a archivos para Apache
    $thumb = Generar-Certificado -Dominio $Dominio
    $cert  = Get-Item "Cert:\LocalMachine\My\$thumb"

    $sslDir  = "$apacheBase\conf\ssl"
    New-Item $sslDir -ItemType Directory -Force | Out-Null

    # Exportar certificado a PFX temporal, luego a CRT/KEY via openssl si existe
    $pfxPath  = "$sslDir\reprobados.pfx"
    $pfxPass  = "P7temporal123!"
    $secPfxPw = ConvertTo-SecureString $pfxPass -AsPlainText -Force

    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secPfxPw | Out-Null

    # Intentar usar openssl si esta disponible (instalado por Chocolatey u otro medio)
    $opensslExe = Get-Command openssl -ErrorAction SilentlyContinue
    if ($opensslExe) {
        & openssl pkcs12 -in $pfxPath -clcerts -nokeys -out "$sslDir\server.crt" -password "pass:$pfxPass" 2>&1 | Out-Null
        & openssl pkcs12 -in $pfxPath -nocerts -nodes  -out "$sslDir\server.key" -password "pass:$pfxPass" 2>&1 | Out-Null
        Write-Host "Certificado exportado a CRT/KEY con openssl." -ForegroundColor Green
    }
    else {
        # Sin openssl: usar el PFX directamente y configurar Apache con mod_pkcs11 o advertir
        Write-Host "openssl no encontrado. Se usara el PFX exportado." -ForegroundColor Yellow
        Write-Host "Instale openssl (choco install openssl) para completar la configuracion de Apache SSL." -ForegroundColor Yellow
        Log-Resumen -Servicio "Apache" -Accion "SSL-443" -Estado "ADVERTENCIA" -Detalle "openssl no disponible"
        return
    }

    # Habilitar mod_ssl en httpd.conf
    $confPath = "$apacheBase\conf\httpd.conf"
    $conf     = Get-Content $confPath -Raw

    # Descomentar modulos necesarios
    foreach ($mod in @("mod_ssl.so", "mod_socache_shmcb.so", "mod_rewrite.so")) {
        $conf = $conf -replace "#(LoadModule\s+\S+\s+modules/$mod)", '$1'
    }

    # Descomentar include de httpd-ssl.conf
    $conf = $conf -replace "#(Include conf/extra/httpd-ssl.conf)", '$1'

    [System.IO.File]::WriteAllText($confPath, $conf)

    # Escribir VirtualHost SSL
    $sslConf = "$apacheBase\conf\extra\httpd-ssl.conf"

    $vhostSSL = @"
Listen 443

SSLPassPhraseDialog builtin
SSLSessionCache "shmcb:$($apacheBase -replace '\\','/')/logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost *:443>
    ServerName $Dominio
    DocumentRoot "$($apacheBase -replace '\\','/')/htdocs"

    SSLEngine on
    SSLCertificateFile    "$($sslDir -replace '\\','/')/server.crt"
    SSLCertificateKeyFile "$($sslDir -replace '\\','/')/server.key"

    SSLProtocol all -SSLv2 -SSLv3
    SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES

    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</VirtualHost>

# Redireccion HTTP -> HTTPS
<VirtualHost *:80>
    ServerName $Dominio
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]
</VirtualHost>
"@
    [System.IO.File]::WriteAllText($sslConf, $vhostSSL, [System.Text.UTF8Encoding]::new($false))

    # Abrir puerto 443 en firewall
    Remove-NetFirewallRule -DisplayName "HTTPS-443-Apache" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTPS-443-Apache" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow | Out-Null

    # Reiniciar Apache
    Restart-Service "Apache2.4" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $verif     = Test-NetConnection -ComputerName localhost -Port 443 -WarningAction SilentlyContinue
    $estadoSSL = if ($verif.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }

    Write-Host "Apache SSL en puerto 443: $estadoSSL" -ForegroundColor $(if ($estadoSSL -eq "OK") { "Green" } else { "Yellow" })
    Log-Resumen -Servicio "Apache" -Accion "SSL-443" -Estado $estadoSSL -Detalle "Thumbprint: $thumb"
}

# ============================================================
# SSL EN NGINX (Windows)
# ============================================================
function Activar-SSL-Nginx {
    param([string]$Dominio = "www.reprobados.com")

    Write-Host ""
    Write-Host "Activando SSL/TLS en Nginx para $Dominio ..." -ForegroundColor Cyan

    $nginxBase = "C:\nginx"
    if (-not (Test-Path "$nginxBase\nginx.exe")) {
        Write-Host "Nginx no esta instalado. Instale Nginx primero." -ForegroundColor Red
        Log-Resumen -Servicio "Nginx" -Accion "SSL-443" -Estado "ERROR" -Detalle "Nginx no instalado"
        return
    }

    $thumb = Generar-Certificado -Dominio $Dominio
    $cert  = Get-Item "Cert:\LocalMachine\My\$thumb"

    $sslDir  = "$nginxBase\ssl"
    New-Item $sslDir -ItemType Directory -Force | Out-Null

    $pfxPath  = "$sslDir\reprobados.pfx"
    $pfxPass  = "P7temporal123!"
    $secPfxPw = ConvertTo-SecureString $pfxPass -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secPfxPw | Out-Null

    $opensslExe = Get-Command openssl -ErrorAction SilentlyContinue
    if (-not $opensslExe) {
        Write-Host "openssl no encontrado. Instale openssl (choco install openssl) para generar CRT/KEY." -ForegroundColor Yellow
        Log-Resumen -Servicio "Nginx" -Accion "SSL-443" -Estado "ADVERTENCIA" -Detalle "openssl no disponible"
        return
    }

    & openssl pkcs12 -in $pfxPath -clcerts -nokeys -out "$sslDir\server.crt" -password "pass:$pfxPass" 2>&1 | Out-Null
    & openssl pkcs12 -in $pfxPath -nocerts -nodes  -out "$sslDir\server.key" -password "pass:$pfxPass" 2>&1 | Out-Null

    # Obtener puerto HTTP actual de Nginx
    $confPath    = "$nginxBase\conf\nginx.conf"
    $puertoHttp  = 80
    if (Test-Path $confPath) {
        $linea = Select-String -Path $confPath -Pattern "listen\s+(\d+)" | Select-Object -First 1
        if ($linea -and $linea.Line -match "listen\s+(\d+)") { $puertoHttp = [int]$matches[1] }
    }

    $sslDirFwd = $sslDir -replace '\\', '/'
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

    # Redireccion HTTP -> HTTPS
    server {
        listen $puertoHttp;
        server_name $Dominio;
        return 301 https://`$host`$request_uri;
    }

    # HTTPS
    server {
        listen 443 ssl;
        server_name $Dominio;
        root html;

        ssl_certificate     $sslDirFwd/server.crt;
        ssl_certificate_key $sslDirFwd/server.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";

        location / {
            index index.html index.htm;
        }
    }
}
"@
    [System.IO.File]::WriteAllText($confPath, $nginxConf, [System.Text.UTF8Encoding]::new($false))

    # Abrir 443 en firewall
    Remove-NetFirewallRule -DisplayName "HTTPS-443-Nginx" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTPS-443-Nginx" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow | Out-Null

    # Reiniciar Nginx
    taskkill /f /im nginx.exe 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden
    Start-Sleep -Seconds 3

    $verif     = Test-NetConnection -ComputerName localhost -Port 443 -WarningAction SilentlyContinue
    $estadoSSL = if ($verif.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }

    Write-Host "Nginx SSL en puerto 443: $estadoSSL" -ForegroundColor $(if ($estadoSSL -eq "OK") { "Green" } else { "Yellow" })
    Log-Resumen -Servicio "Nginx" -Accion "SSL-443" -Estado $estadoSSL -Detalle "Thumbprint: $thumb"
}

# ============================================================
# FTPS EN IIS-FTP (SSL sobre canal de control y datos)
# Requiere que IIS FTP este instalado (Practica 5)
# ============================================================
function Activar-SSL-FTP-IIS {
    param([string]$Dominio = "www.reprobados.com", [string]$SitioFTP = "FTP_SERVER")

    Write-Host ""
    Write-Host "Activando FTPS (SSL) en IIS-FTP para $Dominio ..." -ForegroundColor Cyan

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Verificar que el sitio FTP existe
    $sitioExiste = Get-WebSite -Name $SitioFTP -ErrorAction SilentlyContinue
    if (-not $sitioExiste) {
        Write-Host "El sitio FTP '$SitioFTP' no existe. Ejecute primero la Practica 5." -ForegroundColor Red
        Log-Resumen -Servicio "IIS-FTP" -Accion "FTPS" -Estado "ERROR" -Detalle "Sitio FTP no encontrado"
        return
    }

    $thumb = Generar-Certificado -Dominio $Dominio

    # Aplicar SSL al sitio FTP via appcmd
    $appcmd = "C:\Windows\System32\inetsrv\appcmd.exe"

    # Modo: SslRequire = obliga SSL en canal de control
    # SslDataRequire = obliga SSL en canal de datos
    & $appcmd set config $SitioFTP `
        -section:system.ftpServer/security/ssl `
        /serverCertHash:$thumb `
        /controlChannelPolicy:"SslRequire" `
        /dataChannelPolicy:"SslRequire" `
        /commit:apphost 2>&1 | Out-Null

    # Abrir puerto 990 (FTPS implicito) adicionalmente
    Remove-NetFirewallRule -DisplayName "FTPS-990" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "FTPS-990" -Direction Inbound -Protocol TCP -LocalPort 990 -Action Allow | Out-Null

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $verif     = Test-NetConnection -ComputerName localhost -Port 21 -WarningAction SilentlyContinue
    $estadoFTP = if ($verif.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }

    Write-Host "IIS-FTPS configurado: $estadoFTP" -ForegroundColor $(if ($estadoFTP -eq "OK") { "Green" } else { "Yellow" })
    Log-Resumen -Servicio "IIS-FTP" -Accion "FTPS-SSL" -Estado $estadoFTP -Detalle "Thumbprint: $thumb"
}

# ============================================================
# MENU: SELECCION FUENTE DE INSTALACION
# ============================================================
function Menu-Fuente-Instalacion {
    param([string]$Servicio)

    Write-Host ""
    Write-Host "--- Fuente de instalacion para: $Servicio ---" -ForegroundColor Cyan
    Write-Host "  1) WEB  - Repositorio oficial (Chocolatey / descarga directa)"
    Write-Host "  2) FTP  - Repositorio privado (Practica 5)"
    Write-Host ""

    return Leer-Opcion -Prompt "Seleccione fuente [1/2]: " -Validas @("1","2")
}

# ============================================================
# MENU: ACTIVAR SSL POR SERVICIO
# ============================================================
function Preguntar-SSL {
    param([string]$Servicio)

    Write-Host ""
    $resp = Leer-Opcion -Prompt "¿Desea activar SSL/TLS en $Servicio ? [S/N]: " -Validas @("S","N","s","n")
    return $resp -match "^[Ss]$"
}

# ============================================================
# VERIFICACION AUTOMATIZADA DE TODOS LOS SERVICIOS
# ============================================================
function Verificar-Todos-Los-Servicios {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "          VERIFICACION AUTOMATIZADA DE SERVICIOS             " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    $checks = @(
        @{ Nombre = "IIS HTTP";   Puerto = 80  },
        @{ Nombre = "IIS HTTPS";  Puerto = 443 },
        @{ Nombre = "Apache HTTP"; Puerto = 80  },
        @{ Nombre = "Apache HTTPS"; Puerto = 443 },
        @{ Nombre = "Nginx HTTP";  Puerto = 80  },
        @{ Nombre = "Nginx HTTPS"; Puerto = 443 },
        @{ Nombre = "FTP";         Puerto = 21  },
        @{ Nombre = "FTPS";        Puerto = 990 }
    )

    foreach ($svc in $checks) {
        $test = Test-NetConnection -ComputerName localhost -Port $svc.Puerto -WarningAction SilentlyContinue
        $est  = if ($test.TcpTestSucceeded) { "ACTIVO" } else { "INACTIVO" }
        $col  = if ($est -eq "ACTIVO") { "Green" } else { "Gray" }
        Write-Host ("  {0,-18} Puerto {1,-5} -> {2}" -f $svc.Nombre, $svc.Puerto, $est) -ForegroundColor $col
        Log-Resumen -Servicio $svc.Nombre -Accion "Verificacion" -Estado $(if ($est -eq "ACTIVO") { "OK" } else { "ADVERTENCIA" }) -Detalle "Puerto $($svc.Puerto)"
    }
}
