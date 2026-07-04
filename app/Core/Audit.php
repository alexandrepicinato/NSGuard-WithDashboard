<?php
namespace App\Core;
final class Audit { public static function log(string $action,array $details=[]): void { try{ $s=Db::pdo()->prepare('INSERT INTO audit_logs(user_id,action,ip_address,details) VALUES(?,?,?,?)'); $s->execute([$_SESSION['user_id']??null,$action,$_SERVER['REMOTE_ADDR']??null,json_encode($details,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES)]); }catch(\Throwable){} } }
