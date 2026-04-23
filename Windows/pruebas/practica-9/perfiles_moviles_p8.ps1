# ============================================================
#  perfiles_moviles_p8.ps1
#  Perfiles Moviles (Roaming Profiles) - Practica 08
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
#  Carpeta  : C:\PerfilesMoviles  ->  \\192.168.1.202\Perfiles$
#  Carpeta FSRM: C:\Usuarios\<usuario> -> \\192.168.1.202\Usuarios
#
#  La Redireccion de Carpetas hace que Escritorio y Documentos
#  del cliente apunten a C:\Usuarios\<usuario> en el servidor,
#  donde FSRM tiene las cuotas y el apantallamiento activos.
#  Asi cualquier archivo guardado en esas carpetas es vigilado
#  por FSRM EN TIEMPO REAL desde el servidor.
# ============================================================

. "$PSScriptRoot\funciones_p8.ps1"

$SERVIDOR    = "192.168.1.202"
$CARPETA     = "C:\PerfilesMoviles"
$SHARE_NAME  = "Perfiles`$"
$SHARE_UNC   = "\\$SERVIDOR\Perfiles`$"
$CSV_PATH    = "$PSScriptRoot\usuarios.csv"

# Carpeta donde estan las cuotas FSRM (de la opcion 5 del main)
$CARPETA_USUARIOS = "C:\Usuarios"
$UNC_USUARIOS     = "\\$SERVIDOR\Usuarios"

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
            '4' { Ver-PerfilesAlmacenados }
            '5' { Configurar-RedireccionCarpetas }
            '6' { Verificar-FSRM }
            '0' { Write-Host "`n  Saliendo.`n" -ForegroundColor Green }
            default { Write-Host "  Opcion invalida." -ForegroundColor Red }
        }
    } while ($op -ne '0')
}


