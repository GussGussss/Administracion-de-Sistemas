#!/bin/bash

# Variable global para el entorno de trabajo
DIR_BASE="/opt/practica11"

verificar_dependencias() {
    echo "Iniciando verificacion de dependencias..."

    # 1. Verificar Docker
    if command -v docker &> /dev/null; then
        echo "Docker ya esta instalado en el sistema."
        read -p "Desea forzar la reinstalacion de Docker? (s/n): " resp
        if [ "$resp" == "s" ]; then
            dnf remove -y docker-ce docker-ce-cli containerd.io
            dnf install -y docker-ce docker-ce-cli containerd.io
            systemctl enable --now docker
        fi
    else
        echo "Instalando Docker..."
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io
        systemctl enable --now docker
    fi

    # 2. Verificar Docker Compose (plugin o binario)
    if docker compose version &> /dev/null; then
        echo "Docker Compose ya esta instalado."
        read -p "Desea forzar la reinstalacion de Docker Compose? (s/n): " resp
        if [ "$resp" == "s" ]; then
            dnf install -y docker-compose-plugin
        fi
    else
        echo "Instalando Docker Compose..."
        dnf install -y docker-compose-plugin
    fi

    # 3. Crear directorio base de trabajo
    if [ ! -d "$DIR_BASE" ]; then
        echo "Creando directorio base en $DIR_BASE..."
        mkdir -p "$DIR_BASE"
    else
        echo "El directorio de trabajo $DIR_BASE ya existe."
    fi

    echo "Dependencias listas para operar."
}
