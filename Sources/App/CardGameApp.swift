import SwiftUI

@main
struct CardGameApp: App {
    var body: some Scene {
        WindowGroup {
            GameTableView()
        }
    }
}

enum Table {
    /// A four-handed demo table. One deck seats up to `GameRules.maxPlayers`,
    /// so this is a choice of table size, not a limit of the engine.
    static let demo: [Player] = [
        Player(id: "A", name: "Azzam", avatarName: "image6", seat: Seat(0), isHuman: true),
        Player(id: "B", name: "Ahmad", avatarName: "image1", seat: Seat(1)),
        Player(id: "C", name: "Omar", avatarName: "image5", seat: Seat(2)),
        Player(id: "D", name: "Ammar", avatarName: "image2", seat: Seat(3)),
    ]
}
