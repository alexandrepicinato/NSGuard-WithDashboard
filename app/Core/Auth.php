<?php
namespace App\Core;
final class Auth {
    public static function user(): ?array { if(empty($_SESSION['user_id'])) return null; $s=Db::pdo()->prepare('SELECT id,name,email,role FROM users WHERE id=? AND active=1'); $s->execute([(int)$_SESSION['user_id']]); $u=$s->fetch(); return $u?:null; }
    public static function login(string $email,string $password): bool { $s=Db::pdo()->prepare('SELECT * FROM users WHERE email=? AND active=1'); $s->execute([mb_strtolower(trim($email))]); $u=$s->fetch(); if(!$u||!password_verify($password,$u['password_hash'])) return false; session_regenerate_id(true); $_SESSION['user_id']=(int)$u['id']; return true; }
    public static function logout(): void { $_SESSION=[]; if(ini_get('session.use_cookies')){ $p=session_get_cookie_params(); setcookie(session_name(),'',time()-42000,$p['path'],$p['domain'],$p['secure'],$p['httponly']); } session_destroy(); }
    public static function requireLogin(): void { if(!self::user()){ header('Location: /admin?page=login'); exit; } }
}
