# Tabela incydentów – namespace demo

Źródła: Prometheus, Loki (`{app="alert-log"}` i logi `orders-api`), `app/deploy/helm/kantyna/templates/prometheusrule.yaml`.
Godziny w czasie polskim (CEST, UTC+2); w logu `alert-log` `starts_at` / `ends_at` są w UTC.

## 1. Dzień przed szkoleniem (wtorek 13.10)

Założenie: wiersze w tabeli ze slajdu odpowiadają wtorkowi 13.10 (kolejność i progi się zgadzają).
Kolumny Grafana, CloudWatch i Wy / AI wypełniamy na żywo.

| Kiedy | Co zepsuliśmy | Alert (próg) | Grafana | CloudWatch | Wy / AI |
|---|---|---|---|---|---|
| rano (10:35–11:05) | ok. 7 % błędów 5xx w API, tylko na `route="unmatched"` (165 błędów ERROR w orders-api) | tak: ponad 5 % błędów przez 5 min. Wg wyrażenia reguły powinien zadziałać, ale w alert-log z 13.10 go nie ma | | | |
| przedpołudnie (11:35–12:15) | p95 POST /api/orders ponad 2 s (norma 0,04 s) | tak: p95 > 1 s przez 10 min (zadziałał 11:42–12:14) | | | |
| obiad (13:05–14:40) | kolejka zamówień rośnie do 10 783; przepustowość workera spadła 10× (4,5 → 0,46 wiad./s) | tak: ponad 50 wiadomości przez 10 min (13:12–14:40) | | | |
| po obiedzie (14:35–15:05) | 24–36 % płatności nieudanych (223 błędy ERROR w `payments`) | tak: ponad 10 % porażek (14:37–15:04) | | | |
| popołudnie (ok. 16:00–18:00) | nowy błąd w logach orders-api: `ReceiptTemplateError: missing field 'nip'` ("Failed to render receipt template"), ok. 350 razy, ok. 2/min, wersja 1.1.0; 5xx bez zmian | **nie: żaden alert** | | | |
| wieczór (19:09–19:54) | pamięć do limitu, OOMKilled w orders-api (pody `7c96b54996-fb96d` i `-vxtcm`, ok. 134 MiB wobec ok. 78 MiB wcześniej) | tak: pod zabity (OOMKilled), `for: 0m` (19:09–19:54) | | | |
| dzień 1, rano | nie znaleziono skoku CPU odbiegającego od normy (patrz niżej) | **nie: brak reguły CPU** | | | |

### Dowody i zapytania

- **Rano:** `sum by (route) (rate(http_requests_total{namespace="demo", app="orders-api", status=~"5.."}[5m]))`. Jedyna seria to `unmatched`.
- **Przedpołudnie:** `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="demo", app="orders-api", route="/api/orders", method="POST"}[5m])))`. Płaskie 2,425 s to prawdopodobnie granica kubełka histogramu, czytaj jako „ponad 2 s".
- **Obiad:** `worker_queue_visible_messages{namespace="demo"}` oraz `sum(rate(worker_messages_processed_total{namespace="demo"}[5m]))`. W logach workera i orders-api nie ma w tym oknie żadnych ERROR ani WARNING. To ciche pogorszenie.
- **Po obiedzie:** `100 * sum(rate(payments_failed_total{namespace="demo"}[5m])) / sum(rate(payments_requests_total{namespace="demo"}[5m]))`.
- **Popołudnie:** `{namespace="demo", app="orders-api"} | json | msg="Failed to render receipt template"`. Błąd pochodzi z `runtime.py` (`maybe_receipt_variant_error`) i dotyczy zamówień obsługiwanych przez pody `86db7f5b77` (wersja 1.1.0). Seria 5xx z 4 dni nie ma w tym oknie żadnego skoku, więc `KantynaHighErrorRate` nie miał szans zadziałać. Błąd nie psuje odpowiedzi API, więc wzrost błędów w logach jest niewidoczny dla alertów.
- **Wieczór:** pody `86db7f5b77` zniknęły ok. 18:00–18:30, a nowe `7c96b54996` ruszyły o 18:30 i po godzinie zostały zabite przez OOM. Powtórka w środę 14.10 14:01–14:37.
- **CPU:** `sum(rate(container_cpu_usage_seconds_total{namespace="demo", container="orders-api"}[10m]))`. Suma CPU orders-api ma ten sam wzór każdego dnia: ok. 0,006 rdzenia w nocy, ok. 0,03 rano (ok. 08:30), ok. 0,10 w lunch (11:30–14:30). Nie widać dnia, który by się wyróżniał. Brak reguły CPU potwierdzony w `prometheusrule.yaml` (są tylko: HighErrorRate, HighLatencyP95, PaymentsFailing, PodCrashLooping, PodOOMKilled, QueueBacklog, DBPoolExhausted).
- **Do sprawdzenia:** w porze lunchu CPU jest skupione na jednym podzie (np. czw 15.10: `zw7fx` ok. 0,083 rdzenia, `85r5n` ok. 0,013). To może być właściwy „skok CPU", ale nie potwierdzam tego.

