# Dziennik incydentu – Kantyna, namespace piotr-z

Zgłoszenie: „Użytkownicy piszą, że menu ładuje się bardzo wolno, a czasem dostają błąd.”
Godziny w czasie polskim (CEST), 16.10.2026. Status: `potwierdzona` (jest dowód), `niepotwierdzona` (tylko hipoteza), `odrzucona`.

## Dziennik

| Godzina | Hipoteza (AI / ja) | Komenda / zapytanie | Wynik | Status |
|---|---|---|---|---|
| 14:29 | Wykrycie: Kantyna niezdrowa | `setup/check.sh` | 8/11: `kantyna-orders-api` gotowe 0/2, nie działają menu i zamówienie przez web | objaw |
| 14:29 | Pody orders-api nie przechodzą readiness (AI) | `kubectl -n piotr-z get pods`, `get events` | oba pody `Running 0/1`, 0 restartów, 25 h; event `Readiness probe failed: … context deadline exceeded` | objaw |
| 14:29 | To nie brak zasobów (AI) | `kubectl -n piotr-z top pods` | orders-api CPU 16–18m, pamięć ok. 64 MiB; nic nie przy limicie | odrzucona (jako przyczyna) |
| 14:29 | Wyciek puli połączeń z bazą: `db_pool_leak` (AI) | `kubectl -n piotr-z get cm kantyna-flags -o jsonpath='{.data.flags\.json}'`; `kubectl -n piotr-z logs deploy/kantyna-orders-api --tail=15` | flaga `orders-api.db_pool_leak = true`; w logach powtarzane `Readiness check failed … couldn't get a connection after 30.00 sec` | potwierdzona |
| 14:29 | Wolne zapytanie o menu: `slow_menu_query` (AI) | `kubectl -n piotr-z get cm kantyna-flags -o jsonpath='{.data.flags\.json}'` | flaga `orders-api.slow_menu_query = true`; brak jeszcze pomiaru czasu odpowiedzi `/api/menu` | niepotwierdzona (tylko flaga) |
| 14:35 | p95 `/api/menu` z metryk orders-api (AI) | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="piotr-z", app="orders-api", route="/api/menu"}[5m])))` | brak danych: `up{job="kantyna-orders-api"} = 0` dla obu podów, Prometheus nie zbiera metryk niegotowych podów | brak pomiaru |
| 14:35 | Objaw widziany z klienta (loadgen) (AI) | `sum by (exported_endpoint, status) (rate(loadgen_requests_total{namespace="piotr-z"}[5m]))` | `menu`: ok. 0,60 req/s `error` + 0,06 `timeout`, 0 odpowiedzi 200; to samo dla `orders_create`, `menu_search`, `orders_get` | potwierdzony objaw |
| 14:35 | Czas odpowiedzi menu z klienta (AI) | `histogram_quantile(0.95/0.5, sum by (le) (rate(loadgen_request_duration_seconds_bucket{namespace="piotr-z", exported_endpoint="menu"}[5m])))` | p50 ok. 8 ms (szybkie błędy), p95 = 10 s (prawdopodobnie górny kubełek = timeouty) | nie dowodzi `slow_menu_query` |
| 14:37 | MITYGACJA: wyłączenie `db_pool_leak` (ja, z rekomendacji AI) | patch ConfigMapy: `kubectl -n piotr-z patch configmap kantyna-flags --type merge --patch-file …` (`orders-api.db_pool_leak: true → false`; `slow_menu_query` celowo zostawione `true`, żeby zmierzyć jego wpływ) | `configmap/kantyna-flags patched`; flagi na klastrze: tylko `slow_menu_query = true`. Efekt na podach do sprawdzenia po ok. 1 min | wykonana, efekt niepotwierdzony |
| 14:42 | Sama flaga nie wystarcza: już wyciekłe połączenia zostają w puli procesu (AI, hipoteza) | `kubectl -n piotr-z exec deploy/kantyna-orders-api -- cat /etc/kantyna/flags/flags.json`; `kubectl -n piotr-z logs deploy/kantyna-orders-api --tail=4`; `setup/check.sh` | pod widzi już `db_pool_leak: false`, ale readiness nadal pada (`couldn't get a connection after 30.00 sec`), `check.sh` → 8/11, pody `0/1` | flaga zastosowana, usługa niewyleczona; hipoteza o puli do potwierdzenia restartem |
| 14:44 | MITYGACJA 2: restart orders-api, żeby wyczyścić pulę (ja, z rekomendacji AI) | `kubectl -n piotr-z rollout restart deploy/kantyna-orders-api` | `deployment.apps/kantyna-orders-api restarted` (14:44:30); efekt do sprawdzenia | wykonana, efekt niepotwierdzony |
| 14:46 | Efekt mitygacji: restart wyczyścił pulę (AI, hipoteza z 14:42) | `setup/check.sh`; `kubectl -n piotr-z get pods \| grep orders`; `kubectl -n piotr-z logs deploy/kantyna-orders-api --tail=3` | `check.sh` → **11/11**; nowe pody `6dddbc76f6-4sl7k` i `-wf2sj` `1/1 Running`; w logach `Order created`, `POST http://kantyna-payments:8080/pay 200 OK` | potwierdzona: sama flaga nie wystarczała, trzeba było zrestartować procesy. Usługa przywrócona ok. 14:46 |
| 14:46 | Pomiar po mitygacji (AI) | `histogram_quantile(0.95, …http_request_duration_seconds_bucket{route="/api/menu"}[2m])`; `up{app="orders-api"}` | brak danych: Prometheus jeszcze nie zebrał metryk nowych podów (`up` = 0 dla serii z `6dddbc76f6`); okno 2 min z loadgena nadal zawiera błędy sprzed restartu (`menu`: 0,34 req/s 200, 0,32 error) | za wcześnie, powtórzyć po ok. 5 min |
| 14:57 | Czy `slow_menu_query = true` spowalnia menu? (AI) | `histogram_quantile(0.95, sum by (le, exported_endpoint) (rate(loadgen_request_duration_seconds_bucket{namespace="piotr-z"}[3m])))` oraz `sum by (exported_endpoint, status) (rate(loadgen_requests_total{namespace="piotr-z"}[3m]))`; kod: `app/orders-api/app/runtime.py:52` (`menu_uses_n_plus_one`) | przy włączonej fladze p95 po stronie klienta: `menu` ok. 10 ms, `menu_search` ok. 9,5 ms, `orders_create` ok. 25 ms; 0 błędów i 0 timeoutów (menu 0,63 req/s). Flaga włącza wzorzec N+1 w zapytaniu o menu | **nie potwierdzona jako przyczyna zgłoszonej wolnej odpowiedzi**: przy obecnym ruchu i rozmiarze danych nie daje mierzalnego opóźnienia. Wolne menu z początku incydentu tłumaczy oczekiwanie na połączenie z puli (30 s) |
| 14:57 | Metryki orders-api (AI) | `up{namespace="piotr-z", app="orders-api"}` | `up = 0` także dla zdrowych, nowych podów; histogramy `http_request_duration_seconds` dla `route="/api/menu"` nadal puste, więc p95 po stronie serwera nie da się zmierzyć | nierozwiązane: przyczyna braku scrapowania nieznana (nie sprawdzona) |
| 15:10 | Dlaczego `up{app="orders-api"} = 0`? Scrape Prometheusa do orders-api jest blokowany (AI) | `GET /api/datasources/proxy/uid/prometheus/api/v1/targets` (jq po `app=="orders-api"`); `kubectl -n piotr-z get networkpolicy -o yaml`; kod `app/orders-api/app/main.py:129` (`/metrics` bez zapytań do bazy); `lab02/dziennik.md` wiersz 7 | target `health: down`, `lastError: Get "http://10.40.43.185:8000/metrics": context deadline exceeded` (10 s); `/metrics` w kodzie jest prosty, więc to nie aplikacja. NetworkPolicy `kantyna-orders-api-ingress` (lab02, `kubectl apply`, poza chartem) wpuszcza do orders-api tylko pody `name=web`, a `kantyna-loadgen-to-orders-api` (lab07) tylko `loadgen` na porcie 8000. Namespace `monitoring` (Prometheus) nie jest dopuszczony | potwierdzona (przyczyna braku metryk orders-api; nie powoduje wolnego menu) |
| 15:00 | MITYGACJA 3: wyrównanie flag klastra z repo, żeby `helm upgrade` nie zgłosił `conflict with "kubectl-patch"` (ja, z rekomendacji AI) | patch ConfigMapy `kantyna-flags`: `orders-api.slow_menu_query: true → false` (`kubectl … patch configmap … --patch-file`) | `configmap/kantyna-flags patched` (15:00:39); wszystkie flagi `false`/`0`, zgodnie z `values.yaml` | wykonana; flagi na klastrze = repo |
| 15:02 | NAPRAWA (przez repo): NetworkPolicy dla scrape metryk orders-api (ja, z rekomendacji AI) | nowy plik `app/deploy/helm/kantyna/templates/networkpolicy-metrics.yaml`; `helm lint app/deploy/helm/kantyna`; `helm template … -s templates/networkpolicy-metrics.yaml` | lint bez błędów; render poprawny; SHA commita i link do przebiegu: do uzupełnienia po wdrożeniu | commit/push w toku |
| 14:29 | Pozostałe flagi bez wpływu (AI) | j.w. | `error_rate: 0`, `memory_leak_mb_per_min: 0`, `cpu_burn: false`, `log_noise: false`; `payments` i `worker` bez zakłóceń | odrzucona |

