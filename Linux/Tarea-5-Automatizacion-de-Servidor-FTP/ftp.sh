if [[ $EUID -ne 0 ]]; then
  echo "El script debe de ejecutarse como root :D"
  exit 1
fi

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
  
  read -p "Presione ENTER para continuar..."
}

configurarftp(){
  cp -n /etc/vsftpd.conf /etc/vsftpd.conf.bak

  if grep -q "^anonymous_enable" /etc/vsftpd.conf; then
    sed -i "s/^anonymous_enable=.*/anonymous_enable=YES/" /etc/vsftpd.conf
  else
    echo "anonymous_enable=YES" >> /etc/vsftpd.conf
  fi
  
  if grep -q "^local_enable" /etc/vsftpd.conf; then
    sed -i "s/^local_enable=.*/local_enable=YES/" /etc/vsftpd.conf
  else
    echo "local_enable=YES" >> /etc/vsftpd.conf
  fi
  
  if grep -q "^write_enable" /etc/vsftpd.conf; then
    sed -i "s/^write_enable=.*/write_enable=YES/" /etc/vsftpd.conf
  else
    echo "write_enable=YES" >> /etc/vsftpd.conf
  fi
  
  if grep -q "^chroot_local_user" /etc/vsftpd.conf; then
    sed -i "s/^chroot_local_user=.*/chroot_local_user=YES/" /etc/vsftpd.conf
  else
    echo "chroot_local_user=YES" >> /etc/vsftpd.conf
  fi

  if grep -q "^allow_writeable_chroot" /etc/vsftpd.conf; then
    sed -i "s/^allow_writeable_chroot=.*/allow_writeable_chroot=YES/" /etc/vsftpd.conf
  else
    echo "allow_writeable_chroot=YES" >> /etc/vsftpd.conf
  fi

  if grep -q "^pasv_enable" /etc/vsftpd.conf; then
    sed -i "s/^pasv_enable=.*/pasv_enable=YES/" /etc/vsftpd.conf
  else
    echo "pasv_enable=YES" >> /etc/vsftpd.conf
  fi
  
  systemctl restart vsftpd
}

menu(){
  echo ""
  while true; do  
    echo "***** Menu FTP *****"
    echo "1) instalar servicio FTP"
    read -p "Seleccione una opcion: " opcion
    case $opcion in
      1)instalar_ftp ;;
      0)exit 0;;
      *) echo "opcion invalida"; sleep 1;;
    esac
  done
}

menu
