#!/usr/bin/env python3
"""05-grafico.py — gera os graficos e as tabelas do relatorio.

Le results/runs.csv e results/recursos.csv e produz:
  results/g1_latencia.png     latencia media por configuracao e tamanho
  results/g2_tokens.png       tokens/s medio por configuracao e tamanho
  results/g3_recursos.png     pico de RSS e nucleos medios por configuracao
  results/tabelas.md          as mesmas medias em tabela markdown

Uso: python3 scripts/05-grafico.py
"""
import csv
import os
import statistics as st
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(BASE, "results")
CONFIGS = ["padrao", "concorrencia", "contexto_longo"]
SIZES = ["short", "long"]


def load(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def num(row, key):
    v = (row.get(key) or "").strip()
    try:
        return float(v)
    except ValueError:
        return None


def media(rows, key, cfg, size=None):
    vals = [
        num(r, key)
        for r in rows
        if r["config"] == cfg
        and (size is None or r["prompt_size"] == size)
        and num(r, key) is not None
    ]
    return st.mean(vals) if vals else 0.0


def barras(titulo, ylabel, series, arquivo):
    """series: dict rotulo -> lista de valores (um por configuracao)."""
    x = range(len(CONFIGS))
    largura = 0.8 / len(series)
    fig, ax = plt.subplots(figsize=(8, 4.5))
    for i, (rotulo, valores) in enumerate(series.items()):
        pos = [k + i * largura for k in x]
        barras = ax.bar(pos, valores, largura, label=rotulo)
        ax.bar_label(barras, fmt="%.1f", fontsize=8)
    ax.set_xticks([k + largura * (len(series) - 1) / 2 for k in x])
    ax.set_xticklabels(CONFIGS)
    ax.set_ylabel(ylabel)
    ax.set_title(titulo)
    ax.legend()
    ax.grid(axis="y", alpha=0.3)
    fig.tight_layout()
    saida = os.path.join(RES, arquivo)
    fig.savefig(saida, dpi=150)
    plt.close(fig)
    print("gerado:", saida)


def main():
    runs_path = os.path.join(RES, "runs.csv")
    rec_path = os.path.join(RES, "recursos.csv")
    for p in (runs_path, rec_path):
        if not os.path.exists(p):
            sys.exit("ERRO: %s nao existe. Rode scripts/04-bench.sh antes." % p)

    runs = [r for r in load(runs_path) if r["http_status"] == "200"]
    rec = load(rec_path)
    if not runs:
        sys.exit("ERRO: runs.csv nao tem nenhuma chamada com status 200.")

    barras(
        "Latencia media por requisicao (qwen3:8b)",
        "segundos",
        {s: [media(runs, "client_elapsed_s", c, s) for c in CONFIGS] for s in SIZES},
        "g1_latencia.png",
    )
    barras(
        "Vazao de geracao (tokens por segundo)",
        "tokens/s",
        {s: [media(runs, "tokens_per_second", c, s) for c in CONFIGS] for s in SIZES},
        "g2_tokens.png",
    )
    barras(
        "Pico de memoria residente do Ollama",
        "RSS (MB)",
        {s: [media(rec, "rss_pico_mb", c, s) for c in CONFIGS] for s in SIZES},
        "g3_memoria.png",
    )
    barras(
        "CPU e threads por configuracao",
        "valor",
        {
            "nucleos medios ocupados": [media(rec, "cores_medio", c) for c in CONFIGS],
            "pico de threads": [media(rec, "threads_pico", c) for c in CONFIGS],
        },
        "g4_cpu_threads.png",
    )

    linhas = ["# Tabelas de resultados", "",
              "## Latencia, tokens/s e tokens gerados (media por chamada)", "",
              "| Config | Prompt | n | Latencia (s) | tokens/s | eval_count | prompt_eval_count |",
              "|---|---|---|---|---|---|---|"]
    for c in CONFIGS:
        for s in SIZES:
            n = len([r for r in runs if r["config"] == c and r["prompt_size"] == s])
            linhas.append("| %s | %s | %d | %.2f | %.2f | %.0f | %.0f |" % (
                c, s, n,
                media(runs, "client_elapsed_s", c, s),
                media(runs, "tokens_per_second", c, s),
                media(runs, "eval_count", c, s),
                media(runs, "prompt_eval_count", c, s),
            ))

    linhas += ["", "## Recursos por execucao (media)", "",
               "| Config | Prompt | wall (s) | CPU (s) | nucleos medios | RSS pico (MB) | threads pico | procs pico | vazao (req/s) |",
               "|---|---|---|---|---|---|---|---|---|"]
    for c in CONFIGS:
        for s in SIZES:
            linhas.append("| %s | %s | %.2f | %.2f | %.2f | %.0f | %.0f | %.0f | %.3f |" % (
                c, s,
                media(rec, "wall_s", c, s), media(rec, "cpu_s", c, s),
                media(rec, "cores_medio", c, s), media(rec, "rss_pico_mb", c, s),
                media(rec, "threads_pico", c, s), media(rec, "procs_pico", c, s),
                media(rec, "vazao_req_s", c, s),
            ))

    falhas = len([r for r in load(runs_path) if r["http_status"] != "200"])
    linhas += ["", "Chamadas com status 200: %d | falhas: %d | execucoes: %d"
               % (len(runs), falhas, len(rec)), ""]

    saida = os.path.join(RES, "tabelas.md")
    with open(saida, "w") as f:
        f.write("\n".join(linhas))
    print("gerado:", saida)
    print()
    print("\n".join(linhas))


if __name__ == "__main__":
    main()
