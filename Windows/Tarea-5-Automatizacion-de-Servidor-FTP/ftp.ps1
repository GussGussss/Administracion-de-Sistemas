Import-Module ServerManager

$ftpRoot="C:\FTP"
$ftpSite="FTP_SERVER"
$logFile="C:\FTP\ftp_log.txt"

if (!(Test-Path $ftpRoot)) {
New-Item $ftpRoot -ItemType Directory -Force | Out-Null
}

# ------------------------------------------------------------
# LOG
# ------------------------------------------------------------

function Log {

param($msg)

$fecha=Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Add-Content $logFile "$fecha - $msg"

}

# ------------------------------------------------------------
# INSTALAR FTP
# ------------------------------------------------------------

function Instalar-FTP {

Write-Host "Instalando IIS + FTP..."

Import-Module ServerManager

$features=@(
"Web-Server",
"Web-FTP-Server",
"Web-FTP-Service",
"Web-FTP-Ext"
)

foreach($f in $features){

$estado = Get-WindowsFeature $f

if(!$estado.Installed){

Write-Host "Instalando $f ..."
Install-WindowsFeature $f -IncludeManagementTools

}
else{

Write-Host "$f ya está instalado."

}

}

# Importar módulo IIS después de instalar
Import-Module WebAdministration -ErrorAction SilentlyContinue

Start-Service W3SVC -ErrorAction SilentlyContinue
Start-Service ftpsvc -ErrorAction SilentlyContinue

Set-Service ftpsvc -StartupType Automatic

Write-Host "FTP instalado correctamente."

Log "FTP instalado"

}

# ------------------------------------------------------------
# FIREWALL
# ------------------------------------------------------------

function Configurar-Firewall {

New-NetFirewallRule `
-DisplayName "FTP 21" `
-Direction Inbound `
-Protocol TCP `
-LocalPort 21 `
-Action Allow `
-ErrorAction SilentlyContinue

New-NetFirewallRule `
-DisplayName "FTP Passive" `
-Direction Inbound `
-Protocol TCP `
-LocalPort 50000-51000 `
-Action Allow `
-ErrorAction SilentlyContinue

Write-Host "Firewall configurado"

Log "Firewall configurado"

}

# ------------------------------------------------------------
# CREAR GRUPOS
# ------------------------------------------------------------

function Crear-Grupos {

$grupos=@("reprobados","recursadores","ftpusuarios")

foreach($g in $grupos){

if(!(Get-LocalGroup $g -ErrorAction SilentlyContinue)){

New-LocalGroup $g

Write-Host "Grupo $g creado"

}

}

Log "Grupos creados"

}

# ------------------------------------------------------------
# ESTRUCTURA
# ------------------------------------------------------------

function Crear-Estructura {

New-Item $ftpRoot -ItemType Directory -Force

New-Item "$ftpRoot\general" -ItemType Directory -Force
New-Item "$ftpRoot\reprobados" -ItemType Directory -Force
New-Item "$ftpRoot\recursadores" -ItemType Directory -Force

New-Item "$ftpRoot\Data\Usuarios" -ItemType Directory -Force

New-Item "$ftpRoot\LocalUser\Public" -ItemType Directory -Force

cmd /c mklink /J "$ftpRoot\LocalUser\Public\general" "$ftpRoot\general"

Write-Host "Estructura creada"

Log "Estructura FTP creada"

}

# ------------------------------------------------------------
# PERMISOS
# ------------------------------------------------------------

function Permisos {

# ROOT
icacls $ftpRoot /inheritance:r
icacls $ftpRoot /grant "Administrators:(OI)(CI)F"
icacls $ftpRoot /grant "SYSTEM:(OI)(CI)F"
icacls $ftpRoot /grant "IUSR:(RX)"

# GENERAL
icacls "$ftpRoot\general" /inheritance:r
icacls "$ftpRoot\general" /grant "Administrators:(OI)(CI)F"
icacls "$ftpRoot\general" /grant "SYSTEM:(OI)(CI)F"
icacls "$ftpRoot\general" /grant "ftpusuarios:(OI)(CI)M"
icacls "$ftpRoot\general" /grant "IUSR:(OI)(CI)RX"

# REPROBADOS
icacls "$ftpRoot\reprobados" /inheritance:r
icacls "$ftpRoot\reprobados" /grant "Administrators:(OI)(CI)F"
icacls "$ftpRoot\reprobados" /grant "SYSTEM:(OI)(CI)F"
icacls "$ftpRoot\reprobados" /grant "reprobados:(OI)(CI)M"

# RECURSADORES
icacls "$ftpRoot\recursadores" /inheritance:r
icacls "$ftpRoot\recursadores" /grant "Administrators:(OI)(CI)F"
icacls "$ftpRoot\recursadores" /grant "SYSTEM:(OI)(CI)F"
icacls "$ftpRoot\recursadores" /grant "recursadores:(OI)(CI)M"

# LOCALUSER
icacls "$ftpRoot\LocalUser" /inheritance:r
icacls "$ftpRoot\LocalUser" /grant "Administrators:(OI)(CI)F"
icacls "$ftpRoot\LocalUser" /grant "SYSTEM:(OI)(CI)F"
icacls "$ftpRoot\LocalUser" /grant "IUSR:(OI)(CI)RX"
icacls "$ftpRoot\LocalUser" /grant "IIS_IUSRS:(OI)(CI)RX"

# PUBLIC
icacls "$ftpRoot\LocalUser\Public" /inheritance:r
icacls "$ftpRoot\LocalUser\Public" /grant "Administrators:(OI)(CI)F"
icacls "$ftpRoot\LocalUser\Public" /grant "SYSTEM:(OI)(CI)F"
icacls "$ftpRoot\LocalUser\Public" /grant "IUSR:(OI)(CI)RX"
icacls "$ftpRoot\LocalUser\Public" /grant "IIS_IUSRS:(OI)(CI)RX"

Write-Host "Permisos aplicados correctamente"

}

