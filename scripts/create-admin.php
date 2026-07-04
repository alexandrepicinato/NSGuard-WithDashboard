#!/usr/bin/env php
<?php
require_once __DIR__.'/../app/Core/Config.php';require_once __DIR__.'/../app/Core/Db.php';
use App\Core\Config;use App\Core\Db;
Config::load(__DIR__.'/../config/config.php');
$name=$argv[1]??'Administrador';$email=mb_strtolower($argv[2]??'admin@local');$pass=$argv[3]??bin2hex(random_bytes(8));
Db::pdo()->prepare('INSERT INTO users(name,email,password_hash,role,active) VALUES(?,?,?,?,1) ON CONFLICT(email) DO UPDATE SET name=excluded.name,password_hash=excluded.password_hash,role=excluded.role,active=1')->execute([$name,$email,password_hash($pass,PASSWORD_DEFAULT),'admin']);
echo "ADMIN_EMAIL=$email\nADMIN_PASSWORD=$pass\n";
