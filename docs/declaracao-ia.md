# Declaração de Uso de IA Generativa

Seção 10 do enunciado. Este arquivo reproduz a Seção 14 do relatório técnico
([`relatorio.pdf`](relatorio.pdf)), que é a versão oficial da declaração.

## 1. Ferramenta e modelo

Interface web do Claude (Anthropic), modelo **Claude Opus 5**, durante setembro de
2026, como apoio à geração e revisão dos cinco scripts Bash de automação da
atividade. A ferramenta foi utilizada majoritariamente no desenvolvimento dos
scripts.

## 2. Finalidade

Construção dos scripts de inventário do ambiente, configuração (Ollama + Open
WebUI), monitoramento de processos, captura de chamadas de sistema e benchmark
comparativo — respectivamente [`00-ambiente.sh`](../scripts/00-ambiente.sh),
[`01-setup.sh`](../scripts/01-setup.sh), [`02-processos.sh`](../scripts/02-processos.sh),
[`03-strace.sh`](../scripts/03-strace.sh) e [`04-bench.sh`](../scripts/04-bench.sh).

## 3. Prompts relevantes

1. **Geração inicial dos scripts** — "Segue o enunciado da atividade em PDF.
   Precisamos automatizar a Parte A, a Parte B e a Parte C: inventário do ambiente,
   subida do Ollama no host com Open WebUI em contêiner, captura de processos e
   threads durante inferência ativa, captura de chamadas de sistema com strace e um
   benchmark comparativo. O ambiente é WSL2 sobre Windows, execução em CPU, modelo
   qwen3:8b. Gere scripts em Bash, um por etapa, que gravem evidências em arquivos
   versionáveis e produzam os dados em CSV."
2. **Desenho experimental do benchmark** — "O script de benchmark varia apenas o
   número de threads em três valores, o que são três pontos do mesmo eixo e não
   atende a seção 8 da atividade, que pede três configurações distintas. Reestruture
   para execução padrão, concorrência com requisições simultâneas e ajuste de janela
   de contexto, mantendo o mesmo modelo, com dois tamanhos de entrada e repetições
   por cenário."
3. **Instrumentação de recursos** — "Além dos tempos retornados pela API do Ollama,
   o script precisa medir consumo de CPU, memória residente, número de threads e
   número de processos durante cada execução. Implemente a coleta lendo o sistema de
   arquivos /proc, com amostragem periódica em segundo plano, gravando uma série
   temporal por execução e os agregados na tabela de recursos."
4. **Captura de chamadas de sistema** — "No script de strace, quando anexamos ao
   processo com o modelo já carregado só aparecem chamadas de sincronização e espera,
   sem as operações de abertura e mapeamento dos pesos. Ajuste o script para capturar
   também a carga do modelo e produza tanto um resumo agregado quanto um traçado
   detalhado das famílias de chamadas relacionadas a arquivo, memória e rede."
5. **Cobertura das métricas obrigatórias** — "Confira se o script de benchmark cobre
   as métricas mínimas da seção 8.2 e implemente o que estiver faltando: tempo até a
   primeira resposta, critério objetivo de avaliação da resposta gerada, taxa de erro
   e registro de parâmetros, modelo, versão do runtime e horário de cada execução."

## 4. Sugestões aproveitadas

Organização dos scripts por etapa, registro das evidências em arquivos versionáveis
e coleta de dados em diferentes níveis. Também foram incorporados:

- uso de `/proc` para monitoramento e de `/proc/uptime` como relógio monotônico;
- identificação dos processos do Ollama por descendência;
- descarregamento do modelo antes do `strace`, para que o `llama-server` nasça já
  sob observação e as chamadas de carga dos pesos apareçam no traçado;
- marcadores únicos (nonce) no início de cada prompt, para evitar interferência do
  cache de prefixo entre repetições.

## 5. Sugestões corrigidas ou rejeitadas

| Sugestão | Problema | Desfecho |
| --- | --- | --- |
| `host.docker.internal` sem `--add-host` | No Linux o Docker Engine não resolve esse nome por padrão (ao contrário do Docker Desktop); o contêiner não lista modelo algum | Corrigida com `--add-host=host.docker.internal:host-gateway` em [`01-setup.sh`](../scripts/01-setup.sh) |
| Aquecimento com o próprio prompt do experimento | Eliminava o custo de leitura do prompt, que era justamente o fenômeno analisado | **Rejeitada** |
| Explicação para valores nulos na coleta de métricas | Teste direto mostrou que a causa real estava no conjunto de processos monitorado | **Descartada** |
| Benchmark variando apenas `num_thread` em 2/4/8 | Três pontos do mesmo eixo, não três configurações distintas como pede a Seção 8 | Reestruturado em padrão / concorrência / contexto longo |

## 6. Erros de instrumentação encontrados e corrigidos

1. uso de relógio de parede sob WSL2 (substituído por `/proc/uptime`);
2. exclusão do processo `llama-server` do monitoramento;
3. aquecimento com prompt diferente do experimento;
4. truncamento dos argumentos capturados pelo `strace`.

Todos foram corrigidos antes da execução definitiva.

## 7. Como as respostas foram verificadas

- todos os scripts passaram por `bash -n` e por execução completa em ambiente de teste;
- os campos usados de `/proc/<pid>/stat` foram conferidos na documentação de `proc(5)`;
- a medição de tempo do cliente foi validada contra o `total_duration` do servidor,
  com divergência máxima de **107 ms** nas 36 requisições;
- a identificação dos processos foi confirmada pelos picos de processos e de memória,
  compatíveis com a execução do modelo.

Respostas de IA não substituíram comandos, logs, medições ou documentação oficial:
todos os números apresentados vêm dos CSVs em [`../resultados/`](../resultados/) e das
evidências em [`../evidencias/`](../evidencias/).

## 8. Distribuição das contribuições

Ver Seção 1 do relatório técnico e a tabela do [`README.md`](../README.md).
