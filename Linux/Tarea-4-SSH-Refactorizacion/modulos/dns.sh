#!/bin/bash
source ./lib/network.sh
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

crear_dominio(){
	echo ""
	echo "***** Agregar nuevo dominio *****"
	read -p "Ingresa el nombre del dominio (ej: pikachu.com) " dominio
	if [[ -z "$dominio" ]]; then
		echo "El nombre no puede estar vacio"
		read -p "Presione ENTER para continuar"
		return
	fi

	if sudo grep -q "zone \"$dominio\"" /etc/named.rfc1912.zones; then
		echo "EL dominio ya existe"
		read -p "Presione ENTER para continuar"
	fi

	read -p "Ingresa la IP del dominio (ej: 192.168.0.70 o presione ENTER para usar la IP del servidor) " ipDominio
	if [[ -z "$ipDominio" ]]; then
		ipDominio=$ipActual
	fi

	zona_file="/var/named/$dominio.db"
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
	read -p "presione ENTER para continuar"
}

listar_dominio(){
	echo ""
	echo "***** Lista de Dominios *****"
	sudo grep 'zone "' /etc/named.rfc1912.zones | awk -F '"' '{print $2}'
	read -p "Presione ENTER para continuar"
}

eliminar_dominio(){
	echo ""
	echo "***** Eliminar dominio ******"
	read -p "Ingresa el nombre del dominio a eliminar: " dominio
	if ! sudo grep -q "zone \"$dominio\"" /etc/named.rfc1912.zones; then
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

configurar_named_base(){

    echo ""
    echo "***** Configuracion base de BIND *****"

    CONF="/etc/named.conf"

    if [[ ! -f ${CONF}.backup ]]; then
        echo "Creando backup de named.conf..."
        sudo cp $CONF ${CONF}.backup
    fi

    if ! sudo grep -q "listen-on port 53 { any; };" $CONF; then
        echo "Configurando listen-on para todas las interfaces..."

        sudo sed -i '/listen-on port 53/c\        listen-on port 53 { any; };' $CONF
    else
        echo "listen-on ya esta correctamente configurado."
    fi

    if ! sudo grep -q "allow-query     { any; };" $CONF; then
        echo "Configurando allow-query para permitir consultas externas..."

        sudo sed -i '/allow-query/c\        allow-query     { any; };' $CONF
    else
        echo "allow-query ya esta correctamente configurado."
    fi
    if sudo named-checkconf; then
        echo "Configuracion valida."
        sudo systemctl restart named
        echo "Servicio DNS reiniciado correctamente."
    else
        echo "ERROR en la configuracion. Restaurando backup..."
        sudo cp ${CONF}.backup $CONF
        sudo systemctl restart named
    fi

    echo "Configuracion base finalizada."
}
