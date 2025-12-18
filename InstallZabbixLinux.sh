#!/bin/bash
# ==============================================================================
#  SCRIPT DE AUTO-INSTALACION ZABBIX AGENT 2 (MULTI-OS)
#  Soporta: Ubuntu (20.04/22.04/24.04), Debian 12, RHEL/CentOS/Alma (7/8/9)
#  Version Zabbix: 7.0 LTS
# ==============================================================================

# --- VARIABLES ---
ZABBIX_SERVER_IPS="192.168.100.200,192.168.100.205,172.16.0.205"
ZABBIX_VER="7.0"

# --- 1. VERIFICAR ROOT ---
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root (sudo)."
  exit 1
fi

echo "=================================================="
echo "   INSTALADOR AUTOMATICO ZABBIX AGENT 2 ($ZABBIX_VER)"
echo "=================================================="

# --- 2. CONFIGURACION DEL HOSTNAME ---
CURRENT_HOST=$(hostname)
echo "Hostname actual: $CURRENT_HOST"
# Nota: Si lo ejecutas desatendido, puedes comentar estas lineas de read
if [ -t 0 ]; then
    read -p "¿Deseas cambiar el Hostname de este servidor? (s/n): " CAMBIAR_HOST
    if [[ "$CAMBIAR_HOST" == "s" || "$CAMBIAR_HOST" == "S" ]]; then
        read -p "Ingresa el NUEVO nombre de HOST: " NUEVO_HOST
        hostnamectl set-hostname "$NUEVO_HOST"
        echo "[OK] Hostname cambiado a: $NUEVO_HOST"
        CURRENT_HOST=$NUEVO_HOST 
    fi
else
    echo "[INFO] Ejecución no interactiva. Se mantiene hostname: $CURRENT_HOST"
fi

# --- 3. DETECCION DE S.O. Y LIMPIEZA ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER_ID=$VERSION_ID
    # Para RHEL/CentOS, tomamos solo el numero mayor (ej: 8.5 -> 8)
    MAJOR_VER=${VER_ID%%.*}
else
    echo "[ERROR] No se pudo detectar el sistema operativo."
    exit 1
fi

echo "[INFO] Detectado: $OS versión $VER_ID"

# Limpieza universal
echo "[INFO] Eliminando agentes antiguos..."
systemctl stop zabbix-agent zabbix-agent2 >/dev/null 2>&1 || true
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get remove --purge zabbix-agent zabbix-agent2 zabbix-release -y >/dev/null 2>&1
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
    yum remove zabbix-agent zabbix-agent2 zabbix-release -y >/dev/null 2>&1
fi

# --- 4. INSTALACION SEGUN S.O. ---

if [[ "$OS" == "ubuntu" ]]; then
    # UBUNTU LOGIC
    echo "[INFO] Instalando para Ubuntu $VER_ID..."
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-2+ubuntu${VER_ID}_all.deb"
    
    wget -O zabbix-release.deb "$REPO_URL"
    dpkg -i zabbix-release.deb
    apt-get update
    apt-get install zabbix-agent2 zabbix-agent2-plugin-* -y
    
    # Firewall UFW
    if command -v ufw >/dev/null; then
        ufw allow 10050/tcp
        ufw allow 10050/udp
        ufw reload
    fi

elif [[ "$OS" == "debian" ]]; then
    # DEBIAN LOGIC
    echo "[INFO] Instalando para Debian $VER_ID..."
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/debian/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-2+debian${VER_ID}_all.deb"
    
    wget -O zabbix-release.deb "$REPO_URL"
    dpkg -i zabbix-release.deb
    apt-get update
    apt-get install zabbix-agent2 zabbix-agent2-plugin-* -y

elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
    # RHEL/CENTOS LOGIC (7, 8, 9)
    echo "[INFO] Instalando para RHEL/CentOS/Alma $MAJOR_VER..."
    
    # URL dinamica basada en la version mayor (7, 8, 9)
    rpm -Uvh "https://repo.zabbix.com/zabbix/${ZABBIX_VER}/rhel/${MAJOR_VER}/x86_64/zabbix-release-${ZABBIX_VER}-2.el${MAJOR_VER}.noarch.rpm"
    
    yum clean all
    yum install zabbix-agent2 zabbix-agent2-plugin-* -y

    # Firewall Firewalld
    if command -v firewall-cmd >/dev/null; then
        firewall-cmd --permanent --add-port=10050/tcp
        firewall-cmd --reload
    fi
else
    echo "[ERROR] Sistema operativo $OS no soportado por este script."
    exit 1
fi

# --- 5. CONFIGURACION FINAL (sed) ---
CONF_FILE="/etc/zabbix/zabbix_agent2.conf"
echo "[INFO] Configurando $CONF_FILE..."

# Backup
cp "$CONF_FILE" "${CONF_FILE}.bak"

# Limpieza de parametros para evitar duplicados
sed -i '/^Hostname=/d' "$CONF_FILE"
sed -i '/^Server=/d' "$CONF_FILE"
sed -i '/^ServerActive=/d' "$CONF_FILE"
sed -i '/^Timeout=/d' "$CONF_FILE" # Limpiamos timeout viejo

# Inyección de nueva configuración
# Nota: Usamos echo >> para asegurar que se escriban al final
echo "Hostname=$CURRENT_HOST" >> "$CONF_FILE"
echo "Server=$ZABBIX_SERVER_IPS" >> "$CONF_FILE"
echo "ServerActive=$ZABBIX_SERVER_IPS" >> "$CONF_FILE"
echo "Timeout=30" >> "$CONF_FILE"

# --- 6. HABILITAR Y REINICIAR ---
echo "[INFO] Reiniciando servicio..."
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2

# Verificación simple
if systemctl is-active --quiet zabbix-agent2; then
    echo "=================================================="
    echo "   [EXITO] Zabbix Agent 2 instalado y corriendo."
    echo "   Hostname: $CURRENT_HOST"
    echo "=================================================="
else
    echo "=================================================="
    echo "   [ALERTA] El servicio no arrancó correctamente."
    echo "   Revisa: systemctl status zabbix-agent2"
    echo "=================================================="
fi
