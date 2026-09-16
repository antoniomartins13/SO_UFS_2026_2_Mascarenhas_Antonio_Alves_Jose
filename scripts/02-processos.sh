#!/usr/bin/env bash
# 02-processos.sh — Evidência de processos e threads (Parte B, seção 7.1).
#
# Dispara uma inferência longa em background e, ENQUANTO ela roda, tira
# várias fotos do sistema. Não precisa de dois terminais.
#
# Correção: o conjunto de PIDs agora é 'ollama serve' + seus filhos, em vez de
# `pgrep -x ollama`. O runner (processo filho que carrega os pesos) não casava
# com -x, então as seções que usavam pgrep -x mostravam só o servidor.

set -uo pipefail

URL="http://127.0.0.1:11434"
MODEL="qwen3:8b"
BASE="$(cd "$(dirname "$0")/.." && pwd)"
DOCS="$BASE/docs"
mkdir -p "$DOCS"

command -v pstree >/dev/null || { echo "ERRO: instale psmisc (sudo apt install -y psmisc)"; exit 1; }

SERVE_PID=$(pgrep -f 'ollama serve' | head -1)
[ -n "${SERVE_PID:-}" ] || { echo "ERRO: 'ollama serve' não está rodando. Rode 01-setup.sh"; exit 1; }
ollama_pids() { echo "$SERVE_PID"; pgrep -P "$SERVE_PID" 2>/dev/null || true; }

echo "PID do ollama serve: $SERVE_PID"

echo "Descarregando o modelo para capturar também o nascimento do runner..."
curl -s -X POST "$URL/api/generate" -d "{\"model\":\"$MODEL\",\"keep_alive\":0}" >/dev/null
sleep 3

echo "Disparando inferência longa em background..."
jq -n --arg m "$MODEL" --rawfile p "$BASE/prompts/long.txt" \
  '{model:$m, prompt:$p, stream:false, options:{num_predict:400, temperature:0, seed:42}}' \
  > /tmp/payload_proc.json
curl -s -X POST "$URL/api/generate" -H 'Content-Type: application/json' \
  -d @/tmp/payload_proc.json > /tmp/infer_proc.json &
CURL_PID=$!

sleep 8   # dá tempo do runner nascer e carregar os pesos

echo "Capturando..."
{
  echo "### Capturado em $(date -Is) durante inferência ativa"
  echo "### PID do serve: $SERVE_PID | PIDs observados: $(ollama_pids | tr '\n' ' ')"
  echo
  echo "### ps -eo pid,ppid,stat,ni,pri,psr,pcpu,pmem,nlwp,comm (top CPU)"
  ps -eo pid,ppid,stat,ni,pri,psr,pcpu,pmem,nlwp,comm --sort=-pcpu | head -20
  echo
  echo "### processos do Ollama (serve + filhos)"
  ps -o pid,ppid,stat,nlwp,pcpu,pmem,rss,etime,args -p "$(ollama_pids | tr '\n' ',' | sed 's/,$//')"
  echo
  echo "### threads (ps -eLf | grep ollama) — mesmo PID, LWP diferentes"
  ps -eLf | grep -E '[o]llama'
  echo
  echo "### contagem de threads por PID via /proc"
  for p in $(ollama_pids); do
    echo "PID $p -> $(ls /proc/$p/task | wc -l) threads | cmd: $(tr '\0' ' ' < /proc/$p/cmdline)"
  done
  echo
  echo "### /proc/<pid>/status (estado, threads, memória)"
  for p in $(ollama_pids); do
    echo "--- PID $p"
    grep -E '^(Name|State|Tgid|Pid|PPid|Threads|VmRSS|VmSize):' "/proc/$p/status"
  done
  echo
  echo "### conexões na porta 11434"
  ss -tnp 2>/dev/null | grep 11434 || true
} > "$DOCS/processos_threads.txt" 2>&1

pstree -p "$SERVE_PID" > "$DOCS/arvore_processos.txt" 2>&1 || true
pstree -aps "$SERVE_PID" >> "$DOCS/arvore_processos.txt" 2>&1 || true

wait $CURL_PID 2>/dev/null || true

echo
echo "Arquivos gerados:"
wc -l "$DOCS/processos_threads.txt" "$DOCS/arvore_processos.txt"
echo
NPIDS=$(ollama_pids | wc -l)
if [ "$NPIDS" -lt 2 ]; then
  echo "ATENÇÃO: só $NPIDS processo do Ollama encontrado. O runner deveria estar vivo"
  echo "durante a inferência. Confira com: pgrep -af ollama"
else
  echo "OK: $NPIDS processos (serve + runner). O runner tem PPid = $SERVE_PID —"
  echo "é isso que responde a questão 5 do relatório."
fi
grep -E '^(Name|Pid|PPid|Threads|VmRSS):' "$DOCS/processos_threads.txt" | head -24
