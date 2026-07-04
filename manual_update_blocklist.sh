cat > /root/nsguard-recriar-apply-dns-zonas.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

APPLY="/usr/local/sbin/nsguard-apply-dns"

echo "==> Backup do apply atual"
if [ -f "$APPLY" ]; then
    cp -a "$APPLY" "${APPLY}.bak.$(date +%Y%m%d-%H%M%S)"
fi

echo "==> Criando novo nsguard-apply-dns usando zonas falsas"

cat > "$APPLY" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/nsguard-apply-dns.log"
DOMAINS_FILE="/etc/bind/nsguard-blocked-domains.txt"
ZONES_FILE="/etc/bind/nsguard-block-zones.conf"
BLOCK_ZONE_FILE="/etc/bind/db.nsguard.blocked-domain"
NSGUARD_LOCAL_ZONE="/etc/bind/db.nsguard.local"

mkdir -p /etc/bind
touch "$LOG"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

VM_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
[ -z "${VM_IP:-}" ] && VM_IP="$(hostname -I | awk '{print $1}')"

if [ -z "${VM_IP:-}" ]; then
    log "ERRO: não consegui detectar o IPv4 da VM."
    exit 1
fi

SERIAL="$(date +%s)"

log "Aplicando DNS por zonas falsas: IP=${VM_IP} SERIAL=${SERIAL}"

TMP="/tmp/nsguard-domains-apply.txt"
: > "$TMP"

# Domínio de teste sempre presente
echo "malicioso.test" >> "$TMP"

# Buscar domínios em SQLite do app
if command -v sqlite3 >/dev/null 2>&1; then
    find /opt/nsguard /root/NSGuard-WithDashboard -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) 2>/dev/null | while read -r DB; do
        TABLES="$(sqlite3 "$DB" ".tables" 2>/dev/null || true)"

        for T in $TABLES; do
            # Só procura em tabelas com nome provável de bloqueio/domínio
            if echo "$T" | grep -Eiq 'domain|dominio|block|bloq|black|malicious|malware|threat|site|url|dns'; then
                COLS="$(sqlite3 "$DB" "PRAGMA table_info($T);" 2>/dev/null | awk -F'|' '{print $2}' || true)"

                for C in $COLS; do
                    if echo "$C" | grep -Eiq 'domain|dominio|host|hostname|url|site|value|name|fqdn'; then
                        sqlite3 "$DB" "SELECT $C FROM $T;" 2>/dev/null \
                            | grep -Ehoi '([a-zA-Z0-9_-]+\.)+[a-zA-Z]{2,}' \
                            >> "$TMP" || true
                    fi
                done
            fi
        done
    done
fi

# Buscar em arquivos de lista do projeto
find /opt/nsguard /root/NSGuard-WithDashboard -type f 2>/dev/null \
    | grep -Ei 'block|bloq|black|domain|dominio|malicious|malware|suspeit|rpz|list|txt' \
    | while read -r F; do
        case "$F" in
            *.db|*.sqlite|*.sqlite3|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.zip|*.gz|*.tar) continue ;;
        esac

        if file "$F" 2>/dev/null | grep -qiE 'text|json|php|shell|ascii|utf'; then
            grep -Ehoi '([a-zA-Z0-9_-]+\.)+[a-zA-Z]{2,}' "$F" 2>/dev/null >> "$TMP" || true
        fi
    done

# Normalizar domínios
cat "$TMP" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's#^https\?://##' \
    | sed 's#/.*$##' \
    | sed 's/:.*$//' \
    | sed 's/^\*\.//' \
    | sed 's/\.$//' \
    | grep -E '^([a-z0-9_-]+\.)+[a-z]{2,}$' \
    | grep -Ev '^(localhost|localdomain|nsguard\.local|rpz\.nsguard)$' \
    | grep -Ev '^(google\.com|cloudflare\.com|ubuntu\.com|debian\.org|bind9\.net)$' \
    | sort -u > "$DOMAINS_FILE"

