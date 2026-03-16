# ============================================================
# ftp_client.ps1
# Cliente FTP dinamico para repositorio privado
# Practica 07
# ============================================================

# ------------------------------------------------------------
# CONFIGURACION DEL FTP
# ------------------------------------------------------------

$FTP_SERVER = "192.168.1.100"
$FTP_USER   = "ftpuser"
$FTP_PASS   = "password"

$BASE_PATH  = "/http/Windows"

$DOWNLOAD_DIR = "C:\Temp\ftp_downloads"

if (-not (Test-Path $DOWNLOAD_DIR)) {
    New-Item $DOWNLOAD_DIR -ItemType Directory | Out-Null
}

# ------------------------------------------------------------
# LISTAR DIRECTORIO FTP
# ------------------------------------------------------------

function Listar-FTP {

    param($path)

    $uri = "ftp://$FTP_SERVER$path"

    $request = [System.Net.FtpWebRequest]::Create($uri)
    $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory

    $request.Credentials = New-Object System.Net.NetworkCredential($FTP_USER,$FTP_PASS)

    $response = $request.GetResponse()

    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())

    $items = @()

    while (-not $reader.EndOfStream) {
        $items += $reader.ReadLine()
    }

    $reader.Close()
    $response.Close()

    return $items
}

# ------------------------------------------------------------
# DESCARGAR ARCHIVO FTP
# ------------------------------------------------------------

function Descargar-Archivo-FTP {

    param(
        $remoteFile,
        $localFile
    )

    $uri = "ftp://$FTP_SERVER$remoteFile"

    $wc = New-Object System.Net.WebClient
    $wc.Credentials = New-Object System.Net.NetworkCredential($FTP_USER,$FTP_PASS)

    Write-Host "Descargando $remoteFile ..." -ForegroundColor Cyan

    $wc.DownloadFile($uri,$localFile)

    Write-Host "Descarga completada." -ForegroundColor Green
}

# ------------------------------------------------------------
# INSTALACION DESDE FTP
# ------------------------------------------------------------

function Instalar-HTTP-FTP {

    Write-Host ""
    Write-Host "Conectando al repositorio FTP..." -ForegroundColor Yellow

    # listar servicios disponibles
    $servicios = Listar-FTP $BASE_PATH

    if ($servicios.Count -eq 0) {
        Write-Host "No se encontraron servicios en el FTP." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Servicios disponibles:" -ForegroundColor Cyan

    for ($i=0; $i -lt $servicios.Count; $i++) {
        Write-Host "$($i+1)) $($servicios[$i])"
    }

    $op = Read-Host "Seleccione servicio"

    $servicio = $servicios[$op-1]

    $rutaServicio = "$BASE_PATH/$servicio"

    # listar instaladores
    $archivos = Listar-FTP $rutaServicio

    Write-Host ""
    Write-Host "Versiones disponibles:" -ForegroundColor Cyan

    for ($i=0; $i -lt $archivos.Count; $i++) {
        Write-Host "$($i+1)) $($archivos[$i])"
    }

    $op2 = Read-Host "Seleccione archivo"

    $archivo = $archivos[$op2-1]

    $remoteFile = "$rutaServicio/$archivo"

    $localFile = "$DOWNLOAD_DIR\$archivo"

    Descargar-Archivo-FTP $remoteFile $localFile

    # descargar hash
    $hashRemote = "$remoteFile.sha256"
    $hashLocal  = "$localFile.sha256"

    Descargar-Archivo-FTP $hashRemote $hashLocal

    # verificar integridad
    Verificar-Hash $localFile $hashLocal

    Write-Host ""
    Write-Host "Procediendo a instalacion..." -ForegroundColor Yellow

    if ($archivo -like "*.msi") {

        Start-Process msiexec.exe `
        -ArgumentList "/i `"$localFile`" /quiet" `
        -Wait

    }
    elseif ($archivo -like "*.zip") {

        Expand-Archive $localFile -DestinationPath "C:\Servidores"

    }

    Write-Host ""
    Write-Host "Instalacion completada." -ForegroundColor Green
}
