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
        
        VERSIONES=$(dnf list --showduplicates httpd | grep httpd.x86_64 | awk '{print $2}' | sort -V | uniq)
        
        OLDEST=$(echo "$VERSIONES" | head -n 1)
        LTS=$(echo "$VERSIONES" | sed -n '2p')
        LATEST=$(echo "$VERSIONES" | tail -n 1)
        
        read -p "Seleccione número de versión: " VERSION_NUM
        
        case $VERSION_NUM in
        1) VERSION=$LATEST ;;
        2) VERSION=$LTS ;;
        3) VERSION=$OLDEST ;;
        *) echo "Opción inválida"; continue ;;
        esac
        
        read -p "Ingrese puerto: " PUERTO
        
        validar_puerto $PUERTO
        
        if [ $? -eq 0 ]; then
        
        instalar_apache $VERSION $PUERTO
        
        else
        
        echo "Puerto inválido"
        
        fi
        
        ;;
        
        2)
        # Ejecutamos la función para que el usuario vea la lista
        listar_versiones_nginx
        
        # Recalculamos para asignar a las variables locales del main
        VERSIONES=$(dnf repoquery --showduplicates nginx | awk -F'-' '{print $2}' | sort -V | uniq)
        
        OLDEST=$(echo "$VERSIONES" | head -n 1)
        LTS=$(echo "$VERSIONES" | sed -n '2p')
        LATEST=$(echo "$VERSIONES" | tail -n 1)
        
        read -p "Seleccione número de versión: " VERSION_NUM
        
        case $VERSION_NUM in
        1) VERSION=$LATEST ;;
        2) VERSION=$LTS ;;
        3) VERSION=$OLDEST ;;
        *) echo "Opción inválida"; continue ;;
        esac
        
        read -p "Ingrese puerto: " PUERTO
        
        validar_puerto $PUERTO
        
        if [ $? -eq 0 ]; then
            instalar_nginx $VERSION $PUERTO
        else
            echo "Puerto inválido"
        fi
        
        ;;
        
        3)
        listar_versiones_tomcat
        
        read -p "Seleccione número de versión: " opcion
        
        case $opcion in
        1) VERSION="10.1.28";;
        2) VERSION="10.1.26";;
        3) VERSION="9.0.91";;
        *) echo "Opción inválida"; continue;;
        esac
        
        read -p "Ingrese puerto: " PUERTO
        
        validar_puerto $PUERTO
        
        if [ $? -eq 0 ]; then
            instalar_tomcat $VERSION $PUERTO
        else
            echo "Puerto inválido"
        fi
        ;;
        
        4)
        exit
        ;;
        
        *)
        echo "Opción inválida"
        ;;
    
    esac

done