### Hipotezy (niesprawdzone)

- Błąd z paragonem (popołudnie), wycofanie wersji o 18:30 i OOM wieczorem mogą być ciągiem wydań: zła wersja 1.1.0, potem wersja z większym zużyciem pamięci.
- Wolne zamówienia o 11:35 mogą wynikać z wolnych płatności (POST /api/orders czeka na `payments` przed zapisem do bazy). Nie sprawdzałem `payments_duration_seconds`.

## 2. Wszystkie incydenty z alert-log (demo, 13–16.10)

Incydent = para powiadomień `firing` → `resolved` o tym samym `fingerprint`.

| # | Początek (PL) | Koniec (PL) | Czas | Alert | Waga | Szczegóły z logu |
|---|---|---|---|---|---|---|
| 1 | wt 13.10 11:42 | wt 13.10 12:14 | 32 min | KantynaHighLatencyP95 | warning | p95 orders-api 2,187 s (próg 1 s) |
| 2 | wt 13.10 13:12 | wt 13.10 14:40 | 88 min | KantynaQueueBacklog | warning | 2,5 tys. wiadomości w kolejce (próg 50) |
| 3 | wt 13.10 14:37 | wt 13.10 15:04 | 27 min | KantynaPaymentsFailing | warning | 26,49 % nieudanych płatności (próg 10 %) |
| 4 | wt 13.10 19:09 | wt 13.10 19:54 | 45 min | KantynaPodOOMKilled | critical | OOMKilled: orders-api-7c96b54996-fb96d i -vxtcm |
| 5 | śr 14.10 14:01 | śr 14.10 14:37 | 36 min | KantynaPodOOMKilled | critical | OOMKilled: te same dwa pody (ponownie) |
| 6 | czw 15.10 08:32 | czw 15.10 08:48 | 16 min | KantynaHighErrorRate | warning | 14,81 % odpowiedzi 5xx (próg 5 %) |
| 7a | czw 15.10 16:23 | czw 15.10 16:26 | 2,5 min | KantynaDBPoolExhausted | critical | pula DB 100 % (próg 90 %), pod orders-api-5d87d9d47d-85r5n |
| 7b | czw 15.10 16:41 | czw 15.10 16:48 | 6,5 min | KantynaDBPoolExhausted | critical | j.w. |
| 7c | czw 15.10 16:54 | czw 15.10 16:55 | 0,5 min | KantynaDBPoolExhausted | critical | j.w. |

Razem: 9 incydentów z 6 różnych alertów: 5 critical (OOMKilled ×2, DBPoolExhausted ×3) i 4 warning.

## 3. Inne alerty w alert-log (poza demo)

W namespace `piotr-z` (liczba powiadomień, nie incydentów; powtórzenia tego samego alertu):
KubePodNotReady 22 firing / 6 resolved, KubeDeploymentReplicasMismatch 19 / 4,
TargetDown 12 / 0, KubePodCrashLooping 11 / 2.
Ogólnoklastrowe: KubeControllerManagerDown i KubeSchedulerDown (critical, po 18 powiadomień, bez resolved).
