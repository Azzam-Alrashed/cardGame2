# cardGame2

A SwiftUI rebuild of [cardsGame](https://github.com/azzam-dev) (2020, UIKit + storyboards).

The rules live in [`SPEC.md`](SPEC.md), which is the authoritative
specification; the engine in `Sources/Engine/` implements it, in plain Swift
value types with no UIKit, no views and no timers, so it can be unit-tested on
its own.

## Layout

```
project.yml              XcodeGen spec — regenerate with `xcodegen generate`
SPEC.md                  the rules, and what is still open
Sources/Engine/          the game, as pure Swift
  Card.swift             Rank, Suit, Card, Deck (52 cards)
  HandEvaluator.swift    Combination, the comparison key, classification
  HandComparator.swift   the only comparison of two hands
  Hand.swift             four cards plus their ranking
  Player.swift           Seat, PlayerID, Player, round standing
  GameRules.swift        constants, seats, turn order
  Betting.swift          BetRange, legal actions and amounts
  Policy.swift           every rule the spec leaves open, as configuration
  Sharah.swift           buy-out offers, and the policy knobs still open
  Settlement.swift       the money, elimination, the target
  GameState.swift        phases, and what one player may know about another
  GameEngine.swift       the state machine that sequences all of it
  AIStrategy.swift       opponents that see only public information
  RandomGenerator.swift  seedable RNG so games replay
Sources/App/             the table, as SwiftUI
  Views/CardView.swift   card art where it exists, drawn pip faces where it does not
Resources/Assets.xcassets  art carried over from the old project
Tests/                   XCTest suites for the above
```

## The game

Up to **13 players**, one standard **52-card** deck, **four cards each**.
Suits never affect anything.

**Hands** are classified and then compared — type first, ranks second, never a
numeric score:

> Four of a kind > Three of a kind > Two pairs > One pair > No matching cards

with `A > K > Q > J > 10 > 9 > 8 > 7 > 6 > 5 > 4 > 3 > 2` inside a type. Suits
cannot break a tie, so true ties happen, and tied winners split the prize.

**Betting** is one pass round the table. Each player folds, bets any affordable
multiple of 500 at or above what is required to stay in, or goes all-in. 500 is
an increment, not a step limit: a player holding 12,000 can bet 10,000 and keep
2,000, and nothing caps a bet by the table size. An all-in may be below the
standing bet, which is how a short stack stays in. Nothing treats a bet as a
measure of a hand: bluffing is the point.

**Sharah** is a side deal. One player pays another to leave the round; the money
moves the moment the offer is accepted, the accepter's bet is neither lost nor
refunded, and their cards are never seen.

**Settlement has no pot.** The winner collects the round's highest bet whoever
placed it; every other player at the showdown pays exactly their own bet. Those
two numbers are independent, so the money supply is not conserved — see
[`SPEC.md` §11](SPEC.md).

**Elimination.** Start on 5,000, out at 0, win the game at 100,000.

## Running it

```bash
xcodegen generate
xcodebuild test -scheme CardGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

141 tests, all passing, in about a tenth of a second — the engine has no UIKit
or SwiftUI in it, so the suite is pure computation.

`project.yml` is the source of truth for the project file — add files to
`Sources/` or `Tests/` and re-run `xcodegen generate`.

## Privacy, structurally

A hand is private, and the engine is built so that it cannot leak rather than
merely choosing not to:

- `GameEngine` keeps its participation table private. A hand is read through
  `hand(of:asSeenBy:)`, which answers nil for an opponent's hidden cards and for
  a folded or bought-out hand in any phase.
- `AIStrategy` is handed its own hand and a `PublicTableView`, whose opponent
  hands are nil until a reveal. There is no path from an AI decision to a hidden
  card.
- The table UI reads every hand through the same accessor, with the human as the
  viewer.

## Still open

[`SPEC.md` §15](SPEC.md) lists what is not settled, and every item is a field on
`GamePolicy` rather than a decision in the engine: the Sharah procedure, where a
Sharah payment is funded from, which zero balances eliminate, who wins when two
players cross 100,000 in one settlement, the multiplayer model, and the table
size in play. The defaults are starting points, not rulings.

## Not built yet

Catalogue art for the 36 number cards — they are drawn from rank and suit for
now, in the same classic style as the A/K/Q/J art that came from the old game —
the leaderboard polish, chat, settings, and a table laid
out for more than the four demo seats — the geometry scales, but the shipped
table seats four.
