#!/bin/bash

# ==============================================================================
#  SCRIPT DE AUTO-INSTALACION ZABBIX AGENT 2 (ORACLE LINUX / RHEL / UBUNTU)
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
echo "   INSTALADOR MANUAL ZABBIX AGENT 2 ($ZABBIX_VER)"
echo "=================================================="

# --- 2. CONFIGURACION DEL HOSTNAME ---
CURRENT_HOST=$(hostname)
echo "Hostname actual: $CURRENT_HOST"

# Detección para ejecución automática (sin espera)
if [ -t 0 ]; then
    read -p "¿Deseas cambiar el Hostname? (s/n): " CAMBIAR_HOST
    if [[ "$CAMBIAR_HOST" == "s" || "$CAMBIAR_HOST" == "S" ]]; then
        read -p "Ingresa el NUEVO nombre de HOST: " NUEVO_HOST
        hostnamectl set-hostname "$NUEVO_HOST"
        CURRENT_HOST=$NUEVO_HOST 
    fi
fi

# --- 3. DETECCION DE S.O. ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER_ID=$VERSION_ID
    # Extraer versión mayor (ej: 8.6 -> 8)
    MAJOR_VER=${VER_ID%%.*}
else
    echo "[ERROR] No se pudo detectar el sistema operativo."
    exit 1
fi

echo "[INFO] Sistema: $OS ($VER_ID) - Base RHEL: $MAJOR_VER"

# Limpieza previa
systemctl stop zabbix-agent zabbix-agent2 >/dev/null 2>&1 || true

# --- 4. INSTALACION ---

# BLOQUE DEBIAN/UBUNTU
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get remove --purge zabbix-agent zabbix-agent2 zabbix-release -y >/dev/null 2>&1
    
    echo "[INFO] Instalando DEB para $OS..."
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-2+ubuntu${VER_ID}_all.deb"
    if [[ "$OS" == "debian" ]]; then
        REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/debian/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-2+debian${VER_ID}_all.deb"
    fi
    
    wget -O zabbix-release.deb "$REPO_URL"
    dpkg -i zabbix-release.deb
    apt-get update
    apt-get install zabbix-agent2 zabbix-agent2-plugin-* -y
    
    if command -v ufw >/dev/null; then ufw allow 10050/tcp && ufw reload; fi

# BLOQUE RHEL / CENTOS / ORACLE (AQUI ESTÁ LA CLAVE "ol")
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "almalinux" || "$OS" == "rocky" || "$OS" == "ol" ]]; then
    
    yum remove zabbix-agent zabbix-agent2 zabbix-release -y >/dev/null 2>&1
    echo "[INFO] Instalando RPM para RHEL/Oracle versión $MAJOR_VER..."
    
    # URL oficial de Zabbix para RHEL (Oracle Linux es 100% compatible binario con RHEL)
    rpm -Uvh "https://repo.zabbix.com/zabbix/${ZABBIX_VER}/rhel/${MAJOR_VER}/x86_64/zabbix-release-${ZABBIX_VER}-2.el${MAJOR_VER}.noarch.rpm"
    
    yum clean all
    yum install zabbix-agent2 zabbix-agent2-plugin-* -y

    # Firewall
    if command -v firewall-cmd >/dev/null; then
        firewall-cmd --permanent --add-port=10050/tcp
        firewall-cmd --reload
    fi

else
    echo "[ERROR] Sistema operativo $OS no soportado por este script."
    exit 1
fi

# --- 5. CONFIGURACION ---
CONF_FILE="/etc/zabbix/zabbix_agent2.conf"
echo "[INFO] Configurando $CONF_FILE..."

cp "$CONF_FILE" "${CONF_FILE}.bak"

# Borrar config vieja
sed -i '/^Hostname=/d' "$CONF_FILE"
sed -i '/^Server=/d' "$CONF_FILE"
sed -i '/^ServerActive=/d' "$CONF_FILE"
sed -i '/^Timeout=/d' "$CONF_FILE"

# Escribir config nueva
echo "Hostname=$CURRENT_HOST" >> "$CONF_FILE"
echo "Server=$ZABBIX_SERVER_IPS" >> "$CONF_FILE"
echo "ServerActive=$ZABBIX_SERVER_IPS" >> "$CONF_FILE"
echo "Timeout=30" >> "$CONF_FILE"

# --- 6. INICIO ---
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2

if systemctl is-active --quiet zabbix-agent2; then
    echo "=================================================="
    echo "   [EXITO] Zabbix Agent 2 instalado en Oracle Linux"
    echo "=================================================="
else
    echo "[ERROR] Falló el inicio del servicio."
    systemctl status zabbix-agent2 --no-pager
fi
