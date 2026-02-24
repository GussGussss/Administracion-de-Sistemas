instalar_kea(){
	echo ""
	echo "Verificando si el servicio DHCP (KEA) está instalado..."

	if rpm -q kea &>/dev/null; then
		echo "El servicio DHCP ya está instalado."

		while true; do
			read -p "¿Desea reinstalarlo? (s/n): " opcion

			case $opcion in
				s|S)
					echo "Reinstalando KEA..."
					sudo dnf reinstall -y kea > /dev/null 2>&1
					echo "Reinstalación completada."
					break
					;;
				n|N)
					echo "No se realizará ninguna acción."
					break
					;;
				*)
					echo "Opción inválida. Escriba s o n."
					;;
			esac
		done

	else
		echo "El servicio DHCP no está instalado."
		echo "Instalando KEA..."
		sudo dnf install -y kea > /dev/null 2>&1

		if rpm -q kea &>/dev/null; then
			echo "Instalación completada correctamente."
		else
			echo "Hubo un error en la instalación."
		fi
	fi

	read -p "Presiona ENTER para continuar..."
}
