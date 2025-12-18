#!/bin/bash

# ==============================================================================
#  SCRIPT DE AUTO-INSTALACION ZABBIX AGENT 2 (UBUNTU / CENTOS / RHEL / ALMA)
#  Version: Zabbix 7.0 LTS
# ==============================================================================

# --- VARIABLES DE CONFIGURACION ---
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

# --- 2. CONFIGURACION DEL HOSTNAME (Interactivo) ---
CURRENT_HOST=$(hostname)
echo "Hostname actual: $CURRENT_HOST"
read -p "¿Deseas cambiar el Hostname de este servidor? (s/n): " CAMBIAR_HOST

if [[ "$CAMBIAR_HOST" == "s" || "$CAMBIAR_HOST" == "S" ]]; then
    read -p "Ingresa el NUEVO nombre de HOST: " NUEVO_HOST
    hostnamectl set-hostname "$NUEVO_HOST"
    echo "[OK] Hostname cambiado a: $NUEVO_HOST"
    # Actualizamos la variable para la config de zabbix
    CURRENT_HOST=$NUEVO_HOST 
else
    echo "[INFO] Se mantiene el hostname actual."
fi

# --- 3. DETECCION DE S.O. ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$
