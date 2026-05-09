#!/bin/bash
# funciones_p11.sh
# Lógica de soporte para la Práctica 11 (Versión Definitiva)

DIRECTORIO_INFRA="/opt/practica11"

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

preparar_entorno() {
    clear
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
    clear
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

    # Se eliminó "internal: true" de red_datos para permitir enrutamiento del anfitrión
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

# Helper crítico: Actualiza DNS preservando el contexto SELinux
actualizar_resolucion_dns() {
    local target_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' servidor_pgadmin 2>/dev/null | head -n 1)
    if [ -n "$target_ip" ]; then
        grep -v "servidor_pgadmin" /etc/hosts > /tmp/hosts.tmp
        echo "$target_ip servidor_pgadmin" >> /tmp/hosts.tmp
        cat /tmp/hosts.tmp > /etc/hosts
        rm -f /tmp/hosts.tmp
        # Restaurar contexto SELinux para que SSHD pueda leerlo
        restorecon -v /etc/hosts >/dev/null 2>&1 || true
        export IP_PGADMIN_DETECTADA="$target_ip"
    fi
}

desplegar_infraestructura() {
    clear
    cd "$DIRECTORIO_INFRA" || return
    docker compose up -d
    echo "[*] Esperando inicialización (10s)..."
    sleep 10
    actualizar_resolucion_dns
    echo "[+] Despliegue finalizado."
    read -p "Presione ENTER para continuar..."
}

ejecutar_prueba_11_1() {
    clear
    read -p "Ingrese la IP de Oracle Linux: " ip_host
    curl --connect-timeout 5 -v telnet://"$ip_host":5432
    read -p "Presione ENTER para continuar..."
}

ejecutar_prueba_11_2() {
    clear
    read -p "Ingrese nombre del servicio (ej. db): " target_dns
    docker exec nginx_balancer ping -c 4 "$target_dns"
    read -p "Presione ENTER para continuar..."
}

ejecutar_prueba_11_3() {
    clear
    echo "--- Prueba 11.3: Validación de Túnel Cifrado de Gestión ---"
    
    echo "[*] Diagnosticando estado de red del contenedor..."
    # 1. Extracción ultra-robusta de IP
    IP_PGADMIN=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' servidor_pgadmin 2>/dev/null | head -n 1)
    
    if [ -z "$IP_PGADMIN" ]; then
        echo "[-] ERROR CRÍTICO: La IP está vacía. El contenedor 'servidor_pgadmin' no está corriendo o falló."
        echo "Estado actual del contenedor:"
        docker ps -a -f name=servidor_pgadmin
        read -p "Presione ENTER para regresar al menú..."
        return
    fi

    echo "[+] Contenedor detectado. IP interna: $IP_PGADMIN"

    # 2. Inyección segura en /etc/hosts (Mitigación del bug de EOF)
    echo "[*] Sincronizando tabla de enrutamiento DNS del anfitrión..."
    sed -i '/servidor_pgadmin/d' /etc/hosts
    
    # Truco de Bash: Asegurar que el archivo termina en un salto de línea antes de añadir texto
    tail -c1 /etc/hosts | read -r _ || echo >> /etc/hosts
    
    # Inyectar la variable de forma limpia
    echo "$IP_PGADMIN servidor_pgadmin" >> /etc/hosts
    
    # Imprimir la última línea de /etc/hosts para validar visualmente que no hay corrupción
    echo "[+] Verificación de inyección en /etc/hosts:"
    tail -n 1 /etc/hosts

    # 3. Lógica de Autodetección
    DEFAULT_USER=${SUDO_USER:-$USER}
    DEFAULT_IP=$(ip -4 addr show enp0s3 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    DEFAULT_IP=${DEFAULT_IP:-"192.168.1.15"} # Respaldo en caso de fallo de detección

    echo "---------------------------------------------------"
    read -p "Ingrese su usuario en Oracle Linux [Enter para usar '$DEFAULT_USER']: " usr_ssh
    usr_ssh=${usr_ssh:-$DEFAULT_USER}

    read -p "Ingrese la IP (Adaptador enp0s3) [Enter para usar '$DEFAULT_IP']: " ip_ssh
    ip_ssh=${ip_ssh:-$DEFAULT_IP}

    echo "---------------------------------------------------"
    echo "PASO 1: Abra la terminal o CMD en su maquina fisica."
    echo "PASO 2: Ejecute exactamente el siguiente comando:"
    echo ""
    echo "    ssh -L 8080:servidor_pgadmin:80 $usr_ssh@$ip_ssh"
    echo ""
    echo "PASO 3: Inicie sesion con su contrasena."
    echo "PASO 4: Abra su navegador en Windows y entre a: http://localhost:8080"
    echo "---------------------------------------------------"
    echo "Credenciales definidas en su .env: admin@practica11.com / AdminPassword2026"
    read -p "Presione ENTER una vez que haya validado el acceso en su navegador..."
}

submodo_pruebas() {
    while true; do
        clear
        echo " 1. Prueba 11.1: Aislamiento (curl)"
        echo " 2. Prueba 11.2: DNS interna (ping)"
        echo " 3. Prueba 11.3: Túnel cifrado (ssh -L)"
        echo " 4. Prueba 11.4: Persistencia (down/up)"
        echo " 0. Salir"
        read -p "Opción: " opt
        case $opt in
            1) ejecutar_prueba_11_1 ;;
            2) ejecutar_prueba_11_2 ;;
            3) ejecutar_prueba_11_3 ;;
            4) ejecutar_prueba_11_4 ;;
            0) break ;;
        esac
    done
}
