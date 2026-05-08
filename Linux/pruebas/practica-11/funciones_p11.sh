#!/bin/bash
# funciones_p11.sh
# Lógica de soporte para la Práctica 11

DIRECTORIO_INFRA="/opt/practica11"

# Función crítica: Verifica si un paquete existe antes de intentar descargarlo
verificar_instalar_paquete() {
    local paquete=$1
    
    # Verificamos si el paquete ya está instalado
    if rpm -q "$paquete" &> /dev/null; then
        echo "[!] El paquete '$paquete' ya se encuentra instalado en el sistema."
        read -p "¿Desea forzar su descarga y reinstalación desde internet? (s/N): " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            echo "[+] Forzando reinstalación de $paquete..."
            dnf reinstall -y "$paquete"
        else
            echo "[-] Omitiendo instalación de $paquete para ahorrar datos."
        fi
    else
        echo "[+] El paquete '$paquete' no existe. Descargando e instalando..."
        dnf install -y "$paquete"
    fi
}

preparar_entorno() {
    echo "=== Preparación del Entorno ==="
    
    echo "[*] Verificando directorio de infraestructura externa..."
    if [ ! -d "$DIRECTORIO_INFRA" ]; then
        mkdir -p "$DIRECTORIO_INFRA"
        echo "[+] Directorio $DIRECTORIO_INFRA creado exitosamente."
    else
        echo "[-] El directorio $DIRECTORIO_INFRA ya existe. Omitiendo creación."
    fi

    echo "[*] Verificando dependencias base (Docker y Docker Compose)..."
    verificar_instalar_paquete "docker"
    verificar_instalar_paquete "docker-compose-plugin" # Nombre estándar en repositorios RHEL/Oracle modernos

    echo "[*] Asegurando que el demonio de Docker esté habilitado y en ejecución..."
    systemctl enable --now docker

    echo "[+] Preparación de entorno finalizada."
    read -p "Presione ENTER para continuar..."
}

submodo_pruebas() {
    echo "=== Protocolo de Pruebas Dinámicas ==="
    echo "1. Prueba 11.1: Validación de aislamiento de red"
    echo "2. Prueba 11.2: Validación de resolución interna DNS"
    echo "3. Prueba 11.3: Validación de túnel cifrado de gestión"
    echo "4. Prueba 11.4: Validación de persistencia y healthcheck"
    echo "0. Regresar al menú principal"
    echo "======================================"
    read -p "Seleccione una prueba a ejecutar: " opcion_prueba

    case $opcion_prueba in
        0) return ;;
        *) echo "[!] Prueba aún no implementada." ; read -p "Presione ENTER para continuar..." ;;
    esac
}
