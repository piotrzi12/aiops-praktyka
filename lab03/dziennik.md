# Dziennik – lab03

| # | Objaw (krok, komunikat) | Hipoteza (AI / ja) | Jak sprawdziłem | Poprawka | Status |
|---|---|---|---|---|---|
| 1 | Szkic workflow: SHA `amazon-ecr-login@v2.1.7` | ja: tag jest annotated, SHA z `refs/tags/v2.1.7` to obiekt tagu, nie commit | `git ls-remote ... 'refs/tags/v2.1.7*'`: wpis `^{}` ma inny SHA (`03f1aad…`) | użyty SHA z `^{}` | ✅ |
| 2 | `helm upgrade` w CI: `conflict with "kubectl" … containers[web].image` i `conflict with "kubectl-annotate" … inbound-cidrs` | ja: Helm 4 używa server-side apply, a pola zmienione ręcznie w lab02 mają innego właściciela | `kubectl get … --show-managed-fields`: `image` ← `kubectl` (Update), `inbound-cidrs` ← `kubectl-annotate` (10 CIDR w klastrze, 2 w values Helma) | `image`: usunięty wpis `kubectl` z `managedFields` Deploymentu (patch z `test`); `inbound-cidrs`: workflow odczytuje bieżącą wartość z klastra i przekazuje ją do Helma. Bez `--force-conflicts` | ✅ |
| 3 | Smoke test `/healthz`: `wget: can't connect to remote host: Connection refused` (helm i rollout przeszły) | ja: `localhost` w busybox `wget` idzie na `::1`, a nginx słucha tylko na IPv4 (`listen 8080;`) | log `gh run view --log-failed`, `web/nginx/default.conf.template:7` | adres `127.0.0.1` zamiast `localhost` | ⏳ |
| 4 | Sugestia AI do uzupełnienia po przebiegu: | | | | |
