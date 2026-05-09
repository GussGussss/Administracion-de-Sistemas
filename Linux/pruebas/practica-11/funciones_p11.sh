#!/bin/bash
# funciones_p11.sh
# Lógica de soporte para la Práctica 11 (Versión Inteligente con Autodetección)

DIRECTORIO_INFRA="/opt/practica11"

# --- Funciones de Utilidad ---

verificar_instalar_paquete() {
    local paquete=$1
    if rpm -q "$paquete" &> /dev/null; then
        echo "[!] El paquete '$paquete' ya se encuentra instalado."
        read -p "¿Desea forzar su descarga y reinstalación? (s/N): " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            dnf reinstall -y "$paquete"
        fi
    else
        echo "[+] Descargando e instalando '$paquete'..."
        dnf install -y "$paquete"
    fi
}

actualizar_resolucion_dns() {
    local target_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' servidor_pgadmin 2>/dev/null | head -n 1)
    if [ -n "$target_ip" ]; then
        sed -i '/servidor_pgadmin/d' /etc/hosts
        tail -c1 /etc/hosts | read -r _ || echo >> /etc/hosts
        echo "$target_ip servidor_pgadmin" >> /etc/hosts
        restorecon -v /etc/hosts >/dev/null 2>&1 || true
    fi
}

# --- Funciones de Menú Principal ---

preparar_entorno() {
    echo "=== Preparación del Entorno ==="
    mkdir -p "$DIRECTORIO_INFRA"
    
    verificar_instalar_paquete "dnf-plugins-core"
    if [ ! -f "/etc/yum.repos.d/docker-ce.repo" ]; then
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
    fi

    verificar_instalar_paquete "docker-ce"
    verificar_instalar_paquete "docker-ce-cli"
    verificar_instalar_paquete "containerd.io"
    verificar_instalar_paquete "docker-compose-plugin"

    systemctl enable --now docker
    echo "[+] Preparación finalizada."
    read -p "Presione ENTER para continuar..."
}

