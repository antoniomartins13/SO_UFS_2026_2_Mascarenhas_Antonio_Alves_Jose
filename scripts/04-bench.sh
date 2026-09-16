#!/usr/bin/env bash
# 04-bench.sh — Experimentos comparativos (Parte C, seções 8, 8.1 e 8.2).
#
# Desenho (inalterado):
#   Config 1 padrao          : num_ctx=4096, 1 requisição       (linha de base)
#   Config 2 concorrencia    : num_ctx=4096, 4 requisições simultâneas
#   Config 3 contexto_longo  : num_ctx=8192, 1 requisição
#   x 2 tamanhos de prompt (short/long) x REPS repetições
#
# Correções em relação à versão anterior:
#
#  [1] Relógio monotônico (/proc/uptime) em vez de `date +%s.%N`.
#      O relógio de parede do WSL2 salta ~+21 s / -20 s ao ressincronizar com
#      o host (verificado: aparece nas 12 séries temporais da rodada anterior).
#      Isso corrompia client_elapsed_s, wall_s, vazao_req_s e deixava o eixo
#      de tempo das séries não monotônico.
#
#  [2] Conjunto de PIDs = 'ollama serve' + filhos, em vez de `pgrep -x ollama`.
#      O runner — processo filho que carrega os pesos e consome a CPU — não
#      casava com -x, então CPU/RSS/threads mediam só o servidor idle
#      (rss_pico ~40 MB para um modelo de ~5 GB, cpu_s ~0,07 s).
#
#  [3] Jiffies de CPU lidos DENTRO do sampler. O conjunto de PIDs é relido a
#      cada amostra (o runner nasce e morre no meio do batch) e passa a sair
#      série temporal de CPU, que é o que falta para o gráfico principal.
#
#  [4] Nonce único no início de cada prompt, para invalidar o cache de prefixo
#      do Ollama. Sem isso a rep 1 mede prompt frio e a rep 2 mede cache
#      quente (53 s vs 0,15 s de prompt_eval no mesmo cenário) — as repetições
#      não eram repetições da mesma condição.
#
#  [5] REPS=3, TTFT derivado, done_reason, tamanho da resposta e metadados
#      (modelo, versão do runtime, num_predict, keep_alive, horário).
#
#  [6] Checagem de sanidade ao fim de cada batch: se o runner não foi
#      amostrado, o script avisa em vez de gerar CSV silenciosamente errado.

set -uo pipefail

URL="http://127.0.0.1:11434"
MODEL="qwen3:8b"
SEED=42
NUM_PREDICT=256
REPS=3
CONC=4
KEEP_ALIVE="10m"
CLK=$(getconf CLK_TCK)

BASE="$(cd "$(dirname "$0")/.." && pwd)"
RES="$BASE/results"
mkdir -p "$RES/raw" "$RES/amostras"

RUNS="$RES/runs.csv"
REC="$RES/recursos.csv"

TOTAL=$(( 3 * 2 * REPS ))

# --- [2] PIDs do Ollama: o serve e seus filhos (o runner é filho direto) -----
SERVE_PID=$(pgrep -f 'ollama serve' | head -1)
if [ -z "${SERVE_PID:-}" ]; then
  echo "ERRO: 'ollama serve' não está rodando. Rode 01-setup.sh primeiro."
  exit 1
fi
ollama_pids() { echo "$SERVE_PID"; pgrep -P "$SERVE_PID" 2>/dev/null || true; }

# --- [1] relógio monotônico ---------------------------------------------------
# /proc/uptime é CLOCK_MONOTONIC com resolução de 10 ms: imune aos saltos de
# ressincronização do WSL2. O horário absoluto é registrado uma vez por batch,
# em ts_iso, só para rastreabilidade.
mono() { local up _; read -r up _ < /proc/uptime; echo "$up"; }

OLLAMA_VER=$(ollama --version 2>&1 | head -1 | tr -d ',')