## Obserwacje (nie hipotezy)

- Na klastrze `db_pool_leak` i `slow_menu_query` są `true`, a w repo (`app/deploy/helm/kantyna/values.yaml`) oba mają `false`. Ktoś ustawił je poza chartem.
- W namespace działa `kantyna-loadgen` (uruchomiony ok. 14:18, czyli ok. 11 minut przed wykryciem).
- Pipeline (`.github/workflows/ci.yml`) wdraża przez `helm upgrade`. Zwykły commit z `false` w `values.yaml` może nie zmienić flag na klastrze, jeśli stara i nowa wartość z chartu są takie same. Po wdrożeniu trzeba sprawdzić stan ConfigMapy.

## Pierwszy komunikat (do zespołu, 14:4x)

Szkic wg `docs/prompts/komunikat-incydentu.md`; godzinę następnej aktualizacji (15:00) wybrałem jako kontrolną, nie jako obietnicę naprawy.

> **Incydent: Kantyna (środowisko `piotr-z`) – menu i zamówienia nie działają**
>
> 1. Menu i składanie zamówień w Kantynie nie działają: użytkownicy dostają błąd lub strona nie odpowiada.
> 2. Problem wykryliśmy o 14:29; dokładny początek ustalamy.
> 3. Wpływ: usługa przyjmująca zamówienia nie jest gotowa (0 z 2 instancji), więc w tej chwili żadne zamówienie ani zapytanie o menu nie kończy się sukcesem; płatności, kolejka i baza działają.
> 4. Sprawdzamy dwa podejrzane ustawienia: jedno z nich, związane z połączeniami z bazą, jest potwierdzone jako powiązane z błędami, drugie (wolne wczytywanie menu) jest jeszcze niepotwierdzone; w pierwszej kolejności przywracamy działanie usługi, a trwałą poprawkę wdrożymy przez repozytorium.
> 5. Następna aktualizacja o 15:00 albo wcześniej, jeśli usługa wróci do działania.

Uwagi do treści (do poprawy przez człowieka):
- „płatności, kolejka i baza działają” opiera się na `check.sh` (Deploymenty i Service gotowe) i `up=1` dla payments i worker; jakości nie mierzyłem.
- Nie podaję godziny startu, bo jej nie znamy; `kantyna-loadgen` ruszył ok. 14:18, ale nie wiadomo, czy to on wywołał awarię.

## Do zrobienia

- [ ] Pomiar p95 `/api/menu` (dowód dla `slow_menu_query`): teraz niemożliwy, bo pody orders-api są niegotowe i nie ma ich metryk. Powtórzyć po mitygacji `db_pool_leak`.
- [x] Pierwszy komunikat (`docs/prompts/komunikat-incydentu.md`): szkic wklejony powyżej, do poprawy
- [ ] Mitygacja
- [ ] Naprawa commitem + SHA i link do przebiegu pipeline'u
- [ ] Weryfikacja (`setup/check.sh` → 11/11, metryki stabilne 5 minut)
- [ ] Post-mortem (`docs/prompts/post-mortem.md`)
