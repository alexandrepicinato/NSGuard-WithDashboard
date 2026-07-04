cat > /etc/cron.d/nsguard-apply-dns <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

*/5 * * * * root flock -n /run/nsguard-apply-dns.lock /usr/local/sbin/nsguard-apply-dns >> /var/log/nsguard-apply-dns-cron.log 2>&1
EOF

chmod 644 /etc/cron.d/nsguard-apply-dns

systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
