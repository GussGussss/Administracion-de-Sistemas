#!/bin/bash

# Función para preparar el terreno (Carpetas, Red y Volúmenes)
preparar_entorno() {
    echo "Configurando infraestructura base..."
    
    # Crear carpetas si no existen
    mkdir -p web db ftp
    
    # Crear Red (si no existe)
    docker network inspect infra_red >/dev/null 2>&1 || \
    docker network create --subnet=172.20.0.0/16 infra_red
    
    # Crear Volúmenes (si no existen)
    docker volume create db_data >/dev/null 2>&1
    docker volume create web_content >/dev/null 2>&1
    
    echo "Red y volúmenes listos."
}

# Función para limpiar todo y empezar de cero
limpiar_todo() {
    echo "Deteniendo y eliminando contenedores..."
    docker rm -f web_server db_postgres ftp_server 2>/dev/null
    echo "Limpieza completada."
}
