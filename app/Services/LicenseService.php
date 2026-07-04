<?php
namespace App\Services;
use App\Core\Settings;
final class LicenseService {
    public function status(bool $force=false): array {
        $key=trim((string)Settings::get('license_key','')); $checked=Settings::get('license_checked_at',''); $cached=Settings::get('license_status','unknown');
        if(!$force && $checked && time()-strtotime($checked)<86400 && in_array($cached,['valid','invalid','error'],true)) return ['valid'=>$cached==='valid','status'=>$cached,'message'=>Settings::get('license_last_error',''), 'checked_at'=>$checked];
        if($key===''){ $this->save('invalid','Licença não configurada',''); return ['valid'=>false,'status'=>'invalid','message'=>'Licença não configurada','checked_at'=>date('Y-m-d H:i:s')]; }
        $url=str_replace(['{key}','[CodLicense]'],rawurlencode($key),(string)Settings::get('license_url',''));
        $ch=curl_init($url); curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_CONNECTTIMEOUT=>5,CURLOPT_TIMEOUT=>12,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2]); $raw=curl_exec($ch); $err=curl_error($ch); $code=(int)curl_getinfo($ch,CURLINFO_RESPONSE_CODE); curl_close($ch);
        if($raw===false||$code===0||$code>=500){ $msg='Falha na verificação: '.($err?:'HTTP '.$code); $this->save('error',$msg,(string)$raw); return ['valid'=>false,'status'=>'error','message'=>$msg,'checked_at'=>date('Y-m-d H:i:s')]; }
        $valid=$this->interpret((string)$raw,$code); if($valid){$this->save('valid','Licença válida',(string)$raw); return ['valid'=>true,'status'=>'valid','message'=>'Licença válida','checked_at'=>date('Y-m-d H:i:s')];}
        $this->save('invalid','Licença inválida',(string)$raw); return ['valid'=>false,'status'=>'invalid','message'=>'Licença inválida','checked_at'=>date('Y-m-d H:i:s')];
    }
    public function redirectAllowed(): bool { return $this->status(false)['valid']===true; }
    private function interpret(string $raw,int $code): bool { if($code>=400) return false; $j=json_decode($raw,true); if(is_array($j)){ foreach(['valid','active','ok','success','license_valid'] as $k) if(array_key_exists($k,$j)) return filter_var($j[$k],FILTER_VALIDATE_BOOLEAN)||in_array(strtolower((string)$j[$k]),['valid','active','ok','true','1','success'],true); foreach(['status','state'] as $k) if(isset($j[$k])) return in_array(strtolower((string)$j[$k]),['valid','active','ok','success','approved'],true); } return in_array(strtolower(trim($raw)),['valid','active','ok','success','true','1','licenca valida','licença válida'],true); }
    private function save(string $status,string $err,string $resp): void { Settings::set('license_status',$status); Settings::set('license_checked_at',date('Y-m-d H:i:s')); Settings::set('license_last_error',$err); Settings::set('license_last_response',mb_substr($resp,0,2000)); }
}
