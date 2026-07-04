#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${NSG_APP_DIR:-/opt/nsguard}"
ADMIN_NAME="${NSG_ADMIN_NAME:-Administrador}"
ADMIN_EMAIL="${NSG_ADMIN_EMAIL:-admin@local}"
ADMIN_PASSWORD="${NSG_ADMIN_PASSWORD:-admin123456}"
NO_APT="${NSG_NO_APT:-0}"

if [[ "$EUID" -ne 0 ]]; then
  echo "Execute como root: sudo bash install.sh"
  exit 1
fi

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log(){ echo -e "\n==> $*"; }

detect_ip(){
  local ipaddr=""
  ipaddr="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
  if [[ -z "$ipaddr" ]]; then
    ipaddr="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | grep -v '^127\.' | grep -v '^169\.254\.' | head -n1 || true)"
  fi
  echo "$ipaddr"
}

SERVER_IP="${NSG_SERVER_IP:-$(detect_ip)}"
[[ -z "$SERVER_IP" ]] && SERVER_IP="127.0.0.1"

if [[ ! -d "$SRC_DIR/public" || ! -d "$SRC_DIR/app" ]]; then
  echo "ERRO: execute este install.sh dentro da raiz do pacote NSGuard."
  exit 1
fi

log "Instalador NSGuard completo"
echo "Origem:  $SRC_DIR"
echo "Destino: $APP_DIR"
echo "IP:      $SERVER_IP"

if [[ "$NO_APT" != "1" ]]; then
  log "Instalando dependências"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    nginx curl unzip rsync sqlite3 dnsutils iproute2 \
    bind9 bind9-utils bind9-dnsutils \
    iptables iptables-persistent netfilter-persistent \
    php8.3-fpm php8.3-cli php8.3-sqlite3 php8.3-curl php8.3-mbstring php8.3-xml
else
  log "NSG_NO_APT=1 definido; pulando instalação de pacotes"
fi

log "Detectando PHP-FPM"
PHP_SERVICE=""
if systemctl list-unit-files --all | awk '{print $1}' | grep -qx 'php8.3-fpm.service'; then
  PHP_SERVICE="php8.3-fpm"
else
  PHP_SERVICE="$(systemctl list-unit-files --all | awk '{print $1}' | grep -E '^php[0-9.]+-fpm\.service$' | sed 's/\.service$//' | sort -V | tail -n1 || true)"
fi
[[ -z "$PHP_SERVICE" ]] && { echo "ERRO: serviço PHP-FPM não encontrado."; exit 1; }
systemctl enable --now "$PHP_SERVICE"
systemctl restart "$PHP_SERVICE"
sleep 1

PHP_SOCK=""
for sock in /run/php/php8.3-fpm.sock /run/php/php-fpm.sock; do
  if [[ -S "$sock" ]]; then PHP_SOCK="$sock"; break; fi
done
if [[ -z "$PHP_SOCK" ]]; then
  PHP_SOCK="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' 2>/dev/null | sort -V | tail -n1 || true)"
fi
[[ -z "$PHP_SOCK" ]] && { echo "ERRO: socket PHP-FPM não encontrado."; ls -la /run/php || true; exit 1; }
echo "PHP-FPM: $PHP_SERVICE / $PHP_SOCK"

log "Copiando aplicação"
mkdir -p "$APP_DIR"
rsync -a --delete \
  --exclude='.git' \
  --exclude='*.zip' \
  --exclude='database/*.sqlite' \
  --exclude='data/*.sqlite' \
  "$SRC_DIR"/ "$APP_DIR"/

