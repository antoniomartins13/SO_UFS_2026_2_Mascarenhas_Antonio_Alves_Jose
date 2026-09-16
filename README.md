# SO_UFS_2026_2 — Atividade 1 (AV1)

**Processos, threads, escalonamento e inferência local com Ollama**

Universidade Federal de Sergipe — Sistemas Operacionais — 2026.2
Trilha A — Chat local: Ollama + Open WebUI

---

## 1. Identificação da equipe

**Equipe:** Qwen3

| Integrante | Contribuição principal |
| --- | --- |
| Antônio José Martins Mascarenhas | *(preencher)* |
| José Gustavo Abreu Alves | *(preencher)* |
| Davi Oliveira Machado | *(preencher)* |
| Antonio Carlos Bispo Cunha | *(preencher)* |
| Kaique Teixeira Rodrigues | *(preencher)* |
| Anderson Soares de Santana Junior | *(preencher)* |
| João Felipe Tunes Oliveira | *(preencher)* |

> A tabela detalhada de contribuições consta na Seção 1 do relatório técnico (`docs/relatorio.pdf`).

---

## 2. Vídeo da atividade

**URL:** *(inserir link público — obrigatório)*

Data de gravação: *(preencher)*
Detalhes e identificação dos participantes: [`VIDEO.md`](VIDEO.md)

---

## 3. Trilha e camada de aplicação

| Item | Valor |
| --- | --- |
| Trilha | A — Chat local |
| Camada de aplicação | Open WebUI |
| Repositório | <https://github.com/open-webui/open-webui> |
| Versão / tag utilizada | *(preencher: ex. `v0.x.y`)* |
| Licença | *(preencher conforme o repositório na data de acesso)* |
| Data de acesso | *(preencher)* |
| Runtime obrigatório | Ollama |
| Versão do Ollama | *(preencher: saída de `ollama --version`)* |

**Topologia adotada:** Ollama executado **nativamente no host**; Open WebUI em **contêiner Docker** com volume persistente. A comunicação ocorre por HTTP na API local do Ollama (porta `11434`), acessada de dentro do contêiner via `host.docker.internal`.

Essa separação foi escolhida deliberadamente: ela expõe sockets, mapeamento de portas, namespaces de rede e volumes como objetos de estudo, o que é o foco de observação previsto para a Trilha A. Uma instalação monolítica esconderia esses elementos.

---

## 4. Modelo selecionado

| Critério | Valor |
| --- | --- |
| Nome completo | Qwen3-8B |
| Model card | <https://huggingface.co/Qwen/Qwen3-8B> |
| Organização | Qwen (Alibaba Cloud) |
| Parâmetros | 8,19 bilhões (8.19B) |
| Checkpoint | Instruído / chat (modo híbrido *thinking* e *non-thinking*) |
| Formato | GGUF |
| Quantização | Q4_K_M |
| Licença | Apache-2.0 |
| Tag no Ollama | `qwen3:8b` |
| Janela de contexto | *(preencher conforme model card e configuração usada)* |
| Tamanho em disco | *(preencher: `du -sh ~/.ollama/models`)* |

Registro no Google Classroom: [`docs/registro-classroom.pdf`](docs/) — 04/09/2026, 20:58.
Ficha técnica completa do modelo: [`docs/ficha-modelo.md`](docs/ficha-modelo.md).

---

## 5. Ambiente experimental

| Item | Valor |
| --- | --- |
| Distribuição / versão | *(preencher)* |
| Kernel | *(preencher)* |
| CPU / núcleos / threads | *(preencher)* |
| RAM | *(preencher)* |
| GPU / VRAM | *(preencher ou "não disponível")* |
| Armazenamento livre | *(preencher)* |
| Modo de execução | Nativo / VM / WSL / contêiner — *(preencher)* |
| Docker | *(preencher)* |

Saídas brutas dos comandos de inventário: [`docs/ambiente/`](docs/ambiente/).

---

## 6. Instalação

### 6.1 Pré-requisitos

- Linux x86_64 com Docker instalado
- ~10 GB livres em disco (pesos do modelo + índices + logs)
- `jq`, `strace`, `procps`, `psmisc` (para os scripts de medição)

