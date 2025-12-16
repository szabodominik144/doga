#!/bin/bash
### ================== ALAP BEÁLLÍTÁSOK ==================
LOGFILE="/var/log/pro_install.log"
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"
set -eE
START_TIME=$(date +%s)
echo "===== Script indult: $(date) =====" >> "$LOGFILE"
trap 'echo -e "${RED}Hiba történt a script futása közben!${NC}";
     echo "HIBA $(date)" >> "$LOGFILE";
     exit 1' ERR

### ================== ROOT ELLENŐRZÉS ==================
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Root jogosultság szükséges!${NC}"
  echo "A script root jogosultságokkal futtatható, használd a sudo parancsot."
  exit 1
fi

### ================== SEGÉD FÜGGVÉNYEK ==================
log() {
  echo "$(date '+%F %T') - $1" >> "$LOGFILE"
}

ask_yes_no() {
  while true; do
    read -rp "$1 (i/n): " yn
    case $yn in
      [iI]*) return 0 ;;
      [nN]*) return 1 ;;
      *) echo "Csak i vagy n válasz megengedett!" ;;
    esac
  done
}

declare -A RESULTS
set_result() {
  RESULTS["$1"]="$2"
}

check_service_if_exists() {
  if systemctl list-unit-files | grep -q "^$1"; then
    systemctl is-active --quiet "$1" \
      && set_result "$2" "SIKERES" \
      || set_result "$2" "HIBA"
  fi
}

### ================== APT LOCK VÁRÁS ==================
while fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
  sleep 2
done

clear
echo -e "${BLUE}Rendszer frissítése...${NC}"
apt update >> "$LOGFILE" 2>&1

### ================== TELEPÍTŐ FÜGGVÉNYEK ==================

install_apache() {
  echo -e "${GREEN}Apache telepítése...${NC}"
  log "Apache telepítés"
  apt install -y apache2 libapache2-mod-php >> "$LOGFILE" 2>&1
  systemctl enable --now apache2
}

install_php() {
  echo -e "${GREEN}PHP telepítése...${NC}"
  log "PHP telepítés"
  apt install -y php php-mbstring php-zip php-gd php-json php-curl php-mysql >> "$LOGFILE" 2>&1
}

install_ssh() {
  echo -e "${GREEN}SSH telepítése...${NC}"
  log "SSH telepítés"
  apt install -y openssh-server >> "$LOGFILE" 2>&1
  systemctl enable --now ssh
}

install_mosquitto() {
  echo -e "${GREEN}Mosquitto telepítése...${NC}"
  log "Mosquitto telepítés"
  apt install -y mosquitto mosquitto-clients >> "$LOGFILE" 2>&1
  systemctl enable --now mosquitto
}

install_mariadb() {
  echo -e "${GREEN}MariaDB telepítése...${NC}"
  log "MariaDB telepítés"
  apt install -y mariadb-server >> "$LOGFILE" 2>&1
  systemctl enable --now mariadb
  echo
  echo "Adatbázis beállítása:"
  read -rp "Felhasználónév: " DB_USER
  read -rsp "Jelszó: " DB_PASS
  echo
  read -rp "Adatbázis neve: " DB_NAME
  mysql <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
  unset DB_PASS
}

install_node_red() {
  echo -e "${GREEN}Node-RED telepítése...${NC}"
  log "Node-RED telepítés"
  command -v curl >/dev/null || apt install -y curl >> "$LOGFILE" 2>&1
  curl -fsSL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered | bash
  systemctl enable --now nodered.service
}

install_phpmyadmin() {
  echo -e "${GREEN}phpMyAdmin telepítése...${NC}"
  log "phpMyAdmin telepítés"
  DEBIAN_FRONTEND=noninteractive apt install -y phpmyadmin >> "$LOGFILE" 2>&1
}

### ================== MENÜ ==================
clear
echo "======================================"
echo "        DEBIAN TELEPÍTŐ MENÜ"
echo "======================================"
echo "1) Node-RED"
echo "2) Apache + PHP"
echo "3) Mosquitto MQTT"
echo "4) SSH"
echo "5) phpMyAdmin"
echo "0) Kilépés"
echo "======================================"
read -rp "Választás: " choice
case $choice in
  1)
    ask_yes_no "Apache + PHP szükséges lehet. Telepíted?" && install_apache && install_php
    ask_yes_no "Mosquitto szükséges lehet. Telepíted?" && install_mosquitto
    ask_yes_no "SSH szükséges lehet. Telepíted?" && install_ssh
    install_node_red
    ;;
  2)
    install_apache
    install_php
    ask_yes_no "MariaDB is kell?" && install_mariadb
    ;;
  3)
    install_mosquitto
    ;;
  4)
    install_ssh
    ;;
  5)
    ask_yes_no "Apache + PHP szükséges. Telepíted?" && install_apache && install_php
    ask_yes_no "MariaDB szükséges. Telepíted?" && install_mariadb
    install_phpmyadmin
    ;;
  0)
    exit 0
    ;;
  *)
    echo -e "${RED}Érvénytelen választás!${NC}"
    exit 1
    ;;
esac

### ================== ELLENŐRZÉS ==================
check_service_if_exists apache2.service "Apache2"
check_service_if_exists ssh.service "SSH"
check_service_if_exists mosquitto.service "Mosquitto"
check_service_if_exists nodered.service "Node-RED"
check_service_if_exists mariadb.service "MariaDB"

clear
echo "======================================"
echo "        TELEPÍTÉSI EREDMÉNYEK"
echo "======================================"
for key in "${!RESULTS[@]}"; do
  echo "$key : ${RESULTS[$key]}"
done

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))
echo
echo -e "${GREEN}Script futási ideje: ${RUNTIME} másodperc${NC}"
echo
echo "Rendszerinformáció:"
uname -a
uptime
echo
echo -e "${YELLOW}Megjegyzés:${NC} Nyitott szolgáltatások esetén tűzfal használata ajánlott."
log "Script sikeresen lefutott"
