function Configurar-Firewall {
    if (-not (Get-NetFirewallRule -DisplayName "FTP Server Port 21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Server Port 21" -Direction Inbound -LocalPort 21 -Protocol TCP -Action Allow
    }
    if (-not (Get-NetFirewallRule -DisplayName "FTP Passive Port Range" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Passive Port Range" -Direction Inbound -LocalPort 40000-40100 -Protocol TCP -Action Allow
    }
    Write-Host "Firewall configurado para FTP"
}

function Instalar-FTP {
    Write-Host "`nVerificando si IIS + FTP están instalados...`n"

    $features = @("Web-Server","Web-FTP-Server","Web-FTP-Service","Web-FTP-Ext")

    foreach ($feature in $features) {
        $estado = Get-WindowsFeature $feature
        if (-not $estado.Installed) {
            Write-Host "Instalando $feature ..."
            Install-WindowsFeature $feature -IncludeManagementTools
        } else {
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
    Import-Module WebAdministration

    $ftpSiteName = "FTP_Servidor"
    $ftpRoot = "C:\ftp"

    if (-not (Test-Path $ftpRoot)) {
        New-Item -Path $ftpRoot -ItemType Directory | Out-Null
    }

    if (Get-WebSite -Name $ftpSiteName -ErrorAction SilentlyContinue) {
        Remove-WebSite $ftpSiteName
    }

    Write-Host "Creando sitio FTP..."
    New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $ftpRoot -Force

    Write-Host "Configurando autenticación..."
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.userName -Value "IUSR"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    Write-Host "Configurando aislamiento de usuarios..."
    # Modo 3 = IsolateRootDirectoryOnly
    # Cada usuario cae en C:\ftp\LocalUser\<nombre>
    # El anonimo cae en C:\ftp\LocalUser\Public
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.userIsolation.mode -Value 3

    Write-Host "Configurando puertos pasivos..."
    C:\Windows\System32\inetsrv\appcmd.exe set config -section:system.ftpServer/firewallSupport /lowDataChannelPort:40000 /highDataChannelPort:40100 /commit:apphost

    Write-Host "Desactivando SSL obligatorio..."
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

    Write-Host "Configurando reglas de acceso..."
    Clear-WebConfiguration -Filter "system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $ftpSiteName
    Clear-WebConfiguration -Filter "system.ftpServer/security/authorization" -PSPath "IIS:\" -Location "$ftpSiteName/"

    # Usuarios autenticados del grupo ftpusuarios: lectura+escritura
    Add-WebConfiguration -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\" -Location $ftpSiteName `
        -Value @{accessType="Allow"; roles="ftpusuarios"; permissions="Read,Write"}

    # Anonimo: solo lectura (ve unicamente lo que hay en su home = virtual a /general)
    Add-WebConfiguration -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\" -Location $ftpSiteName `
        -Value @{accessType="Allow"; users="?"; permissions="Read"}

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
    $subcarpetas = @("general","reprobados","recursadores")

    if (-not (Test-Path $raiz)) {
        New-Item -Path $raiz -ItemType Directory | Out-Null
    }

    foreach ($carpeta in $subcarpetas) {
        $path = Join-Path $raiz $carpeta
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory | Out-Null
        }
    }

    # Home del anonimo en modo 3 = C:\ftp\Public
    $anonHome = "$raiz\LocalUser\Public"
    if (-not (Test-Path $anonHome)) {
        New-Item -Path $anonHome -ItemType Directory -Force | Out-Null
    }

    # Junction de general dentro del home anonimo
    $jGeneral = "$anonHome\general"
    if (-not (Test-Path $jGeneral)) {
        cmd /c "mklink /J `"$jGeneral`" `"$raiz\general`"" | Out-Null
    }

    Write-Host "Estructura base creada en $raiz"
}

function Asignar-Permisos {
    Import-Module WebAdministration

    $raiz = "C:\ftp"
    $ftpSiteName = "FTP_Servidor"

    # Permisos generales en la raiz
    icacls "$raiz" /grant:r "Administrators:(OI)(CI)F"
    icacls "$raiz" /grant:r "SYSTEM:(OI)(CI)F"
    icacls "$raiz" /grant "IUSR:(RX)"
    icacls "$raiz" /grant "IIS_IUSRS:(RX)"

    # Carpeta general: todos los ftpusuarios escriben, IUSR solo lee
    icacls "$raiz\general" /inheritance:r `
        /grant:r "Administrators:(OI)(CI)F" `
        /grant:r "SYSTEM:(OI)(CI)F" `
        /grant:r "ftpusuarios:(OI)(CI)M" `
        /grant:r "IUSR:(OI)(CI)RX" `
        /grant:r "IIS_IUSRS:(OI)(CI)RX"

    # Carpetas de grupo: solo el grupo correspondiente
    foreach ($g in @("reprobados","recursadores")) {
        icacls "$raiz\$g" /inheritance:r `
            /grant:r "Administrators:(OI)(CI)F" `
            /grant:r "SYSTEM:(OI)(CI)F" `
            /grant:r "${g}:(OI)(CI)M"
    }

    icacls "$raiz\LocalUser" /grant:r "IUSR:(OI)(CI)RX"
    icacls "$raiz\LocalUser" /grant:r "IIS_IUSRS:(OI)(CI)RX"
    icacls "$raiz\LocalUser" /grant:r "Administrators:(OI)(CI)F"
    icacls "$raiz\LocalUser" /grant:r "SYSTEM:(OI)(CI)F"

    icacls "$raiz\LocalUser\Public" /inheritance:r `
        /grant:r "Administrators:(OI)(CI)F" `
        /grant:r "SYSTEM:(OI)(CI)F" `
        /grant:r "IUSR:(OI)(CI)RX" `
        /grant:r "IIS_IUSRS:(OI)(CI)RX"

    # Directorio virtual en home anonimo que apunta a /general (solo lectura anonima)
    # Primero limpiar si existe
    if (Get-WebVirtualDirectory -Site $ftpSiteName -Application "/" -Name "general" -ErrorAction SilentlyContinue) {
        Remove-WebVirtualDirectory -Site $ftpSiteName -Application "/" -Name "general"
    }
    New-WebVirtualDirectory -Site $ftpSiteName -Application "/" -Name "general" -PhysicalPath "$raiz\general" | Out-Null

    Write-Host "Permisos NTFS aplicados correctamente."
}

function Agregar-VirtualDirs-Usuario {
    param(
        [string]$nombre,
        [string]$grupo
    )
    Import-Module WebAdministration

    $raiz = "C:\ftp"
    $ftpSiteName = "FTP_Servidor"

    # En Windows Server 2019 modo 3, el home es C:\ftp\<nombre>
    # CORRECTO para cuentas locales en modo 3
    $userHome = "$raiz\LocalUser\$nombre"

    if (-not (Test-Path $userHome)) {
        New-Item -Path $userHome -ItemType Directory -Force | Out-Null
    }

    # Permisos en carpeta home del usuario
    icacls $userHome /inheritance:r `
        /grant:r "${nombre}:(OI)(CI)M" `
        /grant:r "Administrators:(OI)(CI)F" `
        /grant:r "SYSTEM:(OI)(CI)F" `
        /grant:r "IUSR:(OI)(CI)RX" `
        /grant:r "IIS_IUSRS:(OI)(CI)RX"
    # Eliminar WebApplication mal creada si existe
    if (Get-WebApplication -Site $ftpSiteName -Name $nombre -ErrorAction SilentlyContinue) {
        Remove-WebApplication -Site $ftpSiteName -Name $nombre
    }

    # Limpiar virtual dirs previos del usuario colgados de la raiz "/"
    foreach ($vd in @("general_$nombre", "${nombre}_personal", "grupo_$nombre")) {
        if (Get-WebVirtualDirectory -Site $ftpSiteName -Application "/" -Name $vd -ErrorAction SilentlyContinue) {
            Remove-WebVirtualDirectory -Site $ftpSiteName -Application "/" -Name $vd
        }
    }

    # Los virtual dirs van DENTRO del home del usuario en IIS
    # Se crean bajo la aplicacion raiz "/" pero apuntando a subcarpetas de $userHome
    # Para modo 3: IIS sirve C:\ftp\<nombre> como raiz, los subdirectorios son virtualdirs

    # Crear junction points (symlinks de carpetas) dentro del home del usuario
    # Esto es mas confiable que virtual dirs en modo 3

    # Carpeta general dentro del home (junction a C:\ftp\general)
    $jGeneral = "$userHome\general"
    if (-not (Test-Path $jGeneral)) {
        cmd /c "mklink /J `"$jGeneral`" `"$raiz\general`"" | Out-Null
    }

    # Carpeta personal dentro del home (carpeta real)
    $jPersonal = "$userHome\$nombre"
    if (-not (Test-Path $jPersonal)) {
        New-Item -Path $jPersonal -ItemType Directory -Force | Out-Null
        icacls $jPersonal /inheritance:r `
            /grant:r "${nombre}:(OI)(CI)M" `
            /grant:r "Administrators:(OI)(CI)F" `
            /grant:r "SYSTEM:(OI)(CI)F"
    }

    # Carpeta de grupo dentro del home (junction a C:\ftp\<grupo>)
    $jGrupo = "$userHome\$grupo"
    if (-not (Test-Path $jGrupo)) {
        cmd /c "mklink /J `"$jGrupo`" `"$raiz\$grupo`"" | Out-Null
    }

    Write-Host "Estructura de $nombre creada: home=$userHome, general, $nombre, $grupo"
}

function Crear-Usuarios {
    $num = Read-Host "Ingrese el número de usuarios a crear"
    for ($i = 1; $i -le $num; $i++) {
        Write-Host "`nUsuario $i"
        $nombre = Read-Host "Nombre de usuario"

        if (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue) {
            Write-Host "El usuario ya existe."
            continue
        }

        $pass  = Read-Host -AsSecureString "Contraseña"
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
            Write-Host "Grupo inválido."
            continue
        }

        New-LocalUser -Name $nombre -Password $pass -FullName $nombre -Description "Usuario FTP"
        Add-LocalGroupMember -Group $grupo       -Member $nombre
        Add-LocalGroupMember -Group "ftpusuarios" -Member $nombre

        Agregar-VirtualDirs-Usuario -nombre $nombre -grupo $grupo

        Write-Host "Usuario $nombre creado correctamente."
    }
}

