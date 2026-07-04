<?php
namespace App\Core;
final class Config {
    private static array $cfg=[];
    public static function load(string $path): void {
        if (!is_file($path)) throw new \RuntimeException('Config não encontrado: '.$path);
        self::$cfg=require $path;
        date_default_timezone_set((string)self::get('app.timezone','America/Sao_Paulo'));
    }
    public static function get(string $key, mixed $default=null): mixed {
        $v=self::$cfg; foreach(explode('.',$key) as $p){ if(!is_array($v)||!array_key_exists($p,$v)) return $default; $v=$v[$p]; } return $v;
    }
}
