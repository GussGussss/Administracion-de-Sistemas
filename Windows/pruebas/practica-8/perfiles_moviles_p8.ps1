# ============================================================
#  perfiles_moviles_p8.ps1
#  Perfiles Moviles (Roaming Profiles) - Practica 08
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
#  Carpeta  : C:\PerfilesMoviles  ->  \\192.168.1.202\Perfiles$
#
#  COMO USAR:
#  1. Ejecutar como Administrator en el servidor
#  2. Opcion 1: Configurar carpeta compartida de perfiles
#  3. Opcion 2: Asignar perfiles a usuarios del CSV
#  4. Opcion 3: Verificar que todo esta correcto
#  5. En el cliente Windows: gpupdate /force y reiniciar sesion
# ============================================================

. "$PSScriptRoot\funciones_p8.ps1"

$SERVIDOR    = "192.168.1.202"
$CARPETA     = "C:\PerfilesMoviles"
$SHARE_NAME  = "Perfiles$"   # El $ lo oculta en la red (buena practica)
$SHARE_UNC   = "\\$SERVIDOR\$SHARE_NAME"
$CSV_PATH    = "$PSScriptRoot\usuarios.csv"

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
        Write-Host "  |  0. Salir                                  |" -ForegroundColor Red
        Write-Host "  +============================================+`n" -ForegroundColor Cyan
        $op = Read-Host "  Selecciona"
        switch ($op) {
            '1' { Configurar-CarpetaPerfiles }
            '2' { Asignar-PerfilesUsuarios }
            '3' { Verificar-Perfiles }
            '4' { Ver-PerfilesAlmacenados }
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

    # --- Crear carpeta raiz ---
    if (-not (Test-Path $CARPETA)) {
        New-Item -Path $CARPETA -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $CARPETA" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Carpeta ya existe: $CARPETA" -ForegroundColor Yellow
    }

    # --- Permisos NTFS ---
    # Los perfiles moviles necesitan permisos especificos:
    # - Administradores: Control Total
    # - SYSTEM: Control Total
    # - Creator Owner: Control Total (heredado a subcarpetas)
    # - Domain Users: Lectura + Escritura en esta carpeta SOLO
    #   (NO en subcarpetas, cada usuario solo ve su propia carpeta)
    Write-Host "  Configurando permisos NTFS..." -ForegroundColor Yellow

    try {
        $acl = Get-Acl $CARPETA

        # Limpiar permisos heredados para control total
        $acl.SetAccessRuleProtection($true, $false)

        # SYSTEM: Control Total
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM",
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )))

        # Administradores: Control Total
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators",
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )))

        # Domain Admins: Control Total
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Admins",
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )))

        # Creator Owner: Control Total en subcarpetas (para que cada usuario
        # tenga control total sobre su propia carpeta de perfil)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "CREATOR OWNER",
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "InheritOnly",
            "Allow"
        )))

        # Domain Users: solo ListDirectory + CreateDirectories en la raiz
        # (necesario para que Windows cree la subcarpeta del perfil)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Users",
            "ReadAndExecute, CreateDirectories",
            "None",
            "None",
            "Allow"
        )))

        Set-Acl $CARPETA $acl
        Write-Host "  [OK] Permisos NTFS configurados correctamente." -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Permisos NTFS: $($_.Exception.Message)" -ForegroundColor Red
    }

    # --- Compartir carpeta ---
    Write-Host "  Configurando recurso compartido '$SHARE_NAME'..." -ForegroundColor Yellow
    $shareExiste = Get-SmbShare -Name $SHARE_NAME -ErrorAction SilentlyContinue
    if ($shareExiste) {
        Remove-SmbShare -Name $SHARE_NAME -Force -ErrorAction SilentlyContinue
        Write-Host "  [INFO] Share anterior eliminado para recrear." -ForegroundColor DarkGray
    }

    try {
        # Permisos de compartido: Everyone con Control Total
        # (los permisos reales los controla NTFS arriba)
        New-SmbShare `
            -Name        $SHARE_NAME `
            -Path        $CARPETA `
            -FullAccess  "Everyone" `
            -Description "Perfiles Moviles - Practica 08" | Out-Null

        Write-Host "  [OK] Carpeta compartida como: $SHARE_UNC" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] No se pudo compartir: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # --- GPO para redireccion de carpetas (opcional pero recomendado) ---
    # Habilitar la GPO que permite que los perfiles moviles funcionen
    # sin problemas con Windows 10
    Write-Host "  Configurando GPO de perfiles moviles..." -ForegroundColor Yellow
    try {
        $gpoNombre = "Practica8-PerfilesMoviles"
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Host "  [CREADO] GPO '$gpoNombre' creada." -ForegroundColor Green
        } else {
            Write-Host "  [OK] GPO ya existe, actualizando." -ForegroundColor Yellow
        }

        $dcBase = (Get-ADDomain).DistinguishedName

        # Configuracion 1: No verificar si el disco tiene espacio suficiente
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
            -ValueName "CompatibleRUPSecurity" `
            -Type DWord -Value 1 | Out-Null

        # Configuracion 2: Permitir perfiles lentos (para red local)
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "SlowLinkDefaultProfile" `
            -Type DWord -Value 1 | Out-Null

        # Configuracion 3: Tiempo de espera para detectar red lenta (0 = siempre cargar)
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "SlowLinkTimeOut" `
            -Type DWord -Value 0 | Out-Null

        # Vincular GPO al dominio
        try {
            New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop | Out-Null
            Write-Host "  [OK] GPO vinculada al dominio." -ForegroundColor Green
        } catch {
            Write-Host "  [OK] GPO ya estaba vinculada." -ForegroundColor Yellow
        }

        gpupdate /force 2>&1 | Out-Null
        Write-Host "  [OK] GPO aplicada." -ForegroundColor Green

    } catch {
        Write-Host "  [WARN] GPO: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         Los perfiles moviles funcionan sin la GPO adicional." -ForegroundColor DarkGray
    }

    Write-Host "`n  +------------------------------------------+" -ForegroundColor Green
    Write-Host "  | Carpeta de perfiles configurada:         |" -ForegroundColor Green
    Write-Host "  | Ruta local : $CARPETA" -ForegroundColor White
    Write-Host "  | Ruta UNC   : $SHARE_UNC" -ForegroundColor White
    Write-Host "  +------------------------------------------+" -ForegroundColor Green
    Write-Host "`n  Siguiente paso: Opcion 2 para asignar perfiles a usuarios." -ForegroundColor Cyan
    Write-Host "`n  Presiona Enter para continuar..."
    Read-Host | Out-Null
}


