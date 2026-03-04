function Configurar-Firewall {
    # Habilitar puerto 21 para el servicio FTP
    if (-not (Get-NetFirewallRule -DisplayName "FTP Server Port 21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Server Port 21" -Direction Inbound -LocalPort 21 -Protocol TCP -Action Allow
    }

    # Habilitar el rango de puertos pasivos
    if (-not (Get-NetFirewallRule -DisplayName "FTP Passive Port Range" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Passive Port Range" -Direction Inbound -LocalPort 40000-40100 -Protocol TCP -Action Allow
    }

    Write-Host "Firewall configurado para FTP"
}

function Instalar-FTP {

    Write-Host "`nVerificando si IIS + FTP están instalados...`n"

    $features = @(
        "Web-Server",
        "Web-FTP-Server",
        "Web-FTP-Service",
        "Web-FTP-Ext"
    )

    foreach ($feature in $features) {

        $estado = Get-WindowsFeature $feature

        if (-not $estado.Installed) {
            Write-Host "Instalando $feature ..."
            Install-WindowsFeature $feature -IncludeManagementTools
        }
        else {
            Write-Host "$feature ya está instalado."
        }
    }

    Write-Host "`nIniciando servicios..."

    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Set-Service ftpsvc -StartupType Automatic

    Start-Service W3SVC -ErrorAction SilentlyContinue
    Set-Service W3SVC -StartupType Automatic

    Configurar-Firewall

    Write-Host "`nInstalación de IIS + FTP completada."
}

function Configurar-FTP {

    $ftpSiteName = "FTP_Servidor"
    $ftpRoot = "C:\ftp"

    Import-Module WebAdministration

    if (-not (Test-Path $ftpRoot)) {
        New-Item -ItemType Directory -Path $ftpRoot | Out-Null
    }

    if (-not (Get-WebSite -Name $ftpSiteName -ErrorAction SilentlyContinue)) {
        Write-Host "Creando sitio FTP..."
        New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $ftpRoot
        Start-Sleep -Seconds 3
    }

    Write-Host "Configurando aislamiento de usuarios..."
    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName -Filter "system.ftpServer/userIsolation" -Name mode -Value 1
    
    Write-Host "Configurando autenticación..."

    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName -Filter "system.ftpServer/security/authentication/anonymousAuthentication" -Name enabled -Value True

    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName -Filter "system.ftpServer/security/authentication/basicAuthentication" -Name enabled -Value True


    Write-Host "Configurando modo pasivo..."

    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName -Filter "system.ftpServer/firewallSupport" -Name passiveEnabled -Value True

    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName -Filter "system.ftpServer/firewallSupport" -Name dataChannelPortRange -Value "40000-40100"


    Write-Host "Desactivando SSL obligatorio..."

    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName -Filter "system.ftpServer/security/ssl" -Name controlChannelPolicy -Value 0

    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName -Filter "system.ftpServer/security/ssl" -Name dataChannelPolicy -Value 0


    Write-Host "Configurando reglas de acceso..."

    Add-WebConfiguration -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName -Filter "system.ftpServer/security/authorization" -Value @{accessType="Allow";users="anonymous";permissions="Read"} -ErrorAction SilentlyContinue

    Add-WebConfiguration -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName -Filter "system.ftpServer/security/authorization" -Value @{accessType="Allow";roles="ftpusuarios";permissions="Read,Write"} -ErrorAction SilentlyContinue

    Restart-Service ftpsvc

    Write-Host "FTP configurado correctamente."
}

function Crear-Grupos {
    $grupos = @("reprobados", "recursadores", "ftpusuarios")

    foreach ($nombre in $grupos) {
        if (-not (Get-LocalGroup -Name $nombre -ErrorAction SilentlyContinue)) {
            Write-Host "Creando grupo $nombre...."
            New-LocalGroup -Name $nombre
        } else {
            Write-Host "El grupo $nombre ya existe."
        }
    }
}

function Crear-Estructura {
    $raiz = "C:\ftp"
    $subcarpetas = @("general","reprobados","recursadores","LocalUser")

    if (-not (Test-Path $raiz)) {
        New-Item -Path $raiz -ItemType Directory | Out-Null
    }

    foreach ($carpeta in $subcarpetas) {
        $path = Join-Path -Path $raiz -ChildPath $carpeta
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory | Out-Null
        }
    }
    
    Write-Host "Estructura base creada en $raiz"
}

function Asignar-Permisos {
    
    $raiz = "C:\ftp"
    icacls "$raiz" /inheritance:r /grant:r "Administrators:(OI)(CI)F" /grant:r "SYSTEM:(OI)(CI)F" /grant:r "Users:(OI)(CI)R"
    
    $grupos = @{ "reprobados" = "reprobados"; "recursadores" = "recursadores" }

    foreach ($nombre in $grupos.Keys) {
        $path = "$raiz\$nombre"
        $g = $grupos[$nombre]
        icacls "$path" /inheritance:r /grant:r "Administrators:(OI)(CI)F" /grant:r "SYSTEM:(OI)(CI)F" /grant:r "${g}:(OI)(CI)M"
    }
    icacls "$raiz\general" /inheritance:r /grant:r "Administrators:(OI)(CI)F" /grant:r "SYSTEM:(OI)(CI)F" /grant:r "ftpusuarios:(OI)(CI)M"

    # 3. Permisos para carpeta general: ftpusuarios con permisos de modificación (M)
    icacls "$raiz\general" /inheritance:r /grant:r "Administrators:(OI)(CI)F" /grant:r "SYSTEM:(OI)(CI)F" /grant:r "ftpusuarios:(OI)(CI)M"

    Write-Host "Permisos NTFS aplicados correctamente."
}

function Crear-Usuarios {
    $num = Read-Host "Ingrese el número de usuarios a crear"
    for ($i = 1; $i -le $num; $i++) {
        Write-Host "`nUsuario $i"
        $nombre = Read-Host "Nombre de usuario"
        
        # Verificar si existe
        if (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue) {
            Write-Host "El usuario ya existe."
            continue
        }

        $pass = Read-Host -AsSecureString "Contraseña"
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
            Write-Host "Grupo inválido."
            continue
        }

        # 1. Crear el usuario
        New-LocalUser -Name $nombre -Password $pass -FullName $nombre -Description "Usuario FTP"
        Add-LocalGroupMember -Group $grupo -Member $nombre
        Add-LocalGroupMember -Group "ftpusuarios" -Member $nombre

        # 2. Crear carpeta personal y aplicar ACLs
        $userPath = "C:\ftp\LocalUser\$nombre"
        New-Item -Path $userPath -ItemType Directory | Out-Null
        
        # Permisos: Solo el dueño (usuario) tiene acceso total
        icacls $userPath /inheritance:r /grant:r "${nombre}:(OI)(CI)F" /grant:r "Administrators:(OI)(CI)F"
        
        Write-Host "Usuario $nombre creado y carpeta personal configurada."
    }
}

