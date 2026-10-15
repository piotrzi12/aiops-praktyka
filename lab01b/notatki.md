# lab01b — notatki

## Trzy różnice między `zly.yaml` a `dobry.yaml`

1. **Obraz:** `orders-api:latest` kontra `123456789012.dkr.ecr.eu-central-1.amazonaws.com/kantyna/orders-api:0.0.0-dev`. Model zgadł nazwę z samej nazwy usługi i użył `latest`, który nie jest przypięty do wersji i nie wskazuje na rejestr z Kantyną.
2. **Port i health checki:** `8080` i `/health` kontra `8000`, `/healthz` i `/readyz`. Model wziął typowe wartości z konwencji. W Kantynie `8080` to port payments, a `orders-api` ma inne ścieżki, więc zły plik nie przeszedłby readiness.
3. **Hasło do bazy:** jawne `postgres:password@postgres:5432/orders` kontra `secretKeyRef` do `kantyna-db`. W dobrym pliku host, baza i użytkownik też pochodzą z charta (`kantyna-postgres`, `kantyna`).

Do tego `zly.yaml` ma zgadnięty `namespace: production` (dry-run odrzucił go przy `-n piotr-z`), nie ma `securityContext` ani wolumenu z flagami i ma 3 repliki zamiast 2.

## Czego walidator nie sprawdził

`--dry-run=server` potwierdził tylko schemat i uprawnienia. Nie sprawdził, czy Secret `kantyna-db` i ConfigMap `kantyna-flags` istnieją w namespace `piotr-z`, ani czy obraz z ECR da się pobrać. Bez nich `dobry.yaml` przechodzi walidację, a pod i tak nie wystartuje (`CreateContainerConfigError` lub `ImagePullBackOff`). Nie sprawdził też, czy limity zasobów (384Mi pamięci) mają sens dla realnego ruchu.

## Część B: diagnoza

- **Maskowanie sekretów (B1):** regex z README (`(password|token|secret)=\S+`) nie złapał hasła zapisanego w innym formacie (linia 20). Poprawiłem go tak, żeby obejmował też `:` i spacje, cudzysłowy, hasło w URL-u (`://user:haslo@`) i `Bearer`. Po poprawce sprawdziłem plik i oczami linię 20. Wniosek: maskowanie trzeba zawsze zweryfikować, bo regex znał tylko jeden format.
- **Halucynacja (drobna):** w tabeli podałem w cudzysłowie „wymieniono node group”, a w danych jest „zespół platformy wymienił node group”. Sens ten sam, ale cytat nie był dosłowny.
- **Wniosek bez dowodu w danych:** hipotezy o strefie wolumenu i o subnetach node group nie mają bezpośredniego dowodu w pliku (nie ma strefy PV, subnetów ani stref starych węzłów). Wynikają z tego, że 3 węzły są w `eu-central-1a`, a zdarzenie mówi o `volume node affinity conflict`. Agent zasygnalizował braki: `kubectl get pv ... -o jsonpath='{.spec.nodeAffinity}'` i `aws eks describe-nodegroup`.
- **Pozostałe dowody:** pozostałe fragmenty z tabeli znalazłem w `awaria-zred.txt` przez `grep`.
