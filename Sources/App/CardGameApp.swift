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
    static let demo: [Player] = [
        Player(id: "A", name: "Azzam", avatarName: "image6", seat: .south, isHuman: true),
        Player(id: "B", name: "Ahmad", avatarName: "image1", seat: .east),
        Player(id: "C", name: "Omar", avatarName: "image5", seat: .north),
        Player(id: "D", name: "Ammar", avatarName: "image2", seat: .west),
    ]
}
