# cardGame2

A SwiftUI rebuild of [cardsGame](https://github.com/azzam-dev) (2020, UIKit + storyboards).

> **The rules below are superseded.** [`SPEC.md`](SPEC.md) is the authoritative
> specification: one 52-card deck, up to 13 players, combination-based hand
> comparison and no-pot settlement. The engine described here still implements
> the old 16-card, four-player rules and has not been rewritten yet.

The rules live in plain Swift value types with no UIKit, no views and no
timers, so they can be unit-tested on their own. On top of that sits a SwiftUI
table you can play a full round on against three AI opponents.

## Layout

```
project.yml              XcodeGen spec — regenerate with `xcodegen generate`
Sources/Engine/          the game, as pure Swift
  Card.swift             Rank, Suit, Card, Deck (16 cards)
  Hand.swift             grouping, Combination, scoring
  Player.swift           Seat, Player, RoundParticipation
  GameRules.swift        StakeRange, bet/offer limits, payout modes, rotation
  Offer.swift            buy-out bids and their resolution
  GameEngine.swift       the round state machine and settlement
  AIStrategy.swift       hand-strength-driven opponents
  RandomGenerator.swift  seedable RNG so games replay
Sources/App/
  GameTableViewModel.swift  owns the engine, plays the AI seats, holds
                            presentation state; round flow reads as awaits
  Views/GameTableView.swift the table: four seats, deck, controls, dial
  Views/SeatView.swift      a seat's fan of cards along its own edge
  Views/CardView.swift      one card, face up or down, at the art's 2:3
  Views/TableControls.swift bet/offer pickers, offer rulings, round summary
  Views/RadialNavButton.swift the drag-out dial, with its geometry extracted
  Views/TablePanel.swift    offers, leaderboard and round-info panels
  Views/BetBubbleView.swift bet bubbles and player badges
Resources/Assets.xcassets  art carried over from the old project
Tests/                   XCTest suites for the above
```

## The game

Four players, a 16-card deck — A K Q J in each of the four suits — four cards
each.

**Betting.** In turn order, each player either enters the round for a bet or
withdraws. Bets are multiples of 100 and must raise the standing bet. Turn order
rotates one seat per round.

**Scoring.** A hand is worth its combination's base value, plus the full rank
value of every rank it holds two or more of, plus a tenth of the rank value of
every loose card. Suits never affect the score — they only settle hands that
are otherwise identical (♠ > ♣ > ♥ > ♦); see decision 1 below.

| Combination | Base | | Rank | Grouped | Loose |
|---|---|---|---|---|---|
| Four of a kind | 4000 | | A | 400 | 40 |
| Three of a kind | 3000 | | K | 300 | 30 |
| Two pair | 2400 | | Q | 200 | 20 |
| Pair | 2000 | | J | 100 | 10 |
| Rainbow | 0 | | | | |

So four aces = 4400, aces over kings = 3100, and a rainbow A K Q J = 100 (the
weakest hand possible).

**Negotiation.** Once bets are in, entrants who are *not* the top bettor may
offer coins to buy their way out of the round. Offers are final once sent; the
top bettor's accept/reject is final once made. Accepting withdraws the sender —
but the coins only change hands if the top bettor goes on to win.

**Settlement.** Losing entrants pay the bet they placed and the winner
collects it. Players who withdrew lose nothing. See decision 3 below for the
variant that matches the old code exactly.

## Rules I had to pin down

The original `GameLogic.swift` was entirely commented-out prose, and the live
code in `GameFieldViewController.swift` left some of it unfinished. Where the
two disagreed or stopped short, I picked a reading and wrote a test for it:

1. **Ties.** The spec notes the collision itself — two aces with two jacks and
   two kings with two queens both score 2900 — but the old code resolved it by
   sorting a `Dictionary`, which is non-deterministic.

   The cause is that rank values are linear, so `A + J = 500 = K + Q`. Across
   all 1820 possible hands that is the *only* score reachable by two different
   rank shapes; separately, 29 of the 34 possible scores can be reached with
   different suits, so two players can tie that way too. Measured over 400k
   four-player deals, the top score was tied in **3.34%** of them — 1.60% the
   2900 case, 1.74% same ranks in different suits.

   Rather than change the scoring table, `Hand` is now `Comparable` through a
   chain, with `score` unchanged at the top of it:

   1. `score` — every value in the table still decides the round
   2. grouped ranks, highest first — the higher pair wins, settling 2900
   3. loose ranks, highest first
   4. the cards themselves, bringing suit order **♠ > ♣ > ♥ > ♦**

   Step 4 cannot tie for two hands from one deck, so a round always has exactly
   one winner and seat position never decides anything. `Hand`'s ordering is
   tested as a total order over all 1820 hands, and separately for never
   contradicting the score.
2. **Paying for an accepted offer.** The old code had `// subtract the offer`
   as a TODO and never moved the coins. The spec's wording ("the coins only go
   to the offer Providers if the top bettor wins") reads backwards for a
   pay-to-exit mechanic, so I implemented the mechanic: the sender pays the top
   bettor, and only if the top bettor wins. **Worth confirming** — if you meant
   the top bettor pays *them*, it's a sign flip in `GameEngine.settle()`.
3. **The winner's own stake — changed from the old code, on purpose.** The old
   payout gave the winner the top bet without ever deducting their own stake,
   so a round was not zero-sum and coins were minted on every win where the
   top bettor won. Compounded, stacks grow about 1.6× per win against the
   default AI and overflow `Int` inside a hundred rounds; a 200-round test was
   what surfaced it. `GameRules.Payout` now has both:
   - `.conserving` (**default**) — losing entrants pay their bets and the
     winner collects exactly that, so the coin supply is constant. This still
     matches the spec's own worked example: one player in for 100, another for
     2000, winner takes 2000.
   - `.topBetToWinner` — the old arithmetic, kept for fidelity and tested,
     including a test asserting that it mints coins. Not safe to leave running.

   Pass it to `GameEngine(players:payout:seed:)` to switch.
4. **Short stacks.** The old rule let a player who couldn't cover the standing
   bet enter from 100 anyway, below the top bet. Kept, and tested.
5. **AI.** The old opponents picked a random index into their legal bets and
   entered when `index % random(2...4) == 0`, so strong hands folded as often
   as weak ones. `AIStrategy` now sizes its bet against the hand it holds, with
   a bluff and a flinch rate, and three personalities (`cautious`, `balanced`,
   `reckless`).
6. **Stakes are a range, not a list.** Legal bets come back as a `StakeRange`
   with O(1) `contains`, and the engine validates against that. The old shape
   — materialise every legal bet, then check membership — allocates
   `coins / 100` integers per check, which is fine at 5000 coins and a
   liability at any larger stack. `options(limit:)` still hands a capped list
   to a picker.

## Running it

```bash
xcodegen generate
xcodebuild test -scheme CardGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

97 tests, all passing, in under two tenths of a second. The engine has no UIKit
or SwiftUI in it, and the view model takes its animation timings as a
parameter, so tests pass `.immediate` and a round resolves as fast as the
engine can score it.

`project.yml` is the source of truth for the project file — add files to
`Sources/` or `Tests/` and re-run `xcodegen generate`.

## The table

Landscape, four seats round the edges, playable end to end: deal, bet or
withdraw, watch the AI act, negotiate, reveal, settle, next round.

A few notes on how it differs from the original:

- **The round is a sequence of `await`s**, not a chain of
  `DispatchQueue.main.asyncAfter` calls hung off animation completion
  handlers. `GameTableViewModel.advance()` plays AI seats until it reaches the
  human, then simply returns — the human's turn is where the driver stops.
- **A seat is one view.** The old controller moved four image views per player
  through four constraint outlets each (sixteen outlets, four copies of the
  same animation). `SeatHandView` knows which edge it sits on and derives the
  rest.
- **The human has no seat badge** — their name and purse ride in the control
  bar, which already owns that edge of the table.
- **Bets are a row of chips**, not a `UIPickerView`. In landscape a row reads
  better than a wheel and both ends of the range are one tap away.
- **The radial home button is still there**: press and drag out of the dot,
  the dial blooms, drop on a destination. Its geometry lives in `RadialDial`,
  away from the view, so the drop logic is unit-tested.

### Known gaps

- Drag-to-drop on the dial is implemented and its geometry is tested, but the
  gesture could not be exercised in the simulator: with the device held
  portrait and the app locked to landscape, the dot lands in iOS's own
  Notification Center zone and the system swallows the drag. Tapping a
  destination works, and this wants a check on a real device held landscape.
- No chat, no voice recording, no sound, no settings beyond the round-info
  panel.
- The deal animation staggers cards into each hand but does not yet throw them
  from the centre of the table the way the original did.
