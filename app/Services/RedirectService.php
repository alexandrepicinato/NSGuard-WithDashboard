<?php
namespace App\Services;
use App\Core\Settings;
use App\Core\Security;
final class RedirectService {
    public function url(): string { $tpl=(string)Settings::get('redirect_url','http://{sinkhole_ip}:89/'); $url=str_replace('{sinkhole_ip}',(string)Settings::get('sinkhole_ip','127.0.0.1'),$tpl); return Security::urlTemplate($url); }
    public function withMeta(string $host,string $uri): string { $u=$this->url(); return $u.(str_contains($u,'?')?'&':'?').http_build_query(['blocked_host'=>$host,'blocked_uri'=>$uri,'source'=>'nsguard']); }
}
