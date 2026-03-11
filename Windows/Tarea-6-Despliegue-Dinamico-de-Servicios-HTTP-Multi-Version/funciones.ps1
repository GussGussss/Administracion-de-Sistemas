# http_functions.ps1

# --- VALIDACIONES ---
function Test-ValidarPuerto ($Puerto) {
    if ($Puerto -match '^\d+$') {
        $p = [int]$Puerto
        if ($p -lt 1 -or $p -gt 65535) { Write-Host "Rango inválido"; return $false }
        if ($p -in @(22, 25, 53, 3389)) { Write-Host "Puerto reservado"; return $false }
        
        # Validar si el puerto está en uso
        if (Test-NetConnection -ComputerName localhost -Port $p -InformationLevel Quiet) {
            Write-Host "Error: Puerto $p ya está en uso." -ForegroundColor Red
            return $false
        }
        return $true
    }
    return $false
}

# --- GESTIÓN DE VERSIONES (WINGET) ---
function Get-VersionesWinget ($Id) {
    # Winget devuelve strings, parseamos para obtener la versión
    $output = winget show $Id --versions
    # Lógica simplificada para extraer versiones de la tabla de winget
    $list = $output | Select-String -Pattern "\d+\.\d+(\.\d+)?" | ForEach-Object { $_.Matches.Value }
    return [PSCustomObject]@{
        Latest = $list[0]
        LTS    = $list[1]
    }
}

# --- FIREWALL ---
function Set-CustomFirewall ($Puerto) {
    Write-Host "Configurando Firewall para puerto $Puerto..."
    New-NetFirewallRule -DisplayName "HTTP-Custom-$Puerto" -Direction Inbound -LocalPort $Puerto -Protocol TCP -Action Allow -Force
}

# --- CREAR INDEX PERSONALIZADO ---
function New-CustomIndex ($Servicio, $Version, $Puerto, $Path) {
    if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force }
    $html = @"
<html>
<head><title>Servidor HTTP Windows</title></head>
<body>
    <h1>Servidor: $Servicio</h1>
    <h2>Versión: $Version</h2>
    <h3>Puerto: $Puerto</h3>
</body>
</html>
"@
    $html | Out-File -FilePath "$Path\index.html" -Encoding utf8
}

function Install-IIS ($Version, $Puerto) {
    Write-Host "Instalando IIS (Instalación Silenciosa)..." -ForegroundColor Cyan
    # Instalación silenciosa del rol
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools > $null
    
    # Forzar la importación del módulo de administración de IIS
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Cambiar puerto (Binding) - Se asegura de que el sitio exista antes de cambiarlo
    if (Test-Path "IIS:\Sites\Default Web Site") {
        Set-WebBinding -Name "Default Web Site" -BindingInformation "*:80:" -PropertyName Port -Value $Puerto
    } else {
        # Si por alguna razón no existe el default, se crea con el puerto nuevo
        New-WebSite -Name "Default Web Site" -Port $Puerto -PhysicalPath "C:\inetpub\wwwroot" -Force
    }
    
    # --- Seguridad: Hardening ---
    # Eliminar X-Powered-By
    Get-WebConfigurationProperty -Filter "system.webServer/httpProtocol/customHeaders" -PSPath "IIS:\" -Name "." | 
        Where-Object { $_.Name -eq "X-Powered-By" } | 
        Remove-WebConfigurationProperty -Filter "system.webServer/httpProtocol/customHeaders" -PSPath "IIS:\" -Name "."

    # Agregar Security Headers (X-Frame y X-Content)
    $configPath = "system.webServer/httpProtocol/customHeaders"
    add-webconfigurationproperty -filter $configPath -pspath "IIS:\" -name "." -value @{name='X-Frame-Options';value='SAMEORIGIN'} -ErrorAction SilentlyContinue
    add-webconfigurationproperty -filter $configPath -pspath "IIS:\" -name "." -value @{name='X-Content-Type-Options';value='nosniff'} -ErrorAction SilentlyContinue

    # Firewall y Index
    Set-CustomFirewall $Puerto
    New-CustomIndex "IIS" $Version $Puerto "C:\inetpub\wwwroot"
    
    Restart-Service W3SVC
    Write-Host "INSTALACIÓN COMPLETADA: IIS en puerto $Puerto" -ForegroundColor Green
}
# --- INSTALACIÓN APACHE (WINGET) ---
function Install-ApacheWin ($Version, $Puerto) {
    Write-Host "Instalando Apache $Version vía Winget..." -ForegroundColor Cyan
    winget install --id ApacheFriends.XAMPP.8.2 --version $Version --silent --accept-package-agreements
    
    $confPath = "C:\xampp\apache\conf\httpd.conf"
    if (Test-Path $confPath) {
        # Cambiar puerto
        (Get-Content $confPath) -replace "Listen 80", "Listen $Puerto" | Set-Content $confPath
        
        # Hardening
        Add-Content $confPath "`nServerTokens Prod`nServerSignature Off"
        
        Set-CustomFirewall $Puerto
        New-CustomIndex "Apache-Win" $Version $Puerto "C:\xampp\htdocs"
        # Reiniciar servicio si existe
        Restart-Service -Name "Apache*" -ErrorAction SilentlyContinue
    }
}

# --- INSTALACIÓN NGINX (WINGET) ---
function Install-NginxWin ($Version, $Puerto) {
    Write-Host "Instalando Nginx $Version..." -ForegroundColor Cyan
    winget install --id nginx.nginx --version $Version --silent
    
    # Nota: Winget suele instalar en C:\Program Files o similar
    # Requiere ajuste manual de ruta según instalación de winget
    $nginxPath = "C:\nginx" 
    $confPath = "$nginxPath\conf\nginx.conf"
    
    if (Test-Path $confPath) {
        (Get-Content $confPath) -replace "listen\s+80;", "listen $Puerto;" | Set-Content $confPath
        # Ocultar versión
        (Get-Content $confPath) -replace "#server_tokens off;", "server_tokens off;" | Set-Content $confPath
        
        Set-CustomFirewall $Puerto
        New-CustomIndex "Nginx-Win" $Version $Puerto "$nginxPath\html"
    }
}
