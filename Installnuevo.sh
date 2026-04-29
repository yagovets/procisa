
#!/bin/bash

set -e

COUNT=2
START_PORT=37008
BASE_DIR="$(pwd)"

echo "===================================="
echo "   NDR INSTALL (MIKROTIK EXTERNO)"
echo "===================================="

# =====================================
# 1. DEPENDENCIAS
# =====================================
echo "[1/5] Instalando dependencias..."

sudo apt update
sudo apt install -y \
    wget unzip build-essential \
    python3-pip python3-requests python3-ujson \
    python3-librouteros python3-pyinotify \
    libpcap-dev tcpdump docker.io

sudo systemctl enable --now docker

# =====================================
# 2. FLUENTD CONFIG
# =====================================
echo "[2/5] Configurando Fluentd..."

mkdir -p ./fluentd
mkdir -p ./suricata/logs
mkdir -p ./nginx

cat <<EOF > ./fluentd/Dockerfile
FROM ghcr.io/calyptia/fluentd:v1.14.6-debian-1.0

USER root

RUN apt-get update && apt-get install -y \
    build-essential \
    libgeoip-dev \
    ruby-dev \
    && rm -rf /var/lib/apt/lists/*

RUN fluent-gem install fluent-plugin-rewrite-tag-filter --no-document
RUN fluent-gem install fluent-plugin-multi-format-parser --no-document
RUN fluent-gem install fluent-plugin-geoip --no-document

USER fluent
ENV FLUENTD_CONF=fluent.conf

CMD ["fluentd"]
EOF

cat <<EOF > ./fluentd/fluent.conf
<source>
  @type tail
  path /var/log/suricata/eve.json
  pos_file /fluentd/log/eve.pos
  tag suricata
  <parse>
    @type json
  </parse>
</source>

<match suricata>
  @type stdout
</match>
EOF

# =====================================
# 3. tzsp2pcap
# =====================================
echo "[3/5] Instalando tzsp2pcap..."

cd /opt || exit

if [ ! -d "tzsp2pcap-master" ]; then
    wget https://github.com/thefloweringash/tzsp2pcap/archive/master.zip
    unzip master.zip
    cd tzsp2pcap-master
    make
    sudo make install
fi

cd "$BASE_DIR"

# =====================================
# 4. TZSP + MIKROCATA
# =====================================
echo "[4/5] Configurando TZSP..."

sudo mkdir -p /etc/systemd/network
sudo mkdir -p /etc/systemd/system
sudo mkdir -p /var/lib/mikrocata

for ((i=0; i<COUNT; i++))
do
    echo "→ tzsp$i"

    # INTERFACES
    sudo cp tzsp.netdev /etc/systemd/network/tzsp$i.netdev
    sudo cp tzsp.network /etc/systemd/network/tzsp$i.network

    sudo sed -i "s/tzsp0/tzsp$i/g" /etc/systemd/network/tzsp$i.*
    sudo sed -i "s/254/25$i/g" /etc/systemd/network/tzsp$i.network

    # MIKROCATA
    sudo cp mikrocata.py /usr/local/bin/mikrocataTZSP$i.py
    sudo chmod +x /usr/local/bin/mikrocataTZSP$i.py
    sudo sed -i "s/tzsp0/tzsp$i/g" /usr/local/bin/mikrocataTZSP$i.py

    # SERVICE
    sudo cp mikrocata.service /etc/systemd/system/mikrocataTZSP$i.service
    sudo sed -i "s/mikrocata.py/mikrocataTZSP$i.py/g" /etc/systemd/system/mikrocataTZSP$i.service

    # DATA
    sudo touch /var/lib/mikrocata/savelists-tzsp$i.json
    sudo touch /var/lib/mikrocata/uptime-tzsp$i.bookmark
    sudo touch /var/lib/mikrocata/ignore-tzsp$i.conf
done

sudo systemctl daemon-reload
sudo systemctl enable systemd-networkd
sudo systemctl restart systemd-networkd

# =====================================
# 5. PUERTOS TZSP
# =====================================
echo "[5/5] Configurando TZSP ports..."

for ((i=0; i<COUNT; i++))
do
    PORT=$((START_PORT + i))

    echo "→ tzsp$i puerto $PORT"

    sudo cp TZSPreplay@.service /etc/systemd/system/TZSPreplay$PORT@.service
    sudo sed -i "s/tzsp2pcap/tzsp2pcap -p $PORT/g" /etc/systemd/system/TZSPreplay$PORT@.service

    sudo systemctl enable --now TZSPreplay$PORT@tzsp$i.service
    sudo systemctl enable --now mikrocataTZSP$i.service
done

# =====================================
# 6. DOCKER
# =====================================
echo "[EXTRA] Docker..."

docker compose down || true
docker compose up -d --build

echo "===================================="
echo "   SISTEMA LISTO 🚀"
echo "===================================="
