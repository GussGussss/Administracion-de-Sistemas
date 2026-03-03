configurar_firewall(){
  if systemctl is-active --quiet firewalld; then
     firewall-cmd --permanent --add-service=ftp
     firewall-cmd --permanent --add-port=40000-40100/tcp
     firewall-cmd --reload
     echo "Firewall configurado para FTP"
  fi
}