generar_archivos() {
    echo "=== Generación de Archivos de Orquestación ==="
    
    cat <<EOF > "$DIRECTORIO_INFRA/.env"
POSTGRES_USER=admin_db
POSTGRES_PASSWORD=SuperSecretPassword2026
POSTGRES_DB=practica11_db
PGADMIN_DEFAULT_EMAIL=admin@practica11.com
PGADMIN_DEFAULT_PASSWORD=AdminPassword2026
EOF
    chmod 600 "$DIRECTORIO_INFRA/.env"

    mkdir -p "$DIRECTORIO_INFRA/nginx"
    cat <<EOF > "$DIRECTORIO_INFRA/nginx/default.conf"
server {
    listen 80;
    server_tokens off;
    location / { proxy_pass http://app_interna:80; }
}
EOF

    cat <<EOF > "$DIRECTORIO_INFRA/docker-compose.yml"
version: '3.8'
networks:
  red_publica:
    driver: bridge
  red_datos:
    driver: bridge
volumes:
  db_data:
services:
  frontend:
    image: nginx:alpine
    container_name: nginx_balancer
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - red_publica
      - red_datos
  app_server:
    image: httpd:alpine
    container_name: app_interna
    restart: always
    networks:
      - red_datos
  db:
    image: postgres:15-alpine
    container_name: postgres_db
    restart: always
    env_file: .env
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - red_datos
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \$\${POSTGRES_USER} -d \$\${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
  pgadmin:
    image: dpage/pgadmin4
    container_name: servidor_pgadmin
    restart: always
    env_file: .env
    networks:
      - red_datos
    depends_on:
      db:
        condition: service_healthy
EOF
    echo "[+] Archivos generados en $DIRECTORIO_INFRA."
    read -p "Presione ENTER para continuar..."
}

desplegar_infraestructura() {
    echo "=== Despliegue de Infraestructura ==="
    cd "$DIRECTORIO_INFRA" || return
    docker compose up -d
    echo "[*] Esperando inicialización (10s)..."
    sleep 10
    actualizar_resolucion_dns
    echo "[+] Despliegue finalizado."
    read -p "Presione ENTER para continuar..."
}

# --- Funciones de Pruebas Dinámicas Automatizadas ---

ejecutar_prueba_11_1() {
    echo "--- Prueba 11.1: Validación de Aislamiento de Red ---"
    DEFAULT_IP=$(ip -4 addr show enp0s3 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    
    read -p "Ingrese la IP de Oracle Linux [Enter para usar '$DEFAULT_IP']: " ip_host
    ip_host=${ip_host:-$DEFAULT_IP}
    
    echo "[*] Ejecutando curl hacia el puerto 5432 de $ip_host..."
    curl --connect-timeout 5 -v telnet://"$ip_host":5432
    read -p "Presione ENTER para continuar..."
}

ejecutar_prueba_11_2() {
    echo "--- Prueba 11.2: Validación de Resolución Interna DNS ---"
    DEFAULT_SERVICE="db"
    
    read -p "Ingrese nombre del servicio a probar [Enter para usar '$DEFAULT_SERVICE']: " target_dns
    target_dns=${target_dns:-$DEFAULT_SERVICE}
    
    echo "[*] Ejecutando ping hacia el servicio '$target_dns' desde el frontend..."
    docker exec nginx_balancer ping -c 4 "$target_dns"
    read -p "Presione ENTER para continuar..."
}

ejecutar_prueba_11_3() {
    echo "--- Prueba 11.3: Validación de Túnel Cifrado de Gestión ---"
    actualizar_resolucion_dns
    
    IP_PGADMIN=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' servidor_pgadmin 2>/dev/null | head -n 1)
    
    if [ -z "$IP_PGADMIN" ]; then
        echo "[-] ERROR: El contenedor 'servidor_pgadmin' no está activo."
        read -p "Presione ENTER..."
        return
    fi

    DEFAULT_USER=${SUDO_USER:-$USER}
    DEFAULT_IP=$(ip -4 addr show enp0s3 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)

    read -p "Ingrese su usuario SSH [Enter para '$DEFAULT_USER']: " usr_ssh
    usr_ssh=${usr_ssh:-$DEFAULT_USER}

    read -p "Ingrese la IP del servidor [Enter para '$DEFAULT_IP']: " ip_ssh
    ip_ssh=${ip_ssh:-$DEFAULT_IP}

    echo "---------------------------------------------------"
    echo "EJECUTE EN SU PC FÍSICA:"
    echo "ssh -L 8080:servidor_pgadmin:80 $usr_ssh@$ip_ssh"
    echo "---------------------------------------------------"
    read -p "Presione ENTER tras validar el acceso en http://localhost:8080"
}

ejecutar_prueba_11_4() {
    echo "--- Prueba 11.4: Validación de Persistencia y Healthcheck ---"
    cd "$DIRECTORIO_INFRA" || return
    echo "[*] Reiniciando infraestructura..."
    docker compose down
    docker compose up -d
    
    echo "[*] Monitoreando Healthcheck (10s)..."
    for i in {1..5}; do
        docker compose ps
        sleep 2
    done
    read -p "Presione ENTER para continuar..."
}

submodo_pruebas() {
    while true; do
        echo ""
        echo ""
        echo "======================================"
        echo " Protocolo de Pruebas Dinámicas"
        echo "======================================"
        echo " 1. Prueba 11.1: Aislamiento (curl)"
        echo " 2. Prueba 11.2: DNS interna (ping)"
        echo " 3. Prueba 11.3: Túnel cifrado (ssh -L)"
        echo " 4. Prueba 11.4: Persistencia (down/up)"
        echo " 0. Regresar"
        echo "======================================"
        read -p "Seleccione una opción [0-4]: " opt
        case $opt in
            1) ejecutar_prueba_11_1 ;;
            2) ejecutar_prueba_11_2 ;;
            3) ejecutar_prueba_11_3 ;;
            4) ejecutar_prueba_11_4 ;;
            0) break ;;
        esac
    echo ""
    echo ""
    done
}
