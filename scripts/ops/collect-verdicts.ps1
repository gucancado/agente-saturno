<#
.SYNOPSIS
  Coleta os vereditos do saturno do log do Coolify (modo veredito / observacao prod).
.DESCRIPTION
  O veredito do R1 vai pro .result do tick e aparece no log do Coolify (multi-linha,
  apos "claude OK projeto ... resultado:"). Este helper puxa o log via API e reconstroi
  os vereditos legiveis. Use durante a janela de observacao em prod (Fase B do rollout).
  Invoke-RestMethod ja devolve UTF-8 decodificado (sem \uXXXX).
.PARAMETER Token
  Token da API do Coolify. Default: env COOLIFY_TOKEN. NAO commitar inline.
.EXAMPLE
  $env:COOLIFY_TOKEN="2|..."; ./scripts/ops/collect-verdicts.ps1
#>
param(
  [string]$Token = $env:COOLIFY_TOKEN,
  [string]$App   = "h5btft2bcfsz57mmmwf7do7q",
  [string]$Base  = "http://5.78.199.192:8000/api/v1",
  [int]$Lines    = 600
)

if (-not $Token) { Write-Error "Token ausente. Defina COOLIFY_TOKEN ou passe -Token."; exit 1 }

$resp  = Invoke-RestMethod -Uri "$Base/applications/$App/logs?lines=$Lines" -Headers @{ Authorization = "Bearer $Token" } -Method Get
$logLines = ($resp.logs) -split "`n"

function Strip([string]$s) {
  $s = $s -replace '^time="[^"]*" level=info msg="?',''
  $s = $s -replace ' channel=stdout.*$',''
  return $s
}

$found = 0
for ($i = 0; $i -lt $logLines.Count; $i++) {
  if ($logLines[$i] -match 'sweep-\d+\] claude OK projeto .* resultado:') {
    $found++
    if ($logLines[$i] -match '\[(20\d{6}T\d{6}Z-sweep-\d+)\]') { $tick = $matches[1] } else { $tick = "?" }
    Write-Host "`n========== VEREDITO ($tick) ==========" -ForegroundColor Cyan
    for ($j = $i; $j -lt [Math]::Min($i + 40, $logLines.Count); $j++) {
      $d = Strip $logLines[$j]
      if ($d -match 'usage: \{|sweep end ') { break }
      if ($d.Trim()) { Write-Host $d }
    }
  }
}
if ($found -eq 0) { Write-Host "Nenhum veredito no buffer (sem tick ativo recente - esperado se o grupo esta sem promessas)." -ForegroundColor Yellow }
else { Write-Host "`n($found no buffer)" -ForegroundColor Green }
