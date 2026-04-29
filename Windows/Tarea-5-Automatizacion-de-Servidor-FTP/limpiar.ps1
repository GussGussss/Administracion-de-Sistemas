# Eliminar sitio FTP completamente
Import-Module WebAdministration
Remove-WebSite "FTP_Servidor" -ErrorAction SilentlyContinue

# Borrar toda la carpeta ftp
Remove-Item "C:\ftp" -Recurse -Force -ErrorAction SilentlyContinue

# Crear estructura limpia
New-Item "C:\ftp" -ItemType Directory
New-Item "C:\ftp\general" -ItemType Directory
New-Item "C:\ftp\reprobados" -ItemType Directory
New-Item "C:\ftp\recursadores" -ItemType Directory
New-Item "C:\ftp\mina" -ItemType Directory

# Permisos simples - dar acceso total a todos los usuarios FTP en toda la raiz
icacls "C:\ftp" /grant "IUSR:(OI)(CI)F"
icacls "C:\ftp" /grant "IIS_IUSRS:(OI)(CI)F"
icacls "C:\ftp" /grant "mina:(OI)(CI)F"

# Crear sitio FTP nuevo simple
New-WebFtpSite -Name "FTP_Servidor" -Port 21 -PhysicalPath "C:\ftp" -Force

# Sin SSL
Set-ItemProperty "IIS:\Sites\FTP_Servidor" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\FTP_Servidor" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

# Autenticacion basica ON, anonima OFF por ahora
Set-ItemProperty "IIS:\Sites\FTP_Servidor" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $false
Set-ItemProperty "IIS:\Sites\FTP_Servidor" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

# Regla: permitir todo a todos
Add-WebConfiguration -Filter "system.ftpServer/security/authorization" -PSPath "IIS:\" -Location "FTP_Servidor" -Value @{accessType="Allow"; users="*"; permissions="Read,Write"}

Restart-Service ftpsvc
