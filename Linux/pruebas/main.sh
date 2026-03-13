#!/bin/bash
source ./funciones.sh

while true; do
    echo "=============================="
    echo " DESPLIEGUE SERVIDORES HTTP "
    echo "   Linux - Oracle Linux Server   "
    echo "=============================="
    echo "1) Apache"
    echo "2) Nginx"
    echo "3) Tomcat"
    echo "4) Salir"
    read -p "Seleccione una opción: " OPCION

    case $OPCION in
        1)
            ESTADO=$(detectar_apache)
            if [ "$ESTADO" == "instalado" ]; then
                gestionar_apache_instalado
            else
                listar_versiones_apache
                VERSIONES=$(dnf list --showduplicates httpd | grep httpd.x86_64 | awk '{print $2}' | sort -V | uniq)
                OLDEST=$(echo "$VERSIONES" | head -n 1)
                LTS=$(echo "$VERSIONES" | sed -n '2p')
                LATEST=$(echo "$VERSIONES" | tail -n 1)
                read -p "Seleccione número de versión [1-3]: " VERSION_NUM
                case $VERSION_NUM in
                    1) VERSION=$LATEST ;;
                    2) VERSION=$LTS ;;
                    3) VERSION=$OLDEST ;;
                    *) echo "Opción inválida"; continue ;;
                esac
                read -p "Ingrese puerto: " PUERTO
                validar_puerto $PUERTO || continue
                instalar_apache $VERSION $PUERTO
            fi
            ;;
        2)
            ESTADO=$(detectar_nginx)
            if [ "$ESTADO" == "instalado" ]; then
                gestionar_nginx_instalado
            else
                listar_versiones_nginx
                read -p "Seleccione número de versión [1-3]: " VERSION_NUM
                case $VERSION_NUM in
                    1) VERSION=$LATEST ;;
                    2) VERSION=$LTS ;;
                    3) VERSION=$OLDEST ;;
                    *) echo "Opción inválida"; continue ;;
                esac
                read -p "Ingrese puerto: " PUERTO
                validar_puerto $PUERTO || continue
                instalar_nginx $VERSION $PUERTO
            fi
            ;;
        3)
            ESTADO=$(detectar_tomcat)
            if [ "$ESTADO" == "instalado" ]; then
                gestionar_tomcat_instalado
            else
                listar_versiones_tomcat
                read -p "Seleccione número de versión [1-3]: " opcion
                case $opcion in
                    1) VERSION="10.1.28" ;;
                    2) VERSION="10.1.26" ;;
                    3) VERSION="9.0.91" ;;
                    *) echo "Opción inválida"; continue ;;
                esac
                read -p "Ingrese puerto: " PUERTO
                validar_puerto $PUERTO || continue
                instalar_tomcat $VERSION $PUERTO
            fi
            ;;
        4)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo "Opción inválida"
            ;;
    esac
done
