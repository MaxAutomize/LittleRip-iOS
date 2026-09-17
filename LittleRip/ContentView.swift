import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var chatGPT: ChatGPTCodexClient
    @StateObject private var game: TriviaGameController

    private let silver = Color(red: 0.84, green: 0.87, blue: 0.88)
    private let silverDim = Color(red: 0.43, green: 0.47, blue: 0.48)
    private let eyeGreen = Color(red: 0.58, green: 1.0, blue: 0.26)
    private let darkBackground = Color(red: 0.012, green: 0.015, blue: 0.017)
    private let panel = Color.white.opacity(0.075)

    init() {
        let client = ChatGPTCodexClient()
        _chatGPT = StateObject(wrappedValue: client)
        _game = StateObject(wrappedValue: TriviaGameController(provider: client))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                gameBackground

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        content
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .task {
                chatGPT.resumeLoginIfNeeded()
                startGameFromWidgetIfRequested()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    game.reconcileTimer()
                    startGameFromWidgetIfRequested()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var gameBackground: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [darkBackground, Color(red: 0.06, green: 0.075, blue: 0.08), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Canvas { context, size in
                    let spacing: CGFloat = 32
                    var grid = Path()
                    for x in stride(from: 0, through: size.width, by: spacing) {
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: 0, through: size.height, by: spacing) {
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(silver.opacity(0.035)), lineWidth: 0.6)
                }

                Circle()
                    .fill(eyeGreen.opacity(0.09))
                    .frame(width: min(proxy.size.width, 420), height: min(proxy.size.width, 420))
                    .blur(radius: 70)
                    .offset(x: proxy.size.width * 0.38, y: -proxy.size.height * 0.36)
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("RobotMinerIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(silver.opacity(0.45), lineWidth: 1))
                .shadow(color: eyeGreen.opacity(0.18), radius: 14)

            Text("LITTLE//RIP")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(silver)

            Spacer(minLength: 8)

            Button {
                game.returnToHome()
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(silver)
                    .frame(width: 42, height: 42)
                    .background(panel, in: Circle())
                    .overlay(Circle().stroke(silver.opacity(0.30), lineWidth: 1))
            }
            .accessibilityLabel("Back to menu")
            .accessibilityHint("Abandons the current game")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch game.phase {
        case .idle:
            homeCard
        case .generating:
            loadingCard
        case .answering, .feedback:
            activeGame
        case .gameOver:
            gameOverCard
        case .error:
            errorCard
        }
    }

    private var homeCard: some View {
        VStack(spacing: 20) {
            Image("RobotMinerIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(silver.opacity(0.42), lineWidth: 1))
                .shadow(color: eyeGreen.opacity(0.20), radius: 24)

            Button {
                game.startNewGame()
            } label: {
                HStack {
                    Text("New Game")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .frame(height: 58)
                .background(eyeGreen, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: eyeGreen.opacity(0.34), radius: 18, y: 7)
            }
            .accessibilityIdentifier("new-game-button")

            HStack {
                Text("BEST")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(silverDim)
                Spacer()
                Text(formatScore(game.bestScore))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 5)
        }
        .padding(22)
        .background(panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(silver.opacity(0.16), lineWidth: 1))
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(eyeGreen)
                .scaleEffect(1.35)
            Text("Loading question…")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 58)
        .background(panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(silver.opacity(0.14), lineWidth: 1))
    }

    private var activeGame: some View {
        VStack(alignment: .leading, spacing: 14) {
            scoreHUD
            questionCard

            if let question = game.currentQuestion {
                VStack(spacing: 10) {
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                        answerButton(index: index, choice: choice, question: question)
                    }
                }
            }

            if game.phase == .feedback {
                feedbackCard
            } else {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("NEXT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(silverDim)
                    Text("+\(game.nextReward)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(game.answeredCount) answered")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, 5)
            }
        }
    }

    private var scoreHUD: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                statBlock(label: "SCORE", value: formatScore(game.score))
                statBlock(label: "BEST", value: formatScore(game.bestScore))
                statBlock(label: "STREAK", value: "×\(game.streak)")
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("QUESTION \(String(format: "%02d", game.answeredCount + 1))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(silverDim)
                    Text("\(game.streak) IN A ROW")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                timerPill
            }
        }
    }

    private var timerPill: some View {
        let urgent = game.secondsRemaining <= 6
        return HStack(spacing: 6) {
            Image(systemName: urgent ? "hourglass.bottomhalf.filled" : "timer")
            Text("\(game.secondsRemaining)s")
                .monospacedDigit()
        }
        .font(.system(size: 17, weight: .bold, design: .rounded))
        .foregroundStyle(urgent ? .black : eyeGreen)
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(urgent ? Color.orange : eyeGreen.opacity(0.13), in: Capsule())
        .overlay(Capsule().stroke((urgent ? Color.orange : eyeGreen).opacity(0.7), lineWidth: 1))
        .accessibilityLabel("\(game.secondsRemaining) seconds remaining")
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(silverDim)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                if let concept = game.currentQuestion?.concept {
                    Text(concept.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(eyeGreen)
                        .lineLimit(1)
                }
                Spacer()
                Text("LIVE")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(silverDim)
            }

            if let prompt = game.currentQuestion?.prompt {
                Text(prompt)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.095), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(silver.opacity(0.20), lineWidth: 1))
    }

    private func answerButton(index: Int, choice: String, question: TriviaQuestion) -> some View {
        let showingResult = game.phase == .feedback || game.phase == .gameOver
        let isCorrect = index == question.correctIndex
        let isSelected = index == game.selectedAnswerIndex
        let tint: Color = showingResult && isCorrect
            ? eyeGreen
            : (showingResult && isSelected ? Color.red.opacity(0.9) : silver)

        return Button {
            game.chooseAnswer(at: index)
        } label: {
            HStack(spacing: 12) {
                Text(String(UnicodeScalar(65 + index)!))
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundStyle(showingResult && (isCorrect || isSelected) ? .black : eyeGreen)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(showingResult && (isCorrect || isSelected) ? 1 : 0.12), in: Circle())
                Text(choice)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if showingResult && isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(eyeGreen)
                } else if showingResult && isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.red.opacity(0.9))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(silverDim)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .background(
                showingResult && (isCorrect || isSelected)
                    ? tint.opacity(0.16)
                    : Color.white.opacity(0.065),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(showingResult && (isCorrect || isSelected) ? tint.opacity(0.8) : silver.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!game.isAnswering)
        .accessibilityLabel("Answer \(String(UnicodeScalar(65 + index)!)): \(choice)")
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .correct(let points) = game.lastResult {
                Label("CORRECT  +\(points)", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(eyeGreen)
            }
        }
        .padding(16)
        .background(eyeGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(eyeGreen.opacity(0.32), lineWidth: 1))
    }

    private var gameOverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                statBlock(label: "SCORE", value: formatScore(game.score))
                statBlock(label: "BEST", value: formatScore(game.bestScore))
                statBlock(label: "ANSWERED", value: "\(game.answeredCount)")
            }

            if let question = game.currentQuestion {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 8) {
                        Image(systemName: game.gameOverReason == .timeExpired ? "hourglass" : "xmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text(game.gameOverReason == .timeExpired ? "TIME EXPIRED" : "RUN ENDED")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(.orange)
                    }
                    Text(question.prompt)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Correct answer: \(question.correctAnswer)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(eyeGreen)
                    explanationContent
                }
                .padding(18)
                .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color.orange.opacity(0.34), lineWidth: 1))
            }

            Button {
                game.startNewGame()
            } label: {
                HStack {
                    Text("New Game")
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                }
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .frame(height: 56)
                .background(eyeGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: eyeGreen.opacity(0.3), radius: 16, y: 6)
            }
            .accessibilityIdentifier("new-game-button")
        }
    }

    private var explanationContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("EXPLANATION")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(silverDim)
            if let question = game.currentQuestion {
                Text(question.explanation)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Couldn’t load a question.")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if chatGPT.isAuthenticated {
                Button("Retry") {
                    game.retryGeneration()
                }
                .buttonStyle(.borderedProminent)
                .tint(eyeGreen)
            } else {
                Button(chatGPT.isSigningIn ? "Signing in…" : "Sign in") {
                    chatGPT.startLogin()
                }
                .buttonStyle(.borderedProminent)
                .tint(eyeGreen)
                .disabled(chatGPT.isSigningIn)
                if let code = chatGPT.deviceCode {
                    Text("Code: \(code)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(eyeGreen)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    private func formatScore(_ score: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: score), number: .decimal)
    }

    private func startGameFromWidgetIfRequested() {
        let defaults = UserDefaults(suiteName: "group.com.maxautomize.LittleRip")
        guard defaults?.bool(forKey: "littlerip.startNewGame") == true else { return }
        defaults?.removeObject(forKey: "littlerip.startNewGame")
        game.startNewGame()
    }
}

#Preview {
    ContentView()
}
