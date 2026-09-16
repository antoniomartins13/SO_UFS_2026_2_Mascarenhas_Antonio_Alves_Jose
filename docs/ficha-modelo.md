# Ficha técnica do modelo — Qwen3-8B

Critérios obrigatórios da Seção 5.3 do enunciado. Campos marcados como
*(preencher)* dependem de medição ou de leitura direta do model card e **não
devem ser estimados**.

| Critério | Verificação | Valor |
| --- | --- | --- |
| Identificação | Organização, nome completo e URL do model card | Qwen (Alibaba Cloud) — Qwen3-8B — <https://huggingface.co/Qwen/Qwen3-8B> |
| Parâmetros | Total do modelo-base | 8,19 B (dentro do limite de 10 B) |
| Finalidade | Base, instruct, chat, código, multilíngue | Chat/instruído, com modos *thinking* e *non-thinking* |
| Idioma | Suporte ao português | *(preencher conforme o model card)* |
| Licença | Permissões e obrigações | Apache-2.0 |
| Formato | GGUF, Safetensors, GGML | GGUF (via tag `qwen3:8b` do Ollama) |
| Quantização | Q4, Q5, Q8, FP16 | Q4_K_M |
| Contexto | Janela máxima e limitações | *(preencher)* |
| Tamanho dos arquivos | Dimensão dos arquivos baixados | *(preencher: `du -sh ~/.ollama/models`)* |
| Requisitos de hardware | RAM, VRAM, CPU/GPU | *(preencher — confrontar com o ambiente da Seção 5 do README)* |
| Compatibilidade | Disponibilidade para Ollama | Sim — tag oficial `qwen3:8b` |
| Documentação | Clareza do model card, exemplos, limitações | *(preencher)* |
| Riscos e limitações | Viés, confabulação, privacidade | *(preencher)* |

## Justificativa da escolha

*(preencher — até 100 palavras, conforme registrado no Google Classroom em
04/09/2026 20:58; deve coincidir com `docs/registro-classroom.pdf`)*

## Relevância para Sistemas Operacionais

A quantização Q4_K_M determina o volume de páginas mapeadas por `mmap` no
carregamento dos pesos e, portanto, o pico de RSS do processo `ollama runner` —
é o elo direto entre a escolha do modelo e as métricas de memória da Parte C.