```bash
sudo apt install -y jq strace procps psmisc
```

### 6.2 Ollama (host)

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama --version
ollama pull qwen3:8b
ollama list
```

Para que o contêiner alcance o Ollama, o serviço precisa escutar além do loopback:

```bash
sudo systemctl edit ollama
# [Service]
# Environment="OLLAMA_HOST=0.0.0.0:11434"
sudo systemctl restart ollama
```

### 6.3 Open WebUI (contêiner)

```bash
docker run -d \
  --name open-webui \
  -p 3000:8080 \
  --add-host=host.docker.internal:host-gateway \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -v open-webui:/app/backend/data \
  --restart always \
  ghcr.io/open-webui/open-webui:main
```

> **Atenção:** em Linux, `host.docker.internal` **não existe por padrão**. A flag `--add-host=...:host-gateway` é obrigatória; sem ela o contêiner não resolve o endereço e a interface não lista nenhum modelo. Este foi um dos erros verificados durante a atividade (ver Declaração de Uso de IA).

Interface disponível em `http://localhost:3000`.

### 6.4 Verificação

```bash
curl http://localhost:11434/api/tags | jq '.models[].name'
ss -tlnp | grep -E '11434|3000'
docker ps
```

---

## 7. Arquitetura

```
┌─────────────────────────── host Linux ───────────────────────────┐
│                                                                  │
│  ┌── contêiner Docker ──────────┐      ┌── processo nativo ───┐  │
│  │  open-webui                  │      │  ollama serve        │  │
│  │  uvicorn/FastAPI  :8080      │─HTTP─▶│  :11434             │  │
│  │  volume: open-webui          │      │      │ fork/exec     │  │
│  └──────────────────────────────┘      │      ▼               │  │
│         ▲  porta 3000                  │  ollama runner       │  │
│         │                              │  (llama.cpp, mmap    │  │
│    navegador                           │   dos pesos GGUF)    │  │
│                                        └──────────────────────┘  │
│                                             ~/.ollama/models     │
└──────────────────────────────────────────────────────────────────┘
```

O `ollama serve` atua como servidor HTTP e supervisor; ele cria um processo filho `ollama runner` que é quem efetivamente carrega os pesos em memória e executa a inferência multithread. A análise de processos, threads e chamadas de sistema concentra-se no **runner**, não no processo pai.

---

## 8. Estrutura do repositório

```
.
├── README.md
├── VIDEO.md
├── .gitignore
├── docs/
│   ├── relatorio.pdf
│   ├── apresentacao.pdf
│   ├── ficha-modelo.md
│   ├── registro-classroom.pdf
│   ├── declaracao-ia.md
│   └── ambiente/              # saídas de uname, lscpu, free, df, nvidia-smi
├── scripts/
│   ├── inventario.sh          # coleta o ambiente
│   ├── bench.sh               # dispara execuções e grava CSV
│   ├── monitor.sh             # amostra CPU/RAM/threads via /proc
│   └── observar-processos.sh  # ps, pstree, strace
├── data/
│   ├── prompts/               # entradas curta e longa
│   └── resultados/            # CSVs brutos
├── logs/                      # strace, logs do Ollama e do WebUI
└── analise/
    ├── analise.ipynb
    └── graficos/
```

---

## 9. Reprodução dos experimentos

### 9.1 Inventário do ambiente

```bash
./scripts/inventario.sh          # grava em docs/ambiente/
```

### 9.2 Observação de processos, threads e chamadas de sistema

```bash
./scripts/observar-processos.sh  # ps, pstree, ps -eLf → logs/
```

Captura de chamadas de sistema no processo de inferência:

```bash
sudo sysctl -w kernel.yama.ptrace_scope=0     # necessário para anexar por PID
RUNNER=$(pgrep -f 'ollama runner' | head -1)
sudo strace -f -c -p "$RUNNER" -o logs/strace-resumo.txt
```

Chamadas analisadas no relatório: `mmap`/`openat` (carregamento dos pesos por memory-mapping), `futex`/`clone` (criação e sincronização das threads de inferência) e `epoll_wait`/`accept4`/`write` (servidor HTTP e streaming da resposta).

