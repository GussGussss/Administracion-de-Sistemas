validar_ip(){
	local ip=$1
	local expresionRegular="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
	if ! [[ $ip =~ $expresionRegular ]]; then
		return 1
	fi

	IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
	for octeto in $o1 $o2 $o3 $o4; do
		if ((octeto < 0 || octeto > 255)); then
			return 1
		fi
	done

	if [[ "$ip" == "0.0.0.0" || "$ip" == "255.255.255.255" || "$ip" == "127.0.0.1" || "$ip" == "127.0.0.0" ]]; then
		return 1
	fi

	return 0
}

validar_ip_rango(){
	local ip=$1
	IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
	for octeto in $o1 $o2 $o3 $o4; do
		if ((octeto < 0 || octeto > 255)); then
			return 1
		fi
	done
	return 0

}

pedir_ip(){
	local mensaje=$1
	local vacio=$2
	local ip

	while true; do
		read -p "$mensaje: " ip
		if [[ -z "$ip" && "$vacio" == "si" ]]; then
			echo ""
			return
		fi

		if validar_ip "$ip"; then
			echo "$ip"
			return
		else
			echo "Esta mal: IP invalida"
		fi
	done
}

ip_entero(){
	local ip=$1
	IFS='.' read -r a b c d <<< "$ip"
	echo $((a<<24 | b<<16 | c<< 8 | d))
}

entero_ip(){
	local entero=$1
	echo "$(( (entero>>24)&255 )).$(( (entero>>16)&255 )).$(( (entero>>8)&255 )).$(( entero&255 ))"
}