COUNT="$(wc -l < "$DOMAINS_FILE" | tr -d ' ')"

log "Domínios bloqueados carregados: ${COUNT}"

if [ "$COUNT" -eq 0 ]; then
    log "ERRO: nenhum domínio encontrado para bloquear."
    exit 1
fi

log "Criando zona nsguard.local"

cat > "$NSGUARD_LOCAL_ZONE" <<ZONE
\$TTL 60
@ IN SOA ns.nsguard.local. root.nsguard.local. (
    ${SERIAL}
    3600
    600
    604800
    60
)
@       IN NS ns.nsguard.local.
ns      IN A  ${VM_IP}
block   IN A  ${VM_IP}
@       IN A  ${VM_IP}
ZONE

log "Criando zona falsa compartilhada"

cat > "$BLOCK_ZONE_FILE" <<ZONE
\$TTL 60
@ IN SOA ns.nsguard.local. root.nsguard.local. (
    ${SERIAL}
    3600
    600
    604800
    60
)
@       IN NS ns.nsguard.local.
@       IN A  ${VM_IP}
www     IN A  ${VM_IP}
*       IN A  ${VM_IP}
ZONE

log "Gerando include de zonas bloqueadas"

: > "$ZONES_FILE"

while read -r D; do
    [ -z "$D" ] && continue

    cat >> "$ZONES_FILE" <<ZONE
zone "${D}" {
    type master;
    file "${BLOCK_ZONE_FILE}";
};

ZONE
done < "$DOMAINS_FILE"

log "Gravando named.conf.local"

cat > /etc/bind/named.conf.local <<CONF
zone "nsguard.local" {
    type master;
    file "${NSGUARD_LOCAL_ZONE}";
};

include "${ZONES_FILE}";
CONF

log "Gravando named.conf.options"

cat > /etc/bind/named.conf.options <<'CONF'
options {
    directory "/var/cache/bind";

    listen-on port 53 {
        any;
    };

    listen-on-v6 {
        none;
    };

    allow-query {
        any;
    };

    allow-query-cache {
        any;
    };

    allow-recursion {
        any;
    };

    recursion yes;

    forward only;

    forwarders {
        1.1.1.1;
        8.8.8.8;
    };

    dnssec-validation no;
    auth-nxdomain no;

    minimal-responses no;
    edns-udp-size 1232;
    max-udp-size 1232;
};
CONF

log "Gravando named.conf principal"

cat > /etc/bind/named.conf <<'CONF'
include "/etc/bind/named.conf.options";
include "/etc/bind/named.conf.local";
include "/etc/bind/named.conf.default-zones";
CONF

log "Ajustando permissões"

chown -R root:bind /etc/bind 2>/dev/null || true
find /etc/bind -type d -exec chmod 755 {} \; 2>/dev/null || true
find /etc/bind -type f -exec chmod 644 {} \; 2>/dev/null || true

log "Validando BIND"

named-checkconf
named-checkconf -z

log "Recarregando BIND"

if systemctl cat named.service >/dev/null 2>&1; then
    systemctl restart named.service
else
    systemctl restart bind9.service
fi

rndc flush 2>/dev/null || true

log "DNS aplicado com sucesso."

log "Teste malicioso.test:"
dig @"${VM_IP}" malicioso.test A +short +time=2 +tries=1 || true

log "Teste google.com:"
dig @"${VM_IP}" google.com A +short +time=2 +tries=1 || true
EOF

chmod +x "$APPLY"

echo "==> Executando novo apply"
"$APPLY"

echo
echo "==> Domínios que o sistema está carregando:"
cat /etc/bind/nsguard-blocked-domains.txt

echo
echo "OK."
SH

chmod +x /root/nsguard-recriar-apply-dns-zonas.sh
bash /root/nsguard-recriar-apply-dns-zonas.sh
