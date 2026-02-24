#!/bin/bash
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
	sudo systemctl start named
	configurar_named_base

	echo ""
	echo "Configurando firewall para permitir DNS"
	sudo firewall-cmd --permanent --add-service=dns
	sudo firewall-cmd --reload
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

	if sudo grep -q "$dominio" /etc/named.rfc1912.zones; then
		echo "El dominio ya existe"
		read -p "Presione ENTERN para continuar"
		return
	fi

	read -p "Ingresa la IP del dominio (ej: 192.168.0.70 o presione ENTER para usar la IP del servidor) " ipDominio

	if [[ -z "$ipDominio" ]]; then
		ipDominio=$ipActual
	fi

	if ! validar_ip "$ipDominio"; then
		echo "IP invalida"
		read -p "Presione ENTER para continuar"
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
@	IN	SOA	ns1.$dominio. admin.$dominio. (
		2024021601
		3600
		1800
		604800
		86400 )

@	IN 	NS	ns1.$dominio.
ns1	IN	A	$ipActual
@	IN	A	$ipDominio
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
