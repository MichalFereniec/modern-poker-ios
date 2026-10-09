# Modern Poker

Trener Texas Hold'em na iPhone'a. Rozgrywasz **pięć pełnych rozdań** przeciwko trzem rywalom z backendem albo jednemu w trybie lokalnym: flop → turn → river → showdown. Podejmujesz decyzje przy stole, a po każdej dostajesz krótką analizę. SwiftUI, ciemny pokerowy stół, Liquid Glass, animowane rozdawanie kart i żetony.

## Uruchomienie

1. Otwórz `ModernPoker.xcodeproj` w Xcode 26.4 lub nowszym.
2. Wybierz schemat **ModernPoker** i symulator iPhone z iOS **26.4 lub nowszym**.
3. Run. Naciśnij **Zajmij miejsce**.

Tryb lokalny generuje rozdania i oblicza equity metodą Monte Carlo. Nie wymaga logowania, klucza do LLM ani serwera. Na fizycznym urządzeniu wybierz swój Team w Signing & Capabilities. Identyfikator aplikacji: `com.modernpoker.trainer`.

```sh
xcodebuild -project ModernPoker.xcodeproj -scheme ModernPoker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build

swift test --scratch-path /private/tmp/modern-poker-tests
```

Xcode używa domyślnego systemowego DerivedData. Biblioteka testowa i aplikacja kompilują te same pliki z `ModernPoker/Core`.

## Jak przebiega lokalne rozdanie

- Twoje dwie karty i ukryte karty rywala są ustalone na początku. Na flopie widać trzy karty stołu; turn i river dokładają po jednej. Karty nie są losowane ponownie po decyzji.
- Dostępne akcje to **CHECK, CALL, FOLD, BET, RAISE**, zależnie od stanu. Przy zakładach wybierasz legalne, przygotowane kwoty.
- Fold kończy rozdanie. All-in uruchamia wyłożenie pozostałych kart. Przy showdown odsłaniane są karty rywala i rozliczana pula, także przy remisie.
- Sesja liczy pięć zakończonych rozdań, nie pięć kliknięć. Jedno rozdanie może zawierać kilka decyzji.
- Zakres rywala jest widoczny przed decyzją; equity i wyjaśnienie pojawiają się po niej. Equity jest liczone względem tego zakresu, a nie ukrytych kart, które zna silnik.

Lokalny przeciwnik ma prostą, jawną politykę demonstracyjną: stawia 50 na flopie, czeka na turnie, stawia połowę puli na riverze i sprawdza twoje zakłady/podbicia. Legalne akcje i kwoty uwzględniają aktualne żetony. To ograniczony trener podstaw, nie solver GTO ani model profesjonalnego przeciwnika.

## Backend dla Krzyśka

Aktualny backend Krzyśka: **[docs/backend-openapi.json](docs/backend-openapi.json)** — API 1.0.0, `/api/v1`. Pliki `openapi.json` (wcześniejszy projekt v2) i `openapi-v1.json` są zachowane jako referencje poprzednich prototypów.

Backend: `/Users/michal.fereniec/Developer/alle-workshop2`.

```sh
cd /Users/michal.fereniec/Developer/alle-workshop2
uv run uvicorn poker_tutor.api:app --host 127.0.0.1 --port 8080
```

- `POST /api/v1/sessions` oraz `/sessions/{id}/hands`: tworzenie z nagłówkiem `Idempotency-Key` UUID.
- `POST /sessions/{id}/hands/{id}/actions`: `{"action":"bet","street":"flop"}`; analizę pokazujemy przed odkryciem następnej karty.
- `POST /sessions/{id}/hands/{id}/continue`: `{"street":"flop"}`; turn, river albo showdown.
- `GET` sesji i rozdania odzyskuje stan po przerwanej odpowiedzi. Nie powtarzamy ruchu, który już został zapisany.
- `POST /sessions/{id}/end`: zamknięcie sesji, zwrot niezakończonych wkładów.

