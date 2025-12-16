#!/bin/bash
# =========================================
# Debian “Okos” telepítő script
# =========================================
set +e
# ------------------------
# Színek
# ------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'
# ------------------------
# Log fájl
# ------------------------
LOGFILE="/var/log/pro_install.log"
declare -A RESULTS
declare -A INSTALLED_NOW
START_TIME=$(date +%s)
# ------------------------
# Root ellenőrzés
# ------------------------
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Root jogosultság szükséges!${RESET}"
   exit 1
fi
# ------------------------
# Segédfüggvények
# ------------------------
log() {
   echo "$(date '+%F %T') - $1" >> "$LOGFILE"
}
ask_yes_no() {
   while true; do
       read -rp "$1 (i/n): " yn
       case $yn in
           [Ii]*) return 0 ;;
           [Nn]*) return 1 ;;
           *) echo -e "${YELLOW}Csak i vagy n!${RESET}" ;;
       esac
   done
}
set_result() {
   RESULTS["$1"]="$2"
}
mark_installed() {
   INSTALLED_NOW["$1"]="igen"
}
check_service() {
   systemctl is-active --quiet "$1"
   if [[ $? -eq 0 ]]; then
       set_result "$2" "${GREEN}FUT / TELEPÍTVE${RESET}"
   else
       set_result "$2" "${RED}NINCS / NEM FUT${RESET}"
   fi
}
is_installed() {
   dpkg -s "$1" &> /dev/null
   return $?
}
remove_package() {
   echo -e "${YELLOW}Eltávolítás: $1${RESET}"
   apt remove -y "$1" >> "$LOGFILE" 2>&1
   apt autoremove -y >> "$LOGFILE" 2>&1
   echo -e "${GREEN}$1 eltávolítva!${RESET}"
}
install_package() {
   echo -e "${CYAN}Telepítés: $1${RESET}"
   apt install -y "$1" >> "$LOGFILE" 2>&1
   mark_installed "$1"
   echo -e "${GREEN}$1 telepítve!${RESET}"
}
# ------------------------
# Telepítési függvények
# ------------------------
apt update >> "$LOGFILE" 2>&1
install_apache_php() {
   echo -e "${CYAN}Apache + PHP telepítése...${RESET}"
   packages=(apache2 php php-mbstring php-mysql php-json php-curl)
   for pkg in "${packages[@]}"; do
       if is_installed "$pkg"; then
           echo -e "${YELLOW}$pkg már telepítve.${RESET}"
           ask_yes_no "Eltávolítod $pkg?" && remove_package "$pkg"
       else
           install_package "$pkg"
       fi
   done
   systemctl enable apache2
   systemctl start apache2
}
install_mariadb() {
   if is_installed mariadb-server; then
       echo -e "${YELLOW}MariaDB már telepítve.${RESET}"
       ask_yes_no "Eltávolítod MariaDB-t?" && remove_package mariadb-server
   else
       install_package mariadb-server
   fi
   systemctl enable mariadb
   systemctl start mariadb
   echo -e "${YELLOW}Adatbázis beállítása:${RESET}"
   read -rp "Felhasználónév: " DB_USER
   read -rsp "Jelszó: " DB_PASS
   echo
   read -rp "Adatbázis neve: " DB_NAME
   mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
   mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
   mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
   mysql -e "FLUSH PRIVILEGES;"
}
install_phpmyadmin() {
   if is_installed phpmyadmin; then
       echo -e "${YELLOW}phpMyAdmin már telepítve.${RESET}"
       ask_yes_no "Eltávolítod phpMyAdmin-t?" && remove_package phpmyadmin
   else
       install_package phpmyadmin
       ln -sf /usr/share/phpmyadmin /var/www/html/phpmyadmin
       chown -R www-data:www-data /usr/share/phpmyadmin
       chmod -R 755 /usr/share/phpmyadmin
       systemctl restart apache2
   fi
}
install_ssh() {
   if is_installed openssh-server; then
       echo -e "${YELLOW}SSH már telepítve.${RESET}"
       ask_yes_no "Eltávolítod SSH-t?" && remove_package openssh-server
   else
       install_package openssh-server
   fi
   systemctl enable ssh
   systemctl start ssh
}
install_mosquitto() {
   packages=(mosquitto mosquitto-clients)
   for pkg in "${packages[@]}"; do
       if is_installed "$pkg"; then
           echo -e "${YELLOW}$pkg már telepítve.${RESET}"
           ask_yes_no "Eltávolítod $pkg?" && remove_package "$pkg"
       else
           install_package "$pkg"
       fi
   done
   systemctl enable mosquitto
   systemctl start mosquitto
}
install_node_red() {
   if systemctl list-units --all | grep -q nodered.service; then
       echo -e "${YELLOW}Node-RED már telepítve.${RESET}"
       ask_yes_no "Eltávolítod Node-RED-t?" && systemctl stop nodered.service && remove_package nodered
   else
       install_package curl
       curl -fsSL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered | bash >> "$LOGFILE" 2>&1
       mark_installed "Node-RED"
   fi
   systemctl enable nodered.service
   systemctl start nodered.service
}
# ------------------------
# Menü
# ------------------------
clear
echo -e "${BLUE}==============================${RESET}"
echo -e "${BLUE} Válaszd ki mit telepítesz${RESET}"
echo -e "${BLUE}==============================${RESET}"
echo "1) Node-RED"
echo "2) Apache + PHP"
echo "3) Mosquitto MQTT"
echo "4) SSH"
echo "5) phpMyAdmin"
echo "6) Minden szükséges komponens telepítése"
echo "0) Kilépés"
echo
read -rp "Választás: " choice
case $choice in
   1)
       ask_yes_no "Apache + PHP kell?" && install_apache_php
       ask_yes_no "Mosquitto kell?" && install_mosquitto
       ask_yes_no "SSH kell?" && install_ssh
       install_node_red
       ;;
   2)
       install_apache_php
       ask_yes_no "MariaDB is kell?" && install_mariadb
       ;;
   3)
       install_mosquitto
       ;;
   4)
       install_ssh
       ;;
   5)
       install_apache_php
       install_mariadb
       install_phpmyadmin
       ;;
   6)
       echo -e "${CYAN}Automatikus telepítés: csak hiányzó csomagok kerülnek telepítésre...${RESET}"
       install_apache_php
       install_mariadb
       install_phpmyadmin
       install_ssh
       install_mosquitto
       install_node_red
       ;;
   0)
       exit 0
       ;;
   *)
       echo -e "${RED}Érvénytelen választás${RESET}"
       exit 1
       ;;
