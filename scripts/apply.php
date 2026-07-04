#!/usr/bin/env php
<?php
require_once __DIR__.'/../app/Core/Config.php';
require_once __DIR__.'/../app/Core/Db.php';
require_once __DIR__.'/../app/Core/Settings.php';
require_once __DIR__.'/../app/Core/Security.php';
use App\Core\Config; use App\Core\Db; use App\Core\Settings; use App\Core\Security;
Config::load(__DIR__.'/../config/config.php');
$mode=$argv[1] ?? 'all';
function sh(array $args,bool $ignore=false): string { $cmd=implode(' ',array_map('escapeshellarg',$args)).' 2>&1'; exec($cmd,$out,$code); $txt=trim(implode("\n",$out)); if($code!==0&&!$ignore) throw new RuntimeException($cmd.' => '.$txt); return $txt; }
function hasRule(array $args): bool { $cmd=implode(' ',array_map('escapeshellarg',$args)).' >/dev/null 2>&1'; exec($cmd,$o,$c); return $c===0; }
function ensureDir(string $d): void { if(!is_dir($d)) mkdir($d,0775,true); }
function rrOwner(string $name,string $zone): string { $name=trim($name); if($name===''||$name==='@') return '@'; return rtrim($name,'.').'.'; }
function rrContent(string $type,string $content): string { $type=strtoupper($type); $content=trim($content); if($type==='TXT' && !(str_starts_with($content,'"')&&str_ends_with($content,'"'))) return '"'.str_replace('"','\\"',$content).'"'; return $content; }
function applyDns(): void {
    $root=Config::get('paths.bind_root'); $zonesDir=Config::get('paths.bind_zones_dir'); $rpz=Config::get('paths.bind_rpz_zone'); ensureDir($root); ensureDir($zonesDir); ensureDir(dirname($rpz));
    $pdo=Db::pdo(); $sink=Settings::get('sinkhole_ip','127.0.0.1'); if(!filter_var($sink,FILTER_VALIDATE_IP,FILTER_FLAG_IPV4)) throw new RuntimeException('sinkhole_ip IPv4 inválido');
    $serial=date('YmdHi'); $lines=['$TTL 60','@ IN SOA localhost. admin.localhost. ( '.$serial.' 60 60 86400 60 )','@ IN NS localhost.','sinkhole IN A '.$sink];
    foreach($pdo->query('SELECT * FROM blocked_domains WHERE active=1 ORDER BY domain')->fetchAll() as $b){ $d=rtrim($b['domain'],'.').'.'; if($b['action']==='nxdomain'){ $lines[]=$d.' CNAME .'; $lines[]='*.'.$d.' CNAME .'; } else { $lines[]=$d.' CNAME sinkhole.rpz.nsguard.'; $lines[]='*.'.$d.' CNAME sinkhole.rpz.nsguard.'; } }
    file_put_contents($rpz,implode("\n",$lines)."\n");
    $zonesConf=[]; foreach($pdo->query('SELECT * FROM zones WHERE active=1 ORDER BY name')->fetchAll() as $z){ $zone=$z['name']; $file=$zonesDir.'/db.'.$zone; $ttl=(int)$z['ttl']; $zl=['$TTL '.$ttl,'@ IN SOA ns1.'.$zone.'. hostmaster.'.$zone.'. ( '.$serial.' 3600 900 1209600 300 )','@ IN NS ns1.'.$zone.'.','ns1 IN A '.$sink]; $s=$pdo->prepare('SELECT * FROM records WHERE zone_id=? AND active=1 ORDER BY type,name'); $s->execute([$z['id']]); foreach($s->fetchAll() as $r){ $zl[]=rrOwner($r['name'],$zone).' '.$r['ttl'].' IN '.strtoupper($r['type']).' '.rrContent($r['type'],$r['content']); } file_put_contents($file,implode("\n",$zl)."\n"); sh(['named-checkzone',$zone,$file]); $zonesConf[]='zone "'.$zone.'" { type master; file "'.$file.'"; allow-transfer { none; }; };'; }
    file_put_contents(Config::get('paths.bind_zones_conf'),implode("\n",$zonesConf)."\n");
    file_put_contents(Config::get('paths.bind_conf'),"zone \"rpz.nsguard\" { type master; file \"$rpz\"; allow-query { none; }; };\ninclude \"".Config::get('paths.bind_zones_conf')."\";\n");
    sh(['named-checkzone','rpz.nsguard',$rpz]); sh(['named-checkconf']); sh(['rndc','reload'],true); sh(['systemctl','reload','bind9'],true); sh(['systemctl','restart','bind9'],true); Settings::set('dns_last_apply',date('Y-m-d H:i:s')); Settings::set('dns_last_output','DNS/BIND aplicado em '.date('Y-m-d H:i:s'));
}
function applyFirewall(): void {
    $chain='NSGUARD_DNS'; $policy=Settings::get('ns_access_policy','allow_all'); if(!in_array($policy,['allow_all','allowlist'],true)) $policy='allow_all'; $rows=Db::pdo()->query('SELECT ip_cidr FROM allowed_ips WHERE active=1')->fetchAll(); $v4=[];$v6=[]; foreach($rows as $r){ if(str_contains($r['ip_cidr'],':')) $v6[]=$r['ip_cidr']; else $v4[]=$r['ip_cidr']; }
    $apply=function($bin,$allowed,$loop) use($chain,$policy){ sh([$bin,'-N',$chain],true); sh([$bin,'-F',$chain],true); if(!hasRule([$bin,'-C','INPUT','-p','udp','--dport','53','-j',$chain])) sh([$bin,'-I','INPUT','1','-p','udp','--dport','53','-j',$chain],true); if(!hasRule([$bin,'-C','INPUT','-p','tcp','--dport','53','-j',$chain])) sh([$bin,'-I','INPUT','1','-p','tcp','--dport','53','-j',$chain],true); sh([$bin,'-A',$chain,'-i','lo','-j','RETURN'],true); if($policy==='allow_all'){ sh([$bin,'-A',$chain,'-j','RETURN'],true); return; } sh([$bin,'-A',$chain,'-s',$loop,'-j','RETURN'],true); foreach($allowed as $cidr) sh([$bin,'-A',$chain,'-s',$cidr,'-j','RETURN'],true); sh([$bin,'-A',$chain,'-j','DROP'],true); };
    $apply('/usr/sbin/iptables',$v4,'127.0.0.1/32'); if(is_file('/usr/sbin/ip6tables')) $apply('/usr/sbin/ip6tables',$v6,'::1/128'); sh(['netfilter-persistent','save'],true); Settings::set('firewall_last_apply',date('Y-m-d H:i:s')); Settings::set('firewall_last_output','Firewall '.$policy.' aplicado em '.date('Y-m-d H:i:s'));
}
try{ if($mode==='dns'||$mode==='all') applyDns(); if($mode==='firewall'||$mode==='all') applyFirewall(); echo "OK $mode\n"; }catch(Throwable $e){ fwrite(STDERR,$e->getMessage()."\n"); exit(1); }
