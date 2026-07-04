<?php
namespace App\Core;
final class Security {
    public static function e(mixed $v): string { return htmlspecialchars((string)$v, ENT_QUOTES|ENT_SUBSTITUTE, 'UTF-8'); }
    public static function domain(string $d): string {
        $d=trim(mb_strtolower($d)); $d=preg_replace('#^https?://#','',$d)??$d; $d=explode('/',$d,2)[0]; $d=explode(':',$d,2)[0]; $d=rtrim($d,'.'); if(str_starts_with($d,'*.')) $d=substr($d,2);
        if($d===''||strlen($d)>253) throw new \InvalidArgumentException('Domínio inválido.');
        foreach(explode('.',$d) as $label){ if($label===''||strlen($label)>63||!preg_match('/^[a-z0-9-]+$/',$label)||str_starts_with($label,'-')||str_ends_with($label,'-')) throw new \InvalidArgumentException('Domínio inválido: '.$d); }
        if(substr_count($d,'.')<1) throw new \InvalidArgumentException('Informe domínio completo.'); return $d;
    }
    public static function zone(string $z): string { return self::domain($z); }
    public static function recordType(string $t): string { $t=strtoupper(trim($t)); $ok=['A','AAAA','CNAME','MX','TXT','NS','SRV','CAA','PTR']; if(!in_array($t,$ok,true)) throw new \InvalidArgumentException('Tipo inválido.'); return $t; }
    public static function ttl(mixed $ttl): int { $ttl=(int)$ttl; if($ttl<30||$ttl>604800) throw new \InvalidArgumentException('TTL inválido.'); return $ttl; }
    public static function urlTemplate(string $u): string { $u=trim($u); if($u==='') $u='http://{sinkhole_ip}:89/'; $test=str_replace('{sinkhole_ip}','127.0.0.1',$u); if(!filter_var($test,FILTER_VALIDATE_URL)||!preg_match('#^https?://#',$test)) throw new \InvalidArgumentException('URL inválida.'); return $u; }
    public static function ipCidr(string $value): string {
        $value=trim($value); if($value==='') throw new \InvalidArgumentException('IP/CIDR vazio.');
        if(str_contains($value,'/')){ [$ip,$p]=explode('/',$value,2); if(!ctype_digit($p)) throw new \InvalidArgumentException('CIDR inválido.'); if(filter_var($ip,FILTER_VALIDATE_IP,FILTER_FLAG_IPV4)){ $n=(int)$p; if($n<0||$n>32) throw new \InvalidArgumentException('CIDR IPv4 inválido.'); return $ip.'/'.$n; } if(filter_var($ip,FILTER_VALIDATE_IP,FILTER_FLAG_IPV6)){ $n=(int)$p; if($n<0||$n>128) throw new \InvalidArgumentException('CIDR IPv6 inválido.'); return $ip.'/'.$n; } }
        if(filter_var($value,FILTER_VALIDATE_IP,FILTER_FLAG_IPV4)) return $value.'/32'; if(filter_var($value,FILTER_VALIDATE_IP,FILTER_FLAG_IPV6)) return $value.'/128'; throw new \InvalidArgumentException('IP/CIDR inválido.');
    }
}