function Cambiar-Grupo-Usuario {
    Write-Host "`n***** Cambiar de grupo a usuario *****"
    $nombre = Read-Host "Ingrese el nombre del usuario"
    
    # 1. Verificar si el usuario existe
    $usuario = Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue
    if (-not $usuario) {
        Write-Host "El usuario no existe."
        return
    }

    $nuevo_grupo = Read-Host "Ingrese el nuevo grupo del usuario (reprobados/recursadores)"
    if ($nuevo_grupo -ne "reprobados" -and $nuevo_grupo -ne "recursadores") {
        Write-Host "Grupo inválido."
        return
    }

    # 2. Identificar y remover del grupo anterior (reprobados o recursadores)
    $grupos = @("reprobados", "recursadores")
    foreach ($g in $grupos) {
        if (Get-LocalGroupMember -Group $g | Where-Object { $_.Name -eq $nombre }) {
            Remove-LocalGroupMember -Group $g -Member $nombre -Confirm:$false
        }
    }

    # 3. Añadir al nuevo grupo
    Add-LocalGroupMember -Group $nuevo_grupo -Member $nombre

    # 4. Actualizar permisos de la carpeta personal (NTFS)
    # Otorgamos acceso al nuevo grupo a la carpeta del usuario
    $userPath = "C:\ftp\LocalUser\$nombre"
    icacls $userPath /grant:r "${nuevo_grupo}:(OI)(CI)M"

    Write-Host "Grupo del usuario $nombre actualizado a $nuevo_grupo y permisos ajustados."
}

function Configurar-Seguridad {
    # SELinux no existe en Windows. 
    # Esta función verifica que las reglas de autorización estén activas en IIS.
    $ftpSiteName = "FTP_Servidor"
    
    # Comprobar si existen reglas de autorización configuradas
    $rules = Get-WebConfiguration -Filter "/system.ftpServer/security/authorization/*" -PSPath "IIS:\Sites\$ftpSiteName"
    
    if ($rules) {
        Write-Host "Seguridad FTP (Reglas de autorización) verificada correctamente."
    } else {
        Write-Host "Advertencia: No se detectaron reglas de seguridad en el sitio FTP."
    }
}

function Mostrar-Menu {
    while ($true) {
        Write-Host "`n***** Menú FTP (Windows Server) *****"
        Write-Host "1) Instalar servicio FTP"
        Write-Host "2) Configurar FTP"
        Write-Host "3) Crear grupos"
        Write-Host "4) Crear estructura base"
        Write-Host "5) Asignar permisos base"
        Write-Host "6) Crear usuarios"
        Write-Host "7) Cambiar grupo usuario"
        Write-Host "0) Salir"
        
        $opcion = Read-Host "Seleccione una opción"
        
        switch ($opcion) {
            "1" { Instalar-FTP }
            "2" { Configurar-FTP }
            "3" { Crear-Grupos }
            "4" { Crear-Estructura }
            "5" { Asignar-Permisos }
            "6" { Crear-Usuarios }
            "7" { Cambiar-Grupo-Usuario }
            "0" { break }
            Default { Write-Host "Opción inválida..."; Start-Sleep -Seconds 1 }
        }
    }
}

# Iniciar el menú
Mostrar-Menu
