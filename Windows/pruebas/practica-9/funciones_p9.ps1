# ============================================================
#  funciones_p9.ps1 - Libreria de funciones para Practica 09
# ============================================================

# ------------------------------------------------------------
# FUNCION 1: Preparar Entorno y Descargar MFA
# ------------------------------------------------------------
function Preparar-EntornoMFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    PREPARAR ENTORNO Y DESCARGAR MFA      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"
    $archivoInstalador = "$rutaDescarga\multiOTP_CP_Installer.exe"
    # URL oficial directa del release de Github de multiOTP
    $urlMFA = "https://github.com/multiOTP/multiOTPCredentialProvider/releases/download/5.9.5.3/multiOTPCredentialProvider-5.9.5.3-x64-Release.exe"

    # 1. Crear carpeta si no existe
    if (-not (Test-Path $rutaDescarga)) {
        New-Item -Path $rutaDescarga -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $rutaDescarga" -ForegroundColor Green
    }

    # 2. Logica de validacion de descarga
    $procederDescarga = $true

    if (Test-Path $archivoInstalador) {
        Write-Host "  [AVISO] El instalador de MFA ya se encuentra descargado en el sistema." -ForegroundColor Yellow
        $respuesta = Read-Host "  Deseas volver a descargarlo y sobreescribirlo? (s/n)"
        
        if ($respuesta.ToLower() -ne 's') {
            $procederDescarga = $false
            Write-Host "  [OK] Omitiendo descarga del instalador..." -ForegroundColor Green
        }
    }

    # 3. Descargar si es necesario
    if ($procederDescarga) {
        Write-Host "  [INFO] Descargando multiOTP Credential Provider. Esto puede tomar un momento..." -ForegroundColor Cyan
        try {
            # === CORRECCION APLICADA: Forzar protocolo TLS 1.2 para GitHub ===
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            # Se usa UseBasicParsing porque Server Core no tiene Internet Explorer engine
            Invoke-WebRequest -Uri $urlMFA -OutFile $archivoInstalador -UseBasicParsing
            Write-Host "  [OK] Descarga completada exitosamente." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Fallo la descarga. Verifica que el servidor tenga salida a internet." -ForegroundColor Red
            Write-Host "  Detalle: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Pause | Out-Null
}
# ------------------------------------------------------------
# FUNCION 2: Crear Usuarios de Administracion (Sin permisos aun)
# ------------------------------------------------------------
function Crear-UsuariosAdmin {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    CREACION DE USUARIOS ADMINISTRATIVOS  |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    # Lista de usuarios a crear basada en tu practica
    $usuarios = @(
        @{ User = "admin_identidad"; Nombre = "Admin"; Apellido = "Identidad" },
        @{ User = "admin_storage";   Nombre = "Admin"; Apellido = "Storage" },
        @{ User = "admin_politicas"; Nombre = "Admin"; Apellido = "Politicas" },
        @{ User = "admin_auditoria"; Nombre = "Admin"; Apellido = "Auditoria" }
    )

    # Vamos a usar una contrasena generica que cumpla la complejidad de Windows Server
    $pwdTexto = "Hardening2026!" 
    $pwdSegura = ConvertTo-SecureString $pwdTexto -AsPlainText -Force

    $creados = 0
    $omitidos = 0

    foreach ($u in $usuarios) {
        # Verificar si existe
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.User)'" -ErrorAction SilentlyContinue
        
        if ($existe) {
            Write-Host "  [OMITIDO] El usuario '$($u.User)' ya existe." -ForegroundColor Yellow
            $omitidos++
        } else {
            try {
                New-ADUser -Name "$($u.Nombre) $($u.Apellido)" `
                           -GivenName $($u.Nombre) `
                           -Surname $($u.Apellido) `
                           -SamAccountName $($u.User) `
                           -UserPrincipalName "$($u.User)@practica8.local" `
                           -AccountPassword $pwdSegura `
                           -Enabled $true `
                           -PasswordNeverExpires $true

                Write-Host "  [OK] Usuario '$($u.User)' creado exitosamente. (Pass: $pwdTexto)" -ForegroundColor Green
                $creados++
            } catch {
                Write-Host "  [ERROR] No se pudo crear a '$($u.User)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Resumen: $creados creados, $omitidos ya existian." -ForegroundColor White
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Pause | Out-Null
}

# ------------------------------------------------------------
# FUNCION 3: Aplicar Permisos RBAC y Delegacion
# ------------------------------------------------------------
function Aplicar-PermisosRBAC {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    APLICAR PERMISOS RBAC Y DELEGACION    |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] El servidor no es Domain Controller o no hay conexion a AD." -ForegroundColor Red
        Pause | Out-Null
        return
    }

    $dcBase  = $dominio.DistinguishedName
    $netbios = $dominio.NetBIOSName

    # =========================================================
    # ROL 1: Operador de Identidad (admin_identidad)
    # Tareas: Gestion total sobre objetos 'user' en OUs Cuates y NoCuates
    # =========================================================
    Write-Host "  Configurando Rol 1: admin_identidad..." -ForegroundColor Yellow
    # /I:T significa "Inherit To All Subobjects" (heredar a todo). 
    # GA = Generic All (Control Total), pero restringido EXCLUSIVAMENTE a la clase ;user
    dsacls "OU=Cuates,$dcBase" /I:T /G "$netbios\admin_identidad:GA;;user" | Out-Null
    dsacls "OU=NoCuates,$dcBase" /I:T /G "$netbios\admin_identidad:GA;;user" | Out-Null
    Write-Host "  [OK] admin_identidad: Control total sobre usuarios en OUs asignado." -ForegroundColor Green

    # =========================================================
    # ROL 2: Operador de Almacenamiento (admin_storage)
    # Restriccion: DENEGAR permiso de Resetear Contrasenas
    # =========================================================
    Write-Host "`n  Configurando Rol 2: admin_storage..." -ForegroundColor Yellow
    # /D es Deny (Denegar). CA es Control Access.
    # Esta regla se aplica a la raiz del dominio y se hereda hacia abajo, bloqueando el Reset.
    dsacls "$dcBase" /I:S /D "$netbios\admin_storage:CA;Reset Password;user" | Out-Null
    Write-Host "  [OK] admin_storage: DENEGADO explicito para Resetear Contrasenas (Test 1 listo)." -ForegroundColor Green

    # =========================================================
    # ROL 3: Admin de Politicas (admin_politicas)
    # Tareas: Modificar GPOs existentes y vincularlas
    # =========================================================
    Write-Host "`n  Configurando Rol 3: admin_politicas..." -ForegroundColor Yellow
    # 1. Agregarlo al grupo nativo para que pueda editar objetos GPO (Group Policy Creator Owners)
    try {
        Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members "admin_politicas" -ErrorAction Stop
        Write-Host "  [OK] admin_politicas: Agregado a 'Group Policy Creator Owners'." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] admin_politicas ya pertenece a 'Group Policy Creator Owners' o hubo un problema." -ForegroundColor DarkGray
    }
    
    # 2. Darle permiso para Vincular (Link) GPOs en las OUs. gPLink es el atributo que controla esto.
    dsacls "OU=Cuates,$dcBase" /I:T /G "$netbios\admin_politicas:RPWP;gPLink" | Out-Null
    dsacls "OU=NoCuates,$dcBase" /I:T /G "$netbios\admin_politicas:RPWP;gPLink" | Out-Null
    Write-Host "  [OK] admin_politicas: Permiso para vincular GPOs a OUs asignado." -ForegroundColor Green

    # =========================================================
    # ROL 4: Auditor de Seguridad (admin_auditoria)
    # Tareas: Lectura de logs (Security Logs). Sin permisos de escritura.
    # =========================================================
    Write-Host "`n  Configurando Rol 4: admin_auditoria..." -ForegroundColor Yellow
    # El grupo nativo 'Event Log Readers' permite leer los Eventos de Seguridad sin ser admin.
    try {
        Add-ADGroupMember -Identity "Event Log Readers" -Members "admin_auditoria" -ErrorAction Stop
        Write-Host "  [OK] admin_auditoria: Agregado a 'Event Log Readers'." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] admin_auditoria ya pertenece a 'Event Log Readers'." -ForegroundColor DarkGray
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Pause | Out-Null
}
