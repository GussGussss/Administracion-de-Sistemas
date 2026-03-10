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
        echo "Seleccionaste Apache"
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
