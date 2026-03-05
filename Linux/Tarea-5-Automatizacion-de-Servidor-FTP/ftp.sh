#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "El script debe de ejecutarse como root :D"
  exit 1
fi

# ─────────────────────────────────────────────
#  ESTRUCTURA DE DIRECTORIOS
# ─────────────────────────────────────────────
# /ftp/                          <- chroot de usuarios autenticados
#   general/                     <- carpeta publica (todos escriben)
#   grupos/
#     reprobados/                <- carpeta del grupo
#     recursadores/              <- carpeta del grupo
#   homes/
#     <usuario>/                 <- chroot jail del usuario
#       general   -> symlink a /ftp/general
#       reprobados o recursadores -> symlink al grupo
#       <usuario> -> symlink a /ftp/homes/<usuario>/private
#       private/  <- carpeta personal real
#
# /ftp_anon/                     <- chroot exclusivo del anonimo
#   general -> symlink a /ftp/general
# ─────────────────────────────────────────────

FTP_ROOT="/ftp"
ANON_ROOT="/ftp_anon"

configurar_firewall(){
  if systemctl is-active --quiet firewalld; then
     firewall-cmd --permanent --add-service=ftp
     firewall-cmd --permanent --add-port=40000-40100/tcp
     firewall-cmd --reload
     echo "Firewall configurado para FTP"
  fi
}

configurar_selinux(){
  if getenforce 2>/dev/null | grep -q Enforcing; then
     setsebool -P ftpd_full_access 1
     setsebool -P ftpd_use_passive_mode 1
     echo "SELinux configurado para FTP"
  fi
}

echo "****** Tarea 5: Automatizacion de Servidor FTP ********"

instalar_ftp(){
  echo ""
  echo "Verificando si el servicio vsftpd esta instalado....."
  echo ""

  if rpm -q vsftpd &>/dev/null; then
    echo "El servicio vsftpd ya esta instalado :D"
    while true; do
      read -p "Desea reinstalarlo (s/n)?: " opcion
      echo ""
      case $opcion in
        s|S)
          echo "Reinstalando el servicio vsftpd...."
          dnf reinstall -y vsftpd > /dev/null 2>&1
          echo "Reinstalacion completada :D"
          break ;;
        n|N)
          echo "No se realizara ninguna accion"
          break ;;
        *)
          echo "Opcion invalida... ingrese s o n" ;;
      esac
    done
  else
    echo "El servicio vsftpd no esta instalado"
    echo "Instalando....."
    dnf install -y vsftpd > /dev/null 2>&1
    if rpm -q vsftpd &>/dev/null; then
      echo "Instalacion completada :D"
    else
      echo "Hubo un error en la instalacion."
    fi
  fi

  if ! systemctl is-enabled --quiet vsftpd; then
     echo "Habilitando servicio..."
     systemctl enable vsftpd
  fi

  if ! systemctl is-active --quiet vsftpd; then
     echo "Iniciando servicio..."
     systemctl start vsftpd
  fi

  configurar_firewall
  configurar_selinux
  read -p "Presione ENTER para continuar..."
}

# ─────────────────────────────────────────────
#  CONFIGURACION VSFTPD
# ─────────────────────────────────────────────
configurarftp(){
  CONF="/etc/vsftpd/vsftpd.conf"
  cp -n "$CONF" "$CONF.bak"

  # Sobreescribimos el archivo de configuracion completamente
  # para evitar conflictos de entradas duplicadas o contradictorias
  cat > "$CONF" << 'EOF'
# ── Acceso general ──────────────────────────
anonymous_enable=YES
local_enable=YES
write_enable=YES

# ── Acceso anonimo: solo lectura ─────────────
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO
# El anonimo aterriza en /ftp_anon (solo tiene symlink a general)
anon_root=/ftp_anon

# ── Chroot para usuarios locales ─────────────
# Cada usuario autenticado aterriza en su propio home
# que solo contiene sus 3 carpetas (general, grupo, personal)
chroot_local_user=YES
allow_writeable_chroot=YES

# El home de cada usuario sera /ftp/homes/<usuario>
# (se configura con useradd -d)

# ── Modo pasivo ──────────────────────────────
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

# ── Logging ──────────────────────────────────
xferlog_enable=YES
xferlog_std_format=YES

# ── Seguir symlinks dentro del chroot ────────
# IMPORTANTE: permite que los symlinks dentro del
# home del usuario apunten fuera del chroot
# (necesario para que general y grupo sean accesibles)
secure_chroot_dir=/var/run/vsftpd/empty
EOF

  # Habilitar follow_symlinks (parametro no estandar en algunos builds)
  # En Oracle Linux / RHEL el vsftpd sigue symlinks por defecto dentro del chroot
  # siempre que ftpd_full_access este activo en SELinux

  # Crear directorio requerido por secure_chroot_dir
  mkdir -p /var/run/vsftpd/empty
  chmod 755 /var/run/vsftpd/empty

  systemctl restart vsftpd
  echo "vsftpd configurado y reiniciado :D"
  read -p "Presione ENTER para continuar..."
}

