# ============================================================
#  perfiles_moviles_p8.ps1 - VERSION LIMPIA SIN REDUNDANCIAS
#  Perfiles Moviles (Roaming Profiles) - Practica 08
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
#
#  IMPORTANTE: Este script hace dot-source de funciones_p8.ps1
#  que ya define:
#    - $script:CARPETA_PERFILES, $script:SHARE_NAME, etc.
#    - $script:CARPETA_USUARIOS, $script:UNC_USUARIOS
#    - Build-LogonHours, Get-TamanoMB, Crear-PlantillasFSRM
#    - Ver-PerfilesAlmacenados (corregida, mide ambas carpetas)
#
#  Este script SOLO agrega las funciones propias de su menu:
#    Configurar-CarpetaPerfiles, Asignar-PerfilesUsuarios,
#    Verificar-Perfiles, Configurar-RedireccionCarpetas,
#    Verificar-FSRM, Crear-CarpetasUsuariosConFSRM
# ============================================================

. "$PSScriptRoot\funciones_p8.ps1"

# Las variables $CARPETA, $SHARE_NAME, $SHARE_UNC, etc.
# se leen de $script:* definidas en funciones_p8.ps1
# para no tener dos definiciones del mismo valor.
$CSV_PATH = "$PSScriptRoot\usuarios.csv"

