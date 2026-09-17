import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var chatGPT: ChatGPTCodexClient
    @StateObject private var game: TriviaGameController
    @State private var showSettings = false
    @State private var smartRentEmail = ""
    @State private var smartRentPassword = ""
    @State private var smartRentStatus = ""
    @State private var isUnlocking = false

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
            .sheet(isPresented: $showSettings) {
                settingsSheet
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

            VStack(alignment: .leading, spacing: 2) {
                Text("LITTLE//RIP")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(silver)
                Text("LUNA • FIRST PRINCIPLES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(eyeGreen.opacity(0.9))
            }

            Spacer(minLength: 8)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(silver)
                    .frame(width: 38, height: 38)
                    .background(panel, in: Circle())
                    .overlay(Circle().stroke(silver.opacity(0.26), lineWidth: 1))
            }
            .accessibilityLabel("SmartRent unlock and settings")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(silver)
                    .frame(width: 38, height: 38)
                    .background(panel, in: Circle())
                    .overlay(Circle().stroke(silver.opacity(0.26), lineWidth: 1))
            }
            .accessibilityLabel("Settings")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch game.phase {
        case .idle:
            welcomeCard
        case .generating:
            generationCard
        case .answering:
            activeGame
        case .feedback:
            activeGame
        case .gameOver:
            gameOverCard
        case .error:
            errorCard
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("THE FIRST PRINCIPLES RUN")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(eyeGreen)
                Text("Think from what is true.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("A progressive physics + math gauntlet generated by Luna. Start with one tiny idea, then follow it toward energy, probability, geometry, information, and fundamental equations.")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                tag("PHYSICS")
                tag("MATH")
                tag("4 CHOICES")
            }

            Button {
                game.startNewGame()
            } label: {
                HStack {
                    Text("New Game")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .frame(height: 58)
                .background(eyeGreen, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: eyeGreen.opacity(0.34), radius: 18, y: 7)
            }
            .accessibilityIdentifier("new-game-button")

            HStack(spacing: 7) {
                Image(systemName: "bolt.horizontal.circle")
                Text("Correct answers compound your score. One miss ends the run.")
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(silverDim)

            if game.bestScore > 0 {
                bestScoreLine
            }
        }
        .padding(22)
        .background(panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(silver.opacity(0.16), lineWidth: 1))
    }

    private var generationCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(silver.opacity(0.18), lineWidth: 2)
                    .frame(width: 84, height: 84)
                Circle()
                    .trim(from: 0.08, to: 0.78)
                    .stroke(eyeGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 84, height: 84)
                    .rotationEffect(.degrees(-90))
                Image("RobotMinerIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(spacing: 6) {
                Text("LUNA IS THINKING")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(eyeGreen)
                Text("Building a \(game.difficulty.title.lowercased()) question")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("No timer runs while a question is being generated.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(eyeGreen.opacity(0.20), lineWidth: 1))
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
                rewardLine
            }

            Text("AI-generated educational content • verify surprising claims independently")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
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
                    Text("ROUND \(String(format: "%02d", game.answeredCount + 1))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(silverDim)
                    Text(game.difficulty.title.uppercased())
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
                Label("LUNA PROMPT", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(eyeGreen)
                Spacer()
                Text("\(game.difficulty.title)")
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
                Text("The next question is loading…")
                    .foregroundStyle(.white.opacity(0.62))
            }
            explanationContent
        }
        .padding(16)
        .background(eyeGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(eyeGreen.opacity(0.32), lineWidth: 1))
    }

    private var rewardLine: some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
            Text("NEXT REWARD")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(silverDim)
            Text("+\(game.nextReward)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text("Keep the chain alive")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(.horizontal, 5)
    }

    private var gameOverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            scoreHUDWithoutTimer

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

    private var scoreHUDWithoutTimer: some View {
        HStack(spacing: 8) {
            statBlock(label: "SCORE", value: formatScore(game.score))
            statBlock(label: "BEST", value: formatScore(game.bestScore))
            statBlock(label: "ANSWERED", value: "\(game.answeredCount)")
        }
    }

    private var explanationContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("WHY IT WORKS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(silverDim)
            if let question = game.currentQuestion {
                Text(question.explanation)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                Text(question.implication)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(eyeGreen.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("QUESTION UNAVAILABLE", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.orange)
            Text(game.errorMessage ?? "LittleRip could not load a question.")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("This was not a wrong answer. Your score and best score are safe; retry when the connection or response is ready.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Button {
                game.retryGeneration()
            } label: {
                HStack {
                    Text("Retry Question")
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .background(eyeGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(20)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    private var bestScoreLine: some View {
        HStack {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.orange)
            Text("Best run")
                .foregroundStyle(silverDim)
            Spacer()
            Text(formatScore(game.bestScore))
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .font(.system(size: 14, design: .rounded))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(silver)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(silver.opacity(0.09), in: Capsule())
            .overlay(Capsule().stroke(silver.opacity(0.22), lineWidth: 1))
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

    private var settingsSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [darkBackground, Color(red: 0.08, green: 0.095, blue: 0.10), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        settingsSectionTitle("LUNA CONNECTION")
                        Text(chatGPT.isAuthenticated
                             ? "Connected to your authenticated ChatGPT account. LittleRip uses GPT-5.6 Luna for new game questions."
                             : "Connect your authenticated ChatGPT account to generate new game questions with GPT-5.6 Luna.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)

                        if chatGPT.isAuthenticated {
                            HStack {
                                Label("Authenticated", systemImage: "checkmark.shield.fill")
                                    .foregroundStyle(eyeGreen)
                                Spacer()
                                Button("Sign Out") { chatGPT.signOut() }
                                    .buttonStyle(.bordered)
                                    .tint(silver)
                            }
                        } else {
                            Button(chatGPT.isSigningIn ? "Connecting…" : "Connect ChatGPT") {
                                chatGPT.startLogin()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(eyeGreen)
                            .disabled(chatGPT.isSigningIn)

                            if let code = chatGPT.deviceCode {
                                Text("Enter code: \(code)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(eyeGreen)
                            }
                        }

                        if let error = chatGPT.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.9))
                        }

                        Divider().overlay(silver.opacity(0.18))
                        settingsSectionTitle("SMARTRENT FRONT DOOR")
                        Text("Credentials stay in the LittleRip App Group on this device. The door widget remains available for one-tap unlock without opening the app.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.white.opacity(0.63))
                            .fixedSize(horizontal: false, vertical: true)

                        TextField("SmartRent email", text: $smartRentEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textFieldStyle(.roundedBorder)
                        SecureField("SmartRent password", text: $smartRentPassword)
                            .textFieldStyle(.roundedBorder)

                        Button("Save SmartRent credentials") {
                            SmartRentClient.saveCredentials(email: smartRentEmail, password: smartRentPassword)
                            smartRentStatus = "Credentials saved on this device."
                        }
                        .buttonStyle(.bordered)
                        .tint(silver)
                        .disabled(smartRentEmail.isEmpty || smartRentPassword.isEmpty)

                        Button {
                            unlockFrontDoor()
                        } label: {
                            HStack {
                                Image(systemName: isUnlocking ? "hourglass" : "lock.open.fill")
                                Text(isUnlocking ? "Unlocking…" : "Unlock Front Door")
                                Spacer()
                            }
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(eyeGreen)
                        .disabled(isUnlocking || smartRentEmail.isEmpty || smartRentPassword.isEmpty)

                        if !smartRentStatus.isEmpty {
                            Text(smartRentStatus)
                                .font(.footnote)
                                .foregroundStyle(smartRentStatus.contains("failed") ? .red : eyeGreen)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadSmartRentCredentials)
        }
        .presentationDetents([.medium, .large])
    }

    private func settingsSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(eyeGreen)
    }

    private func loadSmartRentCredentials() {
        guard let credentials = try? SmartRentClient.loadCredentials() else { return }
        smartRentEmail = credentials.email
        smartRentPassword = credentials.password
    }

    private func unlockFrontDoor() {
        guard !isUnlocking else { return }
        isUnlocking = true
        smartRentStatus = "Unlocking…"
        let email = smartRentEmail
        let password = smartRentPassword
        Task {
            do {
                try await SmartRentClient(email: email, password: password).unlockFrontDoor()
                isUnlocking = false
                smartRentStatus = "Unlock sent."
            } catch {
                isUnlocking = false
                smartRentStatus = "Unlock failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ContentView()
}
