if [[ $EUID -ne 0 ]]; then
  echo "El script debe de ejecutarse como root :D"
  exit 1
fi

configurar_firewall(){
  if systemctl is-active --quiet firewalld; then
     firewall-cmd --permanent --add-service=ftp
     firewall-cmd --permanent --add-port=40000-40100/tcp
     firewall-cmd --reload
     echo "Firewall configurado para FTP"
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
          echo ""
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
    echo ""
    echo "Instalado....."
    dnf install -y vsftpd > /dev/null 2>&1
    dnf install -y acl > /dev/null 2>&1
      if rpm -q vsftpd &>/dev/null; then
  			echo "Instalación completada :D"
  		else
  			echo "Hubo un error en la instalación."
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

configurarftp(){
  CONF="/etc/vsftpd/vsftpd.conf"
  cp -n "$CONF" "$CONF.bak"
  
  #cp -n /etc/vsftpd.conf /etc/vsftpd.conf.bak

  pasv_min_port=40000
  pasv_max_port=40100

  if grep -q "^anonymous_enable" "$CONF"; then
    sed -i "s/^anonymous_enable=.*/anonymous_enable=YES/" "$CONF"
  else
    echo "anonymous_enable=YES" >> "$CONF"
  fi
  
  if grep -q "^local_enable" "$CONF"; then
    sed -i "s/^local_enable=.*/local_enable=YES/" "$CONF"
  else
    echo "local_enable=YES" >> "$CONF"
  fi
  
  if grep -q "^write_enable" "$CONF"; then
    sed -i "s/^write_enable=.*/write_enable=YES/" "$CONF"
  else
    echo "write_enable=YES" >> "$CONF"
  fi
  
  if grep -q "^chroot_local_user" "$CONF"; then
    sed -i "s/^chroot_local_user=.*/chroot_local_user=YES/" "$CONF"
  else
    echo "chroot_local_user=YES" >> "$CONF"
  fi

  if grep -q "^allow_writeable_chroot" "$CONF"; then
    sed -i "s/^allow_writeable_chroot=.*/allow_writeable_chroot=YES/" "$CONF"
  else
    echo "allow_writeable_chroot=YES" >> "$CONF"
  fi

  if grep -q "^pasv_enable" "$CONF"; then
    sed -i "s/^pasv_enable=.*/pasv_enable=YES/" "$CONF"
  else
    echo "pasv_enable=YES" >> "$CONF"
  fi

  if ! grep -q "^pasv_min_port" "$CONF"; then
    echo "pasv_min_port=40000" >> "$CONF"
  fi
  
  if ! grep -q "^pasv_max_port" "$CONF"; then
    echo "pasv_max_port=40100" >> "$CONF"
  fi

  if ! grep -q "^anon_upload_enable" "$CONF"; then
    echo "anon_upload_enable=NO" >> "$CONF"
  fi
  
  if ! grep -q "^anon_mkdir_write_enable" "$CONF"; then
    echo "anon_mkdir_write_enable=NO" >> "$CONF"
  fi

  if ! grep -q "^hide_ids" "$CONF"; then
    echo "hide_ids=YES" >> "$CONF"
  fi

  if ! grep -q "^local_umask" "$CONF"; then
    echo "local_umask=002" >> "$CONF"
  fi

  if ! grep -q "^anon_world_readable_only" "$CONF"; then
    echo "anon_world_readable_only=YES" >> "$CONF"
  fi

  if ! grep -q "^hide_file" "$CONF"; then
    echo 'hide_file={public,users}' >> "$CONF"
  fi

  if grep -q "^anon_root" "$CONF"; then
    sed -i "s|^anon_root=.*|anon_root=/ftp/public|" "$CONF"
  else
    echo "anon_root=/ftp/public" >> "$CONF"
  fi

  systemctl restart vsftpd
}

crear_grupo(){
  if getent group reprobados > /dev/null; then
    echo "El grupo reprobados ya existe"
  else
    echo "Creando grupo reprobados...."
    groupadd reprobados
  fi

  if getent group recursadores > /dev/null; then
    echo "El grupo recursadores ya existe"
  else
    echo "Creando grupo recursadores...."
    groupadd recursadores
  fi

  if ! getent group ftpusuarios > /dev/null; then
    groupadd ftpusuarios
  fi     
}

crear_estructura(){

  mkdir -p /ftp/public/general
  mkdir -p /ftp/users/{reprobados,recursadores}

  mkdir -p /ftp/general
  
  if ! mount | grep -q "/ftp/general"; then
    mount --bind /ftp/public/general /ftp/general
  fi
  ln -sfn /ftp/users/reprobados /ftp/reprobados
  ln -sfn /ftp/users/recursadores /ftp/recursadores

  chmod 755 /ftp
  chmod 755 /ftp/public
  chmod 775 /ftp/public/general

}

asignar_permisos(){

  chown root:root /ftp
  chmod 755 /ftp

  chmod 710 /ftp/users

  chown root:reprobados /ftp/users/reprobados
  chown root:recursadores /ftp/users/recursadores

  chmod 2770 /ftp/users/reprobados
  chmod 2770 /ftp/users/recursadores
  
  chown root:ftpusuarios /ftp/public/general
  chmod 775 /ftp/public/general

  setfacl -m g:ftpusuarios:rwx /ftp/public/general

  setfacl -m u:ftp:rx /ftp
  setfacl -m u:ftp:rx /ftp/public
  setfacl -m u:ftp:rx /ftp/public/general
}
crear_usuarios(){
  read -p "Ingrese el numero de usuarios a capturar: " usuarios

  for (( i=1; i<=usuarios; i++ )); do

    echo "Usuario $i"
    read -p "Nombre de usuario: " nombre

    if id "$nombre" &>/dev/null; then
      echo "El usuario ya existe"
      continue
    fi

    read -p "Contraseña: " password
    read -p "Grupo (reprobados/recursadores): " grupo

    if [[ "$grupo" != "reprobados" && "$grupo" != "recursadores" ]]; then
      echo "Grupo inválido"
      continue
    fi

    useradd -m -d /ftp/users/$nombre -s /sbin/nologin -g "$grupo" "$nombre"
    echo "$nombre:$password" | chpasswd
  
  mkdir -p /ftp/users/$nombre/{general,$grupo,$nombre}

  # Montajes bind
  if ! mountpoint -q /ftp/users/$nombre/general; then
    mount --bind /ftp/public/general /ftp/users/$nombre/general
  fi
  
  if ! mountpoint -q /ftp/users/$nombre/$grupo; then
    mount --bind /ftp/users/$grupo /ftp/users/$nombre/$grupo
  fi
  
  # Permisos
  chown -R $nombre:$grupo /ftp/users/$nombre/$nombre
  chmod 700 /ftp/users/$nombre/$nombre
  
  chown :$grupo /ftp/users/$nombre/$grupo
  chmod 775 /ftp/users/$nombre/$grupo

  done
}

cambiar_grupo_usuario(){

  echo ""
  echo "***** Cambiar de grupo a usuario *****"

  read -p "Ingrese el nombre del usuario: " nombre

  if ! id "$nombre" &>/dev/null; then
    echo "El usuario no existe"
    return
  fi

  read -p "Ingrese el nuevo grupo (reprobados/recursadores): " nuevo_grupo

  if [[ "$nuevo_grupo" != "reprobados" && "$nuevo_grupo" != "recursadores" ]]; then
    echo "Grupo inválido"
    return
  fi

  usermod -g "$nuevo_grupo" "$nombre"
  chown "$nombre":"$nuevo_grupo" /ftp/users/"$nombre"
  
  setfacl -x u:$nombre /ftp/users/reprobados
  setfacl -x u:$nombre /ftp/users/recursadores
  setfacl -m u:$nombre:rx /ftp
  setfacl -m u:$nombre:rwx /ftp/users/"$nuevo_grupo"

  echo "Grupo del usuario $nombre actualizado :D"
}

configurar_selinux(){
  if getenforce | grep -q Enforcing; then
     setsebool -P ftpd_full_access 1
     echo "SELinux configurado para FTP"
  fi
}

menu(){
  echo ""
  while true; do  
    echo "***** Menu FTP *****"
    echo "1) instalar servicio FTP"
    echo "2) Configurar vsftpd"
    echo "3) Crear grupos"
    echo "4) Crear estructura base"
    echo "5) Asignar permisos base"
    echo "6) Crear usuarios"
    echo "7) Cambiar grupo usuario"
    echo "0) Salir"
    read -p "Seleccione una opcion: " opcion
    case $opcion in
      1)instalar_ftp ;;
      2)configurarftp ;;
      3)crear_grupo ;;
      4)crear_estructura ;;
      5)asignar_permisos ;;
      6)crear_usuarios ;;
      7)cambiar_grupo_usuario ;;
      0)exit 0;;
      *) echo "opcion invalida"; sleep 1;;
    esac
  done
}

menu
