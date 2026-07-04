<?php
declare(strict_types=1);

$dbFile = __DIR__ . '/../database/nsguard.sqlite';

function nsguard_current_ip(): string
{
    $serverAddr = trim((string)($_SERVER['SERVER_ADDR'] ?? ''));
    if (filter_var($serverAddr, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) && !str_starts_with($serverAddr, '127.')) {
        return $serverAddr;
    }

    $hostnameIp = trim((string)gethostbyname(gethostname()));
    if (filter_var($hostnameIp, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) && !str_starts_with($hostnameIp, '127.')) {
        return $hostnameIp;
    }

    $route = trim((string)shell_exec("ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if(\$i==\"src\"){print \$(i+1); exit}}'"));
    if (filter_var($route, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
        return $route;
    }

    return '127.0.0.1';
}

$currentIp = nsguard_current_ip();
$host = strtolower(trim(preg_replace('/:\d+$/', '', $_SERVER['HTTP_HOST'] ?? '')));
$uri = $_SERVER['REQUEST_URI'] ?? '/';

try {
    if (is_file($dbFile)) {
        $pdo = new PDO('sqlite:' . $dbFile);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

        $pdo->exec("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT, updated_at TEXT DEFAULT CURRENT_TIMESTAMP)");
        $pdo->exec("CREATE TABLE IF NOT EXISTS blocked_domains (
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
        )");

        $stmt = $pdo->prepare("INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('sinkhole_ipv4', ?, CURRENT_TIMESTAMP)");
        $stmt->execute([$currentIp]);
        $stmt = $pdo->prepare("INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('sinkhole_ip', ?, CURRENT_TIMESTAMP)");
        $stmt->execute([$currentIp]);
        $pdo->exec("INSERT OR REPLACE INTO settings(key,value,updated_at) VALUES('redirect_url', 'AUTO', CURRENT_TIMESTAMP)");

        if ($host !== '') {
            $hit = $pdo->prepare("UPDATE blocked_domains
                SET hits = hits + 1, last_hit_at = datetime('now')
                WHERE active = 1 AND (domain = :host1 OR :host2 LIKE '%.' || domain)");
            $hit->execute([':host1' => $host, ':host2' => $host]);
        }
    }
} catch (Throwable $e) {
    // O redirect não deve quebrar se o banco estiver temporariamente indisponível.
}

$target = 'http://' . $currentIp . ':89/';
$query = http_build_query([
    'blocked_host' => $host,
    'blocked_uri' => $uri,
    'source' => 'nsguard',
]);

header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');
header('Location: ' . $target . '?' . $query, true, 302);
exit;