function Cambiar-Grupo-Usuario {
    Write-Host "`n***** Cambiar de grupo a usuario *****"
    $nombre = Read-Host "Ingrese el nombre del usuario"

    if (-not (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario no existe."
        return
    }

    $nuevo_grupo = Read-Host "Ingrese el nuevo grupo (reprobados/recursadores)"

    if ($nuevo_grupo -ne "reprobados" -and $nuevo_grupo -ne "recursadores") {
        Write-Host "Grupo inválido."
        return
    }

    # Quitar de todos los grupos de clase
    foreach ($g in @("reprobados","recursadores")) {
        if (Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$nombre" }) {
            Remove-LocalGroupMember -Group $g -Member $nombre -Confirm:$false
        }
    }

    # Agregar al nuevo grupo
    Add-LocalGroupMember -Group $nuevo_grupo -Member $nombre

    # Recrear directorios virtuales apuntando al nuevo grupo
    Agregar-VirtualDirs-Usuario -nombre $nombre -grupo $nuevo_grupo

    Restart-Service ftpsvc -Force
    Write-Host "Grupo del usuario $nombre actualizado a $nuevo_grupo correctamente."
}

function Configurar-Seguridad {
    $ftpSiteName = "FTP_Servidor"
    $rules = Get-WebConfiguration -Filter "/system.ftpServer/security/authorization/*" -PSPath "IIS:\Sites\$ftpSiteName"
    if ($rules) {
        Write-Host "Seguridad FTP verificada correctamente."
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

Mostrar-Menu
