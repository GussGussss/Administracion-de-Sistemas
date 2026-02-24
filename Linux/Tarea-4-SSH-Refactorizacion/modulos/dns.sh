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
