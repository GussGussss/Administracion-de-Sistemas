function validar-ip{
	param ([string]$IP)

    if ($IP -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$'){
        return $false
    }

    $octetos = $IP.Split('.')
    foreach ($o in $octetos){
        if ([int]$o -lt 0 -or [int]$o -gt 255){
            return $false
        }
    }

    if ($IP -eq "0.0.0.0" -or
        $IP -eq "255.255.255.255" -or
        $IP -eq "127.0.0.1"){
        return $false
    }

    return $true
}

function pedir-ip{
    param(
        [string]$mensaje,
        [bool]$opcional = $false
    )

    do{
        $ip = Read-Host $mensaje

        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)){
            return ""
        }

        if (-not (validar-ip $ip)){
            Write-Host "Esta mal: IP invalida"
        }

    }while (-not (validar-ip $ip))

	$ip = ($ip.Split('.') | ForEach-Object { [int]$_ }) -join '.'

    return $ip
}

function ip-a-entero($ip){
    $octetos = $ip.Split('.')
    return ([int]$octetos[0] -shl 24) -bor
           ([int]$octetos[1] -shl 16) -bor
           ([int]$octetos[2] -shl 8)  -bor
           ([int]$octetos[3])
}

function entero-a-ip($numero){
    return "$(($numero -shr 24) -band 255)." +
           "$(($numero -shr 16) -band 255)." +
           "$(($numero -shr 8) -band 255)." +
           "$($numero -band 255)"
}

function calcular-red {
    param($ip, $prefijo)

    $ipInt = ip-a-entero $ip
    $mascara = [uint32]([math]::Pow(2,32) - [math]::Pow(2,(32 - [int]$prefijo)))
    $redInt = $ipInt -band $mascara

    return entero-a-ip $redInt
}

function calcular-broadcast {
    param($red, $prefijo)

    $redInt = ip-a-entero $red
    $mascara = [uint32]([math]::Pow(2,32) - [math]::Pow(2,(32 - [int]$prefijo)))
    $broadcastInt = $redInt -bor (-bnot $mascara)

    return entero-a-ip $broadcastInt
}

function calcular-prefijo-desde-rango {
    param(
        [string]$ipInicio,
        [string]$ipFin
    )

    $ini = ip-a-entero $ipInicio
    $fin = ip-a-entero $ipFin

    $xor = $ini -bxor $fin

    $bits = 0
    while ($xor -gt 0) {
        $xor = $xor -shr 1
        $bits++
    }

    return 32 - $bits
}

function cambiar-ip-servidor{
    param(
        [string]$NuevaIP,
        [string]$Prefijo
    )

    Write-Host ""
    Write-Host "Cambiando IP del servidor a $NuevaIP..."

    $adaptador = Get-NetAdapter -Name "Ethernet 2"
    $ifIndex = $adaptador.ifIndex

    Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    New-NetIPAddress -InterfaceIndex $ifIndex -IPAddress $NuevaIP -PrefixLength $Prefijo

    Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ResetServerAddresses
    Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $NuevaIP

    Clear-DnsClientCache

    Write-Host "Nueva IP y DNS configurados correctamente."
}

function priorizar-red-interna {

    $interno = Get-NetAdapter -Name "Ethernet 2"
    $puente  = Get-NetAdapter -Name "Ethernet"

    if ($interno) {
        Set-NetIPInterface -InterfaceIndex $interno.ifIndex -InterfaceMetric 10
    }

    if ($puente) {
        Set-NetIPInterface -InterfaceIndex $puente.ifIndex -InterfaceMetric 50
    }

    Write-Host "Prioridad de red ajustada."
}
