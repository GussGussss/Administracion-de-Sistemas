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
        echo "Seleccionaste Nginx"
        ;;
        
        3)
        echo "Seleccionaste Tomcat"
        ;;
        
        4)
        exit
        ;;
        
        *)
        echo "Opción inválida"
        ;;
    
    esac

done
