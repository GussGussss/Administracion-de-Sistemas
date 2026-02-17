instalar_dns(){
	echo ""
	echo "Verificando si DNS (BIND) esta instalado...."

	if rpm -q bind &>/dev/null; then
		echo "El servicio DNS (BIND) ya esta instalado"
	else
		echo "instalando DNS (BIND)...."
		sudo dnf install -y bind bind-utils
		echo "instalacion completada"
	fi

	sudo systemctl enable named
	sudo systemctl start name

	read -p "presiona ENTER para continuar"
}

estado_dns(){
	echo ""
	echo "***** Estado del servicio DNS (BIND) *****"
	if systemctl is-active --quiet named; then
		echo "Servicio DNS (BIND) activo"
	else
		echo "Servicio DNS (BIND) no activo"
	fi
	read -p "Pesiona ENTER para continuar"
}

crear_dominio_principal(){
	dominio="reprobados.com"
	zona_file="/var/named/$dominio.db"

	if grep -q "$dominio" /etc/named.rfc1912.zones; then
		echo "El dominio ya existe"
		read -p "Presione ENTERN para continuar"
		return
	fi

	read -p "Ingresa la IP del dominio (ej: 192.168.0.70 o presione ENTER para usar la IP del servidor) " ipDomino

	if [[ -z "$ipDominio" ]]; then
		ipDominio=$ipActual
	fi

	if ! validar_ip "$ipDominio"; then
		echo "IP invalida"
		read -p "Presione ENTER para continuar
		return
	fi

	echo "Creando dominio...."
	sudo tee -a /etc/named.rfc1912.zones > /dev/null <<EOF

zone "$dominio" IN {
	type master;
	file "$dominio.db";
};
EOF
	echo "Creando archivo de zona...."
	sudo tee $zona_file > /dev/null <<EOF
\$TTL 86400
@	IN	SOA	ns1.$dominio. admin. $dominio. (
		2024021601
		3600
		1800
		604800
		86400 )

@	IN 	NS	ns1.$dominio.
ns1	IN	A	$ipActual
@	IN	A	$IpDominio
www	IN	CNAME	$dominio.
EOF

	sudo chown named:named $zona_file
	sudo chmod 640 $zona_file

	sudo named-checkconf
	sudo named-checkzone $dominio $zona_file
	sudo systemctl restart named
	echo "Dominio configurado correctamente"
	read -p "Presion ENTER para continuar"

}

crear-dominio(){
	echo ""
	echo "***** Agregar nuevo dominio *****"
	read -p "Ingresa el nombre del dominio (ej: pikachu.com) " dominio
	if [[ -z "$dominio" ]]; then
		echo "El nombre no puede estar vacio"
		read -p "Presione ENTER para continuar"
		return
	fi

	if grep -q "zone \"$dominio"" /etc/named.rfc1912.zones; then
		echo "EL dominio ya existe"
		read -p "Presione ENTER para continuar"
	fi

	read -p "Ingresa la IP del dominio (ej: 192.168.0.70 o presione ENTER para usar la IP del servidor) " ipDominio
	if [[ -z "$ipDominio" ]]; then
		ipDominio=$ipActual
	fi

	zone_file="/var/named/$dominio.db"
	sudo tee -a /etc/named.rfc1912.zones > /dev/null << EOF

zone "$dominio" IN {
    type master;
    file "$dominio.db";
};
EOF

    sudo tee $zona_file > /dev/null <<EOF
\$TTL 86400
@   IN  SOA     ns1.$dominio. admin.$dominio. (
        2024021601
        3600
        1800
        604800
        86400 )

@       IN  NS      ns1.$dominio.
ns1     IN  A       $ipActual
@       IN  A       $ipDominio
www     IN  CNAME   $dominio.
EOF
	sudo chown named:named $zona_file
	sudo chmod 640 $zona_file
	sudo named-checkconf
	sudo named-checkzone $dominio $zona_file
	sudo systemctl restart named
	echo "Dominio creado correctamente"
	read -p "presione ENTER para continuar
}

listar-dominio{
	echo ""
	echo "***** Lista de Dominios *****"
	sudo grep 'zone "' /etc/named.rfc1912.zones | awk -F '"' '{print $2}'
	read -p "Presione ENTER para continuar"
}

eliminar-dominios(){
	echo ""
	echo "***** Eliminar dominio ******"
	read -p "Ingresa el nombre del dominio a eliminar: " dominio
	if !grep -q "zone \"$dominio\"" /etc/named.rfc1912.zones; then
		echo "El dominio no existe"
		read -p "Presione ENTER para continuar"
		return
	fi
	zona_file="/var/named/$dominio.db"
	sudo sed -i "/zone \"$dominio\"/,/};/d" /etc/named.rfc1912.zones
	sudo rm -f $zona_file
	sudo named-checkconf
	sudo systemctl restart named
	echo "Dominio eliminado correctamente"
	read -p "Presiona ENTER para continuar"
}
