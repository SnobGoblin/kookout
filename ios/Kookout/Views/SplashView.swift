import SwiftUI

/// Splash D, alive: right after iOS's launch screen (the same picture, so it's seamless) the pupils look left, then
/// right, then back to looking out, and the app fades in. About 1.6 seconds; with Reduce Motion, just a fade.
struct SplashView: View {
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var look: CGFloat = 0     // pupils' offset from where they rest, in em

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            Image("SplashEyes")
                .frame(width: SplashGeometry.size.width, height: SplashGeometry.size.height)
                .overlay(alignment: .topLeading) {
                    ForEach(SplashGeometry.pupils.indices, id: \.self) { i in
                        Circle()
                            .fill(.white)
                            .frame(width: SplashGeometry.pupilSize, height: SplashGeometry.pupilSize)
                            .position(x: SplashGeometry.pupils[i].x + look * SplashGeometry.em, y: SplashGeometry.pupils[i].y)
                    }
                }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark) // a white clock and battery on the dark background
        .accessibilityHidden(true)
        .task {
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(.easeInOut(duration: 0.35)) { look = -0.18 } // look left
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeInOut(duration: 0.4)) { look = 0.02 }   // and right
                try? await Task.sleep(for: .milliseconds(550))
                withAnimation(.easeInOut(duration: 0.3)) { look = 0 }      // back to looking out
                try? await Task.sleep(for: .milliseconds(400))
            } else {
                try? await Task.sleep(for: .milliseconds(400))
            }
            done()
        }
    }
}
