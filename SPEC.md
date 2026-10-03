# Game Specification

Authoritative rules for the game. The engine in `Sources/Engine/` implements
this document; where code and this document disagree, this document wins.

Status key: **LOCKED** rules are settled and the implementation matches them
exactly. **OPEN** items are not specified and nothing is built on a guess about
them — where an engine cannot avoid taking a position, the position is isolated
in a policy type and marked here.

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
  that four physical copies of each rank exist, and so the art knows which card
  to draw.
- There are no flushes and no straights. Those concepts do not exist in this
  game and must not be introduced.

*Implemented by `Card.swift`. `Suit` is deliberately not `Comparable` and holds
no strength value, so no comparison can reach for one.*

## 3. Players and dealing — LOCKED

- Each active player receives **exactly 4 cards**, dealt once.
- No draws, no discards, no swaps, no community cards.
- 4 cards x 13 players = 52, so **13 players is the hard ceiling**.
- With fewer than 13 players the undealt cards remain in the deck, unseen and
  unused for the round.
- Cards are dealt **one at a time, right to left**: the round's starting player
  takes the first card, then the player to their right, four times round.
- The starting position rotates one seat per round.

**Seat convention.** Seat indices run right to left: the player at seat `i + 1`
sits to the right of the player at seat `i`, and the last seat sits to the right
of seat 0. The same order serves the deal and the betting turns, so a round has
one turn order and nothing has to reconcile two.

*Implemented by `GameRules.seats(for:)`, `GameRules.turnOrder(seats:startingAt:)`
and `GameEngine.startRound()`.*

## 4. Information rules — LOCKED

- A hand is private to its owner for the entire round.
- No player may see another player's cards before the final reveal. No peeking,
  no partial reveals, no showing a single card.
- Cards become public only at the showdown, and only for players who reach it.
- A player who leaves by folding or by accepting a Sharah offer **never reveals
  their cards**, in any phase, ever.
- No UI, AI, log or network state may expose a hidden hand.

*Enforced structurally: the engine's participation table is private, a hand is
read through `GameEngine.hand(of:asSeenBy:)`, and an AI is handed only a
`PublicTableView`, whose opponent hands are nil until a reveal.*

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
- **No numeric hand score.** No 4000 / 3000 / 2400 / 2000 / 4400 table, and no
  single sortable number standing in for a hand. Comparison is type first, then
  rank, and the comparator is the authority.

### Reachability notes

With a single deck, two players can never hold the same quad rank (8 cards of
one rank required) or the same trip rank (6 required). **Four of a kind and
three of a kind are therefore always decided outright by Step 2**, and the trips
kicker branch is unreachable. It is specified and implemented anyway so the
comparator is total.

*Implemented by `HandEvaluator` (classification and comparison key) and
`HandComparator` (the only comparison in the game). `Hand` deliberately does not
conform to `Comparable`, so nothing can sort hands behind the comparator's back.*

## 7. True ties — LOCKED

- A **true tie** is two or more hands whose complete rank comparison under §6 is
  identical.
- **Suits cannot break a tie.** Nothing breaks a tie.
- All money is **integer only**. There are no fractional units anywhere.
- Tied winners **split the highest bet of the round equally**, by integer
  division.
- The remainder goes to the tied player who comes **first in the current turn
  order**.
- The split applies only to the winners' reward. Every losing player still loses
  exactly their own bet.

### Examples

- Highest bet 10,000, two tied winners: 5,000 each.
- Highest bet 10,000, three tied winners: 3,334 to the one earliest in turn
  order, 3,333 to each of the others.

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

## 8. Money — LOCKED

- Every player starts the game with **5,000**.
- Money is **persistent between rounds** and always an **integer**.
- The **minimum bet is 500**.
- A player whose balance reaches **0** is **eliminated** and takes no further
  part in the game.
- The **target is 100,000**: the first player to reach or exceed it wins the
  game (§13).

**Not fully specified — see §15.3.** The rule covers a balance that reaches
zero *after a loss*. It does not say what happens to a zero balance that arrived
some other way, such as paying out a Sharah offer. Both readings are implemented
as `EliminationRule`; the engine has not been given a rule of its own.

## 9. Betting — LOCKED

Betting is **a single pass**. In turn order each player acts once, and when the
last player has acted the committed amounts are final. This is why players reach
a showdown holding unequal bets, as §11's worked example does, and why folding
costs nothing — a fold happens before any money is committed.

