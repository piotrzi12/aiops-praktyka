# Post-mortem: Kantyna `piotr-z`, 16.10.2026 – menu i zamówienia niedostępne

Szkic wg `docs/prompts/post-mortem.md` (blameless), oparty na `incydent.md`. Godziny w czasie polskim (CEST).

**Oznaczenia:** zdania bez znacznika mają dowód w dzienniku `incydent.md` (komenda lub zapytanie i wynik). **[AI, bez dowodu]** to wniosek lub propozycja dopisana przez AI, której dziennik nie potwierdza; człowiek musi ją potwierdzić, poprawić albo usunąć. **[do uzupełnienia]** to dane, których nie mamy.

## Podsumowanie

Menu i składanie zamówień przez web nie działały: oba pody `orders-api` były `Running`, ale niegotowe (0/2), bo readiness nie mógł pobrać połączenia z bazy. W ConfigMapie `kantyna-flags` była włączona flaga `db_pool_leak` (oraz `slow_menu_query`), ustawiona poza repozytorium. Samo wyłączenie flagi nie wystarczyło, usługę przywrócił dopiero restart `orders-api`. W trakcie wyszło też, że Prometheus nie zbierał metryk `orders-api` (NetworkPolicy nie dopuszczała monitoringu), co naprawiono commitem `8287aaf`.

## Wpływ

- Menu i zamówienia przez web nie działały. Loadgen (klient) widział w tym czasie p95 = 10 s i brak odpowiedzi 200 dla `menu` (0,60 req/s błędów, 0,06 req/s timeoutów).
- Okno wpływu: co najmniej od ok. 14:20 (pierwszy pomiar loadgena) do ok. 14:46 (`check.sh` 11/11). **[do uzupełnienia]** Rzeczywisty początek jest nieznany: pody były niegotowe, kiedy je sprawdziłem o 14:29, a wcześniejszych pomiarów po stronie serwera nie ma.
- Liczba dotkniętych użytkowników i zamówień: **[do uzupełnienia]**, nie mierzyłem.
- Płatności, worker i baza: `check.sh` pokazywał gotowe Deploymenty i Service. Jakości ich działania nie mierzyłem **[AI, bez dowodu]**.

## Oś czasu

| Godzina | Zdarzenie | Źródło w dzienniku |
|---|---|---|
| ok. 14:18–14:20 | W namespace działa `kantyna-loadgen` (pod ok. 11 min na 14:29); pierwsze pomiary klienta z p95 = 10 s | wiersz „objaw widziany z klienta” |
| 14:26 | Utworzona NetworkPolicy `kantyna-loadgen-to-orders-api` (etykieta lab07) | wiersz o NetworkPolicy |
| 14:29 | Wykrycie: `check.sh` 8/11, `orders-api` gotowe 0/2; event `Readiness probe failed` | wiersze 14:29 |
| 14:29 | Potwierdzona hipoteza: `db_pool_leak = true` i w logach `couldn't get a connection after 30.00 sec` | wiersz `db_pool_leak` |
| 14:4x | Szkic pierwszego komunikatu do zespołu (co wiemy, wpływ, następna aktualizacja 15:00) | sekcja „Pierwszy komunikat”; **[do uzupełnienia]** czy został wysłany |
| 14:37:55 | Mitygacja 1: `db_pool_leak: false` w ConfigMapie (`kubectl patch`) | wiersz „MITYGACJA” |
| 14:42 | Pody widzą `db_pool_leak: false`, ale readiness nadal pada; `check.sh` 8/11 | wiersz „Sama flaga nie wystarcza” |
| 14:44:30 | Mitygacja 2: `rollout restart` orders-api | wiersz „MITYGACJA 2” |
| ok. 14:46 | `check.sh` 11/11, w logach `Order created` i `POST …/pay 200 OK` | wiersz „Efekt mitygacji” |
| 14:57 | Pomiar po stronie klienta przy `slow_menu_query = true`: p95 `menu` ok. 10 ms, brak błędów. Metryk serwera brak, bo `up = 0` | wiersze 14:57 |
| 15:00:39 | Mitygacja 3: `slow_menu_query: false`, żeby klaster zgadzał się z repo | wiersz „MITYGACJA 3” |
| ok. 15:10 | Przyczyna braku metryk: Prometheus nie może scrapować orders-api, NetworkPolicy wpuszczają tylko `web` i `loadgen` | wiersz „Dlaczego up = 0” |
| 15:02 | Commit `8287aaf`: NetworkPolicy `kantyna-orders-api-metrics`; pipeline czerwony (`conflict with "kubectl-patch"` na `.data.flags.json`) | wiersz „Pipeline czerwony” |
| 15:05 | Tekst `flags.json` na klastrze ustawiony identycznie z chartem, ponowiony przebieg zielony, rewizja Helm 6 `deployed` | wiersz „Usunięcie konfliktu” |
| 15:06 | `up{app="orders-api"} = 1` | wiersz 15:06 |
| 15:12 | `check.sh` 11/11 | wiersz 15:12 |
| 15:18 | Metryki stabilne: p95 `/api/menu` ok. 4,8 ms, `/api/orders` ok. 24 ms, 5xx 0 %, pula DB 0 % | wiersz 15:18 |

## Przyczyna źródłowa

