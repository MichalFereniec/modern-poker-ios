# Modern Poker

Standalone iOS 26.4+ poker trainer, matching the newest installed SDK. Preserve the approved modern native interface and animations. For the current MVP deadline, prioritize complete playable hands and backend integration over further visual polish or expanded scope.

## Product contract

- Backend API 1.0.0 uses four players, CHECK / BET 10 / FOLD, and explicit action/continue stages. Its published contract is `docs/backend-openapi.json`. Preserve fractional payouts and label fold review as hypothetical. Local mode remains heads-up.
- Texas Hold'em, local heads-up. Play the same hand through flop (3 community cards), turn (4), river (5) and showdown. Folding ends the hand early; an all-in runs out the remaining board.
- Five completed hands form a session, not five individual decisions. Count a hand once after folding or showdown.
- Deal two fixed, hidden opponent cards at the start. Keep the hero cards and dealt board unchanged throughout the hand. Reveal the opponent only at showdown.
- Show the opponent's assumed range before an action; show equity and explanations only after the action. Calculate teaching equity against that disclosed range, never the hidden cards known only to the engine.
- Use the hand's `availableActions` to render legal check/call/fold/bet/raise actions and preset amounts. Action amounts mean additional chips committed now; a raise amount includes its call portion.
- Generate legal random hands without replacement. Never alter cards to reward returning users, favor an answer or change an already dealt outcome.
- The local opponent uses a deliberately simple policy: bet 50 on the flop, check the turn, bet half the pot on the river, and call hero bets/raises. Do not present this policy or its explanations as GTO or solver-quality strategy.
- Equity includes split pots. When a call is available, required equity is `callAmount / (pot + callAmount)`; `pot` already includes the opponent's wager and excludes the hero's call.
- Pot odds and call EV are a price benchmark that excludes future betting costs, rake and ICM. On a nonterminal street, never label an action definitively optimal using equity alone. Explain the assumptions and Monte Carlo uncertainty.
- All user-facing copy is Polish; standard poker action names may be English. No trained LLM is required.

## Swift and architecture

- Swift 6 and SwiftUI. Prefer immutable `let`, value types, small views, synthesized Codable and native platform APIs.
- `@Observable` stores are explicitly `@MainActor`. Owned stores use private `@State`.
- Use `async throws`, actor isolation for the service, and `Sendable` models. Compute poker results off the main actor. Cancel obsolete work and ignore stale responses.
- Keep calculation, transport and UI responsibilities separate. Pass dependencies explicitly. Add abstractions only when a concrete need exists.
- Prefer native `.task`, `URLSession`, `Button`, `NavigationStack`, `foregroundStyle`, and current SwiftUI observation. Do not import Allegro's TaskWrapper or dependency injection container.
- The service owns local and remote modes of the same training flow. Remote failures must remain visible; never silently switch to local data.
- `docs/backend-openapi.json` is the current remote contract; `docs/openapi.json` is the previous v2 prototype. `docs/openapi-v1.json` is archival only. Keep Codable names, required fields, errors and value semantics in sync with the current contract.
- Backend creations use a stable Idempotency-Key UUID. Recover uncertain actions/continuations with GET before retrying; the backend rejects stale street/stage transitions. The previous v2 service and local engine retain requestId/revision behavior for their existing tests.
- Do not add dependencies for capabilities available in Swift, SwiftUI or Foundation.

## Visual contract

- Dark graphite, deep emerald felt, ivory cards and restrained champagne accents. Centralize visual tokens.
- Use iOS 26 Liquid Glass for interactive controls and navigation. Cards and primary teaching content remain legible opaque surfaces.
- Use system typography, deliberate hierarchy, expressive spring transitions, staged card dealing, chip flights, celebratory particles and haptics. The user explicitly prioritizes spectacular game-like animation, inspired by Monopoly Poker. Keep sequences short and controls responsive; motion must support understanding.
- Preserve existing Reduce Motion, Dynamic Type, VoiceOver and 44 pt control support. The user has deprioritized accessibility work for this MVP: do not run dedicated VoiceOver or Dynamic Type audits or add further accessibility polish unless requested.
- Inspect the running app at phone size: complete hand progression, every available action, analysis, showdown, fold, all-in, range help, session completion, settings, loading and failure recovery.
- Preserve button animation provenance from `buyers-app-ios`; see `docs/ios-reference-audit.md`.

## Build and validation

- Open `ModernPoker.xcodeproj`; scheme `ModernPoker`. Build using `xcodebuild`, with default system DerivedData. Never put DerivedData or build artifacts in the project.
- Build settings live in `Config/App.xcconfig`. The Xcode project uses synchronized filesystem groups so new Swift files are included automatically.
- Unit tests use Swift Testing. Run `swift test --scratch-path /private/tmp/modern-poker-tests`.
- Test real poker behavior: rankings, ties, blockers, deal validity, fixed cards across streets, legal actions, chip conservation, fold/all-in/showdown, equity, transport validation, idempotent retries, cancellation and five-hand session progression.
- Use deterministic randomness in tests only; production uses the system RNG.
- Keep compiler warnings fixed. Validate the OpenAPI document and its examples when the API changes. Human-authored JSON uses two spaces and a final newline.
- Update README and the API contract together with behavior changes. Report verification only after it has run against the current implementation.

## Source of conventions

All 31 `AGENTS.md` files in `/Users/michal.fereniec/Developer/buyers-app-ios` were reviewed. This file applies the reusable conventions while resolving module-specific contradictions for this standalone project. The inventory and adaptation choices are recorded in `docs/ios-reference-audit.md`.

Allegro's Bazel/Steve, module DI containers, corporate branding, generated localization, and external OpenSpec store are monorepo infrastructure, not dependencies of this app. OpenAPI JSON here describes the backend HTTP contract; it is not an OpenSpec change.
