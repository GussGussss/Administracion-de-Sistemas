#!/bin/bash

# Importar funciones
source ./funciones_p11.sh

# Validacion de privilegios root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Este script debe ejecutarse con privilegios de superusuario (sudo)."
    exit 1
fi

opcion=-1

while [ "$opcion" -ne 0 ]; do
    echo "------------------------------------------------"
    echo "  ADMINISTRACION DE SISTEMAS - PRACTICA 11"
    echo "    ORQUESTACION Y TUNELES SEGUROS"
    echo "------------------------------------------------"
    echo "1. Verificar e instalar dependencias"
    echo "0. Salir"
    echo "------------------------------------------------"
    read -p "Seleccione una opcion: " opcion

    case $opcion in
        1)
            # Llamada a la funcion de verificacion de dependencias
            verificar_dependencias
            ;;
        0)
            echo "Saliendo del script..."
            ;;
        *)
            echo "Opcion no valida."
            ;;
    esac
done
