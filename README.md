# NSGuard Ubuntu 24.04 — instalador único

Pacote completo do NSGuard com app, painel, BIND9/RPZ, Nginx, PHP-FPM e SQLite.

## Instalação

```bash
unzip nsguard-final-installer.zip
cd nsguard-final-installer
sudo bash install.sh
```

Com IP/admin definidos manualmente:

```bash
sudo NSG_SERVER_IP="192.168.177.207" \
     NSG_ADMIN_EMAIL="admin@local" \
     NSG_ADMIN_PASSWORD="admin123456" \
     bash install.sh
```

## Portas

- `53 TCP/UDP`: DNS/NS BIND9 + RPZ
- `80 TCP`: redirect dos domínios bloqueados
- `89 TCP`: banner de bloqueio
- `8087 TCP`: painel administrativo

## Acesso padrão

```txt
Admin: http://IP-DA-VM:8087/admin/
Email: admin@local
Senha: admin123456
```

## Alterar senha

```txt
http://IP-DA-VM:8087/admin/change-password.php
```

## Correção automática de IP e RPZ

O instalador cria uma crontab no root para rodar de 5 em 5 minutos:

```cron
*/5 * * * * /usr/local/sbin/nsguard-cron-ip-rpz >/dev/null 2>&1
```

Ela atualiza o IP atual da VM no banco, recria o RPZ e recarrega o BIND.

## Comandos úteis

```bash
sudo /usr/local/sbin/nsguard-apply all
sudo /usr/local/sbin/nsguard-apply dns
sudo /usr/local/sbin/nsguard-apply firewall
sudo /usr/local/sbin/nsguard-cron-ip-rpz
sudo tail -n 80 /var/log/nsguard-cron-ip-rpz.log
sudo tail -n 80 /var/log/nsguard-apply.log
```

## Testes

No Ubuntu:

```bash
dig @127.0.0.1 malicioso.test A +short
curl -I -H "Host: malicioso.test" http://127.0.0.1/
curl -I http://127.0.0.1:8087/admin/
curl -I http://127.0.0.1:89/
```

No Windows:

```bat
ipconfig /flushdns
nslookup malicioso.test IP-DA-VM
```

## Observação importante

O NSGuard atualiza o IP dentro da VM. Os clientes da rede ainda precisam usar o IP atual da VM como DNS. Para produção, faça reserva DHCP para a VM no roteador.
