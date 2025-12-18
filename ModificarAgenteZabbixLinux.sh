#!/bin/bash

# --- CONFIGURACION ---
# Definimos las variables que nos pediste
# Nota: En Linux usamos espacios o comas. Zabbix acepta comas sin espacios.
MIS_SERVIDORES="192.168.100.200,192.168.100.205,172.16.0.205"
MI_HOSTNAME=$(hostname) # Esto equivale al %COMPUTERNAME% de Windows

echo "=========================================="
echo "   CONFIGURADOR ZABBIX PARA LINUX"
echo "=========================================="

# 1. DETECTAR ARCHIVO DE CONFIGURACION
# Buscamos primero el agente 2, si no, el agente clásico.
if [ -f "/etc/zabbix/zabbix_agent2.conf" ]; then
    CONF_FILE="/etc/zabbix/zabbix_agent2.conf"
    SERVICE_NAME="zabbix-agent2"
    echo "[INFO] Detectado Zabbix Agent 2 en: $CONF_FILE"
elif [ -f "/etc/zabbix/zabbix_agentd.conf" ]; then
    CONF_FILE="/etc/zabbix/zabbix_agentd.conf"
    SERVICE_NAME="zabbix-agent"
    echo "[INFO] Detectado Zabbix Agent (Clásico) en: $CONF_FILE"
else
    echo "[ERROR] No se encontró archivo de configuración de Zabbix en /etc/zabbix/"
    exit 1
fi

# 2. BACKUP DEL ARCHIVO (Seguridad ante todo)
cp "$CONF_FILE" "$CONF_FILE.bak_$(date +%F_%T)"
echo "[OK] Backup creado."

# 3. LIMPIEZA DE CONFIGURACION ANTERIOR (Evitar duplicados)
# Usamos 'sed' para borrar completamente cualquier linea que empiece por Server=, ServerActive= o Hostname=
# Esto asegura que no queden lineas repetidas ni basura.
sed -i '/^Server=/d' "$CONF_FILE"
sed -i '/^ServerActive=/d' "$CONF_FILE"
sed -i '/^Hostname=/d' "$CONF_FILE"
echo "[OK] Lineas antiguas eliminadas."

# 4. INYECTAR NUEVA CONFIGURACION
# Agregamos las nuevas lineas al final del archivo
echo "Server=$MIS_SERVIDORES" >> "$CONF_FILE"
echo "ServerActive=$MIS_SERVIDORES" >> "$CONF_FILE"
echo "Hostname=$MI_HOSTNAME" >> "$CONF_FILE"
echo "[OK] Nuevos parametros aplicados."

# 5. REINICIAR SERVICIO
echo "[INFO] Reiniciando servicio $SERVICE_NAME..."
systemctl restart $SERVICE_NAME

# 6. VERIFICACION
if systemctl is-active --quiet $SERVICE_NAME; then
    echo "=========================================="
    echo "   EXITO: Servicio reiniciado correctamente"
    echo "   Hostname configurado: $MI_HOSTNAME"
    echo "=========================================="
else
    echo "=========================================="
    echo "   ALERTA: El servicio no arrancó. Revisa: systemctl status $SERVICE_NAME"
    echo "=========================================="
fi
