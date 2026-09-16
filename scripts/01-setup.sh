#!/usr/bin/env bash
# 01-setup.sh — Sobe Ollama (dentro do Linux/WSL) + Open WebUI em Docker.
#
# Diferenças em relação ao setup antigo, todas necessárias:
#  - OLLAMA_HOST=0.0.0.0 : sem isso o contêiner do Open WebUI NÃO alcança o
#    Ollama por host.docker.internal (o padrão escuta só em 127.0.0.1).
#  - OLLAMA_NUM_PARALLEL=4 : sem isso as requisições simultâneas da
#    Configuração 2 podem virar fila em vez de concorrência real.
#  - para o serviço systemd do Ollama, se existir, e sobe o serve na mão,
#    para que as variáveis acima valham e o processo fique sob nosso controle.
#
# Idempotente: pode rodar de novo sem problema.

set -euo pipefail

URL="http://127.0.0.1:11434"
MODEL="qwen3:8b"
BASE="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$BASE/docs" "$BASE/logs"

echo "== 1) Pré-requisitos =="
for c in docker ollama curl jq bc; do
  command -v "$c" >/dev/null || { echo "ERRO: '$c' não encontrado. Veja o passo correspondente no PASSO-A-PASSO.md"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "ERRO: daemon do Docker não está rodando. Rode: sudo service docker start"; exit 1; }
echo "OK"

echo "== 2) Parando o serviço systemd do Ollama (se houver) =="
sudo systemctl stop ollama 2>/dev/null || true
pkill -x ollama 2>/dev/null || true
sleep 2

echo "== 3) Subindo o Ollama com bind 0.0.0.0 e paralelismo 4 =="
OLLAMA_HOST=0.0.0.0:11434 OLLAMA_NUM_PARALLEL=4 OLLAMA_KEEP_ALIVE=10m \
  nohup ollama serve > "$BASE/logs/ollama.log" 2>&1 &
for i in $(seq 1 20); do
  curl -sf "$URL/api/tags" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "$URL/api/tags" >/dev/null || { echo "ERRO: Ollama não respondeu em :11434. Veja $BASE/logs/ollama.log"; exit 1; }
echo "OK: Ollama respondendo. PID(s): $(pgrep -x ollama | tr '\n' ' ')"
ss -lntp 2>/dev/null | grep 11434 > "$BASE/docs/portas.txt" || true

echo "== 4) Baixando o modelo $MODEL (~5-6 GB na primeira vez) =="
echo "início do pull: $(date -Is)" | tee "$BASE/docs/tempo_download.txt"
/usr/bin/time -f "tempo real do pull: %E" -a -o "$BASE/docs/tempo_download.txt" \
  ollama pull "$MODEL" || ollama pull "$MODEL"
echo "fim do pull: $(date -Is)" >> "$BASE/docs/tempo_download.txt"
du -sh "$HOME/.ollama/models" >> "$BASE/docs/tempo_download.txt" 2>&1 || true
ollama list

echo "== 5) Medindo o tempo de carregamento do modelo a frio =="
# descarrega da RAM e carrega medindo — isto é a evidência de "tempo de
# carregamento do modelo" pedida na seção 8.2.
curl -s -X POST "$URL/api/generate" -d "{\"model\":\"$MODEL\",\"keep_alive\":0}" >/dev/null || true
sleep 3
curl -s -X POST "$URL/api/generate" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"prompt\":\"oi\",\"stream\":false,\"options\":{\"num_predict\":1}}" \
  | jq '{load_duration, total_duration, prompt_eval_duration}' \
  | tee "$BASE/docs/carga_a_frio.json"

echo "== 6) Subindo o Open WebUI em Docker =="
docker rm -f open-webui >/dev/null 2>&1 || true
docker run -d \
  --name open-webui \
  --add-host=host.docker.internal:host-gateway \
  -p 3000:8080 \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -v open-webui:/app/backend/data \
  --restart unless-stopped \
  ghcr.io/open-webui/open-webui:main

echo "Aguardando o Open WebUI subir (pode levar 1-2 min na primeira vez)..."
ok=0
for i in $(seq 1 60); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000)" = "200" ]; then ok=1; break; fi
  sleep 3
done
[ "$ok" = 1 ] && echo "OK: Open WebUI em http://localhost:3000" || echo "AVISO: ainda não respondeu 200. Rode: docker logs open-webui"

echo "== 7) Verificando WebUI -> Ollama de dentro do contêiner =="
if docker exec open-webui curl -sf http://host.docker.internal:11434/api/tags | jq -e '.models[].name' >/dev/null 2>&1; then
  echo "OK: o contêiner enxerga o Ollama do host"
  docker exec open-webui curl -s http://host.docker.internal:11434/api/tags > "$BASE/docs/webui_ve_ollama.json"
else
  echo "FALHOU. Plano B: recriar o contêiner com --network=host (ver PASSO-A-PASSO.md, Problemas comuns)."
  exit 1
fi

echo
echo "Setup completo. Abra http://localhost:3000, crie a conta local,"
echo "selecione $MODEL no topo do chat e mande uma mensagem de teste (tire print)."
