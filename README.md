# SO_UFS_2026_2 — Atividade 1 (AV1)

**Processos, threads, escalonamento e inferência local com Ollama**

Universidade Federal de Sergipe — Departamento de Computação
Sistemas Operacionais, Turma 02 — 2026.2 — Docente: Glauco de Figueiredo Carneiro

Trilha A — Chat local: **Ollama + Open WebUI** · Modelo **Qwen3-8B** (`qwen3:8b`)

---

## 1. Equipe

| Integrante | Contribuição |
| --- | --- |
| Antônio José Martins Mascarenhas | Organização do GitHub |
| José Gustavo Abreu Alves | Testes na máquina + slides |
| Davi Oliveira Machado | Testes na máquina |
| Antônio Carlos Bispo Cunha | Organização do trabalho + edição do vídeo |
| Kaique Teixeira Rodrigues | Roteiro do vídeo |
| Anderson Soares de Santana Júnior | Organização dos testes + testes na máquina |
| João Felipe Tunes Oliveira | Realização do relatório técnico |

---

## 2. Vídeo da atividade

**URL:** <https://drive.google.com/drive/folders/1Bnsh_tq4IbDktoHM4xNR3b2s2JOMQeQ0?usp=sharing>

Gravado em 14/09/2026, com participação de todos os integrantes.
Detalhes em [`VIDEO.md`](VIDEO.md).

---

## 3. Entregáveis

| Item do enunciado (Seção 11) | Onde está |
| --- | --- |
| 1. Relatório técnico em PDF | [`docs/relatorio.pdf`](docs/relatorio.pdf) |
| 2. Camada de aplicação utilizada | Open WebUI — <https://github.com/open-webui/open-webui>, imagem `ghcr.io/open-webui/open-webui:main` |
| 3. Ficha técnica do modelo | [`docs/ficha-modelo.md`](docs/ficha-modelo.md) |
| 4. Registro no Google Classroom | [`docs/registro-classroom.md`](docs/registro-classroom.md) — 04/09/2026, 20:58 |
| 5. README com instalação e reprodução | este arquivo |
| 6. Scripts de configuração | [`scripts/01-setup.sh`](scripts/01-setup.sh) |
| 7. Scripts de execução e medição | [`scripts/`](scripts/) |
| 8. Logs, tabelas, dados e gráficos | [`resultados/`](resultados/), [`logs/`](logs/) |
| 9. Evidências de processos, threads e syscalls | [`evidencias/`](evidencias/) |
| 10. Declaração de Uso de IA Generativa | [`docs/declaracao-ia.md`](docs/declaracao-ia.md) e Seção 14 do relatório |
| 11. Apresentação | [`docs/apresentacao.pdf`](docs/apresentacao.pdf) |
| 13.1. Vídeo | [`VIDEO.md`](VIDEO.md) |

---

## 4. Modelo

| Item | Valor |
| --- | --- |
| Nome completo | Qwen3-8B |
| Model card | <https://huggingface.co/Qwen/Qwen3-8B> |
| Parâmetros | 8,19 B (8,2 B totais; 6,95 B sem embeddings) |
| Variante | Instruct / chat |
| Formato · Quantização | GGUF · Q4_K_M |
| Licença | Apache-2.0 |
| Artefato executado | tag `qwen3:8b` (registry do Ollama), ~4,9 GB em disco |
| Contexto nativo | 32.768 tokens (até 131.072 com YaRN) |

Ficha completa com os critérios da Seção 5.3 do enunciado:
[`docs/ficha-modelo.md`](docs/ficha-modelo.md).

---

## 5. Ambiente experimental

Duas máquinas independentes, cada uma um bloco de medições próprio — todas as
comparações entre configurações usam sempre a mesma máquina.

| Item | Máquina 1 (principal) | Máquina 2 (comparação) |
| --- | --- | --- |
| Hostname | DESKTOP-B3LNN05 | DESKTOP-1F600RV |
| SO | Ubuntu 26.04.1 LTS (WSL2) | Ubuntu 24.04.5 LTS (WSL2) |
| Kernel | 6.18.33.2-microsoft-standard-WSL2 | 6.18.33.2-microsoft-standard-WSL2 |
| CPU física | AMD Ryzen 7 5700X | AMD Ryzen 5 5600GT |
| CPUs vistas pelo WSL2 (`lscpu`) | 8 lógicas — 4 núcleos × 2 threads | 12 lógicas — 6 núcleos × 2 threads |
| RAM / swap (WSL2) | 11 GiB / 4 GiB | 13 GiB / 4 GiB |
| GPU | não utilizada (execução só em CPU) | não utilizada (execução só em CPU) |
| Ollama | 0.34.0 | 0.34.0 |
| Docker | Docker Engine dentro do WSL/Ubuntu | Docker Engine dentro do WSL/Ubuntu |

> O WSL2 expôs à máquina 1 apenas 8 CPUs lógicas (4 núcleos), metade do que o
> Ryzen 7 5700X oferece fisicamente. É por isso que ela ocupa ~3,9 núcleos durante a
> inferência contra ~5,9 da máquina 2. Saídas brutas em
> [`evidencias/maquina-1/ambiente.txt`](evidencias/maquina-1/ambiente.txt) e
> [`evidencias/maquina-2/ambiente.txt`](evidencias/maquina-2/ambiente.txt).

