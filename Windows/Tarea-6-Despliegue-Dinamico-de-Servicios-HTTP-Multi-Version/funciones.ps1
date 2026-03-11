# http_functions.ps1

# --- VALIDACIONES ---
function Test-PuertoValido {
    param([string]$Puerto)
    if ($Puerto -match '^\d+$') {
        $p = [int]$Puerto
        if ($p -lt 1 -or $p -gt 65535) { return $false }
        # Puertos reservados
        if ($p -eq 22 -or $p -eq 3389) { return $false }
        # Verificar si está en uso
        if (Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue) {
            Write-Host "Error: Puerto $p ya está en uso." -ForegroundColor Red
            return $false
        }
        return $true
    }
    return $false
}

# --- OBTENCIÓN DE VERSIONES (WINGET) ---
function Get-VersionesWinget {
    param($PackageId)
    # Winget devuelve texto, filtramos para obtener versiones
    $raw = winget show $PackageId --versions
    # Extraer las versiones usando Regex (simplificado para el ejemplo)
    $versiones = $raw | Select-String -Pattern "\d+\.\d+\.\d+"
    return $versiones
}

# --- INSTALACIÓN IIS ---
function Install-IIS {
    param($Puerto, $Version)
    Write-Host "Instalando/Configurando IIS..." -ForegroundColor Yellow
    
    # Instalación silenciosa de característica
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole, IIS-ManagementConsole -NoRestart
    
    Import-Module WebAdministration
    
    # Cambio de Puerto
    Set-WebBinding -Name "Default Web Site" -BindingInformation "*:80:" -PropertyName Port -Value $Puerto
    
    # Seguridad: Eliminar X-Powered-By
    Remove-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "system.webServer/httpProtocol/customHeaders" -Name "X-Powered-By"
    
    # Crear Index
    New-CustomIndex -Path "C:\inetpub\wwwroot" -Servicio "IIS" -Version $Version -Puerto $Puerto
    
    # Firewall
    New-NetFirewallRule -DisplayName "HTTP-Custom-IIS" -LocalPort $Puerto -Protocol TCP -Action Allow
}

# --- INSTALACIÓN APACHE/NGINX (VÍA WINGET) ---
function Install-NginxWin {
    param($Version, $Puerto)
    Write-Host "Instalando Nginx v$Version via Winget..." -ForegroundColor Yellow
    
    winget install nginx.nginx --version $Version --silent --accept-package-agreements
    
    # Lógica de edición de nginx.conf usando (Get-Content) -replace
    $confPath = "C:\tools\nginx\conf\nginx.conf" # Ruta típica de winget
    (Get-Content $confPath) -replace 'listen\s+80;', "listen $Puerto;" | Set-Content $confPath
    
    # Seguridad: Crear usuario y permisos NTFS
    # (En Windows Server Core se usan comandos como 'net user' e 'icacls')
    net user nginxsvc /add /active:yes
    icacls "C:\tools\nginx\html" /grant "nginxsvc:(OI)(CI)RX"
    
    New-NetFirewallRule -DisplayName "HTTP-Nginx" -LocalPort $Puerto -Protocol TCP -Action Allow
    Start-Process "C:\tools\nginx\nginx.exe"
}

# --- GENERADOR DE INDEX ---
function New-CustomIndex {
    param($Path, $Servicio, $Version, $Puerto)
    $html = @"
<html>
<head><title>Win Server</title></head>
<body>
    <h1>Servidor: $Servicio</h1>
    <h2>Version: $Version</h2>
    <h3>Puerto: $Puerto</h3>
</body>
</html>
"@
    $html | Out-File -FilePath "$Path\index.html" -Encoding utf8
}
