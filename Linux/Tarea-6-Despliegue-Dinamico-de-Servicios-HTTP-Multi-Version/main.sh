#!/bin/bash
source ./funciones.sh

while true; do

    echo ""
    echo "=============================="
    echo " DESPLIEGUE SERVIDORES HTTP "
    echo "=============================="
    echo "1) Apache"
    echo "2) Nginx"
    echo "3) Tomcat"
    echo "4) Salir"
    echo ""

    read -p "Seleccione una opción: " OPCION

    case $OPCION in

        # ─────────────────────────────
        1)
        listar_versiones_apache

        read -p "Seleccione número de versión: " VERSION_NUM

        case $VERSION_NUM in
            1) VERSION=$APACHE_LATEST ;;
            2) VERSION=$APACHE_LTS ;;
            3) VERSION=$APACHE_OLDEST ;;
            *) echo "Opción inválida"; continue ;;
        esac

        read -p "Ingrese puerto: " PUERTO

        # Si Apache ya está instalado, obtener su puerto actual para no bloquearlo
        PUERTO_ACTUAL=""
        if rpm -q httpd &>/dev/null; then
            PUERTO_ACTUAL=$(grep -m1 "^Listen" /etc/httpd/conf/httpd.conf 2>/dev/null | awk '{print $2}')
        fi

        validar_puerto $PUERTO $PUERTO_ACTUAL

        if [ $? -eq 0 ]; then
            instalar_apache $VERSION $PUERTO
        else
            echo "Puerto inválido, intente con otro"
        fi
        ;;

        # ─────────────────────────────
        2)
        listar_versiones_nginx

        read -p "Seleccione número de versión: " VERSION_NUM

        case $VERSION_NUM in
            1) VERSION=$NGINX_LATEST ;;
            2) VERSION=$NGINX_LTS ;;
            3) VERSION=$NGINX_OLDEST ;;
            *) echo "Opción inválida"; continue ;;
        esac

        read -p "Ingrese puerto: " PUERTO

        # Si Nginx ya está instalado, obtener su puerto actual para no bloquearlo
        PUERTO_ACTUAL=""
        if command -v nginx &>/dev/null; then
            PUERTO_ACTUAL=$(grep -m1 "listen" /etc/nginx/conf.d/default.conf 2>/dev/null | awk '{print $2}' | tr -d ';')
        fi

        validar_puerto $PUERTO $PUERTO_ACTUAL

        if [ $? -eq 0 ]; then
            instalar_nginx $VERSION $PUERTO
        else
            echo "Puerto inválido, intente con otro"
        fi
        ;;

        # ─────────────────────────────
        3)
        listar_versiones_tomcat

        read -p "Seleccione número de versión: " VERSION_NUM

        case $VERSION_NUM in
            1) VERSION="10.1.28" ;;
            2) VERSION="10.1.26" ;;
            3) VERSION="9.0.91" ;;
            *) echo "Opción inválida"; continue ;;
        esac

        read -p "Ingrese puerto: " PUERTO

        # Si Tomcat ya está instalado, obtener su puerto actual para no bloquearlo
        PUERTO_ACTUAL=""
        if [ -f "/opt/tomcat/conf/server.xml" ]; then
            PUERTO_ACTUAL=$(grep -m1 'Connector port=' /opt/tomcat/conf/server.xml 2>/dev/null | grep -o 'port="[0-9]*"' | grep -o '[0-9]*')
        fi

        validar_puerto $PUERTO $PUERTO_ACTUAL

        if [ $? -eq 0 ]; then
            instalar_tomcat $VERSION $PUERTO
        else
            echo "Puerto inválido, intente con otro"
        fi
        ;;

        # ─────────────────────────────
        4)
        echo "Saliendo..."
        exit 0
        ;;

        *)
        echo "Opción inválida"
        ;;

    esac

done
