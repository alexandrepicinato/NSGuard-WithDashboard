<?php
namespace App\Services;
use App\Core\Db;
use App\Core\Security;
use App\Core\Settings;
final class Repository {
    public function stats(): array { $p=Db::pdo(); return ['blocks'=>(int)$p->query('SELECT COUNT(*) FROM blocked_domains WHERE active=1')->fetchColumn(),'zones'=>(int)$p->query('SELECT COUNT(*) FROM zones WHERE active=1')->fetchColumn(),'records'=>(int)$p->query('SELECT COUNT(*) FROM records WHERE active=1')->fetchColumn(),'policy'=>Settings::get('ns_access_policy','allow_all')]; }
    public function blocks(string $q=''): array { $p=Db::pdo(); if($q!==''){ $s=$p->prepare('SELECT * FROM blocked_domains WHERE domain LIKE ? OR reason LIKE ? ORDER BY active DESC, domain'); $l='%'.$q.'%'; $s->execute([$l,$l]); return $s->fetchAll(); } return $p->query('SELECT * FROM blocked_domains ORDER BY active DESC, domain')->fetchAll(); }
    public function addBlock(string $domain,string $category,string $action,string $reason): void { $domain=Security::domain($domain); $action=in_array($action,['redirect','nxdomain'],true)?$action:'redirect'; $s=Db::pdo()->prepare('INSERT INTO blocked_domains(domain,category,action,reason,active,updated_at) VALUES(?,?,?,?,1,datetime("now")) ON CONFLICT(domain) DO UPDATE SET category=excluded.category,action=excluded.action,reason=excluded.reason,active=1,updated_at=datetime("now")'); $s->execute([$domain,$category,$action,$reason]); }
    public function toggleBlock(int $id,bool $active): void { Db::pdo()->prepare('UPDATE blocked_domains SET active=?,updated_at=datetime("now") WHERE id=?')->execute([$active?1:0,$id]); }
    public function deleteBlock(int $id): void { Db::pdo()->prepare('DELETE FROM blocked_domains WHERE id=?')->execute([$id]); }
    public function hit(string $host): void { try{ $host=Security::domain($host); Db::pdo()->prepare('UPDATE blocked_domains SET hits=hits+1,last_hit_at=datetime("now") WHERE active=1 AND (domain=? OR ? LIKE "%\."||domain)')->execute([$host,$host]); }catch(\Throwable){} }
    public function zones(): array { return Db::pdo()->query('SELECT * FROM zones ORDER BY active DESC, name')->fetchAll(); }
    public function addZone(string $name,int $ttl=3600): int { $name=Security::zone($name); $ttl=Security::ttl($ttl); $s=Db::pdo()->prepare('INSERT INTO zones(name,ttl,active,updated_at) VALUES(?,?,1,datetime("now")) ON CONFLICT(name) DO UPDATE SET ttl=excluded.ttl,active=1,updated_at=datetime("now")'); $s->execute([$name,$ttl]); return (int)Db::pdo()->query('SELECT id FROM zones WHERE name='.Db::pdo()->quote($name))->fetchColumn(); }
    public function zone(int $id): ?array { $s=Db::pdo()->prepare('SELECT * FROM zones WHERE id=?'); $s->execute([$id]); $r=$s->fetch(); return $r?:null; }
    public function records(int $zoneId): array { $s=Db::pdo()->prepare('SELECT * FROM records WHERE zone_id=? ORDER BY active DESC,type,name'); $s->execute([$zoneId]); return $s->fetchAll(); }
    public function addRecord(int $zoneId,string $name,string $type,int $ttl,string $content): void { $type=Security::recordType($type); $ttl=Security::ttl($ttl); $name=trim($name)===''?'@':trim($name); Db::pdo()->prepare('INSERT INTO records(zone_id,name,type,ttl,content,active,updated_at) VALUES(?,?,?,?,?,1,datetime("now"))')->execute([$zoneId,$name,$type,$ttl,trim($content)]); }
    public function toggleRecord(int $id,bool $active): void { Db::pdo()->prepare('UPDATE records SET active=? WHERE id=?')->execute([$active?1:0,$id]); }
    public function deleteRecord(int $id): void { Db::pdo()->prepare('DELETE FROM records WHERE id=?')->execute([$id]); }
    public function toggleZone(int $id,bool $active): void { Db::pdo()->prepare('UPDATE zones SET active=? WHERE id=?')->execute([$active?1:0,$id]); }
    public function deleteZone(int $id): void { Db::pdo()->prepare('DELETE FROM zones WHERE id=?')->execute([$id]); }
    public function allowed(): array { return Db::pdo()->query('SELECT * FROM allowed_ips ORDER BY active DESC, ip_cidr')->fetchAll(); }
    public function addAllowed(string $cidr,string $desc): void { $cidr=Security::ipCidr($cidr); Db::pdo()->prepare('INSERT INTO allowed_ips(ip_cidr,description,active,updated_at) VALUES(?,?,1,datetime("now")) ON CONFLICT(ip_cidr) DO UPDATE SET description=excluded.description,active=1,updated_at=datetime("now")')->execute([$cidr,$desc]); }
    public function toggleAllowed(int $id,bool $active): void { Db::pdo()->prepare('UPDATE allowed_ips SET active=? WHERE id=?')->execute([$active?1:0,$id]); }
    public function deleteAllowed(int $id): void { Db::pdo()->prepare('DELETE FROM allowed_ips WHERE id=?')->execute([$id]); }
}
