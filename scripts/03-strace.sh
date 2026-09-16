#!/usr/bin/env bash
# 03-strace.sh — Chamadas de sistema (Parte B, seção 7.2).
#
# Ponto importante: quem carrega os pesos do modelo é o processo FILHO
# (ollama runner), não o 'ollama serve'. Se você anexar o strace com o modelo
# já carregado, só vai ver futex/epoll e nenhum mmap/openat dos pesos.
# Por isso aqui: descarrega o modelo -> anexa strace -f no serve -> dispara a
# inferência, para o runner nascer JÁ sob observação.
#
# Correção: a segunda captura usava `-s 0`, que trunca argumentos string em
# zero caractere. Os openat saíam com caminho vazio e o grep por blobs/.gguf
# logo abaixo nunca achava nada. Agora é `-s 200`.

set -uo pipefail

URL="http://127.0.0.1:11434"
MODEL="qwen3:8b"
BASE="$(cd "$(dirname "$0")/.." && pwd)"
DOCS="$BASE/docs"
mkdir -p "$DOCS"

command -v strace >/dev/null || { echo "ERRO: instale strace (sudo apt install -y strace)"; exit 1; }

SERVE_PID=$(pgrep -f "ollama serve" | head -1)
[ -n "${SERVE_PID:-}" ] || { echo "ERRO: 'ollama serve' não está rodando. Rode 01-setup.sh"; exit 1; }
echo "PID do ollama serve: $SERVE_PID"

echo "Descarregando o modelo da RAM..."
curl -s -X POST "$URL/api/generate" -d "{\"model\":\"$MODEL\",\"keep_alive\":0}" >/dev/null
sleep 3

echo "Anexando strace (-f, resumo) por 60s..."
sudo timeout -s INT 60 strace -f -c -p "$SERVE_PID" 2> "$DOCS/strace_resumo.txt" &
STRACE_PID=$!
sleep 3

echo "Disparando inferência (o runner vai nascer sob o strace)..."
curl -s -X POST "$URL/api/generate" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"prompt\":\"Explique o que é uma chamada de sistema em duas frases.\",\"stream\":false,\"options\":{\"num_predict\":120,\"temperature\":0}}" \
  > /dev/null

echo "Aguardando o strace encerrar..."
wait $STRACE_PID 2>/dev/null || true
sudo kill -INT $STRACE_PID 2>/dev/null || true
sleep 2

# Segunda captura, com trace detalhado só das famílias que interessam,
# para você poder citar argumentos reais (caminho do arquivo de pesos etc.).
echo "Capturando trace detalhado de arquivo/memória/rede (20s)..."
curl -s -X POST "$URL/api/generate" -d "{\"model\":\"$MODEL\",\"keep_alive\":0}" >/dev/null
sleep 3
sudo timeout -s INT 20 strace -f -s 200 -e trace=openat,mmap,read,pread64,socket,accept4,sendto,recvfrom,clone,clone3,execve \
  -p "$SERVE_PID" 2> "$DOCS/strace_detalhado.txt" &
S2=$!
sleep 3
curl -s -X POST "$URL/api/generate" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"prompt\":\"oi\",\"stream\":false,\"options\":{\"num_predict\":20}}" >/dev/null
wait $S2 2>/dev/null || true

echo
echo "=== Resumo capturado ==="
head -30 "$DOCS/strace_resumo.txt"
echo
echo "=== Linhas do detalhado que tocam os pesos do modelo (blobs) ==="
grep -E 'blobs|\.gguf' "$DOCS/strace_detalhado.txt" | head -10 || echo "(nenhuma — veja a nota abaixo)"
echo
echo "=== execve/clone do runner (nascimento do processo filho) ==="
grep -E 'execve|clone' "$DOCS/strace_detalhado.txt" | head -10 || true
echo
cat <<'EOF'
Para o relatório (questão 6), escolha 3 famílias e explique. Sugestão:
  - openat/mmap : abertura e mapeamento do arquivo de pesos em ~/.ollama/models/blobs
                  -> mapeamento de memória, paginação sob demanda
  - clone/clone3: criação das threads de inferência e do processo runner
                  -> criação de processos/threads e paralelismo
  - epoll_wait / accept4 / recvfrom / sendto : socket HTTP da API na porta 11434
                  -> comunicação local entre Open WebUI e Ollama
  - futex       : sincronização entre as threads de inferência (costuma dominar
                  o resumo -f -c) -> concorrência e espera

Se o resumo vier vazio ou com "ptrace: Operation not permitted":
  sudo sysctl -w kernel.yama.ptrace_scope=0
e rode de novo.
EOF
