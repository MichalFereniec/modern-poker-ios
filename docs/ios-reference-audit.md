# buyers-app-ios reference audit

Audited on 2026-10-09. Source root: `/Users/michal.fereniec/Developer/buyers-app-ios`.

All 31 AGENTS.md files were read, including files discovered with `rg --files --hidden --no-ignore -g AGENTS.md -g '!**/.git/**'`. The source repository was not modified.

## Applied conventions

Swift, SwiftUI, immutable models, async/await and structured concurrency, explicit isolation, small presentation views, accessible controls, typed Codable responses, Swift Testing, deterministic tests, and default system DerivedData. The repository's SwiftUI Expert skill informed the use of Observation and native iOS 26 controls.

Module instructions are scoped and sometimes disagree. DealZone discourages constructor injection, while TradeIn and C2CDealZone require it. Older guides mention XCTest while the current root guide prefers Swift Testing for new work. ModernPoker uses explicit dependencies and Swift Testing. Its own AGENTS.md states the resulting consistent rules.

Allegro-specific Bazel/Steve setup, Dune branding and token infrastructure, TaskWrapper, global DI, R.swift, isolated mock containers, and OpenSpec store configuration are not copied into the standalone app. The same outcomes use native Swift and Xcode facilities.

## Component reuse

- `AllegroModules/AllegroShare/AllegroShare/Utils/AnimatedButtonStyle.swift`: adapted the press-scale/spring pattern as `PokerPressStyle`, with Reduce Motion support. Native glass buttons retain their system style.
- `AllegroModules/DesignSystem/Dune/Dune/Extensions/View+DuneHitTarget.swift`: reviewed the 44 pt interaction contract; ordinary ModernPoker controls achieve it with native frames instead of importing the custom layout.
- `AllegroModules/MiniApps/MiniAppsQuirks/MiniAppsQuirks/Extensions/View+reverseMask.swift`: reviewed as an optional decoration primitive; not required by the current design.
- `AllegroModules/DepositCommons/DepositCommons/UI/Loading/Shimmering.swift`: reviewed but not copied; it carries upstream SwiftUI-Shimmer provenance. Native progress indicators keep loading behavior simpler.

## Instruction inventory

```text
AGENTS.md
AllegroModules/AllegroLokalnie/LokalnieNetworking/AGENTS.md
AllegroModules/BayBridgeIntegration/AGENTS.md
AllegroModules/C2CDealZone/AGENTS.md
AllegroModules/Cart/AGENTS.md
AllegroModules/Checkout/AGENTS.md
AllegroModules/CheckoutPlugins/CheckoutCTAPlugin/AGENTS.md
AllegroModules/CheckoutPlugins/CheckoutDonationsPlugin/AGENTS.md
AllegroModules/CheckoutPlugins/CheckoutMessageToSellerPlugin/AGENTS.md
AllegroModules/CreditDashboard/AGENTS.md
AllegroModules/CreditInstallments/AGENTS.md
AllegroModules/CreditOnboarding/AGENTS.md
AllegroModules/DealZone/AGENTS.md
AllegroModules/DesignSystem/DesignSystemTokenization/AGENTS.md
AllegroModules/DesignSystem/Dune/AGENTS.md
AllegroModules/DesignSystem/Metrum/AGENTS.md
AllegroModules/DynamicCards/AGENTS.md
AllegroModules/Favourites/AGENTS.md
AllegroModules/LinkedDepositAccount/AGENTS.md
AllegroModules/MBox/AGENTS.md
AllegroModules/MBox/MBoxReactComponents/AGENTS.md
AllegroModules/MessageCenter/AGENTS.md
AllegroModules/MyAllegro/AGENTS.md
AllegroModules/MyBids/AGENTS.md
AllegroModules/MyOrders/AGENTS.md
AllegroModules/OneClickBuy/AGENTS.md
AllegroModules/OneSCA/AGENTS.md
AllegroModules/Payments/AGENTS.md
AllegroModules/Protect/AGENTS.md
AllegroModules/RecurringPurchases/AGENTS.md
AllegroModules/TradeIn/AGENTS.md
```

Additional references: `docs/swift-guidelines.md`, `docs/testing.md`, `docs/coding-standards.md`, `docs/architecture.md`, `.github/skills/swiftui-expert-skill/SKILL.md`, `.github/skills/swift-testing-expert/SKILL.md`, and `.agents/skills/ponytail/SKILL.md`.

Apple references: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).