echo "batch_id,config,prompt_size,rep,req_index,http_status,client_elapsed_s,ttft_s,total_duration_ns,load_duration_ns,prompt_eval_count,prompt_eval_duration_ns,eval_count,eval_duration_ns,tokens_per_second,done_reason,resp_chars,erro" > "$RUNS"
echo "batch_id,config,prompt_size,rep,num_ctx,concorrencia,ts_iso,wall_s,cpu_s,cores_medio,cores_pico,rss_pico_mb,threads_pico,procs_pico,vazao_req_s,amostras,modelo,ollama_ver,num_predict,keep_alive" > "$REC"

# --- [3] sampler: RSS, threads, processos E jiffies de CPU --------------------
sampler() {
  local out="$1"
  echo "t_mono,cpu_jiffies,rss_total_kb,threads_total,procs" > "$out"
  local p u s t r rss th np jif
  while :; do
    rss=0; th=0; np=0; jif=0
    for p in $(ollama_pids); do
      [ -r "/proc/$p/stat" ] || continue
      # utime/stime/num_threads. O sub() remove "pid (comm) " para que os
      # índices não quebrem se o nome do processo tiver espaços.
      read -r u s t < <(awk '{sub(/^[^)]*\) /,""); print $12, $13, $18}' "/proc/$p/stat" 2>/dev/null)
      jif=$(( jif + ${u:-0} + ${s:-0} ))
      th=$(( th + ${t:-0} ))
      r=$(awk '/^VmRSS:/{print $2}' "/proc/$p/status" 2>/dev/null)
      [ -n "${r:-}" ] && rss=$(( rss + r ))
      np=$(( np + 1 ))
    done
    echo "$(mono),$jif,$rss,$th,$np" >> "$out"
    sleep 0.5
  done
}

