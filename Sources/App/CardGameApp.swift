import SwiftUI

@main
struct CardGameApp: App {
    var body: some Scene {
        WindowGroup {
            EngineProbeView()
        }
    }
}

/// A scaffold, not the game's UI. It plays the engine through a round so the
/// rules can be eyeballed on device while the real table view is still to come.
struct EngineProbeView: View {
    @State private var log: [String] = []

    var body: some View {
        NavigationStack {
            List(Array(log.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(.footnote, design: .monospaced))
            }
            .navigationTitle("Engine")
            .toolbar {
                Button("Play round") { playRound() }
            }
        }
        .onAppear { if log.isEmpty { playRound() } }
    }

    private func playRound() {
        var engine = GameEngine(players: Table.demo, seed: UInt64.random(in: 0...(.max)))
        var ai = AIStrategy()
        var lines: [String] = []

        do {
            try engine.startRound()

            while case .betting(let seat) = engine.phase {
                guard let player = engine.player(at: seat) else { break }
                let hand = engine.participation[player.id]!.hand
                switch ai.decideBet(hand: hand, range: engine.betRange(for: player.id)) {
                case .bet(let amount):
                    try engine.bet(amount, from: player.id)
                    lines.append("\(player.name) bets \(amount)")
                case .withdraw:
                    try engine.withdraw(player.id)
                    lines.append("\(player.name) withdraws")
                }
            }

            if case .negotiation = engine.phase {
                for id in engine.entrants where id != engine.topBettor {
                    let hand = engine.participation[id]!.hand
                    if let amount = ai.decideOffer(hand: hand, range: engine.offerRange(for: id)) {
                        try engine.submitOffer(amount, from: id)
                        lines.append("\(engine.players[id]!.name) offers \(amount)")
                    }
                }
                let outcome = try engine.endRound()
                for (id, hand) in outcome.revealedHands {
                    lines.append("\(engine.players[id]!.name): \(hand)")
                }
                if let winner = outcome.winner {
                    lines.append("→ \(engine.players[winner]!.name) takes \(outcome.pot)")
                }
            } else {
                lines.append("→ nobody entered the round")
            }
        } catch {
            lines.append("error: \(error)")
        }

        log = lines
    }
}

enum Table {
    static let demo: [Player] = [
        Player(id: "A", name: "Azzam", avatarName: "image6", seat: .south, isHuman: true),
        Player(id: "B", name: "Ahmad", avatarName: "image1", seat: .east),
        Player(id: "C", name: "Omar", avatarName: "image5", seat: .north),
        Player(id: "D", name: "Ammar", avatarName: "image2", seat: .west),
    ]
}
