# Dziennik – lab04

Namespace: `piotr-z` · Wynik: `setup/check.sh` → `SUKCES: 11/11` przed i po `apply`

| # | Bramka / krok | Co złapała (albo co poprawiłem sam) | Poprawka |
|---|---|---|---|
| 1 | Krok 1: kubectl-ai (odczyt) | Model zgłosił brak PDB i NetworkPolicy dla Postgresa (potwierdzone: `kubectl get pdb,networkpolicy -n piotr-z` → brak PDB, tylko `kantyna-orders-api-ingress`). Twierdził też, że brakuje limitów zasobów, a `kubectl get deploy,sts -o custom-columns` pokazał requests i limits we wszystkich kontenerach (model sam przyznał, że zgadywał). Pierwsze próby kończyły się `no JSON code block found` albo pytaniem o namespace, który był ustawiony w kontekście | Teza o limitach odrzucona. Ponowne zapytanie z podanym namespace'em i zgoda tylko na `get`/`describe` |
| 2 | Krok 1: porady kubectl-ai | Zalecił 2–3 repliki Postgresa „z replikacją" i PDB dla wszystkich komponentów | Nie wdrożone: StatefulSet z 2 replikami bez replikacji dałby dwie niezależne bazy, a PDB `minAvailable: 1` na pojedynczej replicy (`worker`, `postgres`) blokuje drain węzła. PDB tylko dla `orders-api` (2 repliki) |
| 3 | Krok 3: `kubectl apply --dry-run=server` i `trivy config` | Nic nie złapały: oba pliki przeszły za pierwszym razem (`trivy`: 0 uwag) | Sam poprawiłem selektory: do `name=...` dodałem `instance=kantyna`, żeby nie złapać podów innego releasu |
| 4 | Krok 4: `kubectl diff` i `apply` | Diff pokazał tylko dwa nowe zasoby (PDB i NetworkPolicy), bez zmian w istniejących. Po `apply`: PDB `ALLOWED DISRUPTIONS 1`, `check.sh` 11/11 (zamówienie przez `orders-api` do Postgresa działa). Istniejąca NetworkPolicy z lab02 nie koliduje | brak |
| 5 | Krok 5: `terraform plan` | `Plan: 1 to add` dla zasobu, który już jest w klastrze: plik stanu jest pusty, a Terraform nie czyta klastra | `terraform apply` nie uruchamiany (zakończyłby się `already exists`). Aby przejąć zasób, trzeba by najpierw `terraform import` |
