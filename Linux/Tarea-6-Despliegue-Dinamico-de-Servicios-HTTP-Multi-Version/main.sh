#!/bin/bash
# ============================================================
# main.sh
# Script Principal - Despliegue Dinámico de Servicios HTTP
# Práctica 6 - Oracle Linux 10.1
# Autor: Práctica Administración de Servidores
# Uso: Ejecutar via SSH como root o con sudo
# ============================================================

# Directorio donde se encuentra este script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar archivo de funciones
FUNCIONES="${SCRIPT_DIR}/funciones.sh"
if [[ ! -f "$FUNCIONES" ]]; then
    echo "[ERROR] No se encontró funciones.sh en $SCRIPT_DIR"
    echo "        Asegúrate de que main.sh y funciones.sh estén en el mismo directorio."
    exit 1
fi
source "$FUNCIONES"

# ─────────────────────────────────────────────
# FUNCIÓN: Mostrar banner principal
# ─────────────────────────────────────────────
mostrar_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║       DESPLIEGUE DINÁMICO DE SERVICIOS HTTP              ║"
    echo "  ║       Práctica 6 · Oracle Linux 10.1                     ║"
    echo "  ║       IP: 192.168.0.70                                   ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Mostrar menú principal
# ─────────────────────────────────────────────
mostrar_menu() {
    echo -e "${BOLD}  ┌─────────────────────────────────────┐${NC}"
    echo -e "${BOLD}  │         MENÚ PRINCIPAL               │${NC}"
    echo -e "${BOLD}  ├─────────────────────────────────────┤${NC}"
    echo -e "  │  ${GREEN}[1]${NC} Instalar Apache HTTP Server      │"
    echo -e "  │  ${GREEN}[2]${NC} Instalar Nginx                   │"
    echo -e "  │  ${GREEN}[3]${NC} Instalar Apache Tomcat           │"
    echo -e "  │  ${YELLOW}[4]${NC} Ver estado de servicios          │"
    echo -e "  │  ${YELLOW}[5]${NC} Desinstalar servicio HTTP        │"
    echo -e "  │  ${RED}[0]${NC} Salir                            │"
    echo -e "${BOLD}  └─────────────────────────────────────┘${NC}"
    echo ""
}

# ─────────────────────────────────────────────
# FUNCIÓN: Bucle principal del menú
# ─────────────────────────────────────────────
ejecutar_menu() {
    local opcion

    while true; do
        mostrar_banner
        mostrar_menu

        echo -ne "${CYAN}  Selecciona una opción [0-5]: ${NC}"
        read -r opcion

        # Validar que no sea vacío
        if [[ -z "$opcion" ]]; then
            msg_warn "Por favor ingresa una opción."
            sleep 1
            continue
        fi

        case "$opcion" in
            1)
                echo ""
                echo -e "${BOLD}═══ INSTALACIÓN DE APACHE HTTP SERVER ═══${NC}"
                instalar_apache
                echo ""
                echo -ne "${CYAN}Presiona Enter para continuar...${NC}"
                read -r
                ;;
            2)
                echo ""
                echo -e "${BOLD}═══ INSTALACIÓN DE NGINX ═══${NC}"
                instalar_nginx
                echo ""
                echo -ne "${CYAN}Presiona Enter para continuar...${NC}"
                read -r
                ;;
            3)
                echo ""
                echo -e "${BOLD}═══ INSTALACIÓN DE APACHE TOMCAT ═══${NC}"
                instalar_tomcat
                echo ""
                echo -ne "${CYAN}Presiona Enter para continuar...${NC}"
                read -r
                ;;
            4)
                mostrar_estado_servicios
                echo -ne "${CYAN}Presiona Enter para continuar...${NC}"
                read -r
                ;;
            5)
                desinstalar_servicio
                echo ""
                echo -ne "${CYAN}Presiona Enter para continuar...${NC}"
                read -r
                ;;
            0)
                echo ""
                echo -e "${GREEN}  Hasta luego.${NC}"
                echo ""
                exit 0
                ;;
            *)
                msg_warn "Opción '$opcion' no válida. Elige entre 0 y 5."
                sleep 1
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════
#   PUNTO DE ENTRADA — Solo llamadas a funciones
# ═══════════════════════════════════════════════════════════
verificar_root
ejecutar_menu