# ─────────────────────────────────────────────
#  GRUPOS
# ─────────────────────────────────────────────
crear_grupo(){
  for g in reprobados recursadores ftpusuarios; do
    if getent group "$g" > /dev/null; then
      echo "El grupo '$g' ya existe"
    else
      echo "Creando grupo '$g'...."
      groupadd "$g"
    fi
  done
  read -p "Presione ENTER para continuar..."
}

# ─────────────────────────────────────────────
#  ESTRUCTURA BASE
# ─────────────────────────────────────────────
crear_estructura(){
  echo "Creando estructura base de directorios..."

  # Directorio raiz compartido (no es el chroot de nadie directamente)
  mkdir -p "$FTP_ROOT/general"
  mkdir -p "$FTP_ROOT/grupos/reprobados"
  mkdir -p "$FTP_ROOT/grupos/recursadores"
  mkdir -p "$FTP_ROOT/homes"

  # Directorio exclusivo para el anonimo
  mkdir -p "$ANON_ROOT"

  echo "Estructura base creada"
}

# ─────────────────────────────────────────────
#  PERMISOS BASE
# ─────────────────────────────────────────────
asignar_permisos(){
  echo "Asignando permisos base..."

  # /ftp root: root lo posee, no escribible por otros
  chown root:root "$FTP_ROOT"
  chmod 755 "$FTP_ROOT"

  # general: todos los usuarios FTP pueden escribir
  chown root:ftpusuarios "$FTP_ROOT/general"
  chmod 775 "$FTP_ROOT/general"

  # carpetas de grupo: solo miembros del grupo escriben
  chown root:reprobados  "$FTP_ROOT/grupos/reprobados"
  chown root:recursadores "$FTP_ROOT/grupos/recursadores"
  chmod 2770 "$FTP_ROOT/grupos/reprobados"
  chmod 2770 "$FTP_ROOT/grupos/recursadores"

  # homes: root lo posee
  chown root:root "$FTP_ROOT/homes"
  chmod 755 "$FTP_ROOT/homes"

  # ── Directorio anonimo ───────────────────────
  # El chroot del anonimo debe ser propiedad de root y NO escribible
  chown root:root "$ANON_ROOT"
  chmod 555 "$ANON_ROOT"

  # Symlink en anon_root que apunta a la carpeta general real
  # El anonimo solo vera "general"
  if [ ! -L "$ANON_ROOT/general" ]; then
    ln -s "$FTP_ROOT/general" "$ANON_ROOT/general"
  fi

  echo "Permisos base asignados :D"
  read -p "Presione ENTER para continuar..."
}

# ─────────────────────────────────────────────
#  CREAR CHROOT HOME PARA UN USUARIO
#  $1 = nombre de usuario
#  $2 = grupo (reprobados | recursadores)
# ─────────────────────────────────────────────
crear_home_usuario(){
  local nombre="$1"
  local grupo="$2"
  local home="$FTP_ROOT/homes/$nombre"

  # El directorio raiz del chroot DEBE ser de root y no escribible
  # (requisito de vsftpd con chroot_local_user=YES)
  mkdir -p "$home"
  chown root:root "$home"
  chmod 555 "$home"

  # ── Carpeta personal real ────────────────────
  mkdir -p "$home/private"
  chown "$nombre":"$grupo" "$home/private"
  chmod 700 "$home/private"

  # ── Symlinks visibles desde el chroot ────────
  # 1) general  -> carpeta publica
  if [ ! -L "$home/general" ]; then
    ln -s "$FTP_ROOT/general" "$home/general"
  fi

  # 2) grupo    -> carpeta del grupo al que pertenece
  #    (se llama igual que el grupo para que el usuario lo identifique)
  if [ ! -L "$home/$grupo" ]; then
    ln -s "$FTP_ROOT/grupos/$grupo" "$home/$grupo"
  fi

  # 3) carpeta personal -> apunta a private pero con el nombre del usuario
  if [ ! -L "$home/$nombre" ]; then
    ln -s "$home/private" "$home/$nombre"
  fi
}

