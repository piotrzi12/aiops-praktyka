# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Training repo for the Sages course "AIOps w praktyce" (not a product). Everything user-facing (README, labs, docs, runbooks) is in **Polish**; keep new text in Polish. Participants work in their own fork and their own namespace on a shared EKS cluster. The sample app is **Kantyna** (company canteen ordering) in `app/`. `app/.env` contains *fake* secrets for exercises.

- `app/` – Kantyna: services, Helm chart, runbooks, k6 scenarios
- `labs/labNN-*/README.md` – labs (goal, steps, SUCCESS condition)
- `docs/NN-topic/` – topic material (`.md` + `architektura.html`); `docs/prompts/` – prompt templates
- `setup/` – workstation setup and `check.sh`

## Commands

The Makefile is in `app/` (not the repo root); run these from there.

```bash
docker compose up -d --build          # UI :8088, API :8000 (/docs), payments :8080
make compose-down                     # docker compose down -v
make test                             # orders-api + payments
cd orders-api && uv run pytest -q tests/test_api.py::<test_name>   # single test
make test-payments                    # go test in a golang:1.23 container
make helm-lint && make helm-template
make build push VERSION=1.1.0 VARIANT=receipt-v2   # ECR; extra tag <ver>-<variant>
docker compose --profile loadgen up -d loadgen     # synthetic traffic (PEAK_RPS=…)
```

`setup/check.sh [namespace]` verifies a deployed Kantyna on the cluster (expects `SUKCES: 11/11`); `--all` is the trainer summary.

## Architecture

`web` (nginx, proxies `/api/`) → `orders-api` (FastAPI) → `payments` (Go, `POST /pay`), PostgreSQL, SQS → `worker` (writes receipts to S3, DLQ after 5 tries). `loadgen` produces traffic with a daily curve (Europe/Warsaw). In `POST /api/orders` payment happens *before* the DB write, and SQS publishing happens only if `QUEUE_URL` is set (so locally the worker just idles).

Observability: every service exposes `/metrics`; logs are JSON with `trace_id`; orders-api exports OTLP traces. `templates/prometheusrule.yaml` alerts map 1:1 to `app/runbooks/<AlertName>.md` – add/rename both together.

### Runtime flags (fault injection)

Each service has a `flags.py` that reads env vars plus an optional JSON file (`FLAGS_FILE`), re-read on an interval without restart; file values win over env. Sections `orders-api`, `payments`, `worker` (e.g. `error_rate`, `memory_leak_mb_per_min`, `db_pool_leak`, `slow_menu_query`, `latency_ms`, `fail_rate`). Locally the file is `app/deploy/local/flags.json`; in the cluster it is the ConfigMap `templates/configmap-flags.yaml`. Labs break/fix the app by changing these (see `labs/lab06-agent-runbook/zepsuj.sh`). `APP_VARIANT` (`stable`, `receipt-v2`, `menu-v2`) is a separate build-time variant.

`labs/lab06-agent-runbook/agent.py` is a standalone agent (read tools run freely, action tools sit behind an `input()` confirmation); it needs `OPENAI_API_KEY`/`OPENAI_ENDPOINT` pointing at the LiteLLM gateway.

## Safety conventions

`.claude/settings.json` allows read-only kubectl (`get`, `describe`, `logs`, `top`) and `k8sgpt analyze`, asks for `set/patch/edit/rollout/apply`, and denies `delete`, `exec` and anything touching secrets. Don't print or send credentials to a model, work only in your own namespace (the cluster is shared), and verify every hypothesis and command before applying it.

## Wersje narzędzi

- kubectl v1.37.1
- Helm v3.22.0

## Sprawdzanie zmian

Po zmianie chartu uruchom `helm lint app/deploy/helm/kantyna`.

## Zakaz

Nie uruchamiaj `kubectl delete`.