---

## 6. Arquitetura

```
+---------------------- host Linux (WSL2 / Ubuntu) -----------------------+
|                                                                         |
|  +-- conteiner Docker --------+        +-- processo nativo ----------+  |
|  |  open-webui                |        |  ollama serve   PID 1120    |  |
|  |  uvicorn/FastAPI  :8080    |--HTTP->|  :11434   14 threads        |  |
|  |  volume: open-webui        |        |        | fork/exec          |  |
|  |  1 processo, workers=1     |        |        v                    |  |
|  +----------------------------+        |  llama-server   PID 1681    |  |
|          ^  porta do host 3000         |  pesos via mmap, 12 LWPs    |  |
|          |                             +-----------------------------+  |
|      navegador                                ~/.ollama/models          |
+-------------------------------------------------------------------------+
```

O `ollama serve` é servidor HTTP e supervisor; ele cria o processo filho
`llama-server`, que carrega os pesos e executa a inferência multithread. A análise de
processos e chamadas de sistema concentra-se no filho, não no pai.

Em Linux, `host.docker.internal` **não é resolvido por padrão** pelo Docker Engine
(diferente do Docker Desktop). Sem `--add-host=host.docker.internal:host-gateway` o
contêiner não alcança o Ollama e a interface não lista modelo algum.

---

## 7. Instalação

### 7.1 Pré-requisitos

Linux (nativo, VM ou WSL2) com Docker Engine, ~10 GB livres em disco e:

```bash
sudo apt install -y curl jq bc strace procps psmisc python3-matplotlib
```

### 7.2 Ollama, Open WebUI e modelo

O script [`scripts/01-setup.sh`](scripts/01-setup.sh) faz tudo: sobe o `ollama serve`
com `OLLAMA_HOST=0.0.0.0` e `OLLAMA_NUM_PARALLEL=4`, baixa o modelo, sobe o contêiner
do Open WebUI e mede o carregamento a frio.

```bash
./scripts/01-setup.sh
```

O que ele executa, em resumo:

```bash
curl -fsSL https://ollama.com/install.sh | sh
OLLAMA_HOST=0.0.0.0:11434 OLLAMA_NUM_PARALLEL=4 ollama serve &
ollama pull qwen3:8b

docker run -d \
  --name open-webui \
  --add-host=host.docker.internal:host-gateway \
  -p 3000:8080 \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -v open-webui:/app/backend/data \
  --restart unless-stopped \
  ghcr.io/open-webui/open-webui:main
```

Interface em `http://localhost:3000`. Verificação:

```bash
curl -s http://localhost:11434/api/tags | jq '.models[].name'
ss -tlnp | grep -E '11434|3000'
docker ps
```

---

## 8. Reprodução dos experimentos

```bash
./scripts/00-ambiente.sh      # inventario do ambiente
./scripts/01-setup.sh         # ambiente + modelo + conteiner
./scripts/02-processos.sh     # ps, pstree, ps -eLf durante inferencia ativa
./scripts/03-strace.sh        # chamadas de sistema (resumo e detalhado)
./scripts/04-bench.sh         # 18 execucoes -> runs.csv, recursos.csv, amostras
python3 scripts/05-grafico.py # graficos g1..g4
```

`03-strace.sh` descarrega o modelo antes de anexar o `strace` ao `ollama serve`, para
que o `llama-server` nasça já sob observação — anexar com o modelo residente só mostra
sincronização e espera, sem as operações de carga dos pesos.

### 8.1 Configurações comparadas

| Config | `num_ctx` | Requisições simultâneas | Papel |
| --- | --- | --- | --- |
| `padrao` | 4096 | 1 | linha de base |
| `concorrencia` | 4096 | 4 | efeito da concorrência |
| `contexto_longo` | 8192 | 1 | efeito da janela de contexto |

Cada configuração × 2 tamanhos de prompt (curto ~51 tokens, longo ~1.794 tokens)
× 3 repetições = **18 execuções mensuráveis por máquina** (36 requisições HTTP),
acima do mínimo de 12 exigido pela Seção 8.2 do enunciado. Prompts em
[`prompts/`](prompts/).

### 8.2 Decisões de medição

- **Tempos vêm da API do Ollama**, não de cronometragem manual: `load_duration`,
  `prompt_eval_duration` (prefill / TTFT), `eval_duration` e `total_duration`. A
  medição do cliente divergiu no máximo 107 ms do `total_duration` nas 36 requisições.
- **CPU, RSS, threads e processos** são amostrados em paralelo a partir de
  `/proc/<pid>/stat` e `/proc/<pid>/status`, com `/proc/uptime` como relógio monotônico
  (o relógio de parede não é confiável sob WSL2).
- **Modo de raciocínio fixo:** `think: false` (ou sufixo `/no_think`), para que a
  geração variável de tokens de raciocínio do Qwen3 não introduza variância.
