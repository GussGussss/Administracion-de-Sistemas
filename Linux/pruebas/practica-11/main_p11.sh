#!/bin/bash

# Importar funciones
source ./funciones_11.sh

# REGLA 2: Validacion de privilegios de root
if [[ $EUID -ne 0 ]]; then
   echo "Error: Este script debe ejecutarse con privilegios de sudo."
   exit 1
fi

opcion=-1

while [ "$opcion" -ne 0 ]; do
    echo "------------------------------------------------"
    echo "  Administracion de Sistemas - Tarea 11"
    echo "  Orquestacion y Tuneles Seguros"
    echo "-----------------------------------------------"
    echo "1. Instalar/Verificar dependencias (Docker & Compose)"
    echo "0. Salir"
    echo "-----------------------------------------------"
    read -p "Seleccione una opcion: " opcion

    case $opcion in
        1)
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
