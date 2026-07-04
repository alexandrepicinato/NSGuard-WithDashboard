cat > /root/nsguard-fix-css-admin-8087.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/nsguard"
PUBLIC_DIR="$APP_DIR/public"
ADMIN_DIR="$PUBLIC_DIR/admin"
BANNER_DIR="$PUBLIC_DIR/block"
NGINX_SITE="/etc/nginx/sites-available/nsguard.conf"
NGINX_LINK="/etc/nginx/sites-enabled/nsguard.conf"

echo "==> Detectando IP da VM"
VM_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
[ -z "${VM_IP:-}" ] && VM_IP="$(hostname -I | awk '{print $1}')"

if [ -z "${VM_IP:-}" ]; then
    echo "ERRO: não consegui detectar o IP."
    exit 1
fi

REDIRECT_URL="http://${VM_IP}:89/"

echo "==> IP: $VM_IP"
echo "==> Admin: http://${VM_IP}:8087/"
echo "==> Banner: http://${VM_IP}:89/"

echo "==> Criando links de compatibilidade para CSS/JS, se necessário"

mkdir -p "$PUBLIC_DIR" "$ADMIN_DIR"

# Se os assets estiverem dentro do admin, expõe também em /assets
if [ ! -e "$PUBLIC_DIR/assets" ] && [ -d "$ADMIN_DIR/assets" ]; then
    ln -s "$ADMIN_DIR/assets" "$PUBLIC_DIR/assets"
fi

if [ ! -e "$PUBLIC_DIR/css" ] && [ -d "$ADMIN_DIR/css" ]; then
    ln -s "$ADMIN_DIR/css" "$PUBLIC_DIR/css"
fi

if [ ! -e "$PUBLIC_DIR/js" ] && [ -d "$ADMIN_DIR/js" ]; then
    ln -s "$ADMIN_DIR/js" "$PUBLIC_DIR/js"
fi

if [ ! -e "$PUBLIC_DIR/static" ] && [ -d "$ADMIN_DIR/static" ]; then
    ln -s "$ADMIN_DIR/static" "$PUBLIC_DIR/static"
fi

echo "==> Backup do Nginx"
mkdir -p /root/nsguard-nginx-backup
cp -a "$NGINX_SITE" "/root/nsguard-nginx-backup/nsguard.conf.bak-css.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

echo "==> Regravando Nginx com root em /opt/nsguard/public"
cat > "$NGINX_SITE" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    access_log /var/log/nginx/nsguard-redirect-access.log;
    error_log /var/log/nginx/nsguard-redirect-error.log;

    location / {
        return 302 ${REDIRECT_URL};
    }
}

server {
    listen 89;
    listen [::]:89;
    server_name _;

    root ${BANNER_DIR};
    index index.html;

    access_log /var/log/nginx/nsguard-block-access.log;
    error_log /var/log/nginx/nsguard-block-error.log;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}

server {
    listen 8087;
    listen [::]:8087;
    server_name _;

    root ${PUBLIC_DIR};
    index index.php index.html;

    access_log /var/log/nginx/nsguard-admin-access.log;
    error_log /var/log/nginx/nsguard-admin-error.log;

    client_max_body_size 50M;

    # Arquivos estáticos globais
    location ^~ /assets/ {
        try_files \$uri /admin\$uri =404;
        access_log off;
        expires 1h;
    }

    location ^~ /css/ {
        try_files \$uri /admin\$uri =404;
        access_log off;
        expires 1h;
    }

    location ^~ /js/ {
        try_files \$uri /admin\$uri =404;
        access_log off;
        expires 1h;
    }

    location ^~ /static/ {
        try_files \$uri /admin\$uri =404;
        access_log off;
        expires 1h;
    }

    location ^~ /img/ {
        try_files \$uri /admin\$uri =404;
        access_log off;
        expires 1h;
    }

    location ^~ /images/ {
        try_files \$uri /admin\$uri =404;
        access_log off;
        expires 1h;
    }

    # Permite acessar /admin diretamente também
    location /admin/ {
        try_files \$uri \$uri/ /admin/index.php?\$query_string;
    }

    # A raiz da porta 8087 abre o painel
    location / {
        try_files \$uri \$uri/ /admin/index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$document_root;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

ln -sf "$NGINX_SITE" "$NGINX_LINK"
rm -f /etc/nginx/sites-enabled/default

echo "==> Ajustando permissões básicas"
chown -R www-data:www-data "$APP_DIR" 2>/dev/null || true
find "$PUBLIC_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "$PUBLIC_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true

echo "==> Validando Nginx"
nginx -t

echo "==> Reiniciando serviços"
systemctl restart php8.3-fpm || true
systemctl restart nginx

echo
echo "OK."
echo "Teste no navegador em aba anônima:"
echo "  http://${VM_IP}:8087/"
echo
echo "Testes úteis:"
echo "  curl -I http://${VM_IP}:8087/"
echo "  curl -I http://${VM_IP}:8087/assets/"
SH

chmod +x /root/nsguard-fix-css-admin-8087.sh
bash /root/nsguard-fix-css-admin-8087.sh