# ============================================================
# HELPER: Crear C:\Usuarios con cuotas y apantallamiento FSRM
# Llama a Crear-PlantillasFSRM de funciones_p8.ps1 (sin duplicar).
# ============================================================
function Crear-CarpetasUsuariosConFSRM {
    param([array]$Usuarios)

    Write-Host "  [AUTO] Creando $($script:CARPETA_USUARIOS) con cuotas y apantallamiento..." -ForegroundColor Cyan

    if (-not (Test-Path $script:CARPETA_USUARIOS)) {
        New-Item -Path $script:CARPETA_USUARIOS -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $($script:CARPETA_USUARIOS)" -ForegroundColor Green
    }

    $shareExiste = Get-SmbShare -Name "Usuarios" -ErrorAction SilentlyContinue
    if (-not $shareExiste) {
        try {
            New-SmbShare -Name "Usuarios" -Path $script:CARPETA_USUARIOS `
                -FullAccess  "PRACTICA8\Domain Admins" `
                -ChangeAccess "PRACTICA8\Domain Users" | Out-Null
            Write-Host "  [OK] Compartido como $($script:UNC_USUARIOS)" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Share Usuarios: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [OK] Share 'Usuarios' ya existe." -ForegroundColor Yellow
    }

    try {
        $acl   = Get-Acl $script:CARPETA_USUARIOS
        $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Users", "Modify",
            "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($regla)
        Set-Acl $script:CARPETA_USUARIOS $acl
        Write-Host "  [OK] Permisos NTFS configurados." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Permisos: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Usa la funcion global de funciones_p8.ps1, sin duplicar el codigo
    Crear-PlantillasFSRM

    foreach ($u in $Usuarios) {
        $carpetaU = "$($script:CARPETA_USUARIOS)\$($u.Usuario)"
        if (-not (Test-Path $carpetaU)) {
            New-Item -Path $carpetaU -ItemType Directory | Out-Null
        }

        # Cuota
        try {
            $plantillaN = if ($u.Departamento -eq "Cuates") { "Practica8-Cuates-10MB" } else { "Practica8-NoCuates-5MB" }
            $tamanoB    = if ($u.Departamento -eq "Cuates") { 10MB } else { 5MB }

            $existeP = Get-FsrmQuotaTemplate -Name $plantillaN -ErrorAction SilentlyContinue
            $existeC = Get-FsrmQuota -Path $carpetaU -ErrorAction SilentlyContinue

            if ($existeC) {
                if ($existeP) { Set-FsrmQuota -Path $carpetaU -Template $plantillaN | Out-Null }
                else          { Set-FsrmQuota -Path $carpetaU -Size $tamanoB -SoftLimit:$false | Out-Null }
            } else {
                if ($existeP) { New-FsrmQuota -Path $carpetaU -Template $plantillaN | Out-Null }
                else          { New-FsrmQuota -Path $carpetaU -Size $tamanoB -SoftLimit:$false | Out-Null }
            }
            Write-Host "  [OK] $($u.Usuario) ($($u.Departamento)) -> cuota aplicada." -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Cuota $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Apantallamiento
        try {
            $existeS = Get-FsrmFileScreen -Path $carpetaU -ErrorAction SilentlyContinue
            if ($existeS) {
                Set-FsrmFileScreen -Path $carpetaU -Template "Practica8-Apantallamiento" | Out-Null
            } else {
                New-FsrmFileScreen -Path $carpetaU -Template "Practica8-Apantallamiento" | Out-Null
            }
            Write-Host "  [OK] $($u.Usuario) -> apantallamiento aplicado." -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Screen $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host "  [AUTO] $($script:CARPETA_USUARIOS) listo." -ForegroundColor Cyan
}


# ============================================================
# MENU
# ============================================================
function Mostrar-Menu {
    do {
        Write-Host "`n  +============================================+" -ForegroundColor Cyan
        Write-Host "  |   PERFILES MOVILES - PRACTICA 08           |" -ForegroundColor Cyan
        Write-Host "  |   practica8.local | 192.168.1.202          |" -ForegroundColor Cyan
        Write-Host "  +============================================+" -ForegroundColor Cyan
        Write-Host "  |  1. Configurar carpeta compartida          |" -ForegroundColor White
        Write-Host "  |  2. Asignar perfiles a usuarios del CSV    |" -ForegroundColor White
        Write-Host "  |  3. Verificar configuracion                |" -ForegroundColor White
        Write-Host "  |  4. Ver perfiles almacenados               |" -ForegroundColor White
        Write-Host "  |  5. Configurar redireccion de carpetas     |" -ForegroundColor Cyan
        Write-Host "  |     (Escritorio/Documentos -> servidor)    |" -ForegroundColor DarkCyan
        Write-Host "  |  6. Verificar que FSRM funciona            |" -ForegroundColor White
        Write-Host "  |  0. Salir                                  |" -ForegroundColor Red
        Write-Host "  +============================================+`n" -ForegroundColor Cyan
        $op = Read-Host "  Selecciona"
        switch ($op) {
            '1' { Configurar-CarpetaPerfiles }
            '2' { Asignar-PerfilesUsuarios }
            '3' { Verificar-Perfiles }
            '4' { Ver-PerfilesAlmacenados }    # Funcion de funciones_p8.ps1 (corregida)
            '5' { Configurar-RedireccionCarpetas }
            '6' { Verificar-FSRM }
            '0' { Write-Host "`n  Saliendo.`n" -ForegroundColor Green }
            default { Write-Host "  Opcion invalida." -ForegroundColor Red }
        }
    } while ($op -ne '0')
}


# ============================================================
# FUNCION 1: Crear y compartir carpeta de perfiles moviles
# ============================================================
function Configurar-CarpetaPerfiles {
    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR CARPETA DE PERFILES MOVILES   |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    if (-not (Test-Path $script:CARPETA_PERFILES)) {
        New-Item -Path $script:CARPETA_PERFILES -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $($script:CARPETA_PERFILES)" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Carpeta ya existe: $($script:CARPETA_PERFILES)" -ForegroundColor Yellow
    }

    Write-Host "  Configurando permisos NTFS..." -ForegroundColor Yellow
    try {
        $acl = Get-Acl $script:CARPETA_PERFILES
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Admins","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "CREATOR OWNER","FullControl","ContainerInherit,ObjectInherit","InheritOnly","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Users","ReadAndExecute, CreateDirectories","None","None","Allow")))
        Set-Acl $script:CARPETA_PERFILES $acl
        Write-Host "  [OK] Permisos NTFS configurados." -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Permisos NTFS: $($_.Exception.Message)" -ForegroundColor Red
    }

    $shareExiste = Get-SmbShare -Name $script:SHARE_NAME -ErrorAction SilentlyContinue
    if ($shareExiste) {
        Remove-SmbShare -Name $script:SHARE_NAME -Force -ErrorAction SilentlyContinue
        Write-Host "  [INFO] Share anterior eliminado." -ForegroundColor DarkGray
    }
    try {
        New-SmbShare -Name $script:SHARE_NAME -Path $script:CARPETA_PERFILES `
            -FullAccess "Everyone" -Description "Perfiles Moviles - Practica 08" | Out-Null
        Write-Host "  [OK] Compartido como: $($script:SHARE_UNC)" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Share: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "  Configurando GPO de perfiles moviles..." -ForegroundColor Yellow
    try {
        $dcBase    = (Get-ADDomain).DistinguishedName
        $gpoNombre = "Practica8-PerfilesMoviles"
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Host "  [CREADO] GPO '$gpoNombre'." -ForegroundColor Green
        } else {
            Write-Host "  [OK] GPO ya existe." -ForegroundColor Yellow
        }
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
            -ValueName "CompatibleRUPSecurity" -Type DWord -Value 1 | Out-Null
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "SlowLinkDefaultProfile" -Type DWord -Value 1 | Out-Null
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "SlowLinkTimeOut" -Type DWord -Value 0 | Out-Null
        try {
            New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop | Out-Null
            Write-Host "  [OK] GPO vinculada." -ForegroundColor Green
        } catch {
            Write-Host "  [OK] GPO ya vinculada." -ForegroundColor Yellow
        }
        gpupdate /force 2>&1 | Out-Null
        Write-Host "  [OK] GPO aplicada." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] GPO: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "`n  Carpeta de perfiles: $($script:CARPETA_PERFILES)" -ForegroundColor Green
    Write-Host "  Ruta de red        : $($script:SHARE_UNC)" -ForegroundColor Green
    Write-Host "`n  Siguiente paso: Opcion 2 -> Opcion 5" -ForegroundColor Cyan
    Write-Host "`n  Presiona Enter..." ; Read-Host | Out-Null
}


# ============================================================
# FUNCION 2: Asignar perfil movil a cada usuario del CSV
# ============================================================
function Asignar-PerfilesUsuarios {
    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   ASIGNAR PERFILES MOVILES A USUARIOS      |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    if (-not (Test-Path $CSV_PATH)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv" -ForegroundColor Red ; return
    }
    if (-not (Test-Path $script:CARPETA_PERFILES)) {
        Write-Host "  [ERROR] Ejecuta primero la Opcion 1." -ForegroundColor Red ; return
    }

    $usuarios = Import-Csv -Path $CSV_PATH
    $ok = 0; $errores = 0

    foreach ($u in $usuarios) {
        try {
            $rutaPerfil = "$($script:SHARE_UNC)\$($u.Usuario)"
            Set-ADUser -Identity $u.Usuario -ProfilePath $rutaPerfil -ErrorAction Stop
            Write-Host "  [OK] $($u.Usuario) -> $rutaPerfil" -ForegroundColor Green
            $ok++
        } catch {
            Write-Host "  [ERROR] $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Red
            $errores++
        }
    }

    Write-Host "`n  Admins Practica 09 (si existen)..." -ForegroundColor Yellow
    foreach ($a in @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")) {
        try {
            Get-ADUser $a -ErrorAction Stop | Out-Null
            Set-ADUser -Identity $a -ProfilePath "$($script:SHARE_UNC)\$a" -ErrorAction Stop
            Write-Host "  [OK] $a" -ForegroundColor Green ; $ok++
        } catch {}
    }

    Write-Host "`n  Perfiles asignados: $ok | Errores: $errores" -ForegroundColor Cyan
    Write-Host "`n  AHORA ejecuta la Opcion 5 para redireccion de carpetas." -ForegroundColor Yellow
    Write-Host "`n  Presiona Enter..." ; Read-Host | Out-Null
}


# ============================================================
# FUNCION 3: Verificar configuracion
# ============================================================
function Verificar-Perfiles {
    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   VERIFICAR PERFILES MOVILES               |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    Write-Host "  [1/4] Carpeta perfiles:" -ForegroundColor Yellow
    if (Test-Path $script:CARPETA_PERFILES) {
        Write-Host "  [PASS] $($script:CARPETA_PERFILES) existe." -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] No existe. Ejecuta Opcion 1." -ForegroundColor Red
    }

    Write-Host "`n  [2/4] Share '$($script:SHARE_NAME)':" -ForegroundColor Yellow
    $share = Get-SmbShare -Name $script:SHARE_NAME -ErrorAction SilentlyContinue
    if ($share) {
        Write-Host "  [PASS] Share activo en: $($share.Path)" -ForegroundColor Green
        Get-SmbShareAccess -Name $script:SHARE_NAME | ForEach-Object {
            Write-Host "         $($_.AccountName): $($_.AccessRight)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [FAIL] No existe. Ejecuta Opcion 1." -ForegroundColor Red
    }

    Write-Host "`n  [3/4] ProfilePath en AD:" -ForegroundColor Yellow
    if (Test-Path $CSV_PATH) {
        Import-Csv $CSV_PATH | ForEach-Object {
            try {
                $adUser = Get-ADUser $_.Usuario -Properties ProfilePath -ErrorAction Stop
                if ($adUser.ProfilePath) {
                    Write-Host "  [OK] $($_.Usuario) -> $($adUser.ProfilePath)" -ForegroundColor Green
                } else {
                    Write-Host "  [WARN] $($_.Usuario) sin ProfilePath" -ForegroundColor Yellow
                }
            } catch { Write-Host "  [WARN] $($_.Usuario) no encontrado" -ForegroundColor Yellow }
        }
    }

    Write-Host "`n  [4/4] FSRM en $($script:CARPETA_USUARIOS):" -ForegroundColor Yellow
    if (Test-Path $script:CARPETA_USUARIOS) {
        $subcarpetas = Get-ChildItem $script:CARPETA_USUARIOS -ErrorAction SilentlyContinue
        Write-Host "  [OK] Existe. Subcarpetas: $($subcarpetas.Count)" -ForegroundColor Green
        foreach ($c in $subcarpetas) {
            $cuota  = Get-FsrmQuota -Path $c.FullName -ErrorAction SilentlyContinue
            $screen = Get-FsrmFileScreen -Path $c.FullName -ErrorAction SilentlyContinue
            $ci = if ($cuota)  { "Cuota $([math]::Round($cuota.Size/1MB))MB OK" } else { "SIN CUOTA" }
            $si = if ($screen) { "Screen OK" } else { "SIN SCREEN" }
            Write-Host "    $($c.Name) -> $ci | $si" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  [WARN] $($script:CARPETA_USUARIOS) no existe. Se creara en Opcion 5." -ForegroundColor Yellow
    }

    Write-Host "`n  >>> CAPTURA ESTA PANTALLA como evidencia <<<" -ForegroundColor Magenta
    Write-Host "`n  Presiona Enter..." ; Read-Host | Out-Null
}


# ============================================================
# FUNCION 5: Configurar Redireccion de Carpetas
# ============================================================
function Configurar-RedireccionCarpetas {

    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   REDIRECCION DE CARPETAS (FOLDER REDIR)   |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    Write-Host "  QUE HACE ESTO:" -ForegroundColor White
    Write-Host "  Escritorio del cliente -> $($script:UNC_USUARIOS)\<usuario>\Desktop" -ForegroundColor Cyan
    Write-Host "  Documentos del cliente -> $($script:UNC_USUARIOS)\<usuario>\Documents" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  RESULTADO:" -ForegroundColor White
    Write-Host "  Guardar .mp3 en Escritorio  -> BLOQUEADO por FSRM" -ForegroundColor Yellow
    Write-Host "  Superar cuota (5MB o 10MB)  -> BLOQUEADO por FSRM" -ForegroundColor Yellow
    Write-Host ""

    try { $dominio = Get-ADDomain -ErrorAction Stop }
    catch { Write-Host "  [ERROR] AD no disponible." -ForegroundColor Red ; return }

    if (-not (Test-Path $CSV_PATH)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv" -ForegroundColor Red ; return
    }

    $usuarios = Import-Csv $CSV_PATH

    if (-not (Test-Path $script:CARPETA_USUARIOS)) {
        Write-Host "  [INFO] $($script:CARPETA_USUARIOS) no existe. Creando automaticamente..." -ForegroundColor Yellow
        Crear-CarpetasUsuariosConFSRM -Usuarios $usuarios
        Write-Host ""
    } else {
        Write-Host "  [OK] $($script:CARPETA_USUARIOS) ya existe." -ForegroundColor Green
    }

    $confirmar = Read-Host "  Continuar con la redireccion? (s/n)"
    if ($confirmar -ne 's') { return }

    Write-Host ""
    $dcBase = $dominio.DistinguishedName

    # PASO A: Crear subcarpetas Desktop y Documents
    Write-Host "  [A] Creando subcarpetas Desktop y Documents..." -ForegroundColor Yellow
    foreach ($u in $usuarios) {
        $carpetaU = "$($script:CARPETA_USUARIOS)\$($u.Usuario)"
        if (-not (Test-Path $carpetaU)) { New-Item -Path $carpetaU -ItemType Directory | Out-Null }
        foreach ($sub in @("Desktop", "Documents")) {
            $subPath = "$carpetaU\$sub"
            if (-not (Test-Path $subPath)) {
                New-Item -Path $subPath -ItemType Directory | Out-Null
                Write-Host "  [OK] Creada: $($u.Usuario)\$sub" -ForegroundColor Green
            } else {
                Write-Host "  [OK] Ya existe: $($u.Usuario)\$sub" -ForegroundColor DarkGray
            }
        }
    }

    # PASO B: Verificar permisos NTFS
    Write-Host "`n  [B] Verificando permisos NTFS en $($script:CARPETA_USUARIOS)..." -ForegroundColor Yellow
    try {
        $acl = Get-Acl $script:CARPETA_USUARIOS
        $tieneModify = $acl.Access | Where-Object {
            $_.IdentityReference -like "*Domain Users*" -and
            $_.FileSystemRights -match "Modify|FullControl"
        }
        if (-not $tieneModify) {
            $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "PRACTICA8\Domain Users","Modify",
                "ContainerInherit,ObjectInherit","None","Allow"
            )
            $acl.AddAccessRule($regla)
            Set-Acl $script:CARPETA_USUARIOS $acl
            Write-Host "  [OK] Permisos Modify agregados." -ForegroundColor Green
        } else {
            Write-Host "  [OK] Domain Users ya tiene permisos correctos." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Permisos: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # PASO C: GPO de redireccion de carpetas
    Write-Host "`n  [C] Configurando GPO de redireccion..." -ForegroundColor Yellow
    $gpoNombre = "Practica8-RedireccionCarpetas"
    try {
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Host "  [CREADO] GPO '$gpoNombre'." -ForegroundColor Green
        } else {
            Write-Host "  [OK] GPO ya existe, actualizando." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [ERROR] GPO: $($_.Exception.Message)" -ForegroundColor Red ; return
    }

    $rutaDesktop   = "$($script:UNC_USUARIOS)\%USERNAME%\Desktop"
    $rutaDocuments = "$($script:UNC_USUARIOS)\%USERNAME%\Documents"

    try {
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" `
            -ValueName "Desktop" -Type String -Value $rutaDesktop | Out-Null
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
            -ValueName "Desktop" -Type ExpandString -Value $rutaDesktop | Out-Null
        Write-Host "  [OK] Desktop -> $rutaDesktop" -ForegroundColor Green

        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" `
            -ValueName "Personal" -Type String -Value $rutaDocuments | Out-Null
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
            -ValueName "Personal" -Type ExpandString -Value $rutaDocuments | Out-Null
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
            -ValueName "{F42EE2D3-909F-4907-8871-4C22FC0BF756}" `
            -Type ExpandString -Value $rutaDocuments | Out-Null
        Write-Host "  [OK] Documents -> $rutaDocuments" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Registro GPO: $($_.Exception.Message)" -ForegroundColor Red ; return
    }

    # PASO D: fdeploy.ini en SYSVOL
    Write-Host "`n  [D] Escribiendo politica en SYSVOL..." -ForegroundColor Yellow
    try {
        $gpoId    = $gpo.Id.ToString().ToUpper()
        $userPath = "C:\Windows\SYSVOL\sysvol\practica8.local\Policies\{$gpoId}\User\Documents & Settings"
        if (-not (Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory -Force | Out-Null }
        $fdeployContent = @"
[Version]
signature="`$CHICAGO`$"
Revision=1

[Desktop]
1=$($script:UNC_USUARIOS)\%USERNAME%\Desktop

[My Documents]
1=$($script:UNC_USUARIOS)\%USERNAME%\Documents

[My Pictures]
0=
"@
        $fdeployContent | Out-File -FilePath "$userPath\fdeploy.ini"  -Encoding Unicode -Force
        $fdeployContent | Out-File -FilePath "$userPath\fdeploy1.ini" -Encoding Unicode -Force
        Write-Host "  [OK] fdeploy.ini y fdeploy1.ini escritos." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] SYSVOL: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         La redireccion via registro funcionara de todas formas." -ForegroundColor DarkGray
    }

    # PASO E: Vincular GPO y aplicar
    Write-Host "`n  [E] Vinculando GPO al dominio..." -ForegroundColor Yellow
    try {
        New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop | Out-Null
        Write-Host "  [OK] GPO vinculada." -ForegroundColor Green
    } catch {
        Write-Host "  [OK] GPO ya estaba vinculada." -ForegroundColor Yellow
    }
    gpupdate /force 2>&1 | Out-Null
    Write-Host "  [OK] GPO aplicada en el servidor." -ForegroundColor Green

    # PASO F: Verificar y reparar FSRM
    Write-Host "`n  [F] Verificando FSRM (cuotas y apantallamiento)..." -ForegroundColor Yellow
    $sinCuota  = @()
    $sinScreen = @()
    foreach ($u in $usuarios) {
        $carpetaU = "$($script:CARPETA_USUARIOS)\$($u.Usuario)"
        if (Test-Path $carpetaU) {
            if (-not (Get-FsrmQuota      -Path $carpetaU -ErrorAction SilentlyContinue)) { $sinCuota  += $u }
            if (-not (Get-FsrmFileScreen -Path $carpetaU -ErrorAction SilentlyContinue)) { $sinScreen += $u }
        }
    }

    if ($sinCuota.Count -eq 0 -and $sinScreen.Count -eq 0) {
        Write-Host "  [OK] Todas las cuotas y apantallamientos estan activos." -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Reparando $($sinCuota.Count) cuota(s) y $($sinScreen.Count) screen(s)..." -ForegroundColor Yellow
        $plantillaScreen = "Practica8-Apantallamiento"
        $todos = ($sinCuota + $sinScreen) | Sort-Object Usuario -Unique
        foreach ($u in $todos) {
            $carpetaU = "$($script:CARPETA_USUARIOS)\$($u.Usuario)"
            if (-not (Get-FsrmQuota -Path $carpetaU -ErrorAction SilentlyContinue)) {
                $pn = if ($u.Departamento -eq "Cuates") { "Practica8-Cuates-10MB" } else { "Practica8-NoCuates-5MB" }
                $tb = if ($u.Departamento -eq "Cuates") { 10MB } else { 5MB }
                try {
                    if (Get-FsrmQuotaTemplate -Name $pn -ErrorAction SilentlyContinue) {
                        New-FsrmQuota -Path $carpetaU -Template $pn | Out-Null
                    } else {
                        New-FsrmQuota -Path $carpetaU -Size $tb -SoftLimit:$false | Out-Null
                    }
                    Write-Host "  [OK] Cuota reparada: $($u.Usuario)" -ForegroundColor Green
                } catch {
                    Write-Host "  [WARN] Cuota $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            if (-not (Get-FsrmFileScreen -Path $carpetaU -ErrorAction SilentlyContinue)) {
                try {
                    New-FsrmFileScreen -Path $carpetaU -Template $plantillaScreen | Out-Null
                    Write-Host "  [OK] Screen reparado: $($u.Usuario)" -ForegroundColor Green
                } catch {
                    Write-Host "  [WARN] Screen $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }

    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  | REDIRECCION CONFIGURADA CORRECTAMENTE      |" -ForegroundColor Cyan
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Escritorio -> $($script:UNC_USUARIOS)\<u>\Desktop" -ForegroundColor White
    Write-Host "  | Documentos -> $($script:UNC_USUARIOS)\<u>\Documents" -ForegroundColor White
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | PASOS EN EL CLIENTE WINDOWS 10:            |" -ForegroundColor Yellow
    Write-Host "  | 1. CMD Admin -> gpupdate /force            |" -ForegroundColor White
    Write-Host "  | 2. Cerrar sesion completamente             |" -ForegroundColor White
    Write-Host "  | 3. Volver a iniciar sesion                 |" -ForegroundColor White
    Write-Host "  | 4. Escritorio ahora vive en el servidor    |" -ForegroundColor White
    Write-Host "  | 5. Guarda .mp3 en Escritorio -> BLOQUEADO  |" -ForegroundColor Green
    Write-Host "  | 6. Guarda >5MB o >10MB -> BLOQUEADO        |" -ForegroundColor Green
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Presiona Enter..." ; Read-Host | Out-Null
}


# ============================================================
# FUNCION 6: Verificar que FSRM funciona (prueba real)
# ============================================================
function Verificar-FSRM {

    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   VERIFICAR FSRM (CUOTAS + APANTALLAMIENTO)|" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    if (-not (Test-Path $CSV_PATH)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv" -ForegroundColor Red ; return
    }

    $usuarios      = Import-Csv $CSV_PATH
    $primerUsuario = $usuarios | Select-Object -First 1

    if (-not $primerUsuario) {
        Write-Host "  [ERROR] CSV vacio." -ForegroundColor Red ; return
    }

    if (-not (Test-Path $script:CARPETA_USUARIOS)) {
        Write-Host "  [INFO] $($script:CARPETA_USUARIOS) no existe. Creando con FSRM..." -ForegroundColor Yellow
        Crear-CarpetasUsuariosConFSRM -Usuarios $usuarios
        Write-Host ""
    }

    $carpetaTest = "$($script:CARPETA_USUARIOS)\$($primerUsuario.Usuario)"

    Write-Host "  Usuario de prueba : $($primerUsuario.Usuario)" -ForegroundColor White
    Write-Host "  Grupo             : $($primerUsuario.Departamento)" -ForegroundColor White
    Write-Host "  Carpeta en server : $carpetaTest" -ForegroundColor White
    Write-Host ""

    # [1] Cuota
    Write-Host "  [1/3] Cuota FSRM:" -ForegroundColor Yellow
    $cuota = Get-FsrmQuota -Path $carpetaTest -ErrorAction SilentlyContinue
    if ($cuota) {
        $limiteMB = [math]::Round($cuota.Size / 1MB)
        $usadoMB  = [math]::Round($cuota.Usage / 1MB, 2)
        Write-Host "  [PASS] Cuota activa: ${limiteMB} MB limite | ${usadoMB} MB usado" -ForegroundColor Green
        Write-Host "         Tipo: $(if($cuota.SoftLimit){'SOFT (advertencia)'}else{'HARD (bloqueo estricto)'})" -ForegroundColor Cyan
    } else {
        Write-Host "  [FAIL] Sin cuota. Ejecuta Opcion 5 de este menu." -ForegroundColor Red
    }

    # [2] Apantallamiento
    Write-Host "`n  [2/3] Apantallamiento FSRM:" -ForegroundColor Yellow
    $screen = Get-FsrmFileScreen -Path $carpetaTest -ErrorAction SilentlyContinue
    if ($screen) {
        Write-Host "  [PASS] Apantallamiento activo." -ForegroundColor Green
        foreach ($g in $screen.IncludeGroup) {
            $grupo = Get-FsrmFileGroup -Name $g -ErrorAction SilentlyContinue
            if ($grupo) {
                Write-Host "         Grupo: $g" -ForegroundColor Cyan
                Write-Host "         Ext  : $($grupo.IncludePattern -join ', ')" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "  [FAIL] Sin apantallamiento. Ejecuta Opcion 5 de este menu." -ForegroundColor Red
    }

    # [3] Prueba real: intentar escribir un .mp3
    Write-Host "`n  [3/3] Prueba real (escribir .mp3 en carpeta del servidor):" -ForegroundColor Yellow
    $archivoTest = "$carpetaTest\prueba_bloqueo_$(Get-Random).mp3"
    try {
        "prueba fsrm" | Out-File $archivoTest -Encoding ASCII -ErrorAction Stop
        Remove-Item $archivoTest -Force -ErrorAction SilentlyContinue
        Write-Host "  [FAIL] El .mp3 NO fue bloqueado." -ForegroundColor Red
        Write-Host "         Verifica que el apantallamiento sea ACTIVO (Active Screening)." -ForegroundColor Yellow
        Write-Host "         Ejecuta Opcion 5 nuevamente para reparar." -ForegroundColor Yellow
    } catch {
        Write-Host "  [PASS] Archivo .mp3 BLOQUEADO por FSRM." -ForegroundColor Green
        Write-Host "         Error: $($_.Exception.Message)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Si los 3 puntos son [PASS]: FSRM correcto. |" -ForegroundColor Green
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Presiona Enter..." ; Read-Host | Out-Null
}


# ============================================================
# INICIO - Verificar privilegios y mostrar menu
# ============================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n  [ERROR] Ejecuta como Administrador.`n" -ForegroundColor Red
    exit 1
}

Mostrar-Menu
