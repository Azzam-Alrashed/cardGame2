import XCTest
@testable import CardGame

/// Builds a hand from ranks alone, handing out a different suit to each repeat
/// of a rank. Suits never matter to a comparison, so a test never has to name
/// one — which is itself the point.
func hand(_ ranks: Rank...) -> Hand {
    var seen: [Rank: Int] = [:]
    let cards = ranks.map { rank -> Card in
        let index = seen[rank, default: 0]
        seen[rank] = index + 1
        return Card(rank, Suit.allCases[index % Suit.allCases.count])
    }
    return Hand(cards: cards)
}

/// A table of `count` players, seats 0 upward, all on the same balance.
func table(_ count: Int, balance: Int = GameRules.startingBalance) -> [Player] {
    (0..<count).map { index in
        Player(
            id: PlayerID("P\(index)"),
            name: "P\(index)",
            seat: Seat(index),
            balance: balance,
            isHuman: index == 0
        )
    }
}

/// A table whose players start on different balances.
func table(balances: [Int]) -> [Player] {
    balances.enumerated().map { index, balance in
        Player(id: PlayerID("P\(index)"), name: "P\(index)", seat: Seat(index), balance: balance)
    }
}

/// One player's turn, for a test script.
enum BetScript {
    /// The cheapest legal bet that stays in the round.
    case stayIn
    case bet(Int)
    case allIn
    case fold
}

extension GameEngine {
    /// Deals and opens betting in one step, for tests that care about what
    /// happens after that.
    mutating func startBetting() throws {
        try startRound()
        try finishDealing()
        try beginBetting()
    }

    /// Plays one pass of betting from a script, in turn order.
    mutating func runBetting(_ script: [BetScript]) throws {
        for (id, step) in zip(turnOrder, script) {
            switch step {
            case .fold:
                try act(.fold, by: id)
            case .allIn:
                try act(.allIn, by: id)
            case .bet(let amount):
                try act(.bet(amount), by: id)
            case .stayIn:
                let balance = players[id]?.balance ?? 0
                let cheapest = BettingRules.cheapestWayToStayIn(standingBet: highestBet, balance: balance)
                try act(cheapest.map(BetAction.bet) ?? .allIn, by: id)
            }
        }
    }
}
