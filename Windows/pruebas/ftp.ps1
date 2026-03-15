# ============================================================
# FTP SERVER ADMINISTRATOR - PROFESSIONAL VERSION
# Windows Server 2022 Core (No GUI)
# ============================================================

Import-Module ServerManager
Import-Module WebAdministration

$ftpRoot  = "C:\FTP"
$ftpSite  = "FTP_SERVER"
$logFile  = "C:\FTP\ftp_log.txt"

# ------------------------------------------------------------
# LOG
# ------------------------------------------------------------

function Write-Log {
    param($msg)
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content $logFile "$date - $msg"
}

# ------------------------------------------------------------
# INSTALL FTP
# ------------------------------------------------------------

function Install-FTP {

    Write-Host "Installing IIS + FTP..."

    $features = @(
        "Web-Server",
        "Web-FTP-Server",
        "Web-FTP-Service",
        "Web-FTP-Ext"
    )

    foreach ($f in $features) {
        if (!(Get-WindowsFeature $f).Installed) {
            Install-WindowsFeature $f -IncludeManagementTools
        }
    }

    Start-Service W3SVC
    Start-Service ftpsvc
    Set-Service ftpsvc -StartupType Automatic

    Write-Host "FTP installed successfully."
    Write-Log "FTP installed"
}

# ------------------------------------------------------------
# FIREWALL
# ------------------------------------------------------------

