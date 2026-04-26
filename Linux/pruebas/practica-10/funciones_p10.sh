#!/bin/bash

# Funcion auxiliar para preguntar al usuario (S/N)
# No usa emojis por requerimiento
preguntar_confirmacion() {
    local mensaje=$1
    read -p "$mensaje (s/n): " respuesta
    case "$respuesta" in
        [sS]|[sS][iI]|[yY]|[eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# Nueva Funcion: Descargar Utilidades (Docker Images)
descargar_utilidades() {
    echo "Iniciando descarga de imagenes y utilidades necesarias..."
    
    # Lista de imagenes necesarias para la practica
    local imagenes=("alpine:latest" "postgres:latest" "delfer/alpine-ftp-server")
    
    for img in "${imagenes[@]}"; do
        # Verificar si la imagen ya existe localmente
        if docker images -q "$img" > /dev/null 2>&1; then
            echo "La imagen $img ya se encuentra descargada."
            if preguntar_confirmacion "Desea descargarla nuevamente para actualizar?"; then
                docker pull "$img"
            fi
        else
            echo "Descargando imagen: $img"
            docker pull "$img"
        fi
    done
    echo "Proceso de descarga finalizado."
}

# Funcion: Instalar Dependencias (Docker Engine)
instalar_docker() {
    echo "Verificando instalacion de Docker Engine..."
    
    if command -v docker &> /dev/null; then
        echo "Docker ya esta instalado en el sistema."
        if preguntar_confirmacion "Desea intentar reinstalar o actualizar Docker?"; then
            dnf install -y dnf-utils
            dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        fi
    else
        echo "Instalando Docker Engine por primera vez..."
        dnf install -y dnf-utils
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        systemctl start docker
        systemctl enable docker
    fi
}

# Funcion: Preparar el Terreno
preparar_entorno() {
    echo "Configurando red y volumenes..."
    
    mkdir -p web db ftp
    
    # Validacion de Red
    if docker network inspect infra_red >/dev/null 2>&1; then
        echo "La red infra_red ya existe."
        if preguntar_confirmacion "Desea recrear la red? (Esto podria desconectar contenedores activos)"; then
            docker network rm infra_red
            docker network create --subnet=172.20.0.0/16 infra_red
        fi
    else
        docker network create --subnet=172.20.0.0/16 infra_red
    fi
    
    # Validacion de Volumenes
    local volumenes=("db_data" "web_content")
    for vol in "${volumenes[@]}"; do
        if docker volume inspect "$vol" >/dev/null 2>&1; then
            echo "El volumen $vol ya existe."
        else
            docker volume create "$vol"
        fi
    done
    
    echo "Configuracion de infraestructura base lista."
}

# Funcion: Limpiar todo
limpiar_todo() {
    echo "Deteniendo y eliminando contenedores de la practica..."
    docker rm -f web_server db_postgres ftp_server 2>/dev/null
    echo "Limpieza completada."
}
