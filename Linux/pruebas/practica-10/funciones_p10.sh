#!/bin/bash

# Función para automatizar la instalación de Docker
instalar_docker() {
    echo "Verificando estado de Docker..."
    
    # Comprueba si el comando docker ya existe en el sistema
    if command -v docker &> /dev/null; then
        echo "¡Docker ya está instalado y listo para usarse!"
    else
        echo "Docker no encontrado. Iniciando instalación automatizada..."
        
        # Instalación para Oracle Linux (basado en RHEL/CentOS)
        sudo dnf install -y dnf-utils
        sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        echo "Iniciando y habilitando el servicio de Docker..."
        sudo systemctl start docker
        sudo systemctl enable docker
        
        echo "Configurando permisos para el usuario actual ($USER)..."
        sudo usermod -aG docker $USER
        
        echo "=================================================================="
        echo " INSTALACIÓN COMPLETADA "
        echo " IMPORTANTE: Para que los permisos de Docker apliquen sin usar sudo,"
        echo " debes cerrar esta terminal y volver a entrar, o ejecutar el comando:"
        echo " newgrp docker"
        echo "=================================================================="
    fi
}

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