1. **Wyciek puli połączeń z bazą (`db_pool_leak = true`).** Potwierdzony flagą w ConfigMapie i logiem readiness. Flaga była ustawiona na klastrze, nie w repo (`values.yaml` ma `false`). Kto i kiedy ją ustawił: **[do uzupełnienia]**. Opis w kategoriach systemu: zmiany flag runtime można wprowadzić na klastrze bez śladu w repo i bez alertu.
2. **Wyciekłe połączenia zostają w puli procesu.** Wyłączenie flagi nie przywróciło usługi, dopiero restart podów. Dowód: stan po 14:37 i 14:42 oraz 11/11 po restarcie. Mechanizm w kodzie nie był czytany, więc to wniosek z obserwacji.
3. **Brak widoczności po stronie serwera.** NetworkPolicy `kantyna-orders-api-ingress` (lab02, `kubectl apply`, poza chartem) wpuszczała do orders-api tylko pody `web`, a polityka z lab07 tylko `loadgen`. Namespace `monitoring` nie był dopuszczony, więc target miał `up = 0` (`context deadline exceeded`). Od kiedy jest ślepy: **[AI, bez dowodu]** prawdopodobnie od utworzenia polityki lab02 (14.10), historii `up` nie sprawdzałem.
4. **Brak alertów w release.** `helm get values` pokazuje `prometheusRule.enabled: false`, więc alerty z chartu (np. `KantynaDBPoolExhausted`, `KantynaHighLatencyP95`) nie są wdrożone w `piotr-z`. Czy zadziałałyby, gdyby były, **[AI, bez dowodu]**.

**Nie jest przyczyną (odrzucone lub niepotwierdzone):** `slow_menu_query`. Przy fladze `true` p95 menu u klienta wynosiło ok. 10 ms. Test przy większym obciążeniu nie był robiony. Zasoby podów (CPU 16–18m, pamięć ok. 64 MiB) też nie były przyczyną.

## Co zadziałało

- `setup/check.sh` i eventy od razu wskazały `orders-api` i readiness.
- Najpierw mitygacja (przywrócenie usługi), potem naprawa przez repo, jak w README.
- Pomiar po stronie klienta (loadgen) dał dowód objawu mimo braku metryk serwera.
- Konflikt server-side apply zatrzymał nadpisanie pola ConfigMapy bez wiedzy człowieka; rozwiązany bez `--force-conflicts`.

## Co nie zadziałało

- Brak metryk `orders-api` i brak wdrożonych alertów: wykrycie przez ręczny `check.sh`, nie przez alert.
- Samo wyłączenie flagi nie naprawiło usługi; zajęło to kolejne ok. 8 minut (14:37 → 14:46), zanim wykonano restart.
- Mitygacja `kubectl patch` zostawiła tekst ConfigMapy różny od chartu (`0.0` zamiast `0`, brak końcowego `\n`), co zepsuło pierwsze wdrożenie (ok. 2 minuty).
- Pierwszy komunikat zawierał zdanie „płatności, kolejka i baza działają”, oparte tylko na `check.sh` i `up = 1`.

## Akcje (propozycje **[AI, bez dowodu]**; właściciel i termin do ustalenia przez człowieka)

| # | Akcja | Właściciel | Termin |
|---|---|---|---|
| 1 | Włączyć `prometheusRule.enabled` w release `piotr-z` i sprawdzić, czy `KantynaDBPoolExhausted` i `KantynaHighLatencyP95` wyzwalają się na tym środowisku | [do uzupełnienia] | [do uzupełnienia] |
| 2 | Dodać alert na target down (`up{job="kantyna-orders-api"} == 0`) z runbookiem `app/runbooks/<AlertName>.md` (reguły i runbooki idą parami) | [do uzupełnienia] | [do uzupełnienia] |
| 3 | Przenieść NetworkPolicy z lab02/lab04/lab07 do chartu, żeby żadna polityka nie istniała tylko po `kubectl apply` | [do uzupełnienia] | [do uzupełnienia] |
| 4 | Do runbooka `KantynaDBPoolExhausted` dopisać: po wyłączeniu przyczyny wycieku trzeba zrestartować pody (wniosek z tego incydentu; treść runbooka nie była czytana) | [do uzupełnienia] | [do uzupełnienia] |
| 5 | Zmieniać flagi przez repo/pipeline; do mitygacji ręcznej używać tekstu identycznego z chartem albo `helm upgrade --set`, żeby uniknąć `conflict with "kubectl-patch"` | [do uzupełnienia] | [do uzupełnienia] |
| 6 | Zmierzyć wpływ `slow_menu_query` przy większym ruchu (k6) i zdecydować, czy jest realnym ryzykiem | [do uzupełnienia] | [do uzupełnienia] |

## Pytania otwarte

- Kto i kiedy ustawił `db_pool_leak` i `slow_menu_query` na klastrze i po co?
- Od kiedy dokładnie `orders-api` był niedostępny? Dziennik zaczyna się od 14:29.
- Czy pierwszy komunikat został wysłany i czy kolejna aktualizacja o 15:00 się odbyła?
- Czy `up{app="orders-api"}` był 0 przed incydentem, i od kiedy?
- Skąd wzięła się polityka `kantyna-loadgen-to-orders-api` (14:26) i czy loadgen jest częścią tego scenariusza?
- Co dokładnie utrzymuje wyciekłe połączenia w puli po wyłączeniu flagi (kod `db.py` nie był analizowany)?
