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

Write-Host "IIS instalado en puerto $puerto"

}

function instalar_apache_win($version,$puerto){

Write-Host "Instalando Apache..."

winget install `
--id ApacheFriends.ApacheHTTPServer `
--silent `
--accept-package-agreements `
--accept-source-agreements

$config="C:\Apache24\conf\httpd.conf"

(Get-Content $config) `
-replace "Listen 80","Listen $puerto" `
| Set-Content $config

abrir_firewall $puerto

crear_index "Apache" $version $puerto "C:\Apache24\htdocs"
Restart-Service Apache2.4 -ErrorAction SilentlyContinue
}

function instalar_nginx_win($version,$puerto){

Write-Host "Instalando Nginx..."

winget install `
--id Nginx.Nginx `
--silent `
--accept-package-agreements `
--accept-source-agreements

$config="C:\Program Files\nginx\conf\nginx.conf"

(Get-Content $config) `
-replace "listen\s+80","listen $puerto" `
| Set-Content $config

abrir_firewall $puerto

crear_index "Nginx" $version $puerto "C:\Program Files\nginx\html"
Stop-Process -Name nginx -Force -ErrorAction SilentlyContinue
Start-Process "C:\Program Files\nginx\nginx.exe"
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

Remove-WebConfigurationProperty `
-pspath 'MACHINE/WEBROOT/APPHOST' `
-filter "system.webServer/httpProtocol/customHeaders" `
-name "." `
-atElement @{name='X-Powered-By'} `
-ErrorAction SilentlyContinue