# ─────────────────────────────────────────────
#  ELIMINAR SYMLINKS DE GRUPO DEL HOME
#  Para usar al cambiar de grupo
# ─────────────────────────────────────────────
limpiar_symlinks_grupo(){
  local nombre="$1"
  local home="$FTP_ROOT/homes/$nombre"
  # Eliminar symlinks de grupo (reprobados y recursadores)
  for g in reprobados recursadores; do
    if [ -L "$home/$g" ]; then
      rm -f "$home/$g"
    fi
  done
}

# ─────────────────────────────────────────────
#  CREAR USUARIOS
# ─────────────────────────────────────────────
crear_usuarios(){
  read -p "Ingrese el numero de usuarios a capturar: " usuarios
  for (( i=1; i<=usuarios; i++ )); do
    echo ""
    echo "── Usuario $i ──"
    read -p "Nombre de usuario: " nombre

    if id "$nombre" &>/dev/null; then
      echo "El usuario '$nombre' ya existe, se omite."
      continue
    fi

    read -s -p "Contrasena: " password
    echo ""
    read -p "Grupo (reprobados/recursadores): " grupo

    if [[ "$grupo" != "reprobados" && "$grupo" != "recursadores" ]]; then
       echo "Grupo invalido, se omite el usuario."
       continue
    fi

    # Crear usuario del sistema
    # -d: home es el chroot jail personalizado
    # -s /sbin/nologin: no puede hacer login por SSH
    # -g: grupo primario (define permisos de carpeta de grupo)
    # -G: grupos secundarios
    useradd -d "$FTP_ROOT/homes/$nombre" \
            -s /sbin/nologin \
            -g "$grupo" \
            -G ftpusuarios \
            "$nombre"

    echo "$nombre:$password" | chpasswd

    # Crear estructura de chroot con symlinks
    crear_home_usuario "$nombre" "$grupo"

    echo "Usuario '$nombre' creado en grupo '$grupo' :D"
  done
  read -p "Presione ENTER para continuar..."
}

# ─────────────────────────────────────────────
#  CAMBIAR GRUPO DE USUARIO
# ─────────────────────────────────────────────
cambiar_grupo_usuario(){
  echo ""
  echo "***** Cambiar de grupo a usuario *****"
  read -p "Ingrese el nombre del usuario: " nombre

  if ! id "$nombre" &>/dev/null; then
    echo "El usuario no existe"
    read -p "Presione ENTER para continuar..."
    return
  fi

  read -p "Ingrese el nuevo grupo (reprobados/recursadores): " nuevo_grupo
  if [[ "$nuevo_grupo" != "reprobados" && "$nuevo_grupo" != "recursadores" ]]; then
    echo "Grupo invalido"
    read -p "Presione ENTER para continuar..."
    return
  fi

  local grupo_actual
  grupo_actual=$(id -gn "$nombre")

  if [[ "$grupo_actual" == "$nuevo_grupo" ]]; then
    echo "El usuario ya pertenece al grupo '$nuevo_grupo'"
    read -p "Presione ENTER para continuar..."
    return
  fi

  # Cambiar grupo primario del usuario
  usermod -g "$nuevo_grupo" "$nombre"

  # Actualizar permisos de la carpeta personal
  local home="$FTP_ROOT/homes/$nombre"
  chown "$nombre":"$nuevo_grupo" "$home/private"

  # Eliminar symlink del grupo anterior y crear el nuevo
  limpiar_symlinks_grupo "$nombre"
  ln -s "$FTP_ROOT/grupos/$nuevo_grupo" "$home/$nuevo_grupo"

  echo "Grupo del usuario '$nombre' cambiado de '$grupo_actual' a '$nuevo_grupo' :D"
  echo "Ahora vera: general / $nuevo_grupo / $nombre"
  read -p "Presione ENTER para continuar..."
}

# ─────────────────────────────────────────────
#  MENU
# ─────────────────────────────────────────────
menu(){
  echo ""
  while true; do
    echo "============================================"
    echo "        Menu FTP - Tarea 5                  "
    echo "============================================"
    echo "1) Instalar servicio vsftpd"
    echo "2) Configurar vsftpd"
    echo "3) Crear grupos (reprobados, recursadores)"
    echo "4) Crear estructura base de directorios"
    echo "5) Asignar permisos base"
    echo "6) Crear usuarios"
    echo "7) Cambiar grupo de usuario"
    echo "0) Salir"
    echo "============================================"
    read -p "Seleccione una opcion: " opcion
    echo ""
    case $opcion in
      1) instalar_ftp ;;
      2) configurarftp ;;
      3) crear_grupo ;;
      4) crear_estructura ;;
      5) asignar_permisos ;;
      6) crear_usuarios ;;
      7) cambiar_grupo_usuario ;;
      0) exit 0 ;;
      *) echo "Opcion invalida"; sleep 1 ;;
    esac
  done
}

menu
