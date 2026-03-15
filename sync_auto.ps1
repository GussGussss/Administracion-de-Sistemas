# Forzar la ruta de Git en la sesión actual
$env:Path += ";C:\Program Files\Git\bin;C:\Program Files\Git\cmd"

Set-Location "C:\Users\Administrator\Administracion-de-Sistemas"

git pull origin main
git add .
$fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
git commit -m "Auto-sync Windows: $fecha"
git push origin main