- **`num_predict` fixo em 256 tokens** — respostas a prompts longos são
  deliberadamente truncadas (`done_reason = length`), o que precisa ser considerado ao
  ler tokens/s nesses casos.
- **Nonce único por requisição**, para o cache de prefixo do Ollama não distorcer o
  tempo de avaliação entre repetições.
- **`keep_alive` de 10 min:** o modelo permanece residente durante a bateria, então
  `load_duration` fica abaixo de 5 ms e os tempos não incluem carga de pesos. A carga a
  frio foi medida à parte, em `evidencias/*/carga_a_frio.json`.
- **Critério de avaliação da resposta:** `done_reason` (`stop` vs `length`).

---

## 9. Resultados

Dados brutos em [`resultados/`](resultados/): `runs.csv` (uma linha por requisição),
`recursos.csv` (uma linha por execução), `amostras/` (séries temporais de CPU, RSS e
threads) e `raw/` (JSON de cada resposta). Gráficos em
`resultados/maquina-*/graficos/`.

Principais achados, com a máquina de origem explícita:

| Achado | Valor | Origem |
| --- | --- | --- |
| Latência sob concorrência, prompt curto | 12,65 s -> 25,20 s | M2 |
| Latência sob concorrência, prompt longo | 94,16 s -> 300,65 s | M2 |
| Ganho de vazão, prompt curto | +94% (0,0795 -> 0,1542 req/s) | M2 |
| Ganho de vazão, prompt longo | +25% (0,0106 -> 0,0132 req/s) | M2 |
| CPU por requisição sob concorrência | -45% (curto), -18% (longo) | M1 |
| TTFT, prompt curto -> longo | 1,40 s -> 54,31 s (39x) | M2 |
| RSS ao dobrar `num_ctx` | +2,3 GB (7.405 -> 9.707 MB) | M2 |
| Taxa de erro | 0% em 36 requisições por máquina | M1 e M2 |

Análise completa em [`docs/relatorio.pdf`](docs/relatorio.pdf).

---

## 10. Chamadas de sistema

`strace -f -c` sobre o `ollama serve` e seus filhos durante uma inferência
(evidências em `evidencias/*/strace_resumo.txt` e `strace_detalhado.txt`):

| Chamada | % do tempo (M1 / M2) | Papel |
| --- | --- | --- |
| `futex` | 85,4% / 90,0% | sincronização entre as threads de cálculo do `llama-server` |
| `accept4` | 9,3% / 6,8% | servidor HTTP do Ollama aceitando conexões do Open WebUI |
| `read` | 4,5% / 2,6% | leitura de sockets e arquivos |
| `epoll_pwait` / `nanosleep` | ~0,5% / ~0,4% | espera assíncrona por I/O e pausas de threads worker |

O modo resumo do `strace` contabiliza o tempo **decorrido dentro** de cada chamada, e
`futex` é uma chamada de espera: sua predominância indica threads bloqueadas
aguardando trabalho, não custo de processamento equivalente.

---

## 11. Estrutura do repositório

```
.
├── README.md
├── VIDEO.md
├── docs/
│   ├── relatorio.pdf          relatorio tecnico (16 secoes)
│   ├── apresentacao.pdf       slides
│   ├── ficha-modelo.md        criterios da Secao 5.3
│   └── declaracao-ia.md       Declaracao de Uso de IA Generativa
├── scripts/                   00-ambiente, 01-setup, 02-processos,
│                              03-strace, 04-bench, 05-grafico
├── prompts/                   short.txt (~51 tok), long.txt (~1.794 tok)
├── resultados/
│   ├── maquina-1/             runs.csv, recursos.csv, amostras/, raw/, graficos/
│   └── maquina-2/             idem
├── evidencias/
│   ├── maquina-1/             ambiente, processos, threads, portas, strace
│   └── maquina-2/             idem
└── logs/                      ollama-maquina-1.log, ollama-maquina-2.log
```

---

## 12. Sobre os dados publicados

- Os **pesos do modelo não são versionados** (ver [`.gitignore`](.gitignore)).
  Reproduza com `ollama pull qwen3:8b`.
- Não há chaves, senhas, tokens, arquivos `.env` ou dados pessoais no repositório.
- Logs, CSVs e traçados de `strace` são artefatos de medição, sem conteúdo sensível.

---

## 13. Referências

- SILBERSCHATZ, A.; GALVIN, P. B.; GAGNE, G. *Operating System Concepts*. 10. ed. Wiley, 2018.
- TANENBAUM, A. S.; BOS, H. *Modern Operating Systems*. 5. ed. Pearson, 2023.
- KERRISK, M. *The Linux Programming Interface*. No Starch Press, 2010.
- Linux man-pages: `fork(2)`, `execve(2)`, `clone(2)`, `mmap(2)`, `futex(2)`, `proc(5)`, `pthreads(7)`, `sched(7)` — <https://man7.org/linux/man-pages/>
- Ollama — <https://github.com/ollama/ollama>
- Open WebUI — <https://github.com/open-webui/open-webui>
- Qwen3-8B — <https://huggingface.co/Qwen/Qwen3-8B>
