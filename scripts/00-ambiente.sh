#!/usr/bin/env bash
# 00-ambiente.sh — Inventário do ambiente (Parte A, seção 6.1 da atividade).
# Gera docs/ambiente.txt com tudo que o relatório precisa citar.
# Pode rodar quantas vezes quiser; sobrescreve o arquivo.
#
# Correção: o modelo agora vem de $MODEL, como nos demais scripts, em vez de
# aparecer fixo em "ollama show qwen3:8b".

set -uo pipefail

MODEL="qwen3:8b"

BASE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$BASE/docs/ambiente.txt"
mkdir -p "$BASE/docs"

sec() { printf '\n===== %s =====\n' "$1" >> "$OUT"; }

: > "$OUT"
echo "Coletado em: $(date -Is)" >> "$OUT"
echo "Modelo de referência: $MODEL" >> "$OUT"

sec "uname -a";            uname -a                     >> "$OUT" 2>&1
sec "/etc/os-release";     cat /etc/os-release           >> "$OUT" 2>&1
sec "lscpu";               lscpu                        >> "$OUT" 2>&1
sec "nproc";               nproc                        >> "$OUT" 2>&1
sec "free -h";             free -h                      >> "$OUT" 2>&1
sec "df -h";               df -h                        >> "$OUT" 2>&1
sec "lsblk";               lsblk                        >> "$OUT" 2>&1
sec "getconf CLK_TCK";     getconf CLK_TCK              >> "$OUT" 2>&1

sec "ambiente de execução"
if grep -qi microsoft /proc/version 2>/dev/null; then
  echo "WSL2 (kernel Linux dentro de VM gerenciada pelo Windows)" >> "$OUT"
  echo "/proc/version: $(cat /proc/version)"                      >> "$OUT"
  echo "NOTA: em WSL2 o relógio de parede (CLOCK_REALTIME) pode saltar dezenas de" >> "$OUT"
  echo "segundos ao ressincronizar com o host. Por isso 04-bench.sh mede durações" >> "$OUT"
  echo "com /proc/uptime (CLOCK_MONOTONIC). Registrar isso em Limitações."         >> "$OUT"
else
  echo "Linux nativo ou VM (sem assinatura de WSL em /proc/version)" >> "$OUT"
fi

sec "versões"
{
  echo "ollama: $(ollama --version 2>&1 | head -1)"
  echo "docker: $(docker --version 2>&1)"
  echo "python3: $(python3 --version 2>&1)"
  echo "curl: $(curl --version 2>&1 | head -1)"
  echo "jq: $(jq --version 2>&1)"
} >> "$OUT" 2>&1

sec "ollama list";  ollama list  >> "$OUT" 2>&1

sec "tamanho em disco dos modelos"
du -sh "$HOME/.ollama/models" >> "$OUT" 2>&1 || echo "diretório de modelos ainda não existe" >> "$OUT"

sec "GPU"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi >> "$OUT" 2>&1
else
  echo "nvidia-smi não encontrado — execução em CPU. Registrar isso como limitação." >> "$OUT"
fi

sec "docker ps"; docker ps >> "$OUT" 2>&1

sec "ollama show $MODEL"; ollama show "$MODEL" >> "$OUT" 2>&1

sec "digest da imagem do Open WebUI"
docker image inspect ghcr.io/open-webui/open-webui:main \
  --format '{{index .RepoDigests 0}}' >> "$OUT" 2>&1

echo "Inventário salvo em $OUT"
