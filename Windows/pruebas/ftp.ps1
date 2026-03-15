# ==============================================================================
#  Tarea 5: Automatizacion de Servidor FTP - Windows Server 2019 (Sin GUI)
#  Version final corregida basada en pruebas reales en WS2019
# ==============================================================================

$ftpRoot = "C:\FTP"
$ftpSite = "FTP_SERVER"
$logFile = "C:\FTP\ftp_log.txt"

function Log {
    param($msg)
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if (-not (Test-Path $ftpRoot)) { New-Item $ftpRoot -ItemType Directory -Force | Out-Null }
    Add-Content $logFile "$fecha - $msg"
}

# ------------------------------------------------------------
# INSTALAR FTP
# ------------------------------------------------------------
function Instalar-FTP {
    Write-Host "Instalando IIS + FTP..."

    $features = @("Web-Server","Web-Ftp-Server","Web-Ftp-Service","Web-Ftp-Ext")
    foreach ($f in $features) {
        if (!(Get-WindowsFeature $f).Installed) {
            Install-WindowsFeature $f -IncludeManagementTools
        }
    }

    $w3 = Get-Service -Name W3SVC -ErrorAction SilentlyContinue
    if ($w3) { Start-Service W3SVC -ErrorAction SilentlyContinue }

    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Set-Service ftpsvc -StartupType Automatic

    Write-Host "FTP instalado."
    Write-Host ""
    Write-Host "IMPORTANTE: Cierre PowerShell y vuelva a abrirlo como Administrador" -ForegroundColor Yellow
    Write-Host "antes de ejecutar la opcion 6 (Configurar FTP)." -ForegroundColor Yellow
    Log "FTP instalado"
}

# ------------------------------------------------------------
# FIREWALL
# ------------------------------------------------------------
function Configurar-Firewall {
    New-NetFirewallRule -DisplayName "FTP 21" -Direction Inbound -Protocol TCP `
        -LocalPort 21 -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "FTP Passive" -Direction Inbound -Protocol TCP `
        -LocalPort 50000-51000 -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Firewall configurado"
    Log "Firewall configurado"
}