# ============================================================
# FUNCION 2: Asignar perfil movil a cada usuario del CSV
# ============================================================
function Asignar-PerfilesUsuarios {
    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   ASIGNAR PERFILES MOVILES A USUARIOS      |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    if (-not (Test-Path $CSV_PATH)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv en $PSScriptRoot" -ForegroundColor Red
        return
    }

    # Verificar que la carpeta compartida existe
    if (-not (Test-Path $CARPETA)) {
        Write-Host "  [ERROR] La carpeta $CARPETA no existe." -ForegroundColor Red
        Write-Host "         Ejecuta primero la Opcion 1." -ForegroundColor Yellow
        return
    }

    $usuarios = Import-Csv -Path $CSV_PATH
    Write-Host "  Usuarios a configurar: $($usuarios.Count)" -ForegroundColor White
    Write-Host "  Ruta UNC base: $SHARE_UNC\<usuario>" -ForegroundColor DarkGray
    Write-Host ""

    $ok      = 0
    $errores = 0

    foreach ($u in $usuarios) {
        try {
            # La ruta del perfil movil en AD usa %USERNAME% NO funciona aqui,
            # hay que poner la ruta UNC con el nombre de usuario directamente.
            # Windows agrega automaticamente ".V6" al final para Windows 10/11
            # (version 6 del perfil), asi que ponemos la ruta SIN extension.
            $rutaPerfil = "$SHARE_UNC\$($u.Usuario)"

            Set-ADUser -Identity $u.Usuario `
                -ProfilePath $rutaPerfil `
                -ErrorAction Stop

            Write-Host "  [OK] $($u.Usuario) -> $rutaPerfil" -ForegroundColor Green
            $ok++
        } catch {
            Write-Host "  [ERROR] $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Red
            $errores++
        }
    }

    # Tambien asignar a los admins de la practica 09 si existen
    $adminsP9 = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    Write-Host "`n  Configurando admins de Practica 09 (si existen)..." -ForegroundColor Yellow
    foreach ($a in $adminsP9) {
        try {
            $existe = Get-ADUser $a -ErrorAction Stop
            $rutaPerfil = "$SHARE_UNC\$a"
            Set-ADUser -Identity $a -ProfilePath $rutaPerfil -ErrorAction Stop
            Write-Host "  [OK] $a -> $rutaPerfil" -ForegroundColor Green
            $ok++
        } catch {
            # Si no existe el usuario simplemente se omite
        }
    }

    Write-Host "`n  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | RESUMEN                                  |" -ForegroundColor Cyan
    Write-Host "  | Perfiles asignados: $ok" -ForegroundColor Green
    Write-Host "  | Errores           : $errores" -ForegroundColor Red
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "`n  IMPORTANTE - En el cliente Windows 10:" -ForegroundColor Yellow
    Write-Host "  1. gpupdate /force" -ForegroundColor White
    Write-Host "  2. Cerrar sesion completamente" -ForegroundColor White
    Write-Host "  3. Volver a iniciar sesion" -ForegroundColor White
    Write-Host "  4. Al cerrar sesion, Windows copiara el perfil al servidor" -ForegroundColor White
    Write-Host "  5. En el servidor veras una carpeta nueva en $CARPETA" -ForegroundColor White
    Write-Host "`n  Presiona Enter para continuar..."
    Read-Host | Out-Null
}


