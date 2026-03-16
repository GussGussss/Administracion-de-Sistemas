# ============================================================
# verify_installation.ps1
# Verificacion automatizada de servicios
# Practica 07
# ============================================================

function Verificar-Servicios {

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " VERIFICACION DE SERVICIOS INSTALADOS" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host ""

    $resultados = @()

    # --------------------------------------------------------
    # VERIFICAR IIS
    # --------------------------------------------------------

    $iis = Get-Service W3SVC -ErrorAction SilentlyContinue

    if ($iis -and $iis.Status -eq "Running") {

        Write-Host "IIS activo." -ForegroundColor Green
        $resultados += "IIS .......... OK"

    }
    else {

        Write-Host "IIS no detectado." -ForegroundColor Yellow
        $resultados += "IIS .......... NO INSTALADO"

    }

    # --------------------------------------------------------
    # VERIFICAR APACHE
    # --------------------------------------------------------

    $apache = Get-Service Apache2.4 -ErrorAction SilentlyContinue

    if ($apache -and $apache.Status -eq "Running") {

        Write-Host "Apache activo." -ForegroundColor Green
        $resultados += "Apache ....... OK"

    }
    else {

        Write-Host "Apache no detectado." -ForegroundColor Yellow
        $resultados += "Apache ....... NO INSTALADO"

    }

    # --------------------------------------------------------
    # VERIFICAR NGINX
    # --------------------------------------------------------

    $nginx = Get-Process nginx -ErrorAction SilentlyContinue

    if ($nginx) {

        Write-Host "Nginx activo." -ForegroundColor Green
        $resultados += "Nginx ........ OK"

    }
    else {

        Write-Host "Nginx no detectado." -ForegroundColor Yellow
        $resultados += "Nginx ........ NO INSTALADO"

    }

    # --------------------------------------------------------
    # VERIFICAR FTP
    # --------------------------------------------------------

    $ftp = Get-Service ftpsvc -ErrorAction SilentlyContinue

    if ($ftp -and $ftp.Status -eq "Running") {

        Write-Host "FTP activo." -ForegroundColor Green
        $resultados += "FTP .......... OK"

    }
    else {

        Write-Host "FTP no detectado." -ForegroundColor Yellow
        $resultados += "FTP .......... NO INSTALADO"

    }

    # --------------------------------------------------------
    # VERIFICAR PUERTOS IMPORTANTES
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Verificando puertos..." -ForegroundColor Cyan

    $puertos = @(21,80,443)

    foreach ($p in $puertos) {

        $test = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue

        if ($test.TcpTestSucceeded) {

            Write-Host "Puerto $p abierto." -ForegroundColor Green

        }
        else {

            Write-Host "Puerto $p cerrado." -ForegroundColor Yellow

        }
    }

    # --------------------------------------------------------
    # RESUMEN FINAL
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " RESUMEN DE SERVICIOS" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    foreach ($r in $resultados) {

        Write-Host $r

    }

    Write-Host ""
}