# ============================================================
# FUNCION 1: Crear y compartir carpeta de perfiles
# ============================================================
function Configurar-CarpetaPerfiles {
    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR CARPETA DE PERFILES MOVILES   |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    if (-not (Test-Path $CARPETA)) {
        New-Item -Path $CARPETA -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $CARPETA" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Carpeta ya existe: $CARPETA" -ForegroundColor Yellow
    }

    Write-Host "  Configurando permisos NTFS..." -ForegroundColor Yellow
    try {
        $acl = Get-Acl $CARPETA
        $acl.SetAccessRuleProtection($true, $false)

        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM","FullControl",
            "ContainerInherit,ObjectInherit","None","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators","FullControl",
            "ContainerInherit,ObjectInherit","None","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Admins","FullControl",
            "ContainerInherit,ObjectInherit","None","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "CREATOR OWNER","FullControl",
            "ContainerInherit,ObjectInherit","InheritOnly","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Users","ReadAndExecute, CreateDirectories",
            "None","None","Allow")))

        Set-Acl $CARPETA $acl
        Write-Host "  [OK] Permisos NTFS configurados." -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Permisos NTFS: $($_.Exception.Message)" -ForegroundColor Red
    }

    $shareExiste = Get-SmbShare -Name $SHARE_NAME -ErrorAction SilentlyContinue
    if ($shareExiste) {
        Remove-SmbShare -Name $SHARE_NAME -Force -ErrorAction SilentlyContinue
        Write-Host "  [INFO] Share anterior eliminado." -ForegroundColor DarkGray
    }

    try {
        New-SmbShare -Name $SHARE_NAME -Path $CARPETA `
            -FullAccess "Everyone" `
            -Description "Perfiles Moviles - Practica 08" | Out-Null
        Write-Host "  [OK] Compartido como: $SHARE_UNC" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Share: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "  Configurando GPO de perfiles moviles..." -ForegroundColor Yellow
    try {
        $gpoNombre = "Practica8-PerfilesMoviles"
        $dcBase    = (Get-ADDomain).DistinguishedName
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

    Write-Host "`n  Carpeta de perfiles: $CARPETA" -ForegroundColor Green
    Write-Host "  Ruta de red        : $SHARE_UNC" -ForegroundColor Green
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
    if (-not (Test-Path $CARPETA)) {
        Write-Host "  [ERROR] Ejecuta primero la Opcion 1." -ForegroundColor Red ; return
    }

    $usuarios = Import-Csv -Path $CSV_PATH
    $ok = 0; $errores = 0

    foreach ($u in $usuarios) {
        try {
            $rutaPerfil = "$SHARE_UNC\$($u.Usuario)"
            Set-ADUser -Identity $u.Usuario -ProfilePath $rutaPerfil -ErrorAction Stop
            Write-Host "  [OK] $($u.Usuario) -> $rutaPerfil" -ForegroundColor Green
            $ok++
        } catch {
            Write-Host "  [ERROR] $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Red
            $errores++
        }
    }

    $adminsP9 = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    Write-Host "`n  Admins Practica 09..." -ForegroundColor Yellow
    foreach ($a in $adminsP9) {
        try {
            Get-ADUser $a -ErrorAction Stop | Out-Null
            Set-ADUser -Identity $a -ProfilePath "$SHARE_UNC\$a" -ErrorAction Stop
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
    if (Test-Path $CARPETA) { Write-Host "  [PASS] $CARPETA" -ForegroundColor Green }
    else { Write-Host "  [FAIL] No existe. Opcion 1." -ForegroundColor Red }

    Write-Host "`n  [2/4] Share:" -ForegroundColor Yellow
    $share = Get-SmbShare -Name $SHARE_NAME -ErrorAction SilentlyContinue
    if ($share) { Write-Host "  [PASS] $SHARE_NAME activo." -ForegroundColor Green }
    else { Write-Host "  [FAIL] No existe. Opcion 1." -ForegroundColor Red }

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

    Write-Host "`n  [4/4] Carpeta FSRM (C:\Usuarios):" -ForegroundColor Yellow
    if (Test-Path $CARPETA_USUARIOS) {
        $subcarpetas = Get-ChildItem $CARPETA_USUARIOS -ErrorAction SilentlyContinue
        Write-Host "  [OK] Existe. Subcarpetas: $($subcarpetas.Count)" -ForegroundColor Green
        $subcarpetas | ForEach-Object {
            $cuota = Get-FsrmQuota -Path $_.FullName -ErrorAction SilentlyContinue
            $screen = Get-FsrmFileScreen -Path $_.FullName -ErrorAction SilentlyContinue
            $cuotaInfo   = if ($cuota)  { "Cuota OK ($([math]::Round($cuota.Size/1MB))MB)" } else { "SIN CUOTA" }
            $screenInfo  = if ($screen) { "Screen OK" } else { "SIN SCREEN" }
            Write-Host "    $($_.Name) -> $cuotaInfo | $screenInfo" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  [WARN] C:\Usuarios no existe. Ejecuta opcion 5 del menu principal." -ForegroundColor Yellow
    }

    Write-Host "`n  >>> CAPTURA ESTA PANTALLA como evidencia <<<" -ForegroundColor Magenta
    Write-Host "`n  Presiona Enter..." ; Read-Host | Out-Null
}


# ============================================================
# FUNCION 4: Ver perfiles almacenados
# ============================================================
function Ver-PerfilesAlmacenados {
    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   PERFILES ALMACENADOS EN EL SERVIDOR      |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    if (-not (Test-Path $CARPETA)) {
        Write-Host "  [INFO] $CARPETA no existe aun." -ForegroundColor Yellow ; return
    }

    $carpetas = Get-ChildItem $CARPETA -ErrorAction SilentlyContinue
    if (-not $carpetas -or $carpetas.Count -eq 0) {
        Write-Host "  [INFO] Sin perfiles todavia." -ForegroundColor Yellow
        Write-Host "         Cierra sesion en el cliente para que aparezcan." -ForegroundColor DarkGray
        return
    }

    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White
    Write-Host "  | Nombre                    | Tamano     | Modificado          |" -ForegroundColor White
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White

    foreach ($c in $carpetas) {
        $bytes = (Get-ChildItem $c.FullName -Recurse -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        $mb    = if ($bytes) { [math]::Round($bytes / 1MB, 2) } else { 0 }
        $fecha = $c.LastWriteTime.ToString("dd/MM/yyyy HH:mm")
        $color = if ($c.Name -match "\.V6$") { "Green" } else { "Yellow" }
        Write-Host ("  | {0,-25} | {1,8} MB | {2,-19} |" -f $c.Name, $mb, $fecha) -ForegroundColor $color
    }
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White
    Write-Host "`n  Verde = .V6 sincronizado | Amarillo = base sin login aun" -ForegroundColor White
    Write-Host "`n  >>> CAPTURA ESTA PANTALLA <<<" -ForegroundColor Magenta
    Write-Host "`n  Presiona Enter..." ; Read-Host | Out-Null
}


# ============================================================
# FUNCION 5: Configurar Redireccion de Carpetas
#
# ESTA ES LA CLAVE PARA QUE FSRM FUNCIONE:
#
# Sin esta funcion:
#   Cliente guarda en C:\Users\ecastro\Desktop  (local, FSRM no ve nada)
#
# Con esta funcion:
#   Cliente guarda en \\192.168.1.202\Usuarios\ecastro\Desktop
#   FSRM en el servidor VE el archivo y lo BLOQUEA si supera cuota
#   o si es .mp3/.mp4/.exe/.msi
#
# Mecanismo: GPO de Folder Redirection escrita directamente
# en el SYSVOL del DC usando el formato XML correcto que
# Windows entiende para User Configuration > Folder Redirection.
# ============================================================
function Configurar-RedireccionCarpetas {

    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   REDIRECCION DE CARPETAS (FOLDER REDIR)   |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    Write-Host "  QUE HACE ESTO:" -ForegroundColor White
    Write-Host "  Escritorio del cliente -> \\$SERVIDOR\Usuarios\<usuario>\Desktop" -ForegroundColor Cyan
    Write-Host "  Documentos del cliente -> \\$SERVIDOR\Usuarios\<usuario>\Documents" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  POR QUE:" -ForegroundColor White
    Write-Host "  El FSRM solo bloquea archivos en carpetas del servidor." -ForegroundColor Yellow
    Write-Host "  Al redirigir Escritorio/Documentos al servidor, cualquier" -ForegroundColor Yellow
    Write-Host "  archivo que el usuario guarde pasa por FSRM." -ForegroundColor Yellow
    Write-Host "  Si intenta guardar .mp3 en el Escritorio -> BLOQUEADO." -ForegroundColor Yellow
    Write-Host "  Si intenta superar 5MB o 10MB           -> BLOQUEADO." -ForegroundColor Yellow
    Write-Host ""

    # Verificar prerrequisitos
    try { $dominio = Get-ADDomain -ErrorAction Stop }
    catch { Write-Host "  [ERROR] AD no disponible." -ForegroundColor Red ; return }

    if (-not (Test-Path $CARPETA_USUARIOS)) {
        Write-Host "  [ERROR] C:\Usuarios no existe." -ForegroundColor Red
        Write-Host "  Ejecuta primero Opcion 5 del menu principal (Cuotas FSRM)." -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $CSV_PATH)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv" -ForegroundColor Red ; return
    }

    $confirmar = Read-Host "  Continuar? (s/n)"
    if ($confirmar -ne 's') { return }

    Write-Host ""
    $dcBase  = $dominio.DistinguishedName
    $netbios = $dominio.NetBIOSName
    $usuarios = Import-Csv $CSV_PATH

    # ==============================================================
    # PASO A: Crear subcarpetas Desktop y Documents en C:\Usuarios\usuario
    # Necesarias antes de que el cliente intente escribir ahi
    # ==============================================================
    Write-Host "  [A] Creando subcarpetas Desktop y Documents..." -ForegroundColor Yellow

    foreach ($u in $usuarios) {
        $carpetaUsuario = "$CARPETA_USUARIOS\$($u.Usuario)"
        if (-not (Test-Path $carpetaUsuario)) {
            Write-Host "  [AVISO] $carpetaUsuario no existe. Ejecuta opcion 5 del menu principal." -ForegroundColor Yellow
            continue
        }
        foreach ($sub in @("Desktop", "Documents")) {
            $subPath = "$carpetaUsuario\$sub"
            if (-not (Test-Path $subPath)) {
                New-Item -Path $subPath -ItemType Directory | Out-Null
                Write-Host "  [OK] Creada: $subPath" -ForegroundColor Green
            } else {
                Write-Host "  [OK] Ya existe: $subPath" -ForegroundColor DarkGray
            }
        }
    }

    # ==============================================================
    # PASO B: Configurar permisos NTFS en C:\Usuarios para redireccion
    # Los permisos deben permitir que cada usuario escriba en SU carpeta
    # ==============================================================
    Write-Host "`n  [B] Verificando permisos NTFS en C:\Usuarios..." -ForegroundColor Yellow

    try {
        $acl    = Get-Acl $CARPETA_USUARIOS
        $tieneModify = $acl.Access | Where-Object {
            $_.IdentityReference -like "*Domain Users*" -and
            $_.FileSystemRights -match "Modify|FullControl"
        }
        if ($tieneModify) {
            Write-Host "  [OK] Domain Users tiene permisos de escritura." -ForegroundColor Green
        } else {
            $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "PRACTICA8\Domain Users", "Modify",
                "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($regla)
            Set-Acl $CARPETA_USUARIOS $acl
            Write-Host "  [OK] Permisos Modify agregados a Domain Users." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Permisos: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # ==============================================================
    # PASO C: Crear GPO de Folder Redirection
    # Usamos el metodo de registro HKCU que es compatible con
    # Windows 10 sin necesitar plantillas ADMX adicionales.
    # La clave es usar el GUID correcto de cada carpeta especial.
    # ==============================================================
    Write-Host "`n  [C] Creando GPO de redireccion de carpetas..." -ForegroundColor Yellow

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

    # ------------------------------------------------------------------
    # Redireccion de Desktop (Escritorio)
    # GUID de Desktop: {B4BFCC3A-DB2C-424C-B029-7FE99A87C641}
    # ------------------------------------------------------------------
    $rutaDesktop   = "$UNC_USUARIOS\%USERNAME%\Desktop"
    $rutaDocuments = "$UNC_USUARIOS\%USERNAME%\Documents"

    try {
        # Desktop - clave Shell Folders
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" `
            -ValueName "Desktop" `
            -Type String -Value $rutaDesktop | Out-Null

        # Desktop - clave User Shell Folders (la que Windows realmente usa)
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
            -ValueName "Desktop" `
            -Type ExpandString -Value $rutaDesktop | Out-Null

        Write-Host "  [OK] Desktop -> $rutaDesktop" -ForegroundColor Green

        # Documents - clave Shell Folders
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" `
            -ValueName "Personal" `
            -Type String -Value $rutaDocuments | Out-Null

        # Documents - clave User Shell Folders
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
            -ValueName "Personal" `
            -Type ExpandString -Value $rutaDocuments | Out-Null

        # Documents - GUID alternativo que usa Windows 10
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
            -ValueName "{F42EE2D3-909F-4907-8871-4C22FC0BF756}" `
            -Type ExpandString -Value $rutaDocuments | Out-Null

        Write-Host "  [OK] Documents -> $rutaDocuments" -ForegroundColor Green

    } catch {
        Write-Host "  [ERROR] Registro GPO: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # ==============================================================
    # PASO D: Escribir la politica de Folder Redirection real
    # en el SYSVOL para que Windows la reconozca como FolderRedirection
    # Este archivo va en la GPO dentro del SYSVOL
    # ==============================================================
    Write-Host "`n  [D] Escribiendo politica Folder Redirection en SYSVOL..." -ForegroundColor Yellow

    try {
        $gpoId   = $gpo.Id.ToString().ToUpper()
        $sysvol  = "C:\Windows\SYSVOL\sysvol\practica8.local\Policies\{$gpoId}"
        $userPath = "$sysvol\User\Documents & Settings"

        if (-not (Test-Path $userPath)) {
            New-Item -Path $userPath -ItemType Directory -Force | Out-Null
        }

        # Archivo fdeploy.ini que Windows lee para Folder Redirection
        $fdeployContent = @"
[Version]
signature="`$CHICAGO$"
Revision=1

[Desktop]
1=$UNC_USUARIOS\%USERNAME%\Desktop

[My Documents]
1=$UNC_USUARIOS\%USERNAME%\Documents

[My Pictures]
0=
"@
        $fdeployPath = "$userPath\fdeploy.ini"
        $fdeployContent | Out-File -FilePath $fdeployPath -Encoding Unicode -Force
        Write-Host "  [OK] fdeploy.ini escrito en SYSVOL." -ForegroundColor Green

        # Tambien escribir el archivo fdeploy1.ini (Windows 10 lo busca)
        $fdeployContent | Out-File -FilePath "$userPath\fdeploy1.ini" -Encoding Unicode -Force
        Write-Host "  [OK] fdeploy1.ini escrito en SYSVOL." -ForegroundColor Green

    } catch {
        Write-Host "  [WARN] SYSVOL: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         La redireccion via registro aun funcionara." -ForegroundColor DarkGray
    }

    # ==============================================================
    # PASO E: Vincular GPO al dominio y actualizar
    # ==============================================================
    Write-Host "`n  [E] Vinculando GPO al dominio..." -ForegroundColor Yellow

    try {
        New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop | Out-Null
        Write-Host "  [OK] GPO vinculada." -ForegroundColor Green
    } catch {
        Write-Host "  [OK] GPO ya estaba vinculada." -ForegroundColor Yellow
    }

    gpupdate /force 2>&1 | Out-Null
    Write-Host "  [OK] GPO aplicada." -ForegroundColor Green

    # ==============================================================
    # PASO F: Verificar que FSRM esta en C:\Usuarios
    # Si no hay cuotas/screen, avisamos para que ejecuten opcion 5 y 6
    # ==============================================================
    Write-Host "`n  [F] Verificando FSRM en C:\Usuarios..." -ForegroundColor Yellow

    $sinCuota  = 0
    $sinScreen = 0
    foreach ($u in $usuarios) {
        $carpetaU = "$CARPETA_USUARIOS\$($u.Usuario)"
        if (Test-Path $carpetaU) {
            if (-not (Get-FsrmQuota -Path $carpetaU -ErrorAction SilentlyContinue)) {
                $sinCuota++
            }
            if (-not (Get-FsrmFileScreen -Path $carpetaU -ErrorAction SilentlyContinue)) {
                $sinScreen++
            }
        }
    }

    if ($sinCuota -gt 0) {
        Write-Host "  [WARN] $sinCuota usuario(s) SIN cuota FSRM." -ForegroundColor Yellow
        Write-Host "         Ejecuta Opcion 5 del menu principal." -ForegroundColor Yellow
    } else {
        Write-Host "  [OK] Todas las cuotas FSRM estan activas." -ForegroundColor Green
    }

    if ($sinScreen -gt 0) {
        Write-Host "  [WARN] $sinScreen usuario(s) SIN apantallamiento FSRM." -ForegroundColor Yellow
        Write-Host "         Ejecuta Opcion 6 del menu principal." -ForegroundColor Yellow
    } else {
        Write-Host "  [OK] Todos los apantallamientos FSRM estan activos." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  | REDIRECCION CONFIGURADA                    |" -ForegroundColor Cyan
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Escritorio -> $UNC_USUARIOS\<user>\Desktop" -ForegroundColor White
    Write-Host "  | Documentos -> $UNC_USUARIOS\<user>\Documents" -ForegroundColor White
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | PASOS EN EL CLIENTE WINDOWS 10:            |" -ForegroundColor Yellow
    Write-Host "  |                                            |" -ForegroundColor Yellow
    Write-Host "  | 1. Abrir CMD como Administrador            |" -ForegroundColor White
    Write-Host "  | 2. gpupdate /force                         |" -ForegroundColor White
    Write-Host "  | 3. Cerrar sesion completamente             |" -ForegroundColor White
    Write-Host "  | 4. Volver a iniciar sesion                 |" -ForegroundColor White
    Write-Host "  | 5. El Escritorio ahora vive en el servidor |" -ForegroundColor White
    Write-Host "  | 6. Intenta guardar un .mp3 en Escritorio   |" -ForegroundColor White
    Write-Host "  |    -> Debe aparecer error de acceso        |" -ForegroundColor White
    Write-Host "  | 7. Intenta guardar archivo > 5MB o 10MB    |" -ForegroundColor White
    Write-Host "  |    -> Debe aparecer error de cuota         |" -ForegroundColor White
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Presiona Enter..." ; Read-Host | Out-Null
}


# ============================================================
# FUNCION 6: Verificar que FSRM funciona correctamente
# Prueba real: intenta copiar un archivo prohibido a la
# carpeta del usuario en el servidor para confirmar el bloqueo
# ============================================================
function Verificar-FSRM {

    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   VERIFICAR FSRM (CUOTAS + APANTALLAMIENTO)|" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    if (-not (Test-Path $CSV_PATH)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv" -ForegroundColor Red ; return
    }

    $usuarios = Import-Csv $CSV_PATH
    $primerUsuario = $usuarios | Select-Object -First 1

    if (-not $primerUsuario) {
        Write-Host "  [ERROR] CSV vacio." -ForegroundColor Red ; return
    }

    $carpetaTest = "$CARPETA_USUARIOS\$($primerUsuario.Usuario)"

    if (-not (Test-Path $carpetaTest)) {
        Write-Host "  [ERROR] No existe $carpetaTest" -ForegroundColor Red
        Write-Host "  Ejecuta Opcion 5 del menu principal." -ForegroundColor Yellow
        return
    }

    Write-Host "  Usuario de prueba : $($primerUsuario.Usuario)" -ForegroundColor White
    Write-Host "  Grupo             : $($primerUsuario.Departamento)" -ForegroundColor White
    Write-Host "  Carpeta en server : $carpetaTest" -ForegroundColor White
    Write-Host ""

    # Verificar cuota activa
    Write-Host "  [1/3] Cuota FSRM:" -ForegroundColor Yellow
    $cuota = Get-FsrmQuota -Path $carpetaTest -ErrorAction SilentlyContinue
    if ($cuota) {
        $limiteMB = [math]::Round($cuota.Size / 1MB)
        $usadoMB  = [math]::Round($cuota.Usage / 1MB, 2)
        Write-Host "  [PASS] Cuota activa: ${limiteMB} MB limite | ${usadoMB} MB usado" -ForegroundColor Green
        Write-Host "         Tipo: $(if($cuota.SoftLimit){'SOFT (advertencia)'}else{'HARD (bloqueo estricto)'})" -ForegroundColor Cyan
    } else {
        Write-Host "  [FAIL] Sin cuota. Ejecuta Opcion 5 del menu principal." -ForegroundColor Red
    }

    # Verificar apantallamiento activo
    Write-Host "`n  [2/3] Apantallamiento FSRM:" -ForegroundColor Yellow
    $screen = Get-FsrmFileScreen -Path $carpetaTest -ErrorAction SilentlyContinue
    if ($screen) {
        Write-Host "  [PASS] Apantallamiento activo." -ForegroundColor Green
        $grupos = $screen.IncludeGroup
        Write-Host "         Grupos: $($grupos -join ', ')" -ForegroundColor Cyan
        # Mostrar extensiones bloqueadas
        foreach ($g in $grupos) {
            $grupo = Get-FsrmFileGroup -Name $g -ErrorAction SilentlyContinue
            if ($grupo) {
                Write-Host "         Extensiones: $($grupo.IncludePattern -join ', ')" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "  [FAIL] Sin apantallamiento. Ejecuta Opcion 6 del menu principal." -ForegroundColor Red
    }

    # Prueba real: intentar escribir un .mp3 ficticio
    Write-Host "`n  [3/3] Prueba real de apantallamiento:" -ForegroundColor Yellow
    $archivoTest = "$carpetaTest\test_bloqueo_$(Get-Random).mp3"
    try {
        "esto es una prueba" | Out-File $archivoTest -Encoding ASCII -ErrorAction Stop
        # Si llega aqui, el bloqueo NO funciono
        Remove-Item $archivoTest -Force -ErrorAction SilentlyContinue
        Write-Host "  [FAIL] El archivo .mp3 de prueba NO fue bloqueado." -ForegroundColor Red
        Write-Host "         Verifica que el apantallamiento es de tipo ACTIVO." -ForegroundColor Yellow
        Write-Host "         Ejecuta Opcion 6 del menu principal nuevamente." -ForegroundColor Yellow
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match "denied|denegado|blocked|FSRM|cuota|quota|unauthorized" -or
            $msg -match "0x80070005|0x80070052|access") {
            Write-Host "  [PASS] Archivo .mp3 BLOQUEADO por FSRM." -ForegroundColor Green
            Write-Host "         Error recibido: $msg" -ForegroundColor DarkGray
        } else {
            Write-Host "  [INFO] Error al escribir: $msg" -ForegroundColor Yellow
            Write-Host "         Puede ser bloqueo FSRM u otro error de permisos." -ForegroundColor DarkGray
        }
    }

    Write-Host "`n  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | RESUMEN DE VERIFICACION                    |" -ForegroundColor Cyan
    Write-Host "  | Si ves [PASS] en los 3 puntos:             |" -ForegroundColor White
    Write-Host "  | El FSRM esta listo para la evaluacion.     |" -ForegroundColor Green
    Write-Host "  |                                            |" -ForegroundColor White
    Write-Host "  | Para demostrar al profe:                   |" -ForegroundColor Yellow
    Write-Host "  | 1. En cliente: iniciar sesion con usuario  |" -ForegroundColor White
    Write-Host "  | 2. Guardar .mp3 en Escritorio -> BLOQUEADO |" -ForegroundColor White
    Write-Host "  | 3. Guardar archivo >5MB o >10MB -> BLOQ.   |" -ForegroundColor White
    Write-Host "  | 4. El error aparece en el cliente porque   |" -ForegroundColor White
    Write-Host "  |    el Escritorio esta en el servidor.      |" -ForegroundColor White
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Presiona Enter..." ; Read-Host | Out-Null
}


# ============================================================
# INICIO
# ============================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n  [ERROR] Ejecuta como Administrador.`n" -ForegroundColor Red
    exit 1
}

Mostrar-Menu
