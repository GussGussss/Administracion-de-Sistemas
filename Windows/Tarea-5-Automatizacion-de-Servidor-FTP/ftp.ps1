$usuarioActual = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($usuarioActual)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "El script debe ejecutarse como Administrador :D"
    exit 1
}

function Configurar-Firewall {

    Write-Host "Configurando Firewall para FTP..."
    
    if (-not (Get-NetFirewallRule -DisplayName "FTP Puerto 21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -DisplayName "FTP Puerto 21" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 21 `
            -Action Allow
    }

    if (-not (Get-NetFirewallRule -DisplayName "FTP Pasivo 40000-40100" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -DisplayName "FTP Pasivo 40000-40100" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 40000-40100 `
            -Action Allow
    }

    Write-Host "Firewall configurado correctamente para FTP."
}