# --- preflight: o parâmetro "think" existe nesta versão do Ollama? -----------
USE_THINK=0
if curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/api/generate" \
     -H 'Content-Type: application/json' \
     -d "{\"model\":\"$MODEL\",\"prompt\":\"oi\",\"stream\":false,\"think\":false,\"options\":{\"num_predict\":5}}" \
     | grep -q 200; then
  USE_THINK=1
  echo "preflight: 'think:false' aceito — modo raciocínio desativado (respostas comparáveis)."
else
  echo "preflight: 'think:false' NÃO aceito por esta versão. Os prompts vão levar '/no_think' no fim."
fi

do_request() {  # $1=prompt_file $2=num_ctx $3=tag  -> escreve "<http> <elapsed>" no .meta
  local pf="$1" ctx="$2" tag="$3"
  local payload prompt_extra="" nonce s e code
  [ "$USE_THINK" = 0 ] && prompt_extra=$'\n/no_think'

  # [4] nonce no INÍCIO do prompt: o cache de prefixo do Ollama casa a partir
  # do primeiro token, então um marcador único por requisição garante que toda
  # execução avalie o prompt inteiro. Custa poucos tokens a mais em
  # prompt_eval_count — declarar isso no relatório.
  nonce="[exec ${tag}] "

  payload=$(jq -n --arg m "$MODEL" --rawfile p "$pf" --arg nonce "$nonce" --arg extra "$prompt_extra" \
    --argjson ctx "$ctx" --argjson seed "$SEED" --argjson np "$NUM_PREDICT" --arg ka "$KEEP_ALIVE" \
    '{model:$m, prompt:($nonce+$p+$extra), stream:false, keep_alive:$ka,
      options:{num_ctx:$ctx, seed:$seed, num_predict:$np, temperature:0}}')
  [ "$USE_THINK" = 1 ] && payload=$(echo "$payload" | jq '. + {think:false}')

  s=$(mono)
  code=$(curl -s -o "$RES/raw/${tag}.json" -w '%{http_code}' --max-time 900 \
    -X POST "$URL/api/generate" -H 'Content-Type: application/json' -d "$payload" 2>/dev/null || echo 000)
  e=$(mono)
  echo "$code $(echo "$e - $s" | bc)" > "$RES/raw/${tag}.meta"
}

write_row() {  # $1=batch $2=config $3=size $4=rep $5=req_index $6=tag
  local b="$1" cfg="$2" size="$3" rep="$4" idx="$5" tag="$6"
  local code elapsed json tot load pc pd ec ed tps ttft dr rc erro
  read -r code elapsed < "$RES/raw/${tag}.meta" 2>/dev/null || { code=000; elapsed=; }
  json="$RES/raw/${tag}.json"
  if [ "$code" != "200" ]; then
    echo "$b,$cfg,$size,$rep,$idx,$code,$elapsed,,,,,,,,,,,request_failed" >> "$RUNS"
    return
  fi
  tot=$(jq -r '.total_duration // empty' "$json" 2>/dev/null)
  load=$(jq -r '.load_duration // empty' "$json" 2>/dev/null)
  pc=$(jq -r '.prompt_eval_count // empty' "$json" 2>/dev/null)
  pd=$(jq -r '.prompt_eval_duration // empty' "$json" 2>/dev/null)
  ec=$(jq -r '.eval_count // empty' "$json" 2>/dev/null)
  ed=$(jq -r '.eval_duration // empty' "$json" 2>/dev/null)
  # [5] critério objetivo de avaliação da resposta (seção 8.2): done_reason
  # distingue resposta concluída ("stop") de resposta cortada por num_predict
  # ("length"); resp_chars dá o tamanho do texto gerado.
  dr=$(jq -r '.done_reason // empty' "$json" 2>/dev/null)
  rc=$(jq -r '(.response // "") | length' "$json" 2>/dev/null)

  tps=""
  if [ -n "$ec" ] && [ -n "$ed" ] && [ "$ed" != "0" ]; then
    tps=$(echo "scale=4; $ec / ($ed / 1000000000)" | bc)
  fi
  # [5] TTFT aproximado: carga do modelo + avaliação do prompt. Com
  # stream:false não há medição direta do primeiro token; esta é a melhor
  # estimativa disponível e deve ser descrita como tal no relatório.
  ttft=$(echo "scale=4; (${load:-0} + ${pd:-0}) / 1000000000" | bc)

  erro=""
  [ -z "$ec" ] && erro="sem_metricas"
  echo "$b,$cfg,$size,$rep,$idx,$code,$elapsed,$ttft,$tot,$load,$pc,$pd,$ec,$ed,$tps,$dr,$rc,$erro" >> "$RUNS"
}

batch=0

run_batch() {  # $1=config $2=num_ctx $3=conc $4=size $5=rep
  local cfg="$1" ctx="$2" conc="$3" size="$4" rep="$5"
  batch=$(( batch + 1 ))
  local tag="b${batch}_${cfg}_${size}_r${rep}"
  local pf="$BASE/prompts/${size}.txt"
  local sfile="$RES/amostras/${tag}.csv"
  local ts_iso; ts_iso=$(date -Is)

  printf '[%2d/%2d] config=%-15s prompt=%-5s rep=%s ctx=%s conc=%s ... ' \
    "$batch" "$TOTAL" "$cfg" "$size" "$rep" "$ctx" "$conc"

  sampler "$sfile" & local spid=$!
  local w0; w0=$(mono)

  local qpids=()
  local i
  for i in $(seq 1 "$conc"); do
    do_request "$pf" "$ctx" "${tag}_q${i}" &
    qpids+=($!)
  done
  wait "${qpids[@]}" 2>/dev/null

  local w1; w1=$(mono)
  kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null

  for i in $(seq 1 "$conc"); do
    write_row "$batch" "$cfg" "$size" "$rep" "$i" "${tag}_q${i}"
  done

  local wall cpu cores cpico rssmb thmax npmax n vaz
  wall=$(echo "scale=3; $w1 - $w0" | bc)

  # [3] CPU vem da série: soma só os deltas não negativos, para que a morte de
  # um runner no meio do batch (jiffies caem ao zerar o conjunto de PIDs) não
  # produza CPU negativa.
  cpu=$(awk -F, -v clk="$CLK" 'NR>1{if(prev!=""&&$2>=prev) t+=$2-prev; prev=$2} END{printf "%.3f", t/clk}' "$sfile")
  cpico=$(awk -F, -v clk="$CLK" 'NR>1{if(pt!=""){dt=$1-pt; dj=$2-pj; if(dt>0&&dj>=0){c=dj/clk/dt; if(c>m)m=c}} pt=$1; pj=$2} END{printf "%.2f", m+0}' "$sfile")
  cores=$(echo "scale=2; $cpu / $wall" | bc 2>/dev/null || echo "")
  rssmb=$(awk -F, 'NR>1 && $3>m{m=$3} END{printf "%.1f", m/1024}' "$sfile")
  thmax=$(awk -F, 'NR>1 && $4>m{m=$4} END{print m+0}' "$sfile")
  npmax=$(awk -F, 'NR>1 && $5>m{m=$5} END{print m+0}' "$sfile")
  n=$(( $(wc -l < "$sfile") - 1 ))
  vaz=$(echo "scale=4; $conc / $wall" | bc)

  echo "$batch,$cfg,$size,$rep,$ctx,$conc,$ts_iso,$wall,$cpu,$cores,$cpico,$rssmb,$thmax,$npmax,$vaz,$n,$MODEL,$OLLAMA_VER,$NUM_PREDICT,$KEEP_ALIVE" >> "$REC"

  printf 'wall=%ss cpu=%ss cores_med=%s cores_pico=%s rss_pico=%sMB threads=%s procs=%s\n' \
    "$wall" "$cpu" "$cores" "$cpico" "$rssmb" "$thmax" "$npmax"

  # [6] sanidade: sem o runner no conjunto de PIDs, RSS fica na casa de dezenas
  # de MB e a CPU perto de zero — foi exatamente o que invalidou a rodada
  # anterior. Melhor gritar aqui do que descobrir na análise.
  if [ "${npmax:-0}" -lt 2 ]; then
    echo "        ATENÇÃO: só $npmax processo(s) amostrado(s). O runner não foi capturado."
    echo "        Verifique com: pgrep -af ollama   /   pgrep -P $SERVE_PID"
  fi
  if awk "BEGIN{exit !($rssmb < 500)}"; then
    echo "        ATENÇÃO: rss_pico=${rssmb}MB é baixo demais para $MODEL — provavelmente só o serve foi medido."
  fi
}

warmup() {  # carrega o modelo com o num_ctx desta config (a troca de ctx recarrega o modelo)
  local ctx="$1"
  echo "  (aquecendo com num_ctx=$ctx — garante que load_duration não polua as medições)"
  curl -s -X POST "$URL/api/generate" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"prompt\":\"oi\",\"stream\":false,\"keep_alive\":\"$KEEP_ALIVE\",\"options\":{\"num_ctx\":$ctx,\"num_predict\":10}}" >/dev/null
}

echo
echo "### Config 1 — padrão (num_ctx=4096, 1 requisição)"
warmup 4096
for size in short long; do for rep in $(seq 1 $REPS); do run_batch padrao 4096 1 "$size" "$rep"; done; done

echo
echo "### Config 2 — concorrência (num_ctx=4096, $CONC requisições simultâneas)"
warmup 4096
for size in short long; do for rep in $(seq 1 $REPS); do run_batch concorrencia 4096 "$CONC" "$size" "$rep"; done; done

echo
echo "### Config 3 — contexto longo (num_ctx=8192, 1 requisição)"
warmup 8192
for size in short long; do for rep in $(seq 1 $REPS); do run_batch contexto_longo 8192 1 "$size" "$rep"; done; done

echo
echo "Pronto."
echo "  $RUNS      ($(( $(wc -l < "$RUNS") - 1 )) chamadas registradas)"
echo "  $REC   ($(( $(wc -l < "$REC") - 1 )) execuções registradas)"
echo "  $RES/amostras/  (séries de CPU/RAM/threads por execução)"
echo "  $RES/raw/       (JSON bruto de cada resposta)"
grep -c request_failed "$RUNS" >/dev/null && echo "ATENÇÃO: há linhas request_failed — veja logs/ollama.log"
