#!/bin/bash
set -e

START_PORT=37008
COUNT=2
BASE_DIR="$(pwd)"

echo "===================================="
echo "  MIKROCATA FULL INSTALACION"
echo "===================================="

# -------------------------------------------------
# 1. DEPENDENCIAS SISTEMA
# -------------------------------------------------
echo "[1/9] Instalando dependencias..."

sudo apt-get update
sudo apt-get install -y \
    git python3 python3-pip systemd wget curl

sudo pip3 install --break-system-packages routeros-api

# -------------------------------------------------
# 2. STAMUSCTL
# -------------------------------------------------
echo "[2/9] Instalando stamusctl..."

if ! command -v stamusctl >/dev/null; then
    wget -q https://github.com/StamusNetworks/stamusctl/releases/latest/download/stamusctl-linux-amd64
    chmod +x stamusctl-linux-amd64
    sudo mv stamusctl-linux-amd64 /usr/local/bin/stamusctl
fi

stamusctl compose init || true

# -------------------------------------------------
# 3. REPO
# -------------------------------------------------
echo "[3/9] Descargando Mikrocata..."

if [ ! -d "$BASE_DIR/mikrocata2selks" ]; then
    git clone https://github.com/angolo40/mikrocata2selks.git
fi

# -------------------------------------------------
# 4. VALIDACIÓN CRÍTICA
# -------------------------------------------------
echo "[4/9] Validando entorno..."

MIKRO_SCRIPT=$(find "$BASE_DIR/mikrocata2selks" -name "*.py" | head -n 1)

if [ -z "$MIKRO_SCRIPT" ]; then
    echo "❌ ERROR: No se encontró script Python en el repo"
    exit 1
fi

python3 -m py_compile "$MIKRO_SCRIPT" || {
    echo "❌ ERROR: Python con errores de sintaxis"
    exit 1
}

echo "✔ Script válido: $MIKRO_SCRIPT"

# -------------------------------------------------
# 5. PREPARACIÓN TZSP
# -------------------------------------------------
echo "[5/9] Preparando TZSP..."

sudo mkdir -p /etc/systemd/network
sudo mkdir -p /etc/systemd/system
sudo mkdir -p /var/lib/mikrocata

# -------------------------------------------------
# 6. CREACIÓN INSTANCIAS
# -------------------------------------------------
echo "[6/9] Creando instancias..."

for ((i=0; i<COUNT; i++))
do
    TZSP="tzsp$i"

    # Interfaces systemd
    cp "$BASE_DIR/mikrocata2selks/tzsp.netdev" /etc/systemd/network/${TZSP}.netdev
    cp "$BASE_DIR/mikrocata2selks/tzsp.network" /etc/systemd/network/${TZSP}.network

    sed -i "s/tzsp0/${TZSP}/g" /etc/systemd/network/${TZSP}.netdev
    sed -i "s/tzsp0/${TZSP}/g" /etc/systemd/network/${TZSP}.network

    # Python
    sudo cp "$MIKRO_SCRIPT" /usr/local/bin/mikrocata${TZSP}.py
    sudo chmod +x /usr/local/bin/mikrocata${TZSP}.py

    # Systemd service
    sudo tee /etc/systemd/system/mikrocata${TZSP}.service > /dev/null <<EOF
[Unit]
Description=Mikrocata ${TZSP}
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/mikrocata${TZSP}.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Data files
    sudo touch /var/lib/mikrocata/savelists-${TZSP}.json
    sudo touch /var/lib/mikrocata/uptime-${TZSP}.bookmark
    sudo touch /var/lib/mikrocata/ignore-${TZSP}.conf

done

# -------------------------------------------------
# 7. SYSTEMD RECARGA
# -------------------------------------------------
echo "[7/9] Recargando systemd..."

systemctl daemon-reload
systemctl enable systemd-networkd || true
systemctl restart systemd-networkd || true

# -------------------------------------------------
# 8. ENABLE SERVICIOS
# -------------------------------------------------
echo "[8/9] Habilitando servicios..."

for ((i=0; i<COUNT; i++))
do
    TZSP="tzsp$i"
    systemctl enable mikrocata${TZSP}.service
done

# -------------------------------------------------
# 9. START + VERIFICACIÓN
# -------------------------------------------------
echo "[9/9] Iniciando servicios..."

for ((i=0; i<COUNT; i++))
do
    TZSP="tzsp$i"

    systemctl start mikrocata${TZSP}.service

    sleep 1

    systemctl is-active --quiet mikrocata${TZSP}.service || {
        echo "❌ ERROR: mikrocata${TZSP} no arrancó"
        systemctl status mikrocata${TZSP}.service
        exit 1
    }

    echo "✔ mikrocata${TZSP} OK"
done

echo "===================================="
echo " INSTALACIÓN COMPLETADA CORRECTAMENTE"
echo "===================================="
