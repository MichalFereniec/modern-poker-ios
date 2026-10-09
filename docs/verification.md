# Weryfikacja integracji backendu — 2026-10-09

- Backend Krzyśka: `/Users/michal.fereniec/Developer/alle-workshop2`, API 1.0.0, FastAPI + SQLite, rzeczywisty proces uvicorn pod `http://localhost:8080`. Opublikowany kontrakt: `docs/backend-openapi.json`.
- Finalny build `ModernPoker.xcodeproj`, Debug, iPhone 17 Pro / iOS 26.5: **BUILD SUCCEEDED**. Domyślny systemowy DerivedData. Swift 6; brak błędów kompilacji.
- **60 testów Swift Testing w 6 zestawach przeszło**. Nowe testy: action/continue z utraconą odpowiedzią i pojedynczym naliczeniem zakładu, ułamkowe wypłaty i rozdzielenie hipotetycznego fold review, naliczenie rozdania dopiero po showdown, odtworzenie pot/board/stacks sprzed decyzji.
- RocketSim, rzeczywisty backend: hero 2♠ 6♠, board A♠ T♠ 9♦ → 7♠ → 4♥. Flop BET 10 → analiza; turn CHECK → analiza; river BET 10 → analiza; explicit continue → showdown. Hero i poprzednie karty stołu nie zmieniały się. Pula 40 → 80 → 120; wypłata 120, saldo gracza 1090. Widoczne karty wszystkich trzech rywali.
- Analiza: equity i próg BET 25%, grade, rekomendacja, EV check/bet, wygrana bez podziału, 10000 prób i niepewność 95%. Założenia modelu check-down podane po polsku.
- Fold z flopa: analiza zachowuje tylko informacje znane przed ruchem; wynik ujawnia pełny board i karty rywali. Faktyczna wypłata gracza **0**, hipotetyczny wynik opisany osobno.
- Sesja pięciu rozdań zakończona w aplikacji i API. Backend potwierdził status `ended`, 2 completed + 3 folded, 9 decyzji, net_chips 20. Część dodatkowych rozdań użytkownik rozegrał równolegle przez podgląd.
- Zapisano backend w ustawieniach. Finalny build zainstalowany i uruchomiony bez argumentów wymuszających backend; nowe rozdanie pokazało czterech graczy, co potwierdza trwałość konfiguracji. Sheet zakresów pokazuje osobne zakładki Rywal 1 / 2 / 3.
- RocketSim raz zamknął połączenie IPC i aplikację narzędzia; ponownie uruchomiony, nowy podgląd działa. Nie było błędu aplikacji iOS ani API.
- Aplikacja pozostawiona w trybie backendu, z lokalnym serwerem uruchomionym. Adres dla symulatora: `http://localhost:8080`. Fizyczny iPhone wymaga serwera dostępnego przez LAN; nie wykonywano TestFlight ani podpisania urządzenia.

Materiały: [flop](demo/modern-poker-backend-flop.png), [showdown](demo/modern-poker-backend-showdown.png), [podsumowanie](demo/modern-poker-backend-summary.png).

## Poprzednia weryfikacja lokalnego prototypu v2 (archiwum)

Poniższe informacje opisują wcześniejszą wersję. Obecna integracja rzeczywistego backendu została zweryfikowana powyżej.

### Weryfikacja — pełne rozdania v2, 2026-10-09

- Xcode 26.4.1, Swift 6.3.1, SDK iOS 26.4, deployment target 26.4. `xcodebuild` Debug na iPhone 17 Pro / iOS 26.5: **BUILD SUCCEEDED**. Systemowy DerivedData; brak ostrzeżeń kompilatora Swift. Xcode pomija ekstrakcję App Intents, ponieważ aplikacja nie używa tego frameworka.
- Swift Testing: **56 testów w 5 zestawach — wszystkie przeszły**. Testy obejmują ranking i equity, pełne rozdanie, bilans żetonów, stałe karty, remisy, fold, check/bet/call/raise, all-in, brak podglądania ukrytych kart w analizie, transport, idempotencję, anulowanie i sesję pięciu rozdań. Test sesji przechodzi przez 15 decyzji w pięciu pełnych rozdaniach; wielokrotne kliknięcia nie naliczają ich ponownie.
- OpenAPI **3.1.1 / API 2.0.0**: walidacja `openapi-spec-validator` oraz **39 przykładów** zgodnych z JSON Schema. Sekwencja przykładowego rozdania i fold przechodzą również rzeczywisty walidator Swift. Kontrakt v1 zachowano jako `docs/openapi-v1.json`.
- Symulator, lokalny silnik: flop CALL → analiza → turn CHECK → analiza → river CALL → analiza → showdown. Hero J♣ J♦ pozostawał ten sam, stół rozwijał się K♥ 4♠ 8♠ → 6♠ → 4♣, końcowa pula wyniosła 400. Rywal T♦ T♥ ujawnił się dopiero na showdown; wypłata i stosy odpowiadały wynikowi układów.
- Osobno w UI sprawdzono fold kończący rozdanie bez odkrycia rywala oraz all-in na flopie uruchamiający pełny runout i showdown.
- Rzeczywisty `URLSession` aplikacji z tymczasowym lokalnym serwerem v2: `POST /v2/hands` 201, następnie trzy `POST /v2/hands/{id}/actions` 200 z rewizjami 0 → 1 → 2 → 3. Jedno ID, ten sam hero i rosnący board; CALL 50 → CHECK 0 → CALL 100 → showdown. Backendowy przykład z pokerem królewskim miał znany wynik, pulę 400 i końcowe stosy 1200 / 800. To fixture integracyjny, nie backend Krzyśka ani mechanizm losowania lokalnego.
- Po tym rozdaniu cztery kolejne foldy zakończyły sesję. UI poprawnie pokazało **5 ukończonych rozdań i 7 decyzji** oraz listę wyników.
- Sprawdzono wygląd turna i showdownu. Zmniejszono odstępy treningu: karty i własny stos są widoczne ponad nowymi kontrolkami. Trzy akcje mieszczą się w jednym wierszu, cztery w układzie 2×2. Dotychczasowe karty nie są ponownie rozdawane przy przejściu na następną ulicę.
- Po teście połączenia przywrócono aplikację do lokalnego losowania. Tymczasowy serwer testowy został zatrzymany. Nie zmieniano zapisanego adresu ani trybu backendu.

## Zakres MVP

Lokalny rywal używa prostej, jawnej polityki opisanej w README i pomocy aplikacji. Analiza equity i ceny call jest punktem odniesienia bez przyszłych kosztów, nie oceną optymalnej strategii wieloetapowej. Backend może zwracać inne legalne akcje i dalszą licytację na tej samej ulicy.

Pozostaje połączenie z rzeczywistym serwerem Krzyśka po udostępnieniu adresu i uzgodnieniu kontraktu. Nie wykonywano podpisania na fizycznym iPhonie ani publikacji TestFlight. Dedykowany audyt dostępności pozostaje poza zakresem tego MVP zgodnie z decyzją użytkownika.

Nowe materiały: `docs/demo/modern-poker-v2-flop.png`, `docs/demo/modern-poker-v2-turn.png`, `docs/demo/modern-poker-v2-showdown.png`. Turn pochodzi z jawnego fixture HTTP; flop i showdown z lokalnego losowania. Starsze pliki bez `v2` pokazują poprzedni trening pojedynczej decyzji.
