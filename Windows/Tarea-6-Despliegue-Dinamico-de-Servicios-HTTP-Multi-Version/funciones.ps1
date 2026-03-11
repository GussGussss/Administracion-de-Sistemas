function instalar_winget(){

Write-Host ""
Write-Host "Instalando Winget..."
Write-Host ""

$dir="C:\winget"

New-Item -ItemType Directory -Path $dir -Force | Out-Null

# Descargar dependencias
Invoke-WebRequest `
https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx `
-OutFile "$dir\VCLibs.appx"

Invoke-WebRequest `
https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx `
-OutFile "$dir\UI.Xaml.appx"

Invoke-WebRequest `
https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle `
-OutFile "$dir\winget.msixbundle"

Write-Host "Instalando dependencias..."

Add-AppxPackage "$dir\VCLibs.appx"
Add-AppxPackage "$dir\UI.Xaml.appx"
Add-AppxPackage "$dir\winget.msixbundle"

Write-Host ""
Write-Host "Winget instalado correctamente"
Write-Host ""

}

function validar_puerto($puerto){

if ($puerto -notmatch "^\d+$"){
Write-Host "Puerto inválido"
return $false
}

if ($puerto -lt 1 -or $puerto -gt 65535){
Write-Host "Puerto fuera de rango"
return $false
}

if ($puerto -eq 22 -or $puerto -eq 25 -or $puerto -eq 53){
Write-Host "Puerto reservado"
return $false
}

$ocupado = Get-NetTCPConnection -LocalPort $puerto -ErrorAction SilentlyContinue

if ($ocupado){
Write-Host "Puerto en uso"
return $false
}

return $true

}

function abrir_firewall($puerto){

New-NetFirewallRule `
-DisplayName "HTTP-$puerto" `
-Direction Inbound `
-Protocol TCP `
-LocalPort $puerto `
-Action Allow `
-ErrorAction SilentlyContinue | Out-Null

}

function configurar_seguridad_iis(){

Import-Module WebAdministration

Remove-WebConfigurationProperty `
-pspath 'MACHINE/WEBROOT/APPHOST' `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-atElement @{name='X-Powered-By'} `
-ErrorAction SilentlyContinue

}

function listar_versiones_apache_win(){

Write-Host ""
Write-Host "Versiones disponibles de Apache"
Write-Host ""

winget show ApacheFriends.ApacheHTTPServer

}

function listar_versiones_iis(){

Write-Host ""
Write-Host "IIS es un servicio integrado en Windows."
Write-Host "La versión depende del sistema operativo."
Write-Host ""

Get-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole

}

function listar_versiones_nginx_win(){

Write-Host ""
Write-Host "Versiones disponibles de Nginx"
Write-Host ""

winget show Nginx.Nginx

}

function instalar_iis($puerto){

Write-Host "Instalando IIS..."

Enable-WindowsOptionalFeature `
-Online `
-FeatureName IIS-WebServerRole `
-All `
-NoRestart | Out-Null

Import-Module WebAdministration

Remove-WebBinding `
-Name "Default Web Site" `
-Protocol "http" `
-Port 80 `
-ErrorAction SilentlyContinue

New-WebBinding `
-Name "Default Web Site" `
-Protocol "http" `
-Port $puerto

abrir_firewall $puerto

crear_index "IIS" "Windows" $puerto "C:\inetpub\wwwroot"

configurar_seguridad_iis

Write-Host "IIS instalado en puerto $puerto"

}

function instalar_apache_win($version,$puerto){

Write-Host "Instalando Apache..."

$url="https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.62-win64-VS17.zip"

$zip="C:\temp\apache.zip"
$dest="C:\Apache24"

New-Item -ItemType Directory -Path C:\temp -Force | Out-Null

Invoke-WebRequest $url -OutFile $zip

Expand-Archive $zip -DestinationPath C:\ -Force

$config="$dest\conf\httpd.conf"

(Get-Content $config) `
-replace "Listen 80","Listen $puerto" `
| Set-Content $config

abrir_firewall $puerto

crear_index "Apache" "2.4.62" $puerto "$dest\htdocs"

Start-Process "$dest\bin\httpd.exe"

}

function instalar_nginx_win($version,$puerto){

Write-Host "Instalando Nginx..."

$url="https://nginx.org/download/nginx-1.26.2.zip"

$zip="C:\temp\nginx.zip"
$dest="C:\nginx"

New-Item -ItemType Directory -Path C:\temp -Force | Out-Null

Invoke-WebRequest $url -OutFile $zip

Expand-Archive $zip -DestinationPath C:\ -Force

Rename-Item "C:\nginx-1.26.2" $dest -Force

$config="$dest\conf\nginx.conf"

(Get-Content $config) `
-replace "listen\s+80","listen $puerto" `
| Set-Content $config

abrir_firewall $puerto

crear_index "Nginx" "1.26.2" $puerto "$dest\html"

Start-Process "$dest\nginx.exe"

}

function crear_index($servicio,$version,$puerto,$directorio){

if(!(Test-Path $directorio)){
New-Item -ItemType Directory -Path $directorio | Out-Null
}

$html=@"
<html>
<head>
<title>Servidor HTTP</title>
</head>
<body>
<h1>Servidor: $servicio</h1>
<h2>Version: $version</h2>
<h3>Puerto: $puerto</h3>
</body>
</html>
"@

$html | Out-File "$directorio\index.html" -Encoding utf8

}
