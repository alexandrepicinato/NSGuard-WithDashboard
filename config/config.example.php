<?php
return [
    'app' => [
        'name' => 'NS Guard Ubuntu 24.04',
        'timezone' => 'America/Sao_Paulo',
    ],
    'paths' => [
        'db' => __DIR__ . '/../data/nsguard.sqlite',
        'bind_root' => '/etc/bind/nsguard',
        'bind_conf' => '/etc/bind/nsguard/nsguard.conf',
        'bind_zones_conf' => '/etc/bind/nsguard/zones.conf',
        'bind_rpz_zone' => '/etc/bind/nsguard/rpz/db.rpz.nsguard',
        'bind_zones_dir' => '/etc/bind/nsguard/zones',
    ],
    'license' => [
        'enabled' => true,
        'fail_closed' => true,
        'cache_ttl_seconds' => 86400,
    ],
    'security' => [
        'session_name' => 'NSGUARDSESSID',
    ],
    'commands' => [
        'apply' => 'sudo -n /usr/local/sbin/nsguard-apply all',
        'apply_dns' => 'sudo -n /usr/local/sbin/nsguard-apply dns',
        'apply_firewall' => 'sudo -n /usr/local/sbin/nsguard-apply firewall',
    ],
];
