#!/bin/bash
# Archivo: funciones_p10.sh

instalar_dependencias() {
    echo "----------------------------------------"
    echo " Preparando Dependencias del Sistema"
    echo "----------------------------------------"

    # Validación de Docker
    if command -v docker &> /dev/null; then
        echo "Se ha detectado que Docker ya está instalado."
        read -p "¿Deseas forzar la reinstalación/actualización? (s/n): " reinstalar_docker
        if [[ "$reinstalar_docker" == "s" || "$reinstalar_docker" == "S" ]]; then
            echo "Reinstalando Docker..."
            dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io
        else
            echo "Omitiendo la descarga de Docker."
        fi
    else
        echo "Docker no está instalado. Procediendo a descargar e instalar..."
        dnf -y install dnf-plugins-core
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io
    fi

    # Asegurar que el demonio de Docker esté habilitado y corriendo
    systemctl enable docker
    systemctl start docker

    # Validación de Docker Compose
    if docker compose version &> /dev/null || command -v docker-compose &> /dev/null; then
        echo "Se ha detectado que Docker Compose ya está instalado."
    else
        echo "Docker Compose no está instalado. Instalando..."
        dnf install -y docker-compose-plugin
    fi

    echo "----------------------------------------"
    echo " Dependencias listas y servicios activos."
    echo "----------------------------------------"
    
    # Pausa para que el usuario pueda leer los mensajes antes de volver al menú
    read -p "Presiona Enter para continuar..."
}
