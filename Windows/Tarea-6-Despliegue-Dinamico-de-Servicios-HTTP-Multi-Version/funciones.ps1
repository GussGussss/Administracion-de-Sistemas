# --- 1. VALIDACIONES ---
function Test-ValidarPuerto ($Puerto) {
    if ($Puerto -match '^\d+$') {
        $p = [int]$Puerto
        if ($p -lt 1 -or $p -gt 65535) { Write-Host "Puerto fuera de rango (1-65535)"; return $false }
        if ($p -in @(22, 25, 53, 3389)) { Write-Host "Puerto reservado por el sistema (SSH/RDP/DNS)"; return $false }
        
        $check = Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue
        if ($check) {
            Write-Host "El puerto $p ya está en uso por otro servicio" -ForegroundColor Red
            return $false
        }
        return $true
    }
    Write-Host "Entrada no válida: Debe ser un número" -ForegroundColor Red
    return $false
}

# --- 2. GESTIÓN DE VERSIONES (WINGET) ---
function Get-VersionesWinget ($Id) {
    try {
        $output = winget show $Id --versions
        $list = $output | Select-String -Pattern "\d+\.\d+(\.\d+)?" | ForEach-Object { $_.Matches.Value }
        return [PSCustomObject]@{
            Latest = $list[0]
            LTS    = $list[1]
        }
    } catch {
        return [PSCustomObject]@{ Latest = "Latest"; LTS = "Stable" }
    }
}

# --- 3. FIREWALL (CORREGIDO) ---
function Set-CustomFirewall ($Puerto) {
    Write-Host "Configurando Firewall para puerto $Puerto..." -ForegroundColor Gray
    # Se eliminó -Force porque no existe en este comando en Server 2019
    # Primero borramos si existe una regla previa con el mismo nombre para evitar duplicados
    Remove-NetFirewallRule -DisplayName "HTTP-Custom-$Puerto" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTP-Custom-$Puerto" -Direction Inbound -LocalPort $Puerto -Protocol TCP -Action Allow | Out-Null
}

# --- 4. CREAR INDEX PERSONALIZADO ---
function New-CustomIndex ($Servicio, $Version, $Puerto, $Path) {
    if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    $html = @"
<html>
<head><meta charset='UTF-8'><title>Servidor HTTP</title></head>
<body>
    <h1>Servidor: $Servicio</h1>
    <h2>Versión: $Version</h2>
    <h3>Puerto: $Puerto</h3>
</body>
</html>
"@
    $html | Out-File -FilePath "$Path\index.html" -Encoding utf8 -Force
}

# --- 5. INSTALACIÓN IIS (CORREGIDO) ---
function Install-IIS ($Version, $Puerto) {
    Write-Host "Iniciando despliegue silencioso de IIS..." -ForegroundColor Cyan
    
    # Instalación de característica
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    
    # Cargar módulo de administración
    Import-Module WebAdministration
    
    # Configurar Binding de puerto
    Write-Host "Configurando puerto $Puerto en IIS..."
    if (Test-Path "IIS:\Sites\Default Web Site") {
        Set-WebBinding -Name "Default Web Site" -BindingInformation "*:80:" -PropertyName Port -Value $Puerto
    } else {
        New-WebSite -Name "Default Web Site" -Port $Puerto -PhysicalPath "C:\inetpub\wwwroot" -Force | Out-Null
    }

    # SEGURIDAD (Hardening)
    Write-Host "Aplicando políticas de seguridad (Headers)..."
    $headerPath = "system.webServer/httpProtocol/customHeaders"
    
    # Quitar X-Powered-By de forma segura para evitar el WARNING
    $config = Get-WebConfigurationProperty -Filter $headerPath -Name "." -PSPath "IIS:\"
    if ($config.Collection | Where-Object { $_.name -eq "X-Powered-By" }) {
        Remove-WebConfigurationProperty -Filter $headerPath -Name "." -AtElement @{name='X-Powered-By'} -PSPath "IIS:\"
    }

    # Agregar Security Headers
    add-webconfigurationproperty -filter $headerPath -pspath "IIS:\" -name "." -value @{name='X-Frame-Options';value='SAMEORIGIN'} -ErrorAction SilentlyContinue
    add-webconfigurationproperty -filter $headerPath -pspath "IIS:\" -name "." -value @{name='X-Content-Type-Options';value='nosniff'} -ErrorAction SilentlyContinue

    # Firewall e Index
    Set-CustomFirewall $Puerto
    New-CustomIndex "IIS" $Version $Puerto "C:\inetpub\wwwroot"
    
    Restart-Service W3SVC
    Write-Host "IIS configurado correctamente en puerto $Puerto" -ForegroundColor Green
}

# --- 6. INSTALACIÓN APACHE (WINGET) ---
function Install-ApacheWin ($Version, $Puerto) {
    Write-Host "Instalando Apache $Version..." -ForegroundColor Cyan
    winget install --id ApacheFriends.XAMPP.8.2 --version $Version --silent --accept-package-agreements
    # Aquí puedes añadir la edición del httpd.conf similar al script de Linux
}

# --- 7. INSTALACIÓN NGINX (WINGET) ---
function Install-NginxWin ($Version, $Puerto) {
    Write-Host "Instalando Nginx $Version..." -ForegroundColor Cyan
    winget install --id nginx.nginx --version $Version --silent
    # Aquí puedes añadir la edición del nginx.conf similar al script de Linux
}