esac
# ------------------------
# Ellenőrzés
# ------------------------
check_service apache2 "Apache2"
check_service mariadb "MariaDB"
check_service mosquitto "Mosquitto"
check_service ssh "SSH"
check_service nodered.service "Node-RED"
# ------------------------
# Eredmények
# ------------------------
clear
echo -e "${BLUE}==============================${RESET}"
echo -e "${BLUE} Telepítési összegzés${RESET}"
echo -e "${BLUE}==============================${RESET}"
for key in "${!RESULTS[@]}"; do
   echo "$key : ${RESULTS[$key]}"
done
echo
echo -e "${CYAN}Most telepített komponensek:${RESET}"
if [[ ${#INSTALLED_NOW[@]} -eq 0 ]]; then
   echo " - Nem történt új telepítés"
else
   for key in "${!INSTALLED_NOW[@]}"; do
       echo " - $key"
   done
fi
# ------------------------
# Futási idő és rendszerinfo
# ------------------------
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))
echo
echo -e "${YELLOW}Script futási ideje: ${RUNTIME} másodperc${RESET}"
echo -e "${YELLOW}Rendszerinformáció:${RESET}"
uname -a
uptime
echo
echo -e "${YELLOW}Megjegyzés: Külső elérés esetén tűzfal használata ajánlott.${RESET}"
log "Script sikeresen lefutott"