# ============================================================
# FUNCION 3: Verificar configuracion de perfiles moviles
# ============================================================
function Verificar-Perfiles {
    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   VERIFICAR PERFILES MOVILES               |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    # --- Verificar carpeta ---
    Write-Host "  [1/4] Carpeta local:" -ForegroundColor Yellow
    if (Test-Path $CARPETA) {
        Write-Host "  [PASS] $CARPETA existe." -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $CARPETA NO existe. Ejecuta Opcion 1." -ForegroundColor Red
    }

    # --- Verificar share ---
    Write-Host "`n  [2/4] Recurso compartido:" -ForegroundColor Yellow
    $share = Get-SmbShare -Name $SHARE_NAME -ErrorAction SilentlyContinue
    if ($share) {
        Write-Host "  [PASS] Share '$SHARE_NAME' activo en: $($share.Path)" -ForegroundColor Green
        $permisos = Get-SmbShareAccess -Name $SHARE_NAME
        $permisos | ForEach-Object {
            Write-Host "         $($_.AccountName): $($_.AccessRight)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [FAIL] Share '$SHARE_NAME' NO existe. Ejecuta Opcion 1." -ForegroundColor Red
    }

    # --- Verificar usuarios ---
    Write-Host "`n  [3/4] ProfilePath en AD por usuario:" -ForegroundColor Yellow
    if (Test-Path $CSV_PATH) {
        $usuarios = Import-Csv $CSV_PATH
        $sinPerfil = 0
        foreach ($u in $usuarios) {
            try {
                $adUser = Get-ADUser $u.Usuario -Properties ProfilePath -ErrorAction Stop
                if ($adUser.ProfilePath) {
                    Write-Host "  [OK] $($u.Usuario) -> $($adUser.ProfilePath)" -ForegroundColor Green
                } else {
                    Write-Host "  [WARN] $($u.Usuario) -> Sin ProfilePath asignado" -ForegroundColor Yellow
                    $sinPerfil++
                }
            } catch {
                Write-Host "  [WARN] $($u.Usuario): no encontrado en AD" -ForegroundColor Yellow
            }
        }
        if ($sinPerfil -gt 0) {
            Write-Host "  $sinPerfil usuario(s) sin perfil. Ejecuta Opcion 2." -ForegroundColor Yellow
        }
    }

    # --- Verificar permisos NTFS ---
    Write-Host "`n  [4/4] Permisos NTFS en $CARPETA`:" -ForegroundColor Yellow
    try {
        $acl = Get-Acl $CARPETA
        $acl.Access | ForEach-Object {
            $color = if ($_.AccessControlType -eq "Allow") { "DarkGreen" } else { "Red" }
            Write-Host "  $($_.AccessControlType): $($_.IdentityReference) - $($_.FileSystemRights)" -ForegroundColor $color
        }
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n  >>> CAPTURA ESTA PANTALLA como evidencia de configuracion <<<" -ForegroundColor Magenta
    Write-Host "`n  Presiona Enter para continuar..."
    Read-Host | Out-Null
}


# ============================================================
# FUNCION 4: Ver perfiles que ya se han guardado en el server
# ============================================================
function Ver-PerfilesAlmacenados {
    Write-Host "`n  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   PERFILES ALMACENADOS EN EL SERVIDOR      |" -ForegroundColor Cyan
    Write-Host "  +============================================+`n" -ForegroundColor Cyan

    if (-not (Test-Path $CARPETA)) {
        Write-Host "  [INFO] La carpeta $CARPETA no existe aun." -ForegroundColor Yellow
        Write-Host "         Los perfiles se crean la primera vez que el usuario" -ForegroundColor DarkGray
        Write-Host "         cierra sesion en el cliente Windows." -ForegroundColor DarkGray
        return
    }

    $carpetas = Get-ChildItem $CARPETA -ErrorAction SilentlyContinue
    if (-not $carpetas -or $carpetas.Count -eq 0) {
        Write-Host "  [INFO] No hay perfiles guardados aun." -ForegroundColor Yellow
        Write-Host "         Los perfiles aparecen aqui cuando el usuario" -ForegroundColor DarkGray
        Write-Host "         cierra sesion por primera vez en el cliente." -ForegroundColor DarkGray
        return
    }

    Write-Host "  Perfiles encontrados en $CARPETA`:" -ForegroundColor White
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor White
    Write-Host "  | Nombre                  | Tamano    | Ultima modificacion  |" -ForegroundColor White
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor White

    foreach ($c in $carpetas) {
        # Calcular tamano de la carpeta
        $tamanoBytes = (Get-ChildItem $c.FullName -Recurse -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        $tamanoMB = if ($tamanoBytes) { [math]::Round($tamanoBytes / 1MB, 2) } else { 0 }
        $fecha = $c.LastWriteTime.ToString("dd/MM/yyyy HH:mm")
        $linea = "  | {0,-23} | {1,7} MB | {2,-20} |" -f $c.Name, $tamanoMB, $fecha
        Write-Host $linea -ForegroundColor Green
    }
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor White
    Write-Host "`n  Total perfiles: $($carpetas.Count)" -ForegroundColor Cyan
    Write-Host "`n  NOTA: Windows 10 guarda el perfil como '<usuario>.V6'" -ForegroundColor DarkGray
    Write-Host "        Si ves '<usuario>.V6' el perfil movil esta funcionando." -ForegroundColor DarkGray
    Write-Host "`n  >>> CAPTURA ESTA PANTALLA como evidencia de perfiles activos <<<" -ForegroundColor Magenta
    Write-Host "`n  Presiona Enter para continuar..."
    Read-Host | Out-Null
}


# ---- INICIO ----
# Verificar que se ejecuta como Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n  [ERROR] Ejecuta como Administrador.`n" -ForegroundColor Red
    exit 1
}

Mostrar-Menu
