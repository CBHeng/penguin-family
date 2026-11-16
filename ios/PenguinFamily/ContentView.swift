import SwiftUI

struct ContentView: View {
    @State private var character = CharacterPackLibrary.loadFirst()
    @State private var behavior = PenguinBehavior()

    var body: some View {
        ZStack {
            // 草地色，和私有素材 repo 的預覽相同
            Color(red: 196 / 255, green: 224 / 255, blue: 170 / 255)
                .ignoresSafeArea()
            PenguinView(
                character: character,
                intent: behavior.intent,
                onTap: { behavior.handle(.ownerTapped) },
                onMotionFinished: { behavior.handle(.motionFinished) })
        }
    }
}

#Preview {
    ContentView()
}
