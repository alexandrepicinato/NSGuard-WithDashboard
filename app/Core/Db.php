<?php
namespace App\Core;
use PDO;

final class Db {
    private static ?PDO $pdo = null;

    public static function pdo(): PDO {
        if (self::$pdo instanceof PDO) return self::$pdo;

        $path = Config::get('paths.db')
            ?? Config::get('database.path')
            ?? Config::get('sqlite.path')
            ?? Config::get('db_path')
            ?? (__DIR__ . '/../../database/nsguard.sqlite');

        $path = (string)$path;
        $path = preg_replace('#^sqlite:#', '', $path) ?? $path;

        if ($path === '' || $path === '/' || str_contains($path, "\0")) {
            $path = __DIR__ . '/../../database/nsguard.sqlite';
        }

        if (!str_starts_with($path, '/')) {
            $root = realpath(__DIR__ . '/../..') ?: dirname(__DIR__, 2);
            $path = $root . '/' . ltrim($path, '/');
        }

        $dir = dirname($path);
        if (!is_dir($dir)) mkdir($dir, 0775, true);

        self::$pdo = new PDO('sqlite:' . $path, null, null, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
        self::$pdo->exec('PRAGMA foreign_keys=ON');
        return self::$pdo;
    }

    public static function conn(): PDO { return self::pdo(); }
    public static function connection(): PDO { return self::pdo(); }
    public static function get(): PDO { return self::pdo(); }
}
