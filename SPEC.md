# Game Specification

Authoritative rules for the game. Where this document and `README.md` disagree,
this document wins — the README describes the superseded 16-card engine that is
currently in `Sources/Engine/`.

Status key: **LOCKED** rules are settled and implementation must match them
exactly. **OPEN** items are not yet specified and nothing may be built on a
guess about them.

Last updated 2026-10-02.

---

## 1. Concept — LOCKED

A multiplayer betting game inspired by Baloot but not bound to four players.
Winning is not simply a matter of holding the strongest cards. The game combines
six elements, and the last five can beat the first:

1. **Card strength** — the hand dealt.
2. **Betting** — the amount committed, which is also the only public signal.
3. **Bluffing** — a weak hand that bets large can drive stronger hands out
   before a single card is seen.
4. **Risk management** — judging when a hand is not worth its price.
5. **Negotiation (Sharah)** — paying an opponent to leave rather than beating
   them.
6. **Elimination** — losses persist between rounds, so survival is a separate
   goal from winning any one round.

A player may lose every showdown and still outlast the table. A player holding
four aces may collect nothing if the table exits cheaply.

## 2. Cards and deck — LOCKED

- One standard 52-card poker deck: 13 ranks x 4 suits.
- Ranks: A, K, Q, J, 10, 9, 8, 7, 6, 5, 4, 3, 2.
- **Suits have zero effect on anything** — not strength, not comparison, not
  ties. There is no trump suit and no suit-based tiebreak. Suits exist only so
  that four physical copies of each rank exist.
- There are no flushes and no straights. Those concepts do not exist in this
  game and must not be introduced.

## 3. Players and deal — LOCKED

- Each player receives **exactly 4 cards**, dealt once.
- No draws, no discards, no swaps, no community cards.
- 4 cards x 13 players = 52, so **13 players is the hard ceiling**.
- With fewer than 13 players the undealt cards remain in the deck, unseen and
  unused for the round.

## 4. Information rules — LOCKED

- A hand is private to its owner for the entire round.
- No player may see another player's cards before the final reveal. No peeking,
  no partial reveals, no showing a single card.
- Cards become public only at the showdown, and only for players who reach it.
- A player who leaves the round by accepting a Sharah offer **never reveals
  their cards** (see §8).

Everyone bets on four cards nobody else has seen. This is what makes bluffing
real, and it is a hard constraint on every interface built on this engine: no
view, log, animation or debug output may leak a hand.

## 5. Hand classification — LOCKED

A 4-card hand falls into exactly one type. The five types are complete and
mutually exclusive, because the only possible rank multisets of four cards are
4, 3+1, 2+2, 2+1+1 and 1+1+1+1:

| Type | Shape | Example |
|---|---|---|
| Four of a kind | 4 | A A A A |
| Three of a kind | 3 + 1 | J J J 4 |
| Two pairs | 2 + 2 | A A K K |
| One pair | 2 + 1 + 1 | Q Q A K |
| No matching cards | 1 + 1 + 1 + 1 | A K 10 9 |

## 6. Hand comparison — LOCKED

### Step 1 — type

Strongest to weakest:

**Four of a kind > Three of a kind > Two pairs > One pair > No matching cards.**

If two hands differ in type, the stronger type wins outright. Ranks are not
consulted.

### Step 2 — rank, within a single type

Reached only when both hands are the same type. Every rank uses
**A > K > Q > J > 10 > 9 > 8 > 7 > 6 > 5 > 4 > 3 > 2**.

| Type | Comparison sequence |
|---|---|
| Four of a kind | quad rank |
| Three of a kind | trip rank, then remaining kickers in descending order |
| Two pairs | higher pair, then lower pair (no kicker exists — all 4 cards are paired) |
| One pair | pair rank, then highest kicker, then lowest kicker |
| No matching cards | all 4 ranks sorted descending, compared position by position |

The order a hand is held or displayed in is irrelevant; comparison sorts first.

### Worked examples

- Four of a kind: `AAAA` beats `KKKK`; `KKKK` beats `QQQQ`.
- Three of a kind: `AAA + x` beats `KKK + x`; `JJJ + x` beats `10 10 10 + x`.
- Two pairs: `AAKK` beats `AAQQ` (higher pair equal, K > Q);
  `KKQQ` beats `JJ10 10` (K > J).
- One pair: `KK + x + y` beats `QQ + x + y`;
  `QQAK` beats `QQA9` (pair equal, high kicker A equal, K > 9);
  `QQA10` beats `QQJ10` (pair equal, A > J — decided before the 10s).
- No matching cards: `A K 9 10` beats `K J 8 7` (A > K, decided at the first
  card); `A K 9 7` beats `A Q J 10` (A equal, K > Q).

### Prohibited

- Suits must never be consulted, at any step, for any reason.
- No flush, straight, or any other poker hand not listed in §5.
- The superseded additive `base value + rank points` score must not be used.
  Comparison is type-first, then rank — never a single number. A strict
  hierarchy means a pair always beats a worse type regardless of ranks, so the
  cross-type collisions the old scoring produced cannot occur.

### Reachability notes

With a single deck, two players can never hold the same quad rank (8 cards of
one rank required) or the same trip rank (6 required). **Four of a kind and
three of a kind are therefore always decided outright by Step 2**, and the trips
kicker branch is unreachable. It is specified anyway so the rule is total.

