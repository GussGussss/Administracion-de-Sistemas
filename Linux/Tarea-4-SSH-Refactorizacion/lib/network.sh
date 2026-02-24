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