**500 is an increment, not a step limit.** A player may bet **any affordable
multiple of 500** at or above the amount required to stay in. Nothing caps an
ordinary bet by the number of players, by what the previous player bet, or by
anything else.

A player's options, where *required* is the standing bet, or 500 when nobody has
bet yet:

| Action | Amount | Legal when |
|---|---|---|
| Fold | nothing | always |
| Bet | any multiple of 500 from *required* up to the whole balance | balance ≥ that amount |
| All-in | the whole balance | balance > 0 |

- Valid amounts: 500, 1,000, 1,500, 2,000, 2,500, 3,000, 5,000, 10,000 …
- Invalid amounts: 1,100, 1,750, 2,300 — anything that is not a whole 500.
- A player with 12,000 may bet 10,000 and keep 2,000. A player with 20,000 may
  bet 10,000 and keep 10,000. Neither is an all-in.
- **A player does not need enough to match.** All-in is the one action that may
  commit less than the required amount, and the one amount exempt from the 500
  rule — a balance need not be a multiple of 500, since a tie remainder can
  leave an odd one. An all-in below the standing bet does not become the
  standing bet.
- An all-in that leaves an odd standing bet rounds the next player's minimum
  **up** to a whole 500, since every ordinary bet is one.
- An all-in player who loses reaches 0 and is eliminated.
- **Bet size is not evidence of strength.** A weak hand may bet aggressively; a
  strong hand may bet small. Nothing in the engine may treat a bet as a measure
  of a hand.

*Implemented by `Betting.swift`: `BetAction` (`fold` / `bet(Int)` / `allIn`),
`BetRange` and `BettingRules`. The range is arithmetic rather than a list, so a
large stack's hundreds of legal bets cost nothing to validate.*

## 10. Folding — LOCKED

A player who folds:

- commits nothing and loses nothing,
- takes no part in the showdown and cannot win the round,
- does not reveal their cards, now or later.

## 11. Round settlement — LOCKED

**There is no pot.** The winner's gain and each loser's loss are independent
quantities that are never derived from one another.

- The **winner** receives **only the highest bet amount placed by any player in
  the round**, regardless of what the winner themselves bet, and without their
  own bet being deducted.
- Each **losing player** loses **exactly the amount they personally bet**, and
  no more.
- The losers' bets are **not** summed and awarded to the winner.
- With multiple tied winners, only the highest bet is split between them, per §7.
- The highest bet of the round counts **whoever placed it, and whether or not
  they are still in the round at the showdown** — so buying out the top bettor
  (§12) does not shrink the prize.

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

### Recorded consequence: the money supply is not conserved

This rule is deliberately not zero-sum, and it drifts in both directions:

- In the example above, 15,000 leaves the losers and 10,000 reaches the winner,
  so 5,000 is destroyed.
- Heads-up, where the winner bet 10,000 and the loser bet 100, the winner gains
  10,000 while only 100 is paid, so 9,900 is created.

This is intended and implemented as written. It is recorded because anything
built on a conserved supply — elimination thresholds, a stable buy-in,
long-session balance — has to account for the drift.

*Implemented by `Settlement.swift`, as a pure function of the showdown and the
round's bets.*

## 12. Sharah (negotiation) — LOCKED, except §14.1

Sharah is a separate economic mechanic. It does **not** change hand strength,
hand ranking, the comparison in §6, or who would have won the showdown, and it
never reveals a card.

When a player offers another money to leave the round and the offer is
**accepted**:

- the accepter **immediately receives** the amount, and the offerer's balance is
  **immediately reduced** by it,
- the accepter **leaves the round at once** and takes no part in the showdown,
- the accepter's **cards stay completely private**, for ever,
- the accepter's **existing bet is not deducted and not lost** — and not
  refunded either; it simply stays out of settlement,
- the payment is **not a bet**: it does not count toward the round's highest bet,
- the accepter **cannot return** to the round.

A **rejected** offer changes nothing at all.

### Worked example

A bet 1,000. B bet 10,000. B offers A 3,000 and A accepts:

- A receives **+3,000** and does **not** lose their 1,000 bet.
- B's balance falls by **3,000**.
- A leaves the round; A's cards are never seen.

**Not specified — see §15.2.** Where the payment comes from when some of the
payer's balance is already committed to the round is open. Both readings are
implemented as `SharahFunding`; neither is authoritative.