W trybie backendu: czterech graczy, otwarcie po 10, CHECK / BET 10 / FOLD. Rywale czekają lub sprawdzają; salda przechodzą do następnych rozdań. Podział puli zachowuje ułamkowe żetony. Analiza dotyczy ujawnionych zakresów trzech rywali i uproszczonego modelu check-down. FOLD pokazuje osobno hipotetyczny wynik; rzeczywista wypłata użytkownika wynosi zero.

W aplikacji: **Ustawienia → Korzystaj z backendu → Adres serwera → Zapisz**.

- Symulator: `http://localhost:8080` łączy się z serwerem na Macu.
- Fizyczny iPhone: adres komputera w tej samej sieci lokalnej; serwer musi nasłuchiwać na interfejsie sieciowym. Dla serwera publicznego użyj HTTPS.
- Tryb lokalny i zdalny obsługuje wspólny serwis. Błąd backendu pozostaje widoczny i można ponowić żądanie. Aplikacja nie przełącza się samoczynnie na lokalne obliczenia.
- Serwer nie jest częścią tego projektu. Krzysiek może zaimplementować kontrakt w wybranej technologii.

## Co znaczą liczby

Equity oznacza oczekiwany udział w puli, uwzględniający remisy. Jest estymowane względem jawnego założenia o zakresie rywala z wykluczeniem znanych kart. Wynik Monte Carlo ma niepewność; nie jest dokładną prognozą wyniku tego konkretnego rozdania.

Gdy trzeba zapłacić za call, pokazujemy porównanie jego ceny z equity. `pot` obejmuje już zakład przeciwnika, lecz nie obejmuje twojego call:

```text
próg ceny call = toCall / (pot + toCall)
EV(call) bez dalszych kosztów = equity × (pot + toCall) − toCall
EV(fold) = 0 względem chwili decyzji
```

Na flopie i turnie dalsza licytacja może zmienić opłacalność. Ten rachunek pomija przyszłe zakłady, prowizję i ICM; sam nie dowodzi, że ruch jest optymalny. Nie służy też do wyznaczania najlepszego bet lub raise. Aplikacja objaśnia bieżącą sytuację bez przyznawania definitywnej strategicznej oceny na podstawie samego equity. Wygrany runout nie jest dowodem dobrej wcześniejszej decyzji.

Losowanie nie zależy od wcześniejszych wyników ani częstotliwości używania aplikacji.

## Kod i konwencje

- `ModernPoker/Core`: modele, silnik rozdania, ranking układów, Monte Carlo, walidacja, klient HTTP i store sesji oparty na Observation.
- `ModernPoker/UI`: natywne ekrany i komponenty SwiftUI, karty, stół i animacje.
- `Config/App.xcconfig`: ustawienia kompilacji, deployment target 26.4, Swift 6.
- `Tests`: testy Swift Testing.
- [AGENTS.md](AGENTS.md): zasady dalszej pracy i priorytety.
- [docs/ios-reference-audit.md](docs/ios-reference-audit.md): audyt wszystkich 31 `AGENTS.md` z buyers-app-ios i źródła wykorzystanych wzorców.

Brak zewnętrznych zależności aplikacji. Zachowujemy dotychczasowe wsparcie Reduce Motion i etykiety VoiceOver; priorytetem tego MVP jest pełny przebieg gry w zatwierdzonym interfejsie.

## Weryfikacja

**Build i 60 testów przeszły.** W RocketSim sprawdzono pełne rozdanie z rzeczywistym backendem Krzyśka, analizę na każdej ulicy, pas, wypłaty, podsumowanie pięciu rozdań oraz zapis ustawień po ponownym uruchomieniu. Szczegóły: [docs/verification.md](docs/verification.md).

Aktualne widoki: [flop](docs/demo/modern-poker-v2-flop.png), [turn](docs/demo/modern-poker-v2-turn.png), [showdown](docs/demo/modern-poker-v2-showdown.png). Starsze materiały bez `v2` dotyczą poprzedniego treningu pojedynczej decyzji.