function Set-FTPFirewall {

    New-NetFirewallRule `
        -DisplayName "FTP Port 21" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 21 `
        -Action Allow `
        -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName "FTP Passive Ports" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 50000-51000 `
        -Action Allow `
        -ErrorAction SilentlyContinue

    Write-Host "Firewall rules configured."
    Write-Log "Firewall configured"
}

# ------------------------------------------------------------
# CREATE GROUPS
# ------------------------------------------------------------

function New-FTPGroups {

    $groups = @("failed", "retakers", "ftpusers")

    foreach ($g in $groups) {
        if (!(Get-LocalGroup $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup $g
            Write-Host "Group '$g' created."
        }
    }

    Write-Log "Groups created"
}

# ------------------------------------------------------------
# CREATE FOLDER STRUCTURE
# ------------------------------------------------------------

function New-FTPStructure {

    New-Item $ftpRoot                        -ItemType Directory -Force
    New-Item "$ftpRoot\general"              -ItemType Directory -Force
    New-Item "$ftpRoot\failed"               -ItemType Directory -Force
    New-Item "$ftpRoot\retakers"             -ItemType Directory -Force
    New-Item "$ftpRoot\Data\Users"           -ItemType Directory -Force
    New-Item "$ftpRoot\LocalUser\Public"     -ItemType Directory -Force

    cmd /c mklink /J "$ftpRoot\LocalUser\Public\general" "$ftpRoot\general"

    Write-Host "Folder structure created."
    Write-Log "FTP structure created"
}

# ------------------------------------------------------------
# PERMISSIONS
# ------------------------------------------------------------

function Set-FTPPermissions {

    # ROOT
    icacls $ftpRoot /inheritance:r
    icacls $ftpRoot /grant "Administrators:(OI)(CI)F"
    icacls $ftpRoot /grant "SYSTEM:(OI)(CI)F"
    icacls $ftpRoot /grant "IUSR:(RX)"

    # GENERAL (PUBLIC)
    icacls "$ftpRoot\general" /inheritance:r
    icacls "$ftpRoot\general" /grant "Administrators:(OI)(CI)F"
    icacls "$ftpRoot\general" /grant "SYSTEM:(OI)(CI)F"
    icacls "$ftpRoot\general" /grant "ftpusers:(OI)(CI)M"
    icacls "$ftpRoot\general" /grant "IUSR:(OI)(CI)RX"

    # FAILED
    icacls "$ftpRoot\failed" /inheritance:r
    icacls "$ftpRoot\failed" /grant "Administrators:(OI)(CI)F"
    icacls "$ftpRoot\failed" /grant "SYSTEM:(OI)(CI)F"
    icacls "$ftpRoot\failed" /grant "failed:(OI)(CI)M"

    # RETAKERS
    icacls "$ftpRoot\retakers" /inheritance:r
    icacls "$ftpRoot\retakers" /grant "Administrators:(OI)(CI)F"
    icacls "$ftpRoot\retakers" /grant "SYSTEM:(OI)(CI)F"
    icacls "$ftpRoot\retakers" /grant "retakers:(OI)(CI)M"

    Write-Host "Permissions applied successfully."
    Write-Log "Permissions set"
}

# ------------------------------------------------------------
# CONFIGURE FTP SITE
# ------------------------------------------------------------

function Set-FTPSite {

    if (Get-WebSite $ftpSite -ErrorAction SilentlyContinue) {
        Remove-WebSite $ftpSite
    }

    New-WebFtpSite `
        -Name $ftpSite `
        -Port 21 `
        -PhysicalPath $ftpRoot `
        -Force

    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.userIsolation.mode `
        -Value 3

    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled `
        -Value $true

    Set-ItemProperty "IIS:\Sites\$ftpSite" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled `
        -Value $true

    Clear-WebConfiguration `
        -Filter system.ftpServer/security/authorization `
        -PSPath IIS:\ `
        -Location $ftpSite

    Add-WebConfiguration `
        -Filter system.ftpServer/security/authorization `
        -PSPath IIS:\ `
        -Location $ftpSite `
        -Value @{accessType="Allow"; users="?"; permissions="Read"}

    Add-WebConfiguration `
        -Filter system.ftpServer/security/authorization `
        -PSPath IIS:\ `
        -Location $ftpSite `
        -Value @{accessType="Allow"; roles="ftpusers"; permissions="Read,Write"}

    Restart-Service ftpsvc

    Write-Host "FTP site configured."
    Write-Log "FTP site configured"
}

# ------------------------------------------------------------
# CREATE USER(S)
# ------------------------------------------------------------

function New-FTPUser {

    $count = Read-Host "How many users do you want to create?"

    for ($i = 1; $i -le $count; $i++) {

        Write-Host ""
        Write-Host "Creating user $i of $count"

        $username = Read-Host "Username"
        $pass     = Read-Host "Password" -AsSecureString
        $group    = Read-Host "Group (failed / retakers)"

        if ($group -ne "failed" -and $group -ne "retakers") {
            Write-Host "Invalid group. Skipping user."
            continue
        }

        if (Get-LocalUser $username -ErrorAction SilentlyContinue) {
            Write-Host "User '$username' already exists. Skipping."
            continue
        }

        New-LocalUser $username -Password $pass
        Add-LocalGroupMember -Group $group    -Member $username
        Add-LocalGroupMember -Group "ftpusers" -Member $username

        $userHome = "$ftpRoot\LocalUser\$username"

        New-Item $userHome                          -ItemType Directory -Force
        New-Item "$ftpRoot\Data\Users\$username"    -ItemType Directory -Force

        cmd /c mklink /J "$userHome\general"    "$ftpRoot\general"
        cmd /c mklink /J "$userHome\$group"     "$ftpRoot\$group"
        cmd /c mklink /J "$userHome\$username"  "$ftpRoot\Data\Users\$username"

        icacls "$ftpRoot\Data\Users\$username" /grant "${username}:(OI)(CI)F"

        Write-Log "User '$username' created in group '$group'"
    }

    Restart-Service ftpsvc
    Write-Host "User creation process completed."
}

# ------------------------------------------------------------
# DELETE USER
# ------------------------------------------------------------

function Remove-FTPUser {

    $username = Read-Host "Username to delete"

    Remove-LocalUser $username -ErrorAction SilentlyContinue

    Remove-Item "$ftpRoot\LocalUser\$username"   -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$ftpRoot\Data\Users\$username"  -Recurse -Force -ErrorAction SilentlyContinue

    Restart-Service ftpsvc

    Write-Host "User '$username' deleted."
    Write-Log "User '$username' deleted"
}

# ------------------------------------------------------------
# CHANGE GROUP
# ------------------------------------------------------------

function Set-UserGroup {

    $username = Read-Host "Username"
    $group    = Read-Host "New group (failed / retakers)"

    Remove-LocalGroupMember -Group "failed"   -Member $username -ErrorAction SilentlyContinue
    Remove-LocalGroupMember -Group "retakers" -Member $username -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $group     -Member $username

    $userHome = "$ftpRoot\LocalUser\$username"

    if (Test-Path "$userHome\failed")   { Remove-Item "$userHome\failed"   -Force }
    if (Test-Path "$userHome\retakers") { Remove-Item "$userHome\retakers" -Force }

    cmd /c mklink /J "$userHome\$group" "$ftpRoot\$group"

    # Server Core: iisreset is available but no GUI confirmation — just restart service
    Restart-Service ftpsvc

    Write-Host "Group changed to '$group' for user '$username'."
    Write-Log "User '$username' moved to group '$group'"
}

# ------------------------------------------------------------
# LIST USERS
# ------------------------------------------------------------

function Show-FTPUsers {

    Write-Host ""
    Write-Host "FTP Users:"
    Write-Host ""

    Get-LocalGroupMember "ftpusers" | ForEach-Object {
        $u = $_.Name.Split("\")[-1]
        Write-Host "  User: $u"
    }
}

# ------------------------------------------------------------
# RESTART FTP
# ------------------------------------------------------------

function Restart-FTP {
    Restart-Service ftpsvc
    Write-Host "FTP service restarted."
    Write-Log "FTP service restarted"
}

# ------------------------------------------------------------
# SERVER STATUS
# ------------------------------------------------------------

function Show-Status {

    Write-Host ""
    Write-Host "--- FTP Service Status ---"
    Get-Service ftpsvc

    Write-Host ""
    Write-Host "--- Port 21 ---"
    netstat -an | find ":21"
}

# ------------------------------------------------------------
# MENU
# ------------------------------------------------------------

function Show-Menu {

    while ($true) {

        Write-Host ""
        Write-Host "======== FTP ADMIN ========"
        Write-Host " 1  Install FTP"
        Write-Host " 2  Configure Firewall"
        Write-Host " 3  Create Groups"
        Write-Host " 4  Create Folder Structure"
        Write-Host " 5  Set Permissions"
        Write-Host " 6  Configure FTP Site"
        Write-Host " 7  Create User(s)"
        Write-Host " 8  Delete User"
        Write-Host " 9  Change User Group"
        Write-Host " 10 List Users"
        Write-Host " 11 Server Status"
        Write-Host " 12 Restart FTP"
        Write-Host " 0  Exit"
        Write-Host "==========================="

        $op = Read-Host "Option"

        switch ($op) {
            "1"  { Install-FTP }
            "2"  { Set-FTPFirewall }
            "3"  { New-FTPGroups }
            "4"  { New-FTPStructure }
            "5"  { Set-FTPPermissions }
            "6"  { Set-FTPSite }
            "7"  { New-FTPUser }
            "8"  { Remove-FTPUser }
            "9"  { Set-UserGroup }
            "10" { Show-FTPUsers }
            "11" { Show-Status }
            "12" { Restart-FTP }
            "0"  { break }
        }
    }
}

Show-Menu
