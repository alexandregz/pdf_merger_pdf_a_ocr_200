<?php
ini_set('display_errors', true);
error_reporting(E_ALL);


// --- Config ---
$jsonFile = __DIR__ . '/appcast.json'; 
$logDir   = "../../../CIGcombinadorPDFs";
$logFile  = "$logDir/visitors.log";
$maxSize  = 1024*1024;                  // 1 MB
$keep     = 5;                          // nº de rotacións a manter

// --- Helpers mínimos ---
function log_ip(){
  if (!empty($_SERVER['HTTP_CLIENT_IP'])) return $_SERVER['HTTP_CLIENT_IP'];
  if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) return trim(explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'])[0]);
  return $_SERVER['REMOTE_ADDR'] ?? 'UNKNOWN';
}

function log_os($ua){
  $u = strtolower($ua);
  return (str_contains($u,'windows phone')?'Windows Phone':
    (str_contains($u,'windows')?'Windows':
    (str_contains($u,'android')?'Android':
    ((str_contains($u,'iphone')||str_contains($u,'ipad')||str_contains($u,'ipod'))?'iOS':
    ((str_contains($u,'mac os x')||str_contains($u,'macintosh'))?'macOS':
    (str_contains($u,'cros')?'Chrome OS':
    (str_contains($u,'linux')?'Linux':'Unknown')))))));
}

function rotate($f,$max,$keep){
  if (!file_exists($f) || filesize($f) < $max) return;
  if (file_exists("$f.$keep")) @unlink("$f.$keep");
  for ($i=$keep-1;$i>=1;$i--) if (file_exists("$f.$i")) @rename("$f.$i","$f.".($i+1));
  @rename($f,"$f.1");
}


// --- Prep dir + lock global para evitar carreiras ---
//if (!is_dir($logDir)) @mkdir($logDir,0750,true);
$lk = fopen("$logFile.lock",'c'); if ($lk) flock($lk, LOCK_EX);

// --- Rotación + escritura do log ---
rotate($logFile,$maxSize,$keep);
$ua = $_SERVER['HTTP_USER_AGENT'] ?? '';
$line = sprintf("%s\t%s\t%s\t%s\n", date('c'), log_ip(), log_os($ua), str_replace(["\r","\n","\t"],['','',' '],$ua));
@file_put_contents($logFile, $line, FILE_APPEND);

// --- Servir o ficheiro JSON ---
if (!is_file($jsonFile)) {
  if ($lk){ flock($lk, LOCK_UN); fclose($lk); }
  http_response_code(404);
  header('Content-Type: application/json; charset=utf-8');
  echo json_encode(['error'=>'data.json not found'], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
  exit;
}
$etag = '"'.sha1_file($jsonFile).'"';
$mtime = gmdate('D, d M Y H:i:s', filemtime($jsonFile)).' GMT';
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-cache');
header("ETag: $etag");
header("Last-Modified: $mtime");

// Resposta condicional simple
if ((isset($_SERVER['HTTP_IF_NONE_MATCH']) && trim($_SERVER['HTTP_IF_NONE_MATCH'])===$etag) ||
    (isset($_SERVER['HTTP_IF_MODIFIED_SINCE']) && $_SERVER['HTTP_IF_MODIFIED_SINCE']===$mtime)) {
  if ($lk){ flock($lk, LOCK_UN); fclose($lk); }
  http_response_code(304); exit;
}

// Ler e emitir tal cal
$contents = @file_get_contents($jsonFile);
if ($lk){ flock($lk, LOCK_UN); fclose($lk); }
echo $contents;