find "$APP_DIR" -type f -name '*.sh' ! -path "$APP_DIR/install.sh" -delete || true
chmod +x "$APP_DIR/install.sh" || true
chmod +x "$APP_DIR/scripts"/*.php 2>/dev/null || true

log "Criando diretórios"
mkdir -p "$APP_DIR/config" "$APP_DIR/database" "$APP_DIR/storage" "$APP_DIR/data"
mkdir -p /etc/bind /var/cache/bind /var/lib/nsguard

DB_FILE="$APP_DIR/database/nsguard.sqlite"

log "Gerando config.php"
cat > "$APP_DIR/config/config.php" <<PHP
<?php
return [
    'app' => [
        'name' => 'NSGuard',
        'timezone' => 'America/Sao_Paulo',
    ],
    'paths' => [
        'db' => '${DB_FILE}',
    ],
    'security' => [
        'session_name' => 'NSGUARDSESSID',
        'force_https' => false,
    ],
    'commands' => [
        'apply' => 'sudo -n /usr/local/sbin/nsguard-apply all',
        'apply_dns' => 'sudo -n /usr/local/sbin/nsguard-apply dns',
        'apply_firewall' => 'sudo -n /usr/local/sbin/nsguard-apply firewall',
    ],
];
PHP

log "Inicializando SQLite"
if [[ ! -f "$DB_FILE" ]]; then
  sqlite3 "$DB_FILE" < "$APP_DIR/database/schema.sql"
fi

sqlite3 "$DB_FILE" <<SQL
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT, updated_at TEXT DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS blocked_domains (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT NOT NULL UNIQUE,
    category TEXT DEFAULT 'malware',
    action TEXT DEFAULT 'redirect',
    reason TEXT,
    active INTEGER NOT NULL DEFAULT 1,
    hits INTEGER NOT NULL DEFAULT 0,
    last_hit_at TEXT,
    created_by INTEGER,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('sinkhole_ipv4','${SERVER_IP}',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('sinkhole_ip','${SERVER_IP}',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('redirect_url','AUTO',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('redirect_mode','auto_current_ip',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('last_detected_ip','${SERVER_IP}',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('license_status','valid',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('license_checked_at',datetime('now'),CURRENT_TIMESTAMP);
INSERT OR IGNORE INTO blocked_domains(domain,category,action,reason,active) VALUES('malicioso.test','malware','redirect','Teste NSGuard',1);
UPDATE blocked_domains SET active=1, action='redirect' WHERE domain='malicioso.test';
SQL

log "Criando admin"
ADMIN_OUT="$(php "$APP_DIR/scripts/create-admin.php" "$ADMIN_NAME" "$ADMIN_EMAIL" "$ADMIN_PASSWORD")"

log "Permissões da aplicação"
chown -R root:www-data "$APP_DIR"
find "$APP_DIR" -type d -exec chmod 775 {} \;
find "$APP_DIR" -type f -exec chmod 664 {} \;
chmod +x "$APP_DIR/install.sh" || true
chmod +x "$APP_DIR/scripts"/*.php 2>/dev/null || true
chown -R www-data:www-data "$APP_DIR/config" "$APP_DIR/database" "$APP_DIR/storage" "$APP_DIR/data" 2>/dev/null || true
chmod -R ug+rwX "$APP_DIR/config" "$APP_DIR/database" "$APP_DIR/storage" "$APP_DIR/data" 2>/dev/null || true

log "Liberando porta 53 do systemd-resolved"
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/nsguard-disable-stub.conf <<'CONF'
[Resolve]
DNSStubListener=no
CONF
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved || true

log "Detectando/criando serviço BIND"
BIND_SERVICE=""
if systemctl list-unit-files --all | awk '{print $1}' | grep -qx 'named.service'; then
  BIND_SERVICE="named"
elif systemctl list-unit-files --all | awk '{print $1}' | grep -qx 'bind9.service'; then
  BIND_SERVICE="bind9"
else
  BIND_SERVICE="nsguard-bind"
  cat > /etc/systemd/system/nsguard-bind.service <<'UNIT'
[Unit]
Description=NSGuard BIND9 DNS Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=bind
Group=bind
ExecStart=/usr/sbin/named -f -u bind
ExecReload=/usr/sbin/rndc reload
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
fi
echo "BIND: $BIND_SERVICE"

log "Criando /usr/local/sbin/nsguard-apply"
cat > /usr/local/sbin/nsguard-apply <<'APPLY'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/nsguard"
DB_FILE="$APP_DIR/database/nsguard.sqlite"
RPZ_FILE="/etc/bind/nsguard-rpz.zone"
LOCAL_ZONE="/etc/bind/db.nsguard.local"
ZONES_CONF="/etc/bind/nsguard-zones.conf"
ZONES_DIR="/etc/bind/nsguard-zones"
LOG="/var/log/nsguard-apply.log"
MODE="${1:-all}"

touch "$LOG"
log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

detect_ip(){
  local ipaddr=""
  ipaddr="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
  if [[ -z "$ipaddr" ]]; then
    ipaddr="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | grep -v '^127\.' | grep -v '^169\.254\.' | head -n1 || true)"
  fi
  echo "$ipaddr"
}

detect_bind_service(){
  if systemctl list-unit-files --all 2>/dev/null | awk '{print $1}' | grep -qx 'named.service'; then echo "named";
  elif systemctl list-unit-files --all 2>/dev/null | awk '{print $1}' | grep -qx 'bind9.service'; then echo "bind9";
  elif systemctl list-unit-files --all 2>/dev/null | awk '{print $1}' | grep -qx 'nsguard-bind.service'; then echo "nsguard-bind";
  else echo ""; fi
}

apply_dns(){
  command -v sqlite3 >/dev/null 2>&1 || { log "ERRO: sqlite3 ausente"; exit 1; }
  [[ -f "$DB_FILE" ]] || { log "ERRO: DB ausente: $DB_FILE"; exit 1; }

  local ipaddr serial bind_service count
  ipaddr="$(detect_ip)"; [[ -z "$ipaddr" ]] && ipaddr="127.0.0.1"
  serial="$(date +%s)"
  bind_service="$(detect_bind_service)"
  mkdir -p /etc/bind /var/cache/bind "$ZONES_DIR"

  log "Aplicando DNS: IP=$ipaddr SERIAL=$serial"

  sqlite3 "$DB_FILE" <<SQL
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT, updated_at TEXT DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS blocked_domains (id INTEGER PRIMARY KEY AUTOINCREMENT, domain TEXT NOT NULL UNIQUE, category TEXT DEFAULT 'malware', action TEXT DEFAULT 'redirect', reason TEXT, active INTEGER NOT NULL DEFAULT 1, hits INTEGER NOT NULL DEFAULT 0, last_hit_at TEXT, created_by INTEGER, created_at TEXT DEFAULT CURRENT_TIMESTAMP, updated_at TEXT DEFAULT CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('sinkhole_ipv4','${ipaddr}',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('sinkhole_ip','${ipaddr}',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('redirect_url','AUTO',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('redirect_mode','auto_current_ip',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('last_detected_ip','${ipaddr}',CURRENT_TIMESTAMP);
INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('rpz_serial','${serial}',CURRENT_TIMESTAMP);
INSERT OR IGNORE INTO blocked_domains(domain,category,action,reason,active) VALUES('malicioso.test','malware','redirect','Teste NSGuard',1);
SQL

  cat > /etc/bind/named.conf.options <<'EOF'
acl "nsguard_lans" {
    localhost;
    localnets;
    10.0.0.0/8;
    172.16.0.0/12;
    192.168.0.0/16;
};

options {
    directory "/var/cache/bind";
    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };
    recursion yes;
    allow-query { any; };
    allow-recursion { nsguard_lans; };
    allow-query-cache { nsguard_lans; };
    forwarders { 1.1.1.1; 8.8.8.8; };
    dnssec-validation auto;
    auth-nxdomain no;
    response-policy { zone "nsguard-rpz"; } break-dnssec yes;
};
EOF

  cat > "$LOCAL_ZONE" <<EOF
\$TTL 30
@   IN SOA ns.nsguard.local. admin.nsguard.local. (
        ${serial}
        30
        30
        604800
        30 )
    IN NS ns.nsguard.local.

ns      IN A ${ipaddr}
block   IN A ${ipaddr}
@       IN A ${ipaddr}
EOF

  cat > "$RPZ_FILE" <<EOF
\$TTL 30
@   IN SOA ns.nsguard.local. admin.nsguard.local. (
        ${serial}
        30
        30
        604800
        30 )
    IN NS ns.nsguard.local.

EOF

  sqlite3 "$DB_FILE" "SELECT lower(trim(domain)) FROM blocked_domains WHERE active=1 ORDER BY domain;" \
    | sed 's/\r$//' | sed 's~^https\?://~~' | sed 's~/.*$~~' | sed 's/:.*$//' | sed 's/^\*\.//' | sed 's/^\.\+//' | sed 's/\.$//' \
    | grep -E '^[a-z0-9._-]+\.[a-z0-9._-]+$' | sort -u \
    | while IFS= read -r domain; do
        [[ -z "$domain" ]] && continue
        action="$(sqlite3 "$DB_FILE" "SELECT action FROM blocked_domains WHERE lower(domain)=lower('$domain') LIMIT 1;" 2>/dev/null || echo redirect)"
        if [[ "$action" == "nxdomain" ]]; then
          echo "${domain} CNAME ." >> "$RPZ_FILE"
          echo "*.${domain} CNAME ." >> "$RPZ_FILE"
        else
          echo "${domain} CNAME block.nsguard.local." >> "$RPZ_FILE"
          echo "*.${domain} CNAME block.nsguard.local." >> "$RPZ_FILE"
        fi
      done

  : > "$ZONES_CONF"
  if sqlite3 "$DB_FILE" "SELECT name FROM sqlite_master WHERE type='table' AND name='zones';" | grep -qx zones; then
    sqlite3 -separator '|' "$DB_FILE" "SELECT id,name,ttl FROM zones WHERE active=1 ORDER BY name;" | while IFS='|' read -r zid zname zttl; do
      [[ -z "$zid" || -z "$zname" ]] && continue
      zfile="$ZONES_DIR/db.$zname"
      cat > "$zfile" <<EOF
\$TTL ${zttl:-3600}
@ IN SOA ns1.${zname}. hostmaster.${zname}. ( ${serial} 3600 900 1209600 300 )
@ IN NS ns1.${zname}.
ns1 IN A ${ipaddr}
EOF
      if sqlite3 "$DB_FILE" "SELECT name FROM sqlite_master WHERE type='table' AND name='records';" | grep -qx records; then
        sqlite3 -separator '|' "$DB_FILE" "SELECT name,type,ttl,content FROM records WHERE active=1 AND zone_id=${zid} ORDER BY type,name;" | while IFS='|' read -r rname rtype rttl rcontent; do
          [[ -z "$rtype" || -z "$rcontent" ]] && continue
          owner="$rname"; [[ -z "$owner" || "$owner" == "@" ]] && owner="@" || owner="${owner%.}."
          [[ "${rtype^^}" == "TXT" && "$rcontent" != \"* ]] && rcontent="\"${rcontent//\"/\\\"}\""
          echo "$owner ${rttl:-3600} IN ${rtype^^} $rcontent" >> "$zfile"
        done
      fi
      named-checkzone "$zname" "$zfile" >/dev/null
      echo "zone \"$zname\" { type master; file \"$zfile\"; allow-transfer { none; }; };" >> "$ZONES_CONF"
    done
  fi

  cat > /etc/bind/named.conf.local <<EOF
zone "nsguard-rpz" {
    type master;
    file "$RPZ_FILE";
    allow-query { none; };
};

zone "nsguard.local" {
    type master;
    file "$LOCAL_ZONE";
};

include "$ZONES_CONF";
EOF

  chown root:bind /etc/bind/named.conf.options /etc/bind/named.conf.local "$LOCAL_ZONE" "$RPZ_FILE" "$ZONES_CONF" 2>/dev/null || true
  chmod 644 /etc/bind/named.conf.options /etc/bind/named.conf.local "$LOCAL_ZONE" "$RPZ_FILE" "$ZONES_CONF" 2>/dev/null || true

  named-checkconf
  named-checkzone nsguard.local "$LOCAL_ZONE" >/dev/null
  named-checkzone nsguard-rpz "$RPZ_FILE" >/dev/null

  if [[ -n "$bind_service" ]]; then
    systemctl enable --now "$bind_service" >/dev/null 2>&1 || true
    systemctl restart "$bind_service"
  else
    log "ERRO: serviço BIND não encontrado"
    exit 1
  fi
  command -v rndc >/dev/null 2>&1 && { rndc reload >/dev/null 2>&1 || true; rndc flush >/dev/null 2>&1 || true; }

  count="$(grep -c 'CNAME' "$RPZ_FILE" 2>/dev/null || echo 0)"
  log "DNS aplicado. RPZ_ENTRADAS=$count"
}

apply_firewall(){
  [[ -f "$DB_FILE" ]] || return 0
  local policy chain
  chain="NSGUARD_DNS"
  policy="$(sqlite3 "$DB_FILE" "SELECT value FROM settings WHERE key='ns_access_policy' LIMIT 1;" 2>/dev/null || echo allow_all)"
  [[ "$policy" != "allowlist" ]] && policy="allow_all"

  iptables -N "$chain" 2>/dev/null || true
  iptables -F "$chain" 2>/dev/null || true
  iptables -C INPUT -p udp --dport 53 -j "$chain" 2>/dev/null || iptables -I INPUT 1 -p udp --dport 53 -j "$chain" || true
  iptables -C INPUT -p tcp --dport 53 -j "$chain" 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 53 -j "$chain" || true
  iptables -A "$chain" -i lo -j RETURN || true

  if [[ "$policy" == "allow_all" ]]; then
    iptables -A "$chain" -j RETURN || true
  else
    sqlite3 "$DB_FILE" "SELECT ip_cidr FROM allowed_ips WHERE active=1;" 2>/dev/null | while IFS= read -r cidr; do
      [[ -n "$cidr" ]] && iptables -A "$chain" -s "$cidr" -j RETURN || true
    done
    iptables -A "$chain" -j DROP || true
  fi
  command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
  log "Firewall aplicado: $policy"
}

case "$MODE" in
  dns) apply_dns ;;
  firewall) apply_firewall ;;
  all) apply_dns; apply_firewall ;;
  *) echo "Uso: nsguard-apply [all|dns|firewall]"; exit 2 ;;
esac
APPLY
chmod 750 /usr/local/sbin/nsguard-apply
chown root:www-data /usr/local/sbin/nsguard-apply

log "Criando cron de atualização IP/RPZ sem apt"
cat > /usr/local/sbin/nsguard-cron-ip-rpz <<'CRONFIX'
#!/usr/bin/env bash
set -euo pipefail
LOG="/var/log/nsguard-cron-ip-rpz.log"
STATE="/var/lib/nsguard/last-ip"
mkdir -p /var/lib/nsguard
touch "$LOG"
log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }
detect_ip(){ ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'; }
IP="$(detect_ip || true)"; [[ -z "$IP" ]] && IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
OLD=""; [[ -f "$STATE" ]] && OLD="$(cat "$STATE" 2>/dev/null || true)"
log "Executando cron. IP=$IP OLD=${OLD:-nenhum}"
/usr/local/sbin/nsguard-apply dns >> "$LOG" 2>&1 || exit 1
if [[ "$IP" != "$OLD" ]]; then
  systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
  systemctl reload php8.3-fpm >/dev/null 2>&1 || systemctl restart php8.3-fpm >/dev/null 2>&1 || true
  echo "$IP" > "$STATE"
fi
log "Cron concluído"
CRONFIX
chmod +x /usr/local/sbin/nsguard-cron-ip-rpz

log "Configurando sudoers"
cat > /etc/sudoers.d/nsguard <<'SUDOERS'
www-data ALL=(root) NOPASSWD: /usr/local/sbin/nsguard-apply
SUDOERS
chmod 440 /etc/sudoers.d/nsguard
visudo -cf /etc/sudoers.d/nsguard

log "Aplicando DNS/RPZ inicial"
/usr/local/sbin/nsguard-apply all

log "Configurando Nginx"
NGINX_CONF="/etc/nginx/sites-available/nsguard.conf"
cat > "$NGINX_CONF" <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root $APP_DIR/public;
    index index.php index.html;
    access_log /var/log/nginx/nsguard-redirect.access.log;
    error_log  /var/log/nginx/nsguard-redirect.error.log notice;
    location ^~ /admin { return 404; }
    location ^~ /banner { return 404; }
    location = /api.php { return 404; }
    location /assets/ { try_files \$uri =404; access_log off; expires 7d; }
    location / { rewrite ^ /index.php last; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCK;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param SCRIPT_NAME \$fastcgi_script_name;
    }
    location ~ /(?:app|config|database|scripts|systemd|nginx|storage|vendor|data)/ { deny all; }
    location ~ /\. { deny all; }
}

server {
    listen 8087;
    listen [::]:8087;
    server_name _;
    root $APP_DIR/public;
    index index.php index.html;
    access_log /var/log/nginx/nsguard-admin.access.log;
    error_log  /var/log/nginx/nsguard-admin.error.log notice;
    location = / { return 302 /admin/; }
    location = /admin { return 302 /admin/; }
    location /admin/ { try_files \$uri \$uri/ /admin/index.php?\$query_string; }
    location /assets/ { try_files \$uri =404; access_log off; expires 7d; }
    location / { return 302 /admin/; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCK;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param SCRIPT_NAME \$fastcgi_script_name;
    }
    location ~ /(?:app|config|database|scripts|systemd|nginx|storage|vendor|data)/ { deny all; }
    location ~ /\. { deny all; }
}

server {
    listen 89;
    listen [::]:89;
    server_name _;
    root $APP_DIR/public;
    index index.html;
    access_log /var/log/nginx/nsguard-banner.access.log;
    error_log  /var/log/nginx/nsguard-banner.error.log notice;
    location = / { try_files /banner/index.html /index.html =404; }
    location / { try_files /banner/index.html /index.html =404; }
    location /assets/ { try_files \$uri =404; access_log off; expires 7d; }
    location ~ \.php\$ { return 404; }
    location ~ /(?:app|config|database|scripts|systemd|nginx|storage|vendor|data)/ { deny all; }
    location ~ /\. { deny all; }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/nsguard.conf
nginx -t
systemctl enable --now nginx
systemctl restart "$PHP_SERVICE"
systemctl restart nginx

log "Liberando portas no firewall local"
iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT || true
iptables -C INPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 53 -j ACCEPT || true
iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 80 -j ACCEPT || true
iptables -C INPUT -p tcp --dport 89 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 89 -j ACCEPT || true
iptables -C INPUT -p tcp --dport 8087 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 8087 -j ACCEPT || true
command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true

log "Configurando crontab root a cada 5 minutos"
TMP_CRON="$(mktemp)"
crontab -l 2>/dev/null | grep -v '/usr/local/sbin/nsguard-cron-ip-rpz' > "$TMP_CRON" || true
echo '*/5 * * * * /usr/local/sbin/nsguard-cron-ip-rpz >/dev/null 2>&1' >> "$TMP_CRON"
crontab "$TMP_CRON"
rm -f "$TMP_CRON"

echo "$SERVER_IP" > /var/lib/nsguard/last-ip

log "Testes finais"
echo "Portas:"
ss -lntup | egrep ':53|:80|:89|:8087' || true

echo "DNS teste:"
dig @127.0.0.1 malicioso.test A +short || true

echo "HTTP redirect:"
curl -I --max-time 5 -H 'Host: malicioso.test' http://127.0.0.1/ || true

echo "Admin:"
curl -I --max-time 5 http://127.0.0.1:8087/admin/ || true

echo
cat <<EOF
============================================================
NSGuard instalado com sucesso.
============================================================
Admin:    http://${SERVER_IP}:8087/admin/
Banner:   http://${SERVER_IP}:89/
Redirect: http://${SERVER_IP}:80/
DNS/NS:   ${SERVER_IP}:53 TCP/UDP

${ADMIN_OUT}

Crontab criada:
*/5 * * * * /usr/local/sbin/nsguard-cron-ip-rpz >/dev/null 2>&1

Teste Windows:
ipconfig /flushdns
nslookup malicioso.test ${SERVER_IP}
============================================================
EOF
