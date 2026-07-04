<?php
declare(strict_types=1);

require_once __DIR__ . '/../../app/Core/Config.php';
require_once __DIR__ . '/../../app/Core/Db.php';
require_once __DIR__ . '/../../app/Core/Security.php';
require_once __DIR__ . '/../../app/Core/Csrf.php';
require_once __DIR__ . '/../../app/Core/Auth.php';

use App\Core\Config;
use App\Core\Db;
use App\Core\Security;
use App\Core\Csrf;
use App\Core\Auth;

Config::load(__DIR__ . '/../../config/config.php');
session_name((string) Config::get('security.session_name', 'NSGUARDSESSID'));
session_start();

$user = Auth::user();
if (!$user) {
    header('Location: /admin/?page=login');
    exit;
}

$error = '';
$success = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        Csrf::verify();
        $current = (string)($_POST['current_password'] ?? '');
        $new = (string)($_POST['new_password'] ?? '');
        $confirm = (string)($_POST['confirm_password'] ?? '');

        $stmt = Db::pdo()->prepare('SELECT id,email,password_hash FROM users WHERE id = ? AND active = 1 LIMIT 1');
        $stmt->execute([(int)$user['id']]);
        $admin = $stmt->fetch();
        if (!$admin) throw new RuntimeException('Usuário não encontrado ou inativo.');
        if ($current === '' || $new === '' || $confirm === '') throw new RuntimeException('Preencha todos os campos.');
        if (!password_verify($current, (string)$admin['password_hash'])) throw new RuntimeException('Senha atual incorreta.');
        if ($new !== $confirm) throw new RuntimeException('A confirmação da nova senha não confere.');
        if (strlen($new) < 8) throw new RuntimeException('A nova senha deve ter pelo menos 8 caracteres.');
        if (password_verify($new, (string)$admin['password_hash'])) throw new RuntimeException('A nova senha precisa ser diferente da senha atual.');

        $hash = password_hash($new, PASSWORD_DEFAULT);
        Db::pdo()->prepare('UPDATE users SET password_hash=?, updated_at=datetime("now") WHERE id=?')->execute([$hash, (int)$user['id']]);
        $success = 'Senha alterada com sucesso.';
    } catch (Throwable $e) {
        $error = $e->getMessage();
    }
}
?>
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Alterar senha - NSGuard</title><link rel="stylesheet" href="/assets/app.css"><style>body{min-height:100vh;margin:0;background:#0f172a;color:#e5e7eb;font-family:Arial,sans-serif;display:grid;place-items:center;padding:24px}.card{width:100%;max-width:520px;background:#111827;border:1px solid #1f2937;border-radius:18px;padding:28px;box-shadow:0 20px 70px rgba(0,0,0,.35)}label{display:block;margin:14px 0 6px;color:#cbd5e1}input{width:100%;padding:13px;border-radius:10px;border:1px solid #334155;background:#020617;color:#e5e7eb;box-sizing:border-box}button,.btn{display:inline-block;margin-top:18px;padding:12px 16px;border-radius:10px;border:0;text-decoration:none;font-weight:700;cursor:pointer}button{width:100%;background:#38bdf8;color:#082f49}.btn{background:#1f2937;color:#e5e7eb}.alert{padding:12px;border-radius:10px;margin:16px 0}.error{background:rgba(239,68,68,.16);color:#fecaca;border:1px solid rgba(239,68,68,.35)}.ok{background:rgba(34,197,94,.16);color:#bbf7d0;border:1px solid rgba(34,197,94,.35)}</style></head><body><main class="card"><h1>Alterar senha</h1><p>Administrador: <strong><?= Security::e((string)$user['email']) ?></strong></p><?php if($error): ?><div class="alert error"><?= Security::e($error) ?></div><?php endif; ?><?php if($success): ?><div class="alert ok"><?= Security::e($success) ?></div><?php endif; ?><form method="post" autocomplete="off"><?= Csrf::field() ?><label>Senha atual</label><input type="password" name="current_password" required><label>Nova senha</label><input type="password" name="new_password" minlength="8" required><label>Confirmar nova senha</label><input type="password" name="confirm_password" minlength="8" required><button type="submit">Salvar nova senha</button></form><a class="btn" href="/admin/">Voltar ao painel</a></main></body></html>
