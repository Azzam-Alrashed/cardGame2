import Foundation

/// The game's constants, in one place (SPEC.md §2, §3, §5, §6, §13).
public enum GameRules {
    /// Cards per player.
    public static let handSize = 4
    /// 13 x 4 = 52, so thirteen is the ceiling one deck allows.
    public static let maxPlayers = Deck.all.count / handSize
    /// A round needs an opponent.
    public static let minPlayers = 2

    /// What every player starts the game with.
    public static let startingBalance = 5_000
    /// The smallest bet that enters a round.
    public static let minimumBet = 500
    /// Every bet is a whole number of these. An all-in is the exception: it is
    /// whatever the player has left.
    public static let betUnit = 500
    /// A raise is one of these over the amount required to stay in.
    public static let raiseSteps = [500, 1_000]
    /// Reach this and the game is won.
    public static let targetBalance = 100_000

    /// Seats for `count` players, left to right.
    ///
    /// Seat indices run **right to left** round the table: the player at seat
    /// `i + 1` sits to the right of the player at seat `i`, and seat 0 sits to
    /// the right of the last seat. That is the direction cards are dealt
    /// (SPEC.md §2) and the direction turns move in, so one order serves both.
    public static func seats(for count: Int) -> [Seat] {
        precondition(
            count >= 1 && count <= maxPlayers,
            "a table holds 1...\(maxPlayers) players, got \(count)"
        )
        return (0..<count).map(Seat.init)
    }

    /// `seats` rotated so `start` comes first, then each seat to its right in
    /// turn. Seats not in the list are ignored.
    public static func turnOrder(seats: [Seat], startingAt start: Seat) -> [Seat] {
        let ordered = seats.sorted()
        guard let index = ordered.firstIndex(of: start) else { return ordered }
        return (0..<ordered.count).map { ordered[($0 + index) % ordered.count] }
    }

    /// The seat that starts the next round: the first active seat to the right
    /// of the one that started the last one, wrapping round the table.
    ///
    /// Taken from the previous *seat* rather than a round counter, so that an
    /// elimination cannot send the deal backwards — the start always moves on
    /// round the table, which is what "rotates one seat per round" says.
    public static func nextStartingSeat(after previous: Seat?, among seats: [Seat]) -> Seat? {
        let ordered = seats.sorted()
        guard let first = ordered.first else { return nil }
        guard let previous else { return first }
        return ordered.first { $0 > previous } ?? first
    }
}