## 7. True ties — LOCKED

- A **true tie** is two or more hands whose complete rank comparison under §6 is
  identical.
- **Suits cannot break a tie.** Nothing breaks a tie.
- All money is **integer only**. There are no fractional units anywhere in the
  game.
- Tied winners **split the highest bet amount of the round equally**.
- If the amount does not divide evenly, the remainder goes to the tied player
  who comes **first in the current turn order**.

### Examples

- Highest bet 10,000, two tied winners: 5,000 each.
- Highest bet 10,000, three tied winners: 10,000 = 3 x 3,333 + 1, so the tied
  player earliest in turn order receives 3,334 and the other two receive 3,333.

### Possible tie sizes

Bounded by the four suits per rank:

| Type | Maximum players in a tie |
|---|---|
| Four of a kind | cannot tie |
| Three of a kind | cannot tie |
| Two pairs | 2 |
| One pair | 2 |
| No matching cards | 4 |

So a split is 2-, 3- or 4-way, and only the bottom two types can produce one.

## 8. Sharah (negotiation) — PARTIALLY LOCKED

Locked:

- Sharah is **purely economic**. It has no effect on card strength, on
  classification or comparison under §6, or on who would have won the showdown.
- One player offers another player money to **leave the round** instead of
  continuing to the showdown.
- A player who **accepts** exits the round: they take no part in the showdown,
  and **their cards stay hidden permanently** — the table never learns what they
  held or whether the buy-out was a bargain.

Sharah is therefore a way to remove an opponent without beating them, and a way
to be paid for a hand you would rather not play.

Open — see §11.

## 9. Round settlement — LOCKED

**There is no pot.** The winner's gain and each loser's loss are independent
quantities that are never derived from one another.

- The **winner** receives **only the highest bet amount placed by any player in
  the round**, regardless of what the winner themselves bet.
- Each **losing player** loses **exactly the amount they personally bet**, and
  no more.
- The losers' bets are **not** summed and awarded to the winner. Do not
  redistribute them.
- With multiple tied winners, only the highest bet amount is split between them,
  per §7.

### Worked example

| Player | Bet |
|---|---|
| A | 3,000 |
| B | 1,000 |
| C | 4,000 |
| D | 10,000 |

Player A wins the showdown:

- A gains **+10,000** (the highest bet in the round — D's — not A's own 3,000).
- B loses **1,000**.
- C loses **4,000**.
- D loses **10,000**.

### Recorded consequence: the coin supply is not conserved

This rule is deliberately not zero-sum, and it drifts in both directions:

- In the example above, 15,000 leaves the losers and 10,000 reaches the winner,
  so 5,000 is destroyed.
- Heads-up, where the winner bet 10,000 and the loser bet 100, the winner gains
  10,000 while only 100 is paid, so 9,900 is created.

This is intended and must be implemented as written. It is recorded here because
anything later built on a conserved supply — elimination thresholds, a stable
buy-in, long-session balance — has to account for the drift. The existing
engine's `.conserving` payout mode is the wrong model for this game and is
removed.

## 10. Elimination — CONCEPT ONLY, NOT LOCKED

Losses persist between rounds and a player who runs out of money leaves the
game. The exact threshold and the end-of-game condition are open — see §11.

## 11. Open — nothing may be built on these yet

1. **Betting structure.** How many betting rounds; the enter/withdraw/raise
   sequence; minimum bet and increment; whether a raise must exceed the standing
   bet; how a player short of the standing bet is handled; turn order and how it
   rotates.
2. **Sharah procedure.** Who may offer to whom (only to the top bettor, or any
   player to any player); whether offers are public or private; whether they are
   binding once sent; whether more than one offer may be open at a time; when in
   the round Sharah may happen.
3. **Sharah payment.** Whether money moves on acceptance or conditionally on the
   payer's result, and in which direction.
4. **The top bettor exiting via Sharah.** Settlement in §9 keys off "the highest
   bet made by any player in the round." If the player who made that bet has
   left via Sharah, is the figure still their bet, or the highest among the
   players who actually reach the showdown? This changes payouts directly.
5. **Elimination and game end.** Out at zero, or at "cannot cover the minimum
   bet"? Does play continue until one player remains, or for a fixed number of
   rounds?
6. **Multiplayer model.** One device with AI opponents, as the old project was,
   or networked play. This decides whether §4's privacy guarantee is enforced by
   the UI alone or has to hold across a wire.

## 12. Effect on the existing code

`Sources/Engine/` implements the superseded rules and conflicts with this
specification throughout. Known changes required:

| File | Change |
|---|---|
| `Card.swift` | 13 ranks, not 4; a 52-card deck, not 16 |
| `Hand.swift` | additive scoring removed; replaced by §5 classification and §6 type-then-rank comparison |
| `Player.swift` | up to 13 seats, not exactly 4 |
| `GameRules.swift` | `.conserving` payout removed; settlement per §9 |
| `GameEngine.swift` | tie resolution per §7; settlement per §9; elimination once §11.5 is settled |
| `AIStrategy.swift` | must bluff. Sizing a bet by hand strength makes every AI bet honest and therefore readable, which contradicts §1.3 — bet size carries no information and the engine must never treat it as a proxy for strength |