# ------------------------------------------------------------
# CONFIGURAR FTP
# ------------------------------------------------------------

function Configurar-FTP {

if(Get-WebSite $ftpSite -ErrorAction SilentlyContinue){

Remove-WebSite $ftpSite

}

New-WebFtpSite `
-Name $ftpSite `
-Port 21 `
-PhysicalPath $ftpRoot `
-Force

# DESACTIVAR SSL (SOLUCION ERROR 534)
Set-ItemProperty "IIS:\Sites\$ftpSite" `
-Name ftpServer.security.ssl.controlChannelPolicy `
-Value 0

Set-ItemProperty "IIS:\Sites\$ftpSite" `
-Name ftpServer.security.ssl.dataChannelPolicy `
-Value 0

Set-ItemProperty "IIS:\Sites\$ftpSite" `
-Name ftpServer.userIsolation.mode `
-Value 3

Set-ItemProperty "IIS:\Sites\$ftpSite" `
-Name ftpServer.security.authentication.anonymousAuthentication.enabled `
-Value $true

Set-ItemProperty "IIS:\Sites\$ftpSite" `
-Name ftpServer.security.authentication.basicAuthentication.enabled `
-Value $true

Clear-WebConfiguration `
-Filter system.ftpServer/security/authorization `
-PSPath IIS:\ `
-Location $ftpSite

Add-WebConfiguration `
-Filter system.ftpServer/security/authorization `
-PSPath IIS:\ `
-Location $ftpSite `
-Value @{accessType="Allow";users="?";permissions="Read"}

Add-WebConfiguration `
-Filter system.ftpServer/security/authorization `
-PSPath IIS:\ `
-Location $ftpSite `
-Value @{accessType="Allow";roles="ftpusuarios";permissions="Read,Write"}

Restart-Service ftpsvc

Write-Host "FTP configurado"

Log "FTP configurado"

}
# ------------------------------------------------------------
# CREAR USUARIOS
# ------------------------------------------------------------

function Crear-Usuarios {

$cantidad = Read-Host "¿Cuantos usuarios desea crear?"

for($i=1; $i -le $cantidad; $i++){

Write-Host ""
Write-Host "Creando usuario $i de $cantidad"

$usuario = Read-Host "Nombre de usuario"
$pass = Read-Host "Contraseña" -AsSecureString
$grupo = Read-Host "Grupo (reprobados/recursadores)"

if($grupo -ne "reprobados" -and $grupo -ne "recursadores"){
Write-Host "Grupo inválido"
continue
}

if(Get-LocalUser $usuario -ErrorAction SilentlyContinue){
Write-Host "El usuario ya existe"
continue
}

# crear usuario
New-LocalUser $usuario -Password $pass -FullName $usuario

# agregar a grupos
Add-LocalGroupMember $grupo -Member $usuario
Add-LocalGroupMember "ftpusuarios" -Member $usuario

# crear home ftp
$userHome="$ftpRoot\LocalUser\$usuario"

New-Item $userHome -ItemType Directory -Force

# carpeta personal real
New-Item "$ftpRoot\Data\Usuarios\$usuario" -ItemType Directory -Force

# enlaces
cmd /c mklink /J "$userHome\general" "$ftpRoot\general"
cmd /c mklink /J "$userHome\$grupo" "$ftpRoot\$grupo"
cmd /c mklink /J "$userHome\$usuario" "$ftpRoot\Data\Usuarios\$usuario"

# permisos usuario
icacls "$ftpRoot\Data\Usuarios\$usuario" /grant "${usuario}:(OI)(CI)F"

Write-Host "Usuario $usuario creado"

}

Restart-Service ftpsvc

Write-Host "Usuarios creados correctamente"

}

# ------------------------------------------------------------
# MENU
# ------------------------------------------------------------

function Menu {

while($true){

Write-Host ""
Write-Host "========= ADMIN FTP ========="

Write-Host "1 Instalar FTP"
Write-Host "2 Firewall"
Write-Host "3 Crear Grupos"
Write-Host "4 Crear Estructura"
Write-Host "5 Permisos"
Write-Host "6 Configurar FTP"
Write-host "7 Crear usuarios"
Write-Host "0 Salir"

$op=Read-Host "Opcion"

switch($op){

"1"{Instalar-FTP}
"2"{Configurar-Firewall}
"3"{Crear-Grupos}
"4"{Crear-Estructura}
"5"{Permisos}
"6"{Configurar-FTP}
"7"{Crear-Usuarios}
"0"{break}

}

}

}

Menu