### 9.3 Configurações comparadas

| Config | Variável manipulada | Hipótese |
| --- | --- | --- |
| 1 — padrão | defaults do Ollama | linha de base |
| 2 — concorrência | `OLLAMA_NUM_PARALLEL` = 1 vs 4 | vazão cresce até saturar CPU/memória |
| 3 — ajuste local | quantização `q4_K_M` vs `q8_0` *(ou contexto curto vs longo)* | menor quantização reduz RAM e aumenta tokens/s |

Cada configuração é executada com **duas entradas** (prompt curto e prompt de contexto longo) e **no mínimo duas repetições** — total ≥ 12 execuções mensuráveis.

```bash
# Configuração 1
./scripts/bench.sh --config padrao --repeticoes 3

# Configuração 2
sudo systemctl set-environment OLLAMA_NUM_PARALLEL=4 && sudo systemctl restart ollama
./scripts/bench.sh --config concorrencia --paralelas 4 --repeticoes 3

# Configuração 3
ollama pull qwen3:8b-q8_0
./scripts/bench.sh --config quantizacao --modelo qwen3:8b-q8_0 --repeticoes 3
```

### 9.4 Métricas coletadas

As métricas de tempo vêm diretamente do JSON da API do Ollama, não de cronometragem manual:

| Campo da API | Métrica |
| --- | --- |
| `load_duration` | tempo de carregamento do modelo |
| `prompt_eval_duration` | tempo até o primeiro token (TTFT) |
| `total_duration` | latência total da requisição |
| `eval_count` / `eval_duration` | tokens por segundo |

CPU, RAM, número de processos e de threads são amostrados em paralelo a partir de `/proc/<pid>/status` por `scripts/monitor.sh`.

**Controle de cache:** entre repetições, o modelo é descarregado (`ollama stop qwen3:8b`) para que `load_duration` seja comparável. As execuções com modelo já residente estão marcadas na coluna `warm` do CSV e analisadas separadamente.

**Controle do modo de raciocínio:** o Qwen3-8B alterna entre modos *thinking* e *non-thinking*. Todas as execuções fixam o modo *non-thinking* (`"think": false`), pois a geração variável de tokens de raciocínio introduziria variância que invalidaria a comparação entre configurações.

### 9.5 Análise

```bash
jupyter notebook analise/analise.ipynb    # gera tabelas e gráficos em analise/graficos/
```

---

## 10. Resultados

Dados brutos: [`data/resultados/`](data/resultados/)
Gráficos: [`analise/graficos/`](analise/graficos/)
Discussão completa: [`docs/relatorio.pdf`](docs/relatorio.pdf)

---

## 11. Uso de IA generativa

A declaração completa — ferramentas, finalidades, prompts, sugestões aproveitadas, sugestões corrigidas ou rejeitadas e erros encontrados — está em [`docs/declaracao-ia.md`](docs/declaracao-ia.md).

---

## 12. Observações sobre o repositório

- Os **pesos do modelo não são versionados** (`.gitignore`). Reproduza com `ollama pull qwen3:8b`.
- Não há chaves, senhas, tokens, arquivos `.env` ou dados pessoais neste repositório.
- Logs e CSVs incluídos são artefatos de medição, sem conteúdo sensível.

---

## 13. Referências

- SILBERSCHATZ, A.; GALVIN, P. B.; GAGNE, G. *Operating System Concepts*. 10. ed. Wiley, 2018.
- TANENBAUM, A. S.; BOS, H. *Modern Operating Systems*. 5. ed. Pearson, 2023.
- KERRISK, M. *The Linux Programming Interface*. No Starch Press, 2010.
- Linux man-pages: `fork(2)`, `execve(2)`, `clone(2)`, `mmap(2)`, `pthreads(7)`, `sched(7)` — <https://man7.org/linux/man-pages/>
- Ollama — <https://github.com/ollama/ollama>
- Open WebUI — <https://github.com/open-webui/open-webui>
- Qwen3-8B — <https://huggingface.co/Qwen/Qwen3-8B>
- NIST. *AI Risk Management Framework: Generative AI Profile*. NIST AI 600-1, 2024.
