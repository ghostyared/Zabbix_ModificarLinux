#!/bin/bash

# ==============================================================================
#  SCRIPT MAESTRO ZABBIX AGENT 2 + SOPORTE ORACLE DB (19c / 12c)
#  Soporta: Oracle Linux (ol), RHEL, CentOS, Ubuntu, Debian
#  Version Zabbix: 7.0 LTS
# ==============================================================================

# --- 1. CONFIGURACION GENERAL ---
ZABBIX_SERVER_IPS="192.168.100.200,192.168.100.205,172.16.0.205"
ZABBIX_VER="7.0"

# --- 2. VARIABLES DE RUTAS ORACLE (EDITAR SI ES NECESARIO) ---
# Ruta exacta que me diste para 19c:
PATH_ORA_19C="/u01/app/oracle/19CEE"

# Ruta ESTANDAR para 12c (VERIFICA ESTA RUTA EN TUS SERVIDORES 12C):
# Podria ser /u01/app/oracle/product/12.1.0/dbhome_1 o similar
PATH_ORA_12C="/u01/app/oracle/product/12.2.0/dbhome_1"

# ==============================================================================

# --- VERIFICAR ROOT ---
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root (sudo)."
  exit 1
fi

echo "=================================================="
echo "   INSTALADOR ZABBIX AGENT 2 + ORACLE ENVIRONMENT"
echo "=================================================="

# --- CONFIGURACION DEL HOSTNAME ---
CURRENT_HOST=$(hostname)
if [ -t 0 ]; then
    echo "Hostname actual: $CURRENT_HOST"
    read -p "¿Deseas cambiar el Hostname? (s/n): " CAMBIAR_HOST
    if [[ "$CAMBIAR_HOST" == "s" || "$CAMBIAR_HOST" == "S" ]]; then
        read -p "Ingresa el NUEVO nombre de HOST: " NUEVO_HOST
        hostnamectl set-hostname "$NUEVO_HOST"
        CURRENT_HOST=$NUEVO_HOST 
    fi
fi

# --- DETECCION DE S.O. ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER_ID=$VERSION_ID
    MAJOR_VER=${VER_ID%%.*} # Para RHEL/OL sacar version mayor (8, 9)
else
    echo "[ERROR] No se pudo detectar el sistema operativo."
    exit 1
fi

echo "[INFO] Sistema: $OS ($VER_ID) - Base: $MAJOR_VER"

# --- LIMPIEZA PREVIA ---
systemctl stop zabbix-agent zabbix-agent2 >/dev/null 2>&1 || true

# --- INSTALACION (Usa logica corregida para OL) ---
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt-get remove --purge zabbix-agent zabbix-agent2 zabbix-release -y >/dev/null 2>&1
    
    # URL Builder
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-2+ubuntu${VER_ID}_all.deb"
    [[ "$OS" == "debian" ]] && REPO_URL=${REPO_URL//ubuntu/debian}
    
    wget -O zabbix-release.deb "$REPO_URL"
    dpkg -i zabbix-release.deb
    apt-get update
    apt-get install zabbix-agent2 zabbix-agent2-plugin-* -y
    [[ -x "$(command -v ufw)" ]] && ufw allow 10050/tcp && ufw reload

elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "almalinux" || "$OS" == "rocky" || "$OS" == "ol" ]]; then
    yum remove zabbix-agent zabbix-agent2 zabbix-release -y >/dev/null 2>&1
    
    echo "[INFO] Instalando Repositorio Zabbix para RHEL/OL $MAJOR_VER..."
    rpm -Uvh "https://repo.zabbix.com/zabbix/${ZABBIX_VER}/rhel/${MAJOR_VER}/x86_64/zabbix-release-${ZABBIX_VER}-2.el${MAJOR_VER}.noarch.rpm"
    
    yum clean all
    yum install zabbix-agent2 zabbix-agent2-plugin-* -y
    
    if command -v firewall-cmd >/dev/null; then
        firewall-cmd --permanent --add-port=10050/tcp
        firewall-cmd --reload
    fi
else
    echo "[ERROR] OS no soportado."
    exit 1
fi

# --- CONFIGURACION ORACLE (DETECTAR VERSION) ---
ENV_FILE="/etc/sysconfig/zabbix-agent2"
ORA_FOUND=0

echo "[INFO] Buscando instalaciones de Oracle Database..."

if [ -d "$PATH_ORA_19C" ]; then
    echo "[DETECTADO] Oracle 19c en: $PATH_ORA_19C"
    echo "ORACLE_HOME=$PATH_ORA_19C" > $ENV_FILE
    echo "LD_LIBRARY_PATH=$PATH_ORA_19C/lib" >> $ENV_FILE
    ORA_FOUND=1
elif [ -d "$PATH_ORA_12C" ]; then
    echo "[DETECTADO] Oracle 12c en: $PATH_ORA_12C"
    echo "ORACLE_HOME=$PATH_ORA_12C" > $ENV_FILE
    echo "LD_LIBRARY_PATH=$PATH_ORA_12C/lib" >> $ENV_FILE
    ORA_FOUND=1
else
    echo "[AVISO] No se detectaron rutas de Oracle conocidas."
    echo "[AVISO] El agente se instalara SIN variables de entorno Oracle."
fi

if [ $ORA_FOUND -eq 1 ]; then
    chmod 644 $ENV_FILE
    echo "[OK] Variables de entorno inyectadas en $ENV_FILE"
fi

# --- CONFIGURACION AGENTE ---
CONF_FILE="/etc/zabbix/zabbix_agent2.conf"
cp "$CONF_FILE" "${CONF_FILE}.bak"

sed -i '/^Hostname=/d' "$CONF_FILE"
sed -i '/^Server=/d' "$CONF_FILE"
sed -i '/^ServerActive=/d' "$CONF_FILE"
sed -i '/^Timeout=/d' "$CONF_FILE"

echo "Hostname=$CURRENT_HOST" >> "$CONF_FILE"
echo "Server=$ZABBIX_SERVER_IPS" >> "$CONF_FILE"
echo "ServerActive=$ZABBIX_SERVER_IPS" >> "$CONF_FILE"
echo "Timeout=30" >> "$CONF_FILE"

# --- INICIO ---
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2

if systemctl is-active --quiet zabbix-agent2; then
    echo "=================================================="
    echo "   [EXITO] Zabbix instalado en $OS ($CURRENT_HOST)"
    if [ $ORA_FOUND -eq 1 ]; then
        echo "   [ORACLE] Configurado correctamente."
    fi
    echo "=================================================="
else
    echo "[FAIL] El servicio no arranco. Revisa: systemctl status zabbix-agent2"
fi
