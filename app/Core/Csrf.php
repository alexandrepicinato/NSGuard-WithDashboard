<?php
namespace App\Core;
final class Csrf { public static function token(): string { if(empty($_SESSION['_csrf'])) $_SESSION['_csrf']=bin2hex(random_bytes(32)); return $_SESSION['_csrf']; } public static function field(): string { return '<input type="hidden" name="_csrf" value="'.Security::e(self::token()).'">'; } public static function verify(): void { $t=$_POST['_csrf']??''; if(!is_string($t)||!hash_equals($_SESSION['_csrf']??'', $t)) throw new \RuntimeException('CSRF inválido.'); } }
