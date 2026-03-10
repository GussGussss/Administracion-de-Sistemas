#!/bin/bash

source ./funciones.sh

while true
    do
    
    echo "=============================="
    echo " DESPLIEGUE SERVIDORES HTTP "
    echo "=============================="
    
    echo "1) Apache"
    echo "2) Nginx"
    echo "3) Tomcat"
    echo "4) Salir"
    
    read -p "Seleccione una opción: " OPCION
    
    case $OPCION in
        
       1)
        listar_versiones_apache
        
        read -p "Seleccione número de versión: " VERSION_NUM
        
        VERSION=$(dnf list --showduplicates httpd \
        | grep httpd.x86_64 \
        | awk '{print $2}' \
        | sed -n "${VERSION_NUM}p")
        
        read -p "Ingrese puerto: " PUERTO
        
        validar_puerto $PUERTO
        
        if [ $? -eq 0 ]; then
        
        instalar_apache $VERSION $PUERTO
        
        else
        
        echo "Puerto inválido"
        
        fi
        
        ;;
        
        2)
        
        listar_versiones_nginx
        
        read -p "Seleccione número de versión: " VERSION_NUM
        
        VERSION=$(dnf list --showduplicates nginx \
        | grep nginx.x86_64 \
        | awk '{print $2}' \
        | sed -n "${VERSION_NUM}p")
        
        read -p "Ingrese puerto: " PUERTO
        
        instalar_nginx $VERSION $PUERTO
        
        ;;
        
        3)
        listar_versiones_tomcat

        read -p "Seleccione número de versión: " opcion
        
        case $opcion in
        
        1) VERSION="10.1.28";;
        2) VERSION="10.1.26";;
        3) VERSION="10.1.24";;
        4) VERSION="9.0.91";;
        5) VERSION="9.0.89";;
        
        esac
        
        read -p "Ingrese puerto: " PUERTO
        
        instalar_tomcat $VERSION $PUERTO
        ;;
        
        4)
        exit
        ;;
        
        *)
        echo "Opción inválida"
        ;;
    
    esac

done
