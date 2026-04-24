# ============================================================
#  perfiles_moviles_p8.ps1 - VERSION CORREGIDA
#  Perfiles Moviles (Roaming Profiles) - Practica 08
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
#
#  CORRECCIONES vs version anterior:
#  - Opcion 5 ya NO falla si C:\Usuarios no existe.
#    Si no existe, lo crea con cuotas y apantallamiento FSRM
#    automaticamente antes de configurar la redireccion.
#  - Se unificaron todos los prerequisitos en cada funcion.
#  - La opcion 6 (Verificar FSRM) tambien crea lo que falte.
# ============================================================

. "$PSScriptRoot\funciones_p8.ps1"

$SERVIDOR         = "192.168.1.202"
$CARPETA          = "C:\PerfilesMoviles"
$SHARE_NAME       = "Perfiles`$"
$SHARE_UNC        = "\\$SERVIDOR\Perfiles`$"
$CSV_PATH         = "$PSScriptRoot\usuarios.csv"
$CARPETA_USUARIOS = "C:\Usuarios"
$UNC_USUARIOS     = "\\$SERVIDOR\Usuarios"

# ============================================================
# HELPER: Crear C:\Usuarios con cuotas y apantallamiento FSRM
# Se llama automaticamente desde Opcion 5 si C:\Usuarios
# no existe todavia.
# ============================================================
function Crear-CarpetasUsuariosConFSRM {
    param([array]$Usuarios)

    Write-Host "  [AUTO] Creando C:\Usuarios con cuotas y apantallamiento..." -ForegroundColor Cyan

    # --- Crear carpeta raiz ---
    if (-not (Test-Path $CARPETA_USUARIOS)) {
        New-Item -Path $CARPETA_USUARIOS -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $CARPETA_USUARIOS" -ForegroundColor Green
    }

    # --- Compartir en la red ---
    $shareExiste = Get-SmbShare -Name "Usuarios" -ErrorAction SilentlyContinue
    if (-not $shareExiste) {
        try {
            New-SmbShare -Name "Usuarios" -Path $CARPETA_USUARIOS `
                -FullAccess "PRACTICA8\Domain Admins" `
                -ChangeAccess "PRACTICA8\Domain Users" | Out-Null
            Write-Host "  [OK] Compartido como \\$SERVIDOR\Usuarios" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Share Usuarios: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [OK] Share 'Usuarios' ya existe." -ForegroundColor Yellow
    }

    # --- Permisos NTFS ---
    try {
        $acl   = Get-Acl $CARPETA_USUARIOS
        $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Users", "Modify",
            "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($regla)
        Set-Acl $CARPETA_USUARIOS $acl
        Write-Host "  [OK] Permisos NTFS configurados." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Permisos: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # --- Plantillas de cuota FSRM ---
    $plantillas = @(
        @{ Nombre = "Practica8-Cuates-10MB";  Tamano = 10MB },
        @{ Nombre = "Practica8-NoCuates-5MB"; Tamano = 5MB  }
    )
    foreach ($p in $plantillas) {
        try {
            if (-not (Get-FsrmQuotaTemplate -Name $p.Nombre -ErrorAction SilentlyContinue)) {
                New-FsrmQuotaTemplate -Name $p.Nombre -Size $p.Tamano -SoftLimit:$false | Out-Null
                Write-Host "  [OK] Plantilla cuota '$($p.Nombre)' creada." -ForegroundColor Green
            }
        } catch {
            Write-Host "  [WARN] Plantilla '$($p.Nombre)': $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # --- Grupo de archivos prohibidos ---
    $grupoNombre = "Practica8-ArchivosProhibidos"
    try {
        if (-not (Get-FsrmFileGroup -Name $grupoNombre -ErrorAction SilentlyContinue)) {
            New-FsrmFileGroup -Name $grupoNombre `
                -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
            Write-Host "  [OK] Grupo archivos prohibidos creado." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Grupo FSRM: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # --- Plantilla de apantallamiento ---
    $plantillaScreen = "Practica8-Apantallamiento"
    try {
        if (-not (Get-FsrmFileScreenTemplate -Name $plantillaScreen -ErrorAction SilentlyContinue)) {
            New-FsrmFileScreenTemplate -Name $plantillaScreen `
                -Active:$true -IncludeGroup @($grupoNombre) | Out-Null
            Write-Host "  [OK] Plantilla apantallamiento creada." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Plantilla screen: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # --- Carpetas individuales con cuota y apantallamiento ---
    foreach ($u in $Usuarios) {
        $carpetaU = "$CARPETA_USUARIOS\$($u.Usuario)"

        if (-not (Test-Path $carpetaU)) {
            New-Item -Path $carpetaU -ItemType Directory | Out-Null
        }

        # Cuota
        try {
            if ($u.Departamento -eq "Cuates") {
                $plantillaN = "Practica8-Cuates-10MB"; $tamanoB = 10MB
            } else {
                $plantillaN = "Practica8-NoCuates-5MB"; $tamanoB = 5MB
            }

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
                Set-FsrmFileScreen -Path $carpetaU -Template $plantillaScreen | Out-Null
            } else {
                New-FsrmFileScreen -Path $carpetaU -Template $plantillaScreen | Out-Null
            }
            Write-Host "  [OK] $($u.Usuario) -> apantallamiento aplicado." -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Screen $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host "  [AUTO] C:\Usuarios listo con cuotas y apantallamiento." -ForegroundColor Cyan
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
            '4' { Ver-PerfilesAlmacenados }
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
            "NT AUTHORITY\SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Admins","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "CREATOR OWNER","FullControl","ContainerInherit,ObjectInherit","InheritOnly","Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Users","ReadAndExecute, CreateDirectories","None","None","Allow")))
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
            -FullAccess "Everyone" -Description "Perfiles Moviles - Practica 08" | Out-Null
        Write-Host "  [OK] Compartido como: $SHARE_UNC" -ForegroundColor Green
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
    Write-Host "`n  Admins Practica 09 (si existen)..." -ForegroundColor Yellow
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
    if (Test-Path $CARPETA) { Write-Host "  [PASS] $CARPETA existe." -ForegroundColor Green }
    else { Write-Host "  [FAIL] No existe. Opcion 1." -ForegroundColor Red }

    Write-Host "`n  [2/4] Share '$SHARE_NAME':" -ForegroundColor Yellow
    $share = Get-SmbShare -Name $SHARE_NAME -ErrorAction SilentlyContinue
    if ($share) {
        Write-Host "  [PASS] Share activo en: $($share.Path)" -ForegroundColor Green
        Get-SmbShareAccess -Name $SHARE_NAME | ForEach-Object {
            Write-Host "         $($_.AccountName): $($_.AccessRight)" -ForegroundColor DarkGray
        }
    } else { Write-Host "  [FAIL] No existe. Opcion 1." -ForegroundColor Red }

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

    Write-Host "`n  [4/4] FSRM en C:\Usuarios:" -ForegroundColor Yellow
    if (Test-Path $CARPETA_USUARIOS) {
        $subcarpetas = Get-ChildItem $CARPETA_USUARIOS -ErrorAction SilentlyContinue
        Write-Host "  [OK] Existe. Subcarpetas: $($subcarpetas.Count)" -ForegroundColor Green
        foreach ($c in $subcarpetas) {
            $cuota  = Get-FsrmQuota -Path $c.FullName -ErrorAction SilentlyContinue
            $screen = Get-FsrmFileScreen -Path $c.FullName -ErrorAction SilentlyContinue
            $ci = if ($cuota)  { "Cuota $([math]::Round($cuota.Size/1MB))MB OK" } else { "SIN CUOTA" }
            $si = if ($screen) { "Screen OK" } else { "SIN SCREEN" }
            Write-Host "    $($c.Name) -> $ci | $si" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  [WARN] C:\Usuarios no existe. Se creara en Opcion 5." -ForegroundColor Yellow
    }

    Write-Host "`n  >>> CAPTURA ESTA PANTALLA como evidencia <<<" -ForegroundColor Magenta
    Write-Host "`n  Presiona Enter..." ; Read-Host | Out-Null
}


function Ver-PerfilesAlmacenados {
    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   PERFILES ALMACENADOS EN EL SERVIDOR      |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    # -------------------------------------------------------
    # HELPER: calcular tamano recursivo de una carpeta
    # -------------------------------------------------------
    function Get-TamanoMB {
        param([string]$Ruta)
        if (-not (Test-Path $Ruta)) { return 0 }
        $bytes = (Get-ChildItem $Ruta -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($bytes) { return [math]::Round($bytes / 1MB, 2) } else { return 0 }
    }

    # -------------------------------------------------------
    # SECCION 1: C:\PerfilesMoviles  (perfil roaming .V6)
    # -------------------------------------------------------
    Write-Host "  SECCION 1: Perfiles Moviles (roaming)" -ForegroundColor Yellow
    Write-Host "  Carpeta : $CARPETA" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-Path $CARPETA)) {
        Write-Host "  [INFO] $CARPETA no existe aun. Ejecuta Opcion 1." -ForegroundColor Yellow
    } else {
        $carpetas = Get-ChildItem $CARPETA -ErrorAction SilentlyContinue
        if (-not $carpetas -or $carpetas.Count -eq 0) {
            Write-Host "  [INFO] Sin perfiles todavia. Cierra sesion en el cliente Windows." -ForegroundColor Yellow
        } else {
            Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White
            Write-Host "  | Nombre                    | Tamano     | Modificado          |" -ForegroundColor White
            Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White
            foreach ($c in $carpetas) {
                $mb    = Get-TamanoMB -Ruta $c.FullName
                $fecha = $c.LastWriteTime.ToString("dd/MM/yyyy HH:mm")
                $color = if ($c.Name -match "\.V6$") { "Green" } else { "Yellow" }
                Write-Host ("  | {0,-25} | {1,8} MB | {2,-19} |" -f $c.Name, $mb, $fecha) -ForegroundColor $color
            }
            Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White
            Write-Host ""
            Write-Host "  Verde    = .V6 sincronizado (primer login completado)" -ForegroundColor Green
            Write-Host "  Amarillo = carpeta base, usuario aun no ha hecho login" -ForegroundColor Yellow
        }
    }

    # -------------------------------------------------------
    # SECCION 2: C:\Usuarios  (redireccion Desktop/Documents)
    # -------------------------------------------------------
    Write-Host ""
    Write-Host "  ------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  SECCION 2: Redireccion de Carpetas (Desktop/Documents)" -ForegroundColor Yellow
    Write-Host "  Carpeta : $CARPETA_USUARIOS" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-Path $CARPETA_USUARIOS)) {
        Write-Host "  [INFO] $CARPETA_USUARIOS no existe. Ejecuta Opcion 5." -ForegroundColor Yellow
    } else {
        $subcarpetas = Get-ChildItem $CARPETA_USUARIOS -Directory -ErrorAction SilentlyContinue
        if (-not $subcarpetas -or $subcarpetas.Count -eq 0) {
            Write-Host "  [INFO] Sin carpetas de usuario todavia." -ForegroundColor Yellow
        } else {
            Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor White
            Write-Host "  | Usuario       | Desktop (MB) | Documents (MB) | Total (MB) | Cuota  |" -ForegroundColor White
            Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor White

            foreach ($c in $subcarpetas) {
                $carpetaDesktop   = "$($c.FullName)\Desktop"
                $carpetaDocuments = "$($c.FullName)\Documents"

                $mbDesktop   = Get-TamanoMB -Ruta $carpetaDesktop
                $mbDocuments = Get-TamanoMB -Ruta $carpetaDocuments
                $mbTotal     = [math]::Round($mbDesktop + $mbDocuments, 2)

                # Leer cuota FSRM si existe
                $cuotaInfo = "N/A"
                $cuota = Get-FsrmQuota -Path $c.FullName -ErrorAction SilentlyContinue
                if ($cuota) {
                    $limMB  = [math]::Round($cuota.Size / 1MB)
                    $usaMB  = [math]::Round($cuota.Usage / 1MB, 2)
                    $cuotaInfo = "$usaMB/$limMB MB"
                }

                # Color: rojo si supera el 80% de la cuota
                $color = "Green"
                if ($cuota -and $cuota.Size -gt 0) {
                    $pct = ($cuota.Usage / $cuota.Size) * 100
                    if ($pct -ge 80) { $color = "Red" }
                    elseif ($pct -ge 50) { $color = "Yellow" }
                }

                Write-Host ("  | {0,-13} | {1,12} | {2,14} | {3,10} | {4,-6} |" -f `
                    $c.Name, $mbDesktop, $mbDocuments, $mbTotal, $cuotaInfo) -ForegroundColor $color
            }
            Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor White
            Write-Host ""
            Write-Host "  Verde    = uso normal (menos del 50% de cuota)" -ForegroundColor Green
            Write-Host "  Amarillo = uso moderado (50-79% de cuota)"      -ForegroundColor Yellow
            Write-Host "  Rojo     = uso alto (80% o mas de cuota)"       -ForegroundColor Red
        }
    }

    # -------------------------------------------------------
    # SECCION 3: Resumen por usuario (ambas ubicaciones)
    # -------------------------------------------------------
    Write-Host ""
    Write-Host "  ------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  SECCION 3: Resumen total por usuario" -ForegroundColor Yellow
    Write-Host ""

    if (Test-Path $CSV_PATH) {
        $usuarios = Import-Csv $CSV_PATH -ErrorAction SilentlyContinue
        if ($usuarios) {
            Write-Host "  +-------------------------------------------------------------+" -ForegroundColor White
            Write-Host "  | Usuario       | Perfil .V6 | Redireccion | TOTAL      | Grp |" -ForegroundColor White
            Write-Host "  +-------------------------------------------------------------+" -ForegroundColor White

            foreach ($u in $usuarios) {
                # Perfil movil: buscar con y sin .V6
                $mbPerfil = 0
                foreach ($sufijo in @(".V6", "")) {
                    $ruta = "$CARPETA\$($u.Usuario)$sufijo"
                    if (Test-Path $ruta) {
                        $mbPerfil = Get-TamanoMB -Ruta $ruta
                        break
                    }
                }

                # Redireccion: Desktop + Documents
                $mbRedir = 0
                $rutaUsuario = "$CARPETA_USUARIOS\$($u.Usuario)"
                if (Test-Path $rutaUsuario) {
                    $mbRedir = Get-TamanoMB -Ruta $rutaUsuario
                }

                $mbTotal = [math]::Round($mbPerfil + $mbRedir, 2)

                # Color segun departamento
                $color = if ($u.Departamento -eq "Cuates") { "Cyan" } else { "Magenta" }

                Write-Host ("  | {0,-13} | {1,10} | {2,11} | {3,10} | {4,-3} |" -f `
                    $u.Usuario, "$mbPerfil MB", "$mbRedir MB", "$mbTotal MB", $u.Departamento.Substring(0,3)) `
                    -ForegroundColor $color
            }
            Write-Host "  +-------------------------------------------------------------+" -ForegroundColor White
            Write-Host ""
            Write-Host "  Cyan    = Cuates    (cuota 10 MB)" -ForegroundColor Cyan
            Write-Host "  Magenta = NoCuates  (cuota  5 MB)" -ForegroundColor Magenta
        }
    }

    Write-Host ""
    Write-Host "  NOTA: El almacenamiento se actualiza cuando el usuario" -ForegroundColor DarkGray
    Write-Host "  guarda archivos y se sincronizan al servidor." -ForegroundColor DarkGray
    Write-Host "  Si ves 0 MB en Perfil .V6 pero hay archivos en Redireccion," -ForegroundColor DarkGray
    Write-Host "  es normal: los archivos del Escritorio/Documentos van a" -ForegroundColor DarkGray
    Write-Host "  C:\Usuarios, NO a C:\PerfilesMoviles." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  >>> CAPTURA ESTA PANTALLA como evidencia <<<" -ForegroundColor Magenta
    Write-Host "`n  Presiona Enter..." ; Read-Host | Out-Null
}

# ============================================================
# FUNCION 5: Configurar Redireccion de Carpetas
#
# CORRECCION PRINCIPAL:
# Si C:\Usuarios no existe, lo crea automaticamente con
# cuotas y apantallamiento FSRM antes de configurar la
# redireccion. Ya NO falla con error "no existe".
#
# El flujo correcto queda:
#   - Escritorio del cliente -> \\servidor\Usuarios\usuario\Desktop
#   - Documentos del cliente -> \\servidor\Usuarios\usuario\Documents
#   - FSRM vigila esas carpetas en tiempo real
#   - .mp3/.mp4/.exe/.msi -> BLOQUEADO
#   - Superar 5MB/10MB    -> BLOQUEADO
# ============================================================
function Configurar-RedireccionCarpetas {

    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   REDIRECCION DE CARPETAS (FOLDER REDIR)   |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    Write-Host "  QUE HACE ESTO:" -ForegroundColor White
    Write-Host "  Escritorio del cliente -> $UNC_USUARIOS\<usuario>\Desktop" -ForegroundColor Cyan
    Write-Host "  Documentos del cliente -> $UNC_USUARIOS\<usuario>\Documents" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  RESULTADO:" -ForegroundColor White
    Write-Host "  Guardar .mp3 en Escritorio  -> BLOQUEADO por FSRM" -ForegroundColor Yellow
    Write-Host "  Superar cuota (5MB o 10MB)  -> BLOQUEADO por FSRM" -ForegroundColor Yellow
    Write-Host ""

    # Verificar AD disponible
    try { $dominio = Get-ADDomain -ErrorAction Stop }
    catch { Write-Host "  [ERROR] AD no disponible." -ForegroundColor Red ; return }

    if (-not (Test-Path $CSV_PATH)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv" -ForegroundColor Red ; return
    }

    $usuarios = Import-Csv $CSV_PATH

    # -------------------------------------------------------
    # CORRECCION: Si C:\Usuarios no existe, crearlo con FSRM
    # -------------------------------------------------------
    if (-not (Test-Path $CARPETA_USUARIOS)) {
        Write-Host "  [INFO] C:\Usuarios no existe. Creando automaticamente..." -ForegroundColor Yellow
        Crear-CarpetasUsuariosConFSRM -Usuarios $usuarios
        Write-Host ""
    } else {
        Write-Host "  [OK] C:\Usuarios ya existe." -ForegroundColor Green
    }

    $confirmar = Read-Host "  Continuar con la redireccion? (s/n)"
    if ($confirmar -ne 's') { return }

    Write-Host ""
    $dcBase = $dominio.DistinguishedName

    # ==============================================================
    # PASO A: Crear subcarpetas Desktop y Documents por usuario
    # ==============================================================
    Write-Host "  [A] Creando subcarpetas Desktop y Documents..." -ForegroundColor Yellow

    foreach ($u in $usuarios) {
        $carpetaU = "$CARPETA_USUARIOS\$($u.Usuario)"
        if (-not (Test-Path $carpetaU)) {
            New-Item -Path $carpetaU -ItemType Directory | Out-Null
        }
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

    # ==============================================================
    # PASO B: Verificar permisos NTFS en C:\Usuarios
    # ==============================================================
    Write-Host "`n  [B] Verificando permisos NTFS en C:\Usuarios..." -ForegroundColor Yellow
    try {
        $acl = Get-Acl $CARPETA_USUARIOS
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
            Set-Acl $CARPETA_USUARIOS $acl
            Write-Host "  [OK] Permisos Modify agregados." -ForegroundColor Green
        } else {
            Write-Host "  [OK] Domain Users ya tiene permisos correctos." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Permisos: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # ==============================================================
    # PASO C: GPO de redireccion de carpetas
    # Usa claves de registro HKCU que Windows 10 respeta.
    # Desktop: "Desktop" en User Shell Folders
    # Documents: "Personal" + GUID en User Shell Folders
    # ==============================================================
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

    $rutaDesktop   = "$UNC_USUARIOS\%USERNAME%\Desktop"
    $rutaDocuments = "$UNC_USUARIOS\%USERNAME%\Documents"

    try {
        # Desktop - Shell Folders
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" `
            -ValueName "Desktop" -Type String -Value $rutaDesktop | Out-Null

        # Desktop - User Shell Folders (la que Windows realmente usa)
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
            -ValueName "Desktop" -Type ExpandString -Value $rutaDesktop | Out-Null

        Write-Host "  [OK] Desktop -> $rutaDesktop" -ForegroundColor Green

        # Documents - Shell Folders
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" `
            -ValueName "Personal" -Type String -Value $rutaDocuments | Out-Null

        # Documents - User Shell Folders
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
            -ValueName "Personal" -Type ExpandString -Value $rutaDocuments | Out-Null

        # Documents - GUID alternativo Windows 10
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
    # PASO D: Escribir fdeploy.ini en SYSVOL (Folder Redirection real)
    # ==============================================================
    Write-Host "`n  [D] Escribiendo politica en SYSVOL..." -ForegroundColor Yellow
    try {
        $gpoId    = $gpo.Id.ToString().ToUpper()
        $userPath = "C:\Windows\SYSVOL\sysvol\practica8.local\Policies\{$gpoId}\User\Documents & Settings"
        if (-not (Test-Path $userPath)) {
            New-Item -Path $userPath -ItemType Directory -Force | Out-Null
        }
        $fdeployContent = @"
[Version]
signature="`$CHICAGO`$"
Revision=1

[Desktop]
1=$UNC_USUARIOS\%USERNAME%\Desktop

[My Documents]
1=$UNC_USUARIOS\%USERNAME%\Documents

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

    # ==============================================================
    # PASO E: Vincular GPO y aplicar
    # ==============================================================
    Write-Host "`n  [E] Vinculando GPO al dominio..." -ForegroundColor Yellow
    try {
        New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop | Out-Null
        Write-Host "  [OK] GPO vinculada." -ForegroundColor Green
    } catch {
        Write-Host "  [OK] GPO ya estaba vinculada." -ForegroundColor Yellow
    }
    gpupdate /force 2>&1 | Out-Null
    Write-Host "  [OK] GPO aplicada en el servidor." -ForegroundColor Green

    # ==============================================================
    # PASO F: Verificar FSRM en C:\Usuarios (y reparar si falta)
    # ==============================================================
    Write-Host "`n  [F] Verificando FSRM (cuotas y apantallamiento)..." -ForegroundColor Yellow

    $sinCuota  = @()
    $sinScreen = @()

    foreach ($u in $usuarios) {
        $carpetaU = "$CARPETA_USUARIOS\$($u.Usuario)"
        if (Test-Path $carpetaU) {
            if (-not (Get-FsrmQuota -Path $carpetaU -ErrorAction SilentlyContinue)) {
                $sinCuota += $u
            }
            if (-not (Get-FsrmFileScreen -Path $carpetaU -ErrorAction SilentlyContinue)) {
                $sinScreen += $u
            }
        }
    }

    if ($sinCuota.Count -eq 0 -and $sinScreen.Count -eq 0) {
        Write-Host "  [OK] Todas las cuotas y apantallamientos estan activos." -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Faltan $($sinCuota.Count) cuota(s) y $($sinScreen.Count) screen(s). Reparando..." -ForegroundColor Yellow
        # Reparar lo que falte sin recrear todo
        $plantillaScreen = "Practica8-Apantallamiento"
        foreach ($u in ($sinCuota + $sinScreen | Sort-Object Usuario -Unique)) {
            $carpetaU = "$CARPETA_USUARIOS\$($u.Usuario)"
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
    Write-Host "  | Escritorio -> $UNC_USUARIOS\<u>\Desktop" -ForegroundColor White
    Write-Host "  | Documentos -> $UNC_USUARIOS\<u>\Documents" -ForegroundColor White
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | PASOS EN EL CLIENTE WINDOWS 10:            |" -ForegroundColor Yellow
    Write-Host "  |                                            |" -ForegroundColor Yellow
    Write-Host "  | 1. CMD como Administrador                  |" -ForegroundColor White
    Write-Host "  |    gpupdate /force                         |" -ForegroundColor White
    Write-Host "  | 2. Cerrar sesion completamente             |" -ForegroundColor White
    Write-Host "  | 3. Volver a iniciar sesion                 |" -ForegroundColor White
    Write-Host "  | 4. Escritorio ahora vive en el servidor    |" -ForegroundColor White
    Write-Host "  | 5. Intenta guardar .mp3 en Escritorio      |" -ForegroundColor White
    Write-Host "  |    -> Error: acceso denegado (FSRM)        |" -ForegroundColor Green
    Write-Host "  | 6. Intenta guardar archivo > 5MB o 10MB   |" -ForegroundColor White
    Write-Host "  |    -> Error: cuota superada (FSRM)         |" -ForegroundColor Green
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

    # Si C:\Usuarios no existe, crearlo
    if (-not (Test-Path $CARPETA_USUARIOS)) {
        Write-Host "  [INFO] C:\Usuarios no existe. Creando con FSRM..." -ForegroundColor Yellow
        Crear-CarpetasUsuariosConFSRM -Usuarios $usuarios
        Write-Host ""
    }

    $carpetaTest = "$CARPETA_USUARIOS\$($primerUsuario.Usuario)"

    Write-Host "  Usuario de prueba : $($primerUsuario.Usuario)" -ForegroundColor White
    Write-Host "  Grupo             : $($primerUsuario.Departamento)" -ForegroundColor White
    Write-Host "  Carpeta en server : $carpetaTest" -ForegroundColor White
    Write-Host ""

    # [1] Verificar cuota
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

    # [2] Verificar apantallamiento
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
        Write-Host "         Verifica que el apantallamiento es ACTIVO (Active Screening)." -ForegroundColor Yellow
        Write-Host "         Ejecuta Opcion 5 nuevamente para reparar." -ForegroundColor Yellow
    } catch {
        $msg = $_.Exception.Message
        Write-Host "  [PASS] Archivo .mp3 BLOQUEADO por FSRM." -ForegroundColor Green
        Write-Host "         Error: $msg" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | RESUMEN                                    |" -ForegroundColor Cyan
    Write-Host "  | Si los 3 puntos son [PASS]:                |" -ForegroundColor White
    Write-Host "  | El FSRM esta listo para la evaluacion.     |" -ForegroundColor Green
    Write-Host "  |                                            |" -ForegroundColor White
    Write-Host "  | Para demostrar al profe:                   |" -ForegroundColor Yellow
    Write-Host "  | 1. Cliente: iniciar sesion con usuario     |" -ForegroundColor White
    Write-Host "  | 2. Guardar .mp3 en Escritorio -> BLOQUEADO |" -ForegroundColor White
    Write-Host "  | 3. Archivo >5MB o >10MB       -> BLOQUEADO |" -ForegroundColor White
    Write-Host "  | El error aparece porque el Escritorio      |" -ForegroundColor White
    Write-Host "  | vive en el servidor (redireccion activa).  |" -ForegroundColor White
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