*Implemented by `Sharah.swift` and `GameEngine.offerSharah` /
`respondToSharah`. The rules §15.1 leaves open live in `SharahPolicy`, with
permissive defaults, so pinning one later is a change to that type alone.*

## 13. Game end — LOCKED

After each round, in order:

1. Apply settlement (§11).
2. Apply elimination — anyone on 0 is out (§8).
3. If any player has reached 100,000, the game ends and that player wins.
4. Otherwise deal the next round, if at least two active players remain.

**Not specified — see §15.4.** A tie split can carry two players over the
target in the same round, which this rule does not cover. Both readings are
implemented as `TargetTieBreak`; neither is authoritative.

## 14. Round flow — LOCKED

The game is a state machine, and every action belongs to exactly one state.
Anything out of state is rejected: no betting after the showdown, no Sharah once
the round is over, no second deal, no access to a hidden hand.

| State | What happens | Actions accepted |
|---|---|---|
| `WAITING_FOR_PLAYERS` | no round in progress | `startRound` |
| `DEALING` | four cards each, one at a time, right to left | `finishDealing` |
| `PRIVATE_HAND` | everyone has seen their own cards | `beginBetting` |
| `BETTING` | one pass round the table | fold, bet any legal amount, all-in |
| `SHARAH` | bets are final; players may offer each other money to leave | offer, accept, reject, `closeNegotiation` |
| `SHOWDOWN` | remaining hands face up; no money has moved | `settle` |
| `SETTLEMENT` | the round's money moves | `checkGameEnd` |
| `NEXT_ROUND` | round complete | `startRound` |
| `GAME_OVER` | someone reached the target | nothing |

*Implemented by `GamePhase` in `GameState.swift`; `GameEngine.endRound()` runs
the last three steps in one call for a caller that does not need to stop.*

## 15. Open — nothing is built on these

Each of these is a rule the specification does not settle. None of them is
decided in the engine: they are fields on `GamePolicy`, with the default noted,
and the default is a starting point rather than a ruling.

1. **Sharah procedure.** Who may offer to whom (only the top bettor, or any
   player to any player); whether offers are public or private; whether several
   may be open at once; whether an offer may be changed or withdrawn; when in
   the round Sharah may happen.
   *`SharahPolicy` — default: any player in the round may offer any other, any
   number of times, during the `SHARAH` state, with offers public.*
2. **Where a Sharah payment comes from.** A player's bet is at risk until
   settlement, so it is not obvious whether it may also be promised as a
   payment. Capping the offer at the uncommitted balance leaves an all-in player
   unable to buy anyone out; allowing the whole balance lets a payer who then
   loses their bet finish the round below zero.
   *`SharahFunding` — default: `availableBalanceOnly`.*
3. **Which zero balances eliminate.** §8 covers a zero reached by losing. A
   zero reached by paying out a Sharah offer is not covered.
   *`EliminationRule` — default: `anyZeroBalanceAtRoundEnd`.*
4. **Two players crossing the target at once.** A tie split can do it; §13 names
   only "the first" to reach 100,000.
   *`TargetTieBreak` — default: `largerBalance`, then turn order.*
5. **Multiplayer model.** One device with AI opponents, as built, or networked
   play. This decides whether §4's privacy guarantee is enforced by one process
   or has to hold across a wire.
6. **Table size in play.** The engine seats 2–13. The shipped table seats four.

## 16. Module map

| Module | Responsibility |
|---|---|
| `Card.swift` | `Rank`, `Suit`, `Card`, the 52-card `Deck` |
| `HandEvaluator.swift` | `Combination`, the comparison key, classification |
| `HandComparator.swift` | the only comparison of two hands, and tie detection |
| `Hand.swift` | four cards plus their ranking |
| `Player.swift` | `Seat`, `PlayerID`, `Player`, round standing |
| `GameRules.swift` | constants, seats, turn order |
| `Betting.swift` | `BetRange`, legal actions and amounts |
| `Policy.swift` | every rule §15 leaves open, as configuration |
| `Sharah.swift` | offers, and the policy knobs §15.1 still owns |
| `Settlement.swift` | the money, elimination, the target |
| `GameState.swift` | phases, and what one player may know about another |
| `GameEngine.swift` | the state machine that sequences all of the above |
| `AIStrategy.swift` | opponents that decide from public information only |
