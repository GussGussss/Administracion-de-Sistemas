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

    # 1. Crear carpeta si no existe
    if (-not (Test-Path $rutaDescarga)) {
        New-Item -Path $rutaDescarga -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $rutaDescarga" -ForegroundColor Green
    }

    # 2. Logica de validacion de descarga (CORREGIDA PARA ZIPS)
    $procederDescarga = $true
    $archivosExistentes = Get-ChildItem -Path $rutaDescarga -Filter "multiOTP*" -ErrorAction SilentlyContinue

    if ($archivosExistentes) {
        Write-Host "  [AVISO] Ya existen archivos de multiOTP descargados en el servidor." -ForegroundColor Yellow
        $respuesta = Read-Host "  Deseas conectarte a internet para descargar la ultima version? (s/n)"
        
        if ($respuesta.ToLower() -ne 's') {
            $procederDescarga = $false
            Write-Host "  [OK] Omitiendo descarga. Se usaran los archivos locales (No requiere internet)." -ForegroundColor Green
        }
    }

    # 3. Descargar si es necesario
    if ($procederDescarga) {
        Write-Host "  [INFO] Conectando a la API de GitHub para buscar la ultima version..." -ForegroundColor Cyan
        
        # Forzar protocolos de seguridad modernos (TLS 1.2)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        try {
            $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell" }
            
            # PLAN DINAMICO: Preguntar a GitHub cual es la version más nueva
            $apiUrl = "https://api.github.com/repos/multiOTP/multiOTPCredentialProvider/releases/latest"
            $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing
            
            # Buscar el archivo descargable (.zip o .exe) dentro del release
            $asset = $release.assets | Where-Object { $_.name -like "*.zip" -or $_.name -like "*.exe" } | Select-Object -First 1
            
            if (-not $asset) {
                Write-Host "  [ERROR] No se encontraron instaladores en la ultima version." -ForegroundColor Red
                return
            }

            $urlDinamica = $asset.browser_download_url
            $nombreArchivo = $asset.name
            $rutaArchivo = "$rutaDescarga\$nombreArchivo"

            Write-Host "  [INFO] Descargando $($release.tag_name) ($nombreArchivo)..." -ForegroundColor Yellow
            
            # Descargar el archivo real
            Invoke-WebRequest -Uri $urlDinamica -OutFile $rutaArchivo -UseBasicParsing -Headers $headers
            
            # Si el desarrollador subio un .zip (como lo hacen ahora), lo extraemos automaticamente
            if ($rutaArchivo.EndsWith(".zip")) {
                Write-Host "  [INFO] Archivo ZIP detectado. Extrayendo contenido en $rutaDescarga..." -ForegroundColor Yellow
                Expand-Archive -Path $rutaArchivo -DestinationPath $rutaDescarga -Force
                Write-Host "  [OK] Descarga y extraccion completada exitosamente." -ForegroundColor Green
            } else {
                Write-Host "  [OK] Descarga completada exitosamente." -ForegroundColor Green
            }

        } catch {
            Write-Host "  [ERROR] Fallo la descarga desde la API de GitHub." -ForegroundColor Red
            Write-Host "  Detalle final: $($_.Exception.Message)" -ForegroundColor Red
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

# ------------------------------------------------------------
# FUNCION 4: Configurar Directivas de Contrasena (FGPP)
# ------------------------------------------------------------
function Configurar-FGPP {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    CONFIGURAR DIRECTIVAS FGPP (PSOs)     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    try {
        Get-ADDomain -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  [ERROR] El servidor no es DC o AD no responde." -ForegroundColor Red
        Pause | Out-Null
        return
    }

    # =========================================================
    # POLITICA 1: ADMINISTRADORES (12 Caracteres)
    # =========================================================
    Write-Host "  Creando directiva estricta para Administradores (12 caracteres)..." -ForegroundColor Yellow
    $fgppAdmin = "Practica09-FGPP-Admins"
    
    try {
        # CORRECCION: Usar -Filter en lugar de -Identity para evitar errores si no existe
        $existeAdmin = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppAdmin'"
        
        if ($existeAdmin) {
            Write-Host "  [OK] La directiva '$fgppAdmin' ya existe." -ForegroundColor Yellow
        } else {
            New-ADFineGrainedPasswordPolicy -Name $fgppAdmin `
                -DisplayName "FGPP Alta Seguridad Administradores" `
                -Precedence 10 `
                -ComplexityEnabled $true `
                -ReversibleEncryptionEnabled $false `
                -PasswordHistoryCount 5 `
                -MinPasswordLength 12 `
                -MinPasswordAge "1.00:00:00" `
                -MaxPasswordAge "90.00:00:00" `
                -LockoutThreshold 5 `
                -LockoutObservationWindow "00:15:00" `
                -LockoutDuration "00:30:00"
            Write-Host "  [CREADO] Directiva '$fgppAdmin' generada." -ForegroundColor Green
        }

        # Aplicar la directiva a los usuarios admin
        $sujetosAdmin = @("Domain Admins", "admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")
        foreach ($sujeto in $sujetosAdmin) {
            try {
                Add-ADFineGrainedPasswordPolicySubject -Identity $fgppAdmin -Subjects $sujeto -ErrorAction Stop
                Write-Host "    -> Aplicada a: $sujeto" -ForegroundColor DarkGreen
            } catch {
                # Ignorar error si ya esta aplicada
            }
        }
    } catch {
        Write-Host "  [ERROR] Fallo al configurar FGPP Admins: $($_.Exception.Message)" -ForegroundColor Red
    }

    # =========================================================
    # POLITICA 2: USUARIOS ESTANDAR (8 Caracteres)
    # =========================================================
    Write-Host "`n  Creando directiva base para Estandar (8 caracteres)..." -ForegroundColor Yellow
    $fgppStd = "Practica09-FGPP-Standard"
    
    try {
        # CORRECCION: Usar -Filter en lugar de -Identity
        $existeStd = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppStd'"
        
        if ($existeStd) {
            Write-Host "  [OK] La directiva '$fgppStd' ya existe." -ForegroundColor Yellow
        } else {
            New-ADFineGrainedPasswordPolicy -Name $fgppStd `
                -DisplayName "FGPP Estandar Cuates y NoCuates" `
                -Precedence 20 `
                -ComplexityEnabled $true `
                -ReversibleEncryptionEnabled $false `
                -PasswordHistoryCount 3 `
                -MinPasswordLength 8 `
                -MinPasswordAge "1.00:00:00" `
                -MaxPasswordAge "90.00:00:00" `
                -LockoutThreshold 5 `
                -LockoutObservationWindow "00:15:00" `
                -LockoutDuration "00:30:00"
            Write-Host "  [CREADO] Directiva '$fgppStd' generada." -ForegroundColor Green
        }

        # Aplicar a las OUs/Grupos de Cuates y NoCuates
        $sujetosStd = @("Cuates", "NoCuates")
        foreach ($sujeto in $sujetosStd) {
            try {
                Add-ADFineGrainedPasswordPolicySubject -Identity $fgppStd -Subjects $sujeto -ErrorAction Stop
                Write-Host "    -> Aplicada al grupo: $sujeto" -ForegroundColor DarkGreen
            } catch {
                # Ignorar error si ya esta aplicada
            }
        }
    } catch {
        Write-Host "  [ERROR] Fallo al configurar FGPP Standard: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Pause | Out-Null
}


# ------------------------------------------------------------
# FUNCION 6: Instalar y Activar MFA (Google Authenticator)
# ------------------------------------------------------------
function Instalar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    INSTALAR Y ACTIVAR MULTI-FACTOR MFA   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"
    
    # =========================================================
    # PASO 1: INSTALAR DEPENDENCIA (Visual C++ 2022 Redistributable)
    # =========================================================
    Write-Host "  [1/3] Verificando pre-requisitos (Visual C++ Redistributable)..." -ForegroundColor Yellow
    # CORRECCION: Usar enlace a VS 2022 (v17) para satisfacer el requisito 14.44+ de PHP
    $vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $vcRedistPath = "$rutaDescarga\vc_redist_2022_x64.exe" # Nombre nuevo para forzar descarga
    
    if (-not (Test-Path $vcRedistPath)) {
        Write-Host "  [INFO] Descargando VC++ 2022 Redistributable..." -ForegroundColor Cyan
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $vcRedistUrl -OutFile $vcRedistPath -UseBasicParsing
        } catch {
            Write-Host "  [ERROR] Fallo la descarga de VC++: $($_.Exception.Message)" -ForegroundColor Red
            Pause | Out-Null
            return
        }
    }
    
    Write-Host "  [INFO] Instalando VC++ 2022 silenciosamente..." -ForegroundColor Cyan
    $procVC = Start-Process -FilePath $vcRedistPath -ArgumentList "/install /quiet /norestart" -Wait -PassThru
    if ($procVC.ExitCode -in @(0, 1638, 3010)) {
        Write-Host "  [OK] VC++ 2022 Redistributable listo." -ForegroundColor Green
    } else {
        Write-Host "  [AVISO] VC++ termino con codigo $($procVC.ExitCode). Podria fallar el MFA." -ForegroundColor Yellow
    }

    # Darle tiempo a Windows de registrar la nueva DLL 14.44
    Start-Sleep -Seconds 3

    # =========================================================
    # PASO 2: EXTRAER E INSTALAR MULTIOTP
    # =========================================================
    Write-Host "`n  [2/3] Preparando instalador de multiOTP..." -ForegroundColor Yellow
    $archivosZip = Get-ChildItem -Path $rutaDescarga -Filter "*.zip" -ErrorAction SilentlyContinue
    
    foreach ($zip in $archivosZip) {
        $rutaDestinoZip = "$rutaDescarga\Extracted_$($zip.BaseName)"
        if (-not (Test-Path $rutaDestinoZip)) {
            Expand-Archive -Path $zip.FullName -DestinationPath $rutaDestinoZip -Force
        }
    }

    $instaladores = Get-ChildItem -Path $rutaDescarga -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match "\.(exe|msi)$" -and $_.Name -notmatch "vc_redist" } | Sort-Object Length -Descending
    $instalador = $instaladores | Select-Object -First 1
    
    if (-not $instalador) {
        Write-Host "  [ERROR] No se encontro el instalador de multiOTP." -ForegroundColor Red
        Pause | Out-Null
        return
    }

    Write-Host "  [INFO] Instalando $($instalador.Name) en modo silencioso..." -ForegroundColor Cyan
    try {
        if ($instalador.Extension -eq ".msi") {
            $argumentos = "/i `"$($instalador.FullName)`" /qn"
            $procesoInstalacion = Start-Process -FilePath "msiexec.exe" -ArgumentList $argumentos -Wait -PassThru
        } else {
            $procesoInstalacion = Start-Process -FilePath $instalador.FullName -ArgumentList "/S" -Wait -PassThru
        }
        
        if ($procesoInstalacion.ExitCode -eq 0) {
            Write-Host "  [OK] MFA instalado correctamente en el sistema." -ForegroundColor Green
        } else {
            Write-Host "  [AVISO] El instalador MFA termino con codigo $($procesoInstalacion.ExitCode)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [ERROR] Fallo instalacion MFA: $($_.Exception.Message)" -ForegroundColor Red
        Pause | Out-Null
        return
    }

    Start-Sleep -Seconds 5

    # =========================================================
    # PASO 3: RASTREAR MOTOR Y CONFIGURAR ADMINISTRADOR
    # =========================================================
    Write-Host "`n  [3/3] Buscando motor de configuracion (multiotp.exe)..." -ForegroundColor Yellow
    
    $exeMultiOTP = $null
    $rutasBuscar = @("C:\Program Files", "C:\multiOTP", "C:\Program Files (x86)")
    
    foreach ($ruta in $rutasBuscar) {
        if (Test-Path $ruta) {
            $encontrado = Get-ChildItem -Path $ruta -Filter "multiotp.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($encontrado) {
                $exeMultiOTP = $encontrado.FullName
                Write-Host "  [OK] Motor encontrado en: $exeMultiOTP" -ForegroundColor Green
                break
            }
        }
    }

    if (-not $exeMultiOTP) {
        Write-Host "  [ERROR] No se encontro multiotp.exe despues de la instalacion." -ForegroundColor Red
        Pause | Out-Null
        return
    }

    Write-Host "`n  Configurando MFA para Administrator..." -ForegroundColor Yellow
    $usuarioMFA = "Administrator"
    
try {
        # Viajar a la carpeta de multiOTP
        $directorioBase = Split-Path $exeMultiOTP
        Push-Location $directorioBase

        Write-Host "  [INFO] Evadiendo bug de Active Directory. Forzando inyeccion manual..." -ForegroundColor DarkGray
        
        # 0. Generar nuestro propio secreto matematico (Base32 de 16 caracteres)
        $alfabeto = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        $miSecreto = -join ((1..16) | ForEach-Object { $alfabeto[(Get-Random -Maximum $alfabeto.Length)] })

        # 1. Limpiar rastro viejo
        & ".\multiotp.exe" -delete $usuarioMFA 2>&1 | Out-Null
        
        # 2. Obligar a multiOTP a tragarse nuestro secreto
        & ".\multiotp.exe" -create $usuarioMFA 2>&1 | Out-Null
        & ".\multiotp.exe" -set $usuarioMFA algorithm=TOTP 2>&1 | Out-Null
        & ".\multiotp.exe" -fastcreatenopin $usuarioMFA $miSecreto 2>&1 | Out-Null
        & ".\multiotp.exe" -set $usuarioMFA totpsecret=$miSecreto 2>&1 | Out-Null
        
        # Regresar a la carpeta original
        Pop-Location

        Write-Host "`n  +-------------------------------------------------------------+" -ForegroundColor Magenta
        Write-Host "  |  ATENCION: ABRE GOOGLE AUTHENTICATOR EN TU CELULAR          |" -ForegroundColor Magenta
        Write-Host "  +-------------------------------------------------------------+" -ForegroundColor Magenta
        
        Write-Host "`n  Como el sistema bloqueaba el QR, hemos generado una clave maestra manualmente." -ForegroundColor Yellow
        Write-Host "  En tu app de Google Authenticator:" -ForegroundColor White
        Write-Host "  1. Presiona el boton '+' (Agregar un codigo)" -ForegroundColor White
        Write-Host "  2. Selecciona 'Ingresar clave de configuracion' (Enter setup key)" -ForegroundColor White
        Write-Host "  3. Escribe los siguientes datos:`n" -ForegroundColor White
        
        Write-Host "     Nombre de la cuenta : Administrador" -ForegroundColor Cyan
        Write-Host "     Llave / Secreto     : $miSecreto" -ForegroundColor Green
        Write-Host "     Tipo de llave       : Basada en tiempo (Time based)`n" -ForegroundColor Cyan
        
        Write-Host "  IMPORTANTE: Agregalo a tu celular ANTES de cerrar sesion." -ForegroundColor Red
        
    } catch {
        Write-Host "  [ERROR] Fallo configuracion de usuario: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Pause | Out-Null
}
