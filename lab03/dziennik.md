# Dziennik – lab03

| # | Objaw (krok, komunikat) | Hipoteza (AI / ja) | Jak sprawdziłem | Poprawka | Status |
|---|---|---|---|---|---|
| 1 | Szkic workflow: SHA `amazon-ecr-login@v2.1.7` | ja: tag jest annotated, SHA z `refs/tags/v2.1.7` to obiekt tagu, nie commit | `git ls-remote ... 'refs/tags/v2.1.7*'`: wpis `^{}` ma inny SHA (`03f1aad…`) | użyty SHA z `^{}` | ✅ |
| 2 | Sugestia AI do uzupełnienia po przebiegu: | | | | |
