<?php
namespace App\Core;
final class Settings {
    public static function get(string $key, ?string $default=null): ?string { $s=Db::pdo()->prepare('SELECT value FROM settings WHERE key=?'); $s->execute([$key]); $r=$s->fetch(); return $r?$r['value']:$default; }
    public static function set(string $key, ?string $value): void { $s=Db::pdo()->prepare('INSERT INTO settings(key,value,updated_at) VALUES(?,?,datetime("now")) ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=datetime("now")'); $s->execute([$key,$value]); }
}
