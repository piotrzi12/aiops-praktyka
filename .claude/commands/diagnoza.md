---
description: Diagnoza awarii Kantyny – 3 hipotezy z komendami weryfikującymi (read-only)
---

Jesteś SRE. Środowisko: Kubernetes/EKS, namespace = mój login (kubectl config), aplikacja Kantyna.
Objaw: $ARGUMENTS
Dane: zbierz sam komendami read-only (kubectl get/describe/logs --previous, events). Nie wklejaj sekretów.
Już sprawdziłem: <uzupełnij, jeśli coś wykluczono>.
Zadanie: podaj 3 najbardziej prawdopodobne hipotezy, od najbardziej prawdopodobnej.
Ograniczenia: proponuj tylko komendy read-only. Nie proponuj jeszcze poprawki.
Jeśli brakuje danych, napisz, jakiej komendy potrzebujesz, zamiast zgadywać.
Format: tabela | hipoteza | dowód z danych powyżej | komenda weryfikująca |.
