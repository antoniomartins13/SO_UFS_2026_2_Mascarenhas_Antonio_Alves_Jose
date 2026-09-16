# Ficha técnica do modelo — Qwen3-8B

Critérios obrigatórios da Seção 5.3 do enunciado.

| Critério | O que verificar | Valor |
| --- | --- | --- |
| Identificação | Organização, nome completo, URL do model card | Qwen (Alibaba Cloud) — **Qwen3-8B** — <https://huggingface.co/Qwen/Qwen3-8B> |
| Parâmetros | Total do modelo-base | **8,19 B** (8,2 B totais; 6,95 B sem embeddings) — dentro do limite de 10 B |
| Finalidade | Base, instruct, chat, código, multilíngue | Instruct / chat, com modos *thinking* e *non-thinking* |
| Idioma | Suporte ao português | Multilíngue, com suporte a português |
| Licença | Permissões e obrigações | **Apache-2.0** |
| Formato | GGUF, Safetensors, GGML | **GGUF** (tag `qwen3:8b` do registry do Ollama) |
| Quantização | Q4, Q5, Q8, FP16 | **Q4_K_M** |
| Contexto | Janela máxima e limitações | 32.768 tokens nativos (até 131.072 com YaRN). Nos experimentos: `num_ctx` de 4.096 e 8.192 |
| Tamanho dos arquivos | Dimensão dos arquivos baixados | ~4,9 GB em disco |
| Requisitos de hardware | RAM, VRAM, CPU/GPU | Executado só em CPU, sem GPU, em máquinas com 11 e 13 GiB de RAM sob WSL2 |
| Compatibilidade | Disponibilidade para Ollama | Sim — tag oficial `qwen3:8b`, Ollama 0.34.0 |
| Documentação | Clareza do model card | Model card com arquitetura, janela de contexto, modos de operação e recomendações de uso |
| Riscos e limitações | Viés, confabulação, privacidade | Riscos usuais de LLM (confabulação e viés). Execução local elimina o envio de dados a terceiros, mas transfere à equipe a responsabilidade pela segurança do host e do contêiner |

## Justificativa da escolha

O Qwen3-8B foi selecionado por apresentar bom desempenho em tarefas de conversação
e raciocínio e por ser compatível com execução local via Ollama. A combinação
GGUF/Q4_K_M equilibra qualidade, consumo de memória e desempenho, adequando-se ao
hardware disponível. O modelo permanece dentro do limite de 10 bilhões de parâmetros
estabelecido pela atividade.

## Relevância para Sistemas Operacionais

A quantização Q4_K_M reduz os pesos de cerca de 16 GB (FP16) para ~4,9 GB em disco —
é essa redução que viabiliza um modelo de 8,19 B em máquinas com 11 a 13 GiB de RAM.
Já a janela de contexto não afeta o tempo de resposta, e sim a memória: dobrar
`num_ctx` de 4.096 para 8.192 acrescentou cerca de 2,3 GB ao pico de RSS, sem
qualquer alteração no prompt enviado — alocação antecipada do cache de atenção,
paga na carga do modelo e não sob demanda. Ver Seções 10.3 e 11 (questão 3) do
relatório.