# ------------------------------------------------------------
# CREAR GRUPOS
# ------------------------------------------------------------
function Crear-Grupos {
    foreach ($g in @("reprobados","recursadores","ftpusuarios")) {
        if (!(Get-LocalGroup $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup $g | Out-Null
            Write-Host "Grupo $g creado"
        } else {
            Write-Host "Grupo $g ya existe"
        }
    }
    Log "Grupos creados"
}

# ------------------------------------------------------------
# ESTRUCTURA
# ------------------------------------------------------------
function Crear-Estructura {
    New-Item "$ftpRoot"                    -ItemType Directory -Force | Out-Null
    New-Item "$ftpRoot\general"            -ItemType Directory -Force | Out-Null
    New-Item "$ftpRoot\reprobados"         -ItemType Directory -Force | Out-Null
    New-Item "$ftpRoot\recursadores"       -ItemType Directory -Force | Out-Null
    New-Item "$ftpRoot\Data\Usuarios"      -ItemType Directory -Force | Out-Null
    New-Item "$ftpRoot\LocalUser\Public"   -ItemType Directory -Force | Out-Null

    $jPublic = "$ftpRoot\LocalUser\Public\general"
    if (Test-Path $jPublic) { cmd /c "rmdir `"$jPublic`"" | Out-Null }
    cmd /c "mklink /J `"$jPublic`" `"$ftpRoot\general`"" | Out-Null

    Write-Host "Estructura creada"
    Log "Estructura FTP creada"
}

# ------------------------------------------------------------
# PERMISOS
# ------------------------------------------------------------
function Permisos {
    # ROOT
    icacls $ftpRoot /inheritance:r | Out-Null
    icacls $ftpRoot /grant "Administrators:(OI)(CI)F" | Out-Null
    icacls $ftpRoot /grant "SYSTEM:(OI)(CI)F" | Out-Null
    icacls $ftpRoot /grant "IUSR:(OI)(CI)RX" | Out-Null

    # LocalUser (IIS necesita acceder aqui)
    icacls "$ftpRoot\LocalUser" /inheritance:r | Out-Null
    icacls "$ftpRoot\LocalUser" /grant "Administrators:(OI)(CI)F" | Out-Null
    icacls "$ftpRoot\LocalUser" /grant "SYSTEM:(OI)(CI)F" | Out-Null
    icacls "$ftpRoot\LocalUser" /grant "IUSR:(OI)(CI)RX" | Out-Null

    # GENERAL
    icacls "$ftpRoot\general" /inheritance:r | Out-Null
    icacls "$ftpRoot\general" /grant "Administrators:(OI)(CI)F" | Out-Null
    icacls "$ftpRoot\general" /grant "SYSTEM:(OI)(CI)F" | Out-Null
    icacls "$ftpRoot\general" /grant "ftpusuarios:(OI)(CI)M" | Out-Null
    icacls "$ftpRoot\general" /grant "IUSR:(OI)(CI)RX" | Out-Null

    # REPROBADOS
    icacls "$ftpRoot\reprobados" /inheritance:r | Out-Null
    icacls "$ftpRoot\reprobados" /grant "Administrators:(OI)(CI)F" | Out-Null
    icacls "$ftpRoot\reprobados" /grant "SYSTEM:(OI)(CI)F" | Out-Null
    icacls "$ftpRoot\reprobados" /grant "reprobados:(OI)(CI)M" | Out-Null

    # RECURSADORES
    icacls "$ftpRoot\recursadores" /inheritance:r | Out-Null
    icacls "$ftpRoot\recursadores" /grant "Administrators:(OI)(CI)F" | Out-Null
    icacls "$ftpRoot\recursadores" /grant "SYSTEM:(OI)(CI)F" | Out-Null
    icacls "$ftpRoot\recursadores" /grant "recursadores:(OI)(CI)M" | Out-Null

    Write-Host "Permisos aplicados correctamente"
}

# ------------------------------------------------------------
# CONFIGURAR FTP
# Escribe el XML directamente en applicationHost.config
# para evitar el ID aleatorio y el mal formato que genera
# New-WebFtpSite en WS2019
# ------------------------------------------------------------
function Configurar-FTP {
    try {
        Import-Module WebAdministration -ErrorAction Stop
    } catch {
        Write-Host "ERROR: Cierre PowerShell, vuelva a abrirlo como Administrador y ejecute el script de nuevo." -ForegroundColor Red
        return
    }

    Stop-Service ftpsvc -ErrorAction SilentlyContinue
    Stop-Service W3SVC  -ErrorAction SilentlyContinue

    # Eliminar sitio anterior si existe
    if (Get-WebSite $ftpSite -ErrorAction SilentlyContinue) {
        Remove-WebSite $ftpSite
    }

    $configFile = "C:\Windows\System32\inetsrv\config\applicationHost.config"
    $xml = [xml](Get-Content $configFile -Raw)

    # Eliminar sitio FTP anterior del XML si quedaron restos
    $sites = $xml.configuration.'system.applicationHost'.sites
    $oldSite = $sites.site | Where-Object { $_.name -eq $ftpSite }
    if ($oldSite) { $sites.RemoveChild($oldSite) | Out-Null }

    # Eliminar location FTP anterior
    $locations = $xml.configuration.location | Where-Object { $_.path -eq $ftpSite }
    foreach ($loc in $locations) {
        $xml.configuration.RemoveChild($loc) | Out-Null
    }

    # Crear sitio FTP con XML correcto y ID simple (2)
    $newSite = $xml.CreateElement("site")
    $newSite.SetAttribute("name", $ftpSite)
    $newSite.SetAttribute("id", "2")
    $newSite.SetAttribute("serverAutoStart", "true")
    $newSite.InnerXml = @'
<application path="/">
    <virtualDirectory path="/" physicalPath="C:\FTP" />
</application>
<bindings>
    <binding protocol="ftp" bindingInformation="*:21:" />
</bindings>
<ftpServer>
    <userIsolation mode="IsolateRootDirectoryOnly" />
    <security>
        <ssl controlChannelPolicy="SslAllow" dataChannelPolicy="SslAllow" />
        <authentication>
            <anonymousAuthentication enabled="true" />
            <basicAuthentication enabled="true" />
        </authentication>
    </security>
</ftpServer>
'@
    $sites.AppendChild($newSite) | Out-Null

    # Agregar reglas de autorizacion como location
    $locNode = $xml.CreateElement("location")
    $locNode.SetAttribute("path", $ftpSite)
    $locNode.InnerXml = @'
<system.ftpServer>
    <security>
        <authorization>
            <add accessType="Allow" users="?" permissions="Read" />
            <add accessType="Allow" roles="ftpusuarios" permissions="Read, Write" />
        </authorization>
    </security>
</system.ftpServer>
'@
    $xml.configuration.AppendChild($locNode) | Out-Null

    $xml.Save($configFile)

    Start-Service W3SVC  -ErrorAction SilentlyContinue
    Start-Service ftpsvc -ErrorAction SilentlyContinue

    # Verificar
    $modo = Get-ItemProperty "IIS:\Sites\$ftpSite" ftpServer.userIsolation.mode
    Write-Host "FTP configurado. Modo aislamiento: $modo"
    Get-WebSite | Select-Object Name, Id, State | Format-Table -AutoSize
    Log "FTP configurado"
}

# ------------------------------------------------------------
# CREAR USUARIO
# ------------------------------------------------------------
function Crear-Usuario {
    $cantidad = Read-Host "Cuantos usuarios desea crear?"

    for ($i = 1; $i -le [int]$cantidad; $i++) {
        Write-Host ""
        Write-Host "Creando usuario $i de $cantidad"

        $usuario = Read-Host "Usuario"
        $pass    = Read-Host "Contrasena" -AsSecureString
        $grupo   = Read-Host "Grupo (reprobados/recursadores)"

        if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
            Write-Host "Grupo invalido"
            continue
        }

        if (Get-LocalUser $usuario -ErrorAction SilentlyContinue) {
            Write-Host "El usuario ya existe"
            continue
        }

        New-LocalUser $usuario -Password $pass | Out-Null
        Set-LocalUser $usuario -PasswordNeverExpires $true

        Add-LocalGroupMember $grupo        -Member $usuario
        Add-LocalGroupMember "ftpusuarios" -Member $usuario

        # Esperar registro del SID
        Start-Sleep -Seconds 2

        $userHome    = "$ftpRoot\LocalUser\$usuario"
        $userPrivado = "$ftpRoot\Data\Usuarios\$usuario"

        New-Item $userHome    -ItemType Directory -Force | Out-Null
        New-Item $userPrivado -ItemType Directory -Force | Out-Null

        # Junctions
        cmd /c "mklink /J `"$userHome\general`"  `"$ftpRoot\general`""  | Out-Null
        cmd /c "mklink /J `"$userHome\$grupo`"   `"$ftpRoot\$grupo`""   | Out-Null
        cmd /c "mklink /J `"$userHome\$usuario`" `"$userPrivado`""       | Out-Null

        # Permisos home IIS - critico para que IIS encuentre el directorio
        icacls $userHome /inheritance:r | Out-Null
        icacls $userHome /grant "Administrators:(OI)(CI)F" | Out-Null
        icacls $userHome /grant "SYSTEM:(OI)(CI)F" | Out-Null
        icacls $userHome /grant "${usuario}:(OI)(CI)F" | Out-Null
        icacls $userHome /grant "IUSR:(OI)(CI)RX" | Out-Null

        # Permisos carpeta privada
        icacls $userPrivado /inheritance:r | Out-Null
        icacls $userPrivado /grant "Administrators:(OI)(CI)F" | Out-Null
        icacls $userPrivado /grant "SYSTEM:(OI)(CI)F" | Out-Null
        icacls $userPrivado /grant "${usuario}:(OI)(CI)F" | Out-Null

        Write-Host "Usuario $usuario creado correctamente"
        Log "Usuario creado: $usuario grupo: $grupo"
    }

    Restart-Service ftpsvc
    Write-Host "Usuarios creados correctamente"
}

# ------------------------------------------------------------
# ELIMINAR USUARIO
# ------------------------------------------------------------
function Eliminar-Usuario {
    $usuario = Read-Host "Usuario a eliminar"

    if (!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario no existe"
        return
    }

    Remove-LocalUser $usuario

    $userHome = "$ftpRoot\LocalUser\$usuario"
    if (Test-Path $userHome) {
        foreach ($j in @("general","reprobados","recursadores",$usuario)) {
            if (Test-Path "$userHome\$j") { cmd /c "rmdir `"$userHome\$j`"" | Out-Null }
        }
        Remove-Item $userHome -Recurse -Force -ErrorAction SilentlyContinue
    }

    Remove-Item "$ftpRoot\Data\Usuarios\$usuario" -Recurse -Force -ErrorAction SilentlyContinue

    Restart-Service ftpsvc
    Write-Host "Usuario $usuario eliminado"
    Log "Usuario eliminado: $usuario"
}

# ------------------------------------------------------------
# CAMBIAR GRUPO
# ------------------------------------------------------------
function Cambiar-Grupo {
    $usuario = Read-Host "Usuario"
    $grupo   = Read-Host "Nuevo grupo (reprobados/recursadores)"

    if (!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario no existe"
        return
    }

    Remove-LocalGroupMember -Group "reprobados"   -Member $usuario -ErrorAction SilentlyContinue
    Remove-LocalGroupMember -Group "recursadores" -Member $usuario -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $grupo         -Member $usuario

    $userHome = "$ftpRoot\LocalUser\$usuario"
    foreach ($g in @("reprobados","recursadores")) {
        if (Test-Path "$userHome\$g") { cmd /c "rmdir `"$userHome\$g`"" | Out-Null }
    }
    cmd /c "mklink /J `"$userHome\$grupo`" `"$ftpRoot\$grupo`"" | Out-Null

    iisreset /noforce | Out-Null
    Write-Host "Grupo cambiado correctamente"
    Log "Grupo cambiado: $usuario -> $grupo"
}

# ------------------------------------------------------------
# VER USUARIOS
# ------------------------------------------------------------
function Ver-Usuarios {
    Write-Host ""
    Write-Host "Usuarios FTP:"
    Get-LocalGroupMember ftpusuarios -ErrorAction SilentlyContinue | ForEach-Object {
        $u = $_.Name.Split("\")[-1]
        Write-Host "  $u"
    }
}

# ------------------------------------------------------------
# ESTADO
# ------------------------------------------------------------
function Estado {
    Get-Service ftpsvc | Format-Table Name, Status, StartType -AutoSize
    netstat -an | find ":21"
}

# ------------------------------------------------------------
# MENU
# ------------------------------------------------------------
function Menu {
    Import-Module ServerManager -ErrorAction SilentlyContinue
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    while ($true) {
        Write-Host ""
        Write-Host "========= ADMIN FTP =========" -ForegroundColor Cyan
        Write-Host "1  Instalar FTP"
        Write-Host "2  Firewall"
        Write-Host "3  Crear Grupos"
        Write-Host "4  Crear Estructura"
        Write-Host "5  Permisos"
        Write-Host "6  Configurar FTP"
        Write-Host "7  Crear Usuario"
        Write-Host "8  Eliminar Usuario"
        Write-Host "9  Cambiar Grupo"
        Write-Host "10 Ver Usuarios"
        Write-Host "11 Estado Servidor"
        Write-Host "12 Reiniciar FTP"
        Write-Host "0  Salir"

        $op = Read-Host "Opcion"
        switch ($op) {
            "1"  { Instalar-FTP        }
            "2"  { Configurar-Firewall  }
            "3"  { Crear-Grupos        }
            "4"  { Crear-Estructura    }
            "5"  { Permisos            }
            "6"  { Configurar-FTP      }
            "7"  { Crear-Usuario       }
            "8"  { Eliminar-Usuario    }
            "9"  { Cambiar-Grupo       }
            "10" { Ver-Usuarios        }
            "11" { Estado              }
            "12" { Restart-Service ftpsvc; Write-Host "FTP reiniciado" }
            "0"  { exit 0              }
            default { Write-Host "Opcion invalida"; Start-Sleep -Seconds 1 }
        }
    }
}

Menu
