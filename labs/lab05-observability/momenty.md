# Momenty odbiegające od normy – namespace demo

Godziny w czasie polskim (CEST, UTC+2). Okno analizy: 12–16 października 2026. Każdy moment potwierdzony w Explore (Prometheus) i w Loki.

```text
<dzień gg:mm–gg:mm> | <co widać, z liczbą> | <zapytanie PromQL albo LogQL>
```

wt 13.10 ok. 11:00 | odsetek 5xx w orders-api ok. 6,5 % (poza tym 0 %) | `100 * (sum(rate(http_requests_total{namespace="demo", app="orders-api", status=~"5.."}[10m])) or vector(0)) / sum(rate(http_requests_total{namespace="demo", app="orders-api"}[10m]))`

wt 13.10 ok. 12:00 | p95 POST /api/orders ok. 2,4 s (norma ok. 0,04 s) | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="demo", app="orders-api", route="/api/orders", method="POST"}[10m])))`

wt 13.10 13:30–15:30 | kolejka workera do ok. 11 020 wiadomości (norma 0–30, lunchowe piki do ok. 30) | `max_over_time(worker_queue_visible_messages{namespace="demo"}[30m])`

czw 15.10 ok. 08:30 | odsetek 5xx w orders-api ok. 7,5 % | `100 * (sum(rate(http_requests_total{namespace="demo", app="orders-api", status=~"5.."}[10m])) or vector(0)) / sum(rate(http_requests_total{namespace="demo", app="orders-api"}[10m]))`

## Logi potwierdzające (Loki)

Okna: wt 13.10 10:00–16:00 oraz czw 15.10 07:30–09:30.

```logql
{namespace="demo", app="orders-api"} | json | level="ERROR"
```
