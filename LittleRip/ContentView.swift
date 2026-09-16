import SwiftUI
import UIKit

struct SelectableTextView: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let color: UIColor
    var onTap: () -> Void = {}

    final class Coordinator: NSObject {
        let onTap: () -> Void
        var lastRenderedText: String?
        var lastFontSize: CGFloat = -1
        var lastColor: UIColor?

        init(onTap: @escaping () -> Void) { self.onTap = onTap }
        @objc func tapped() { onTap() }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byWordWrapping
        view.textContainer.widthTracksTextView = true
        view.dataDetectorTypes = [.link]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.lastRenderedText == text,
           coordinator.lastFontSize == fontSize,
           coordinator.lastColor?.isEqual(color) == true {
            return
        }

        let font = UIFont(name: "Times New Roman", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        view.attributedText = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        coordinator.lastRenderedText = text
        coordinator.lastFontSize = fontSize
        coordinator.lastColor = color
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 48
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

struct RobotProspectorLogo: View {
    var gold: Color
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.radialGradient(colors: [gold.opacity(0.28), .clear], center: .center, startRadius: 2, endRadius: size * 0.62))
                .frame(width: size * 1.35, height: size * 1.35)
                .blur(radius: 8)

            Canvas { ctx, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let metal = Color(red: 0.56, green: 0.62, blue: 0.63)
                let shadowMetal = Color(red: 0.28, green: 0.33, blue: 0.34)
                let neon = Color(red: 0.58, green: 1.0, blue: 0.26)
                let dark = Color(red: 0.08, green: 0.1, blue: 0.1)

                // Antenna
                var antenna = Path()
                antenna.move(to: CGPoint(x: w * 0.5, y: h * 0.08))
                antenna.addLine(to: CGPoint(x: w * 0.5, y: h * 0.0))
                ctx.stroke(antenna, with: .color(gold.opacity(0.8)), lineWidth: 3)

                // Futuristic helmet / head
                var head = Path()
                head.move(to: CGPoint(x: w * 0.19, y: h * 0.23))
                head.addQuadCurve(to: CGPoint(x: w * 0.52, y: h * 0.14), control: CGPoint(x: w * 0.32, y: h * 0.12))
                head.addQuadCurve(to: CGPoint(x: w * 0.86, y: h * 0.24), control: CGPoint(x: w * 0.72, y: h * 0.13))
                head.addLine(to: CGPoint(x: w * 0.80, y: h * 0.74))
                head.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.87), control: CGPoint(x: w * 0.70, y: h * 0.88))
                head.addQuadCurve(to: CGPoint(x: w * 0.20, y: h * 0.74), control: CGPoint(x: w * 0.30, y: h * 0.88))
                head.closeSubpath()
                ctx.fill(head, with: .linearGradient(Gradient(colors: [metal, shadowMetal]), startPoint: CGPoint(x: w * 0.35, y: h * 0.12), endPoint: CGPoint(x: w * 0.8, y: h * 0.88)))
                ctx.stroke(head, with: .color(dark.opacity(0.7)), lineWidth: 4)

                // Side plates like the reference image
                let leftPlate = Path(CGRect(x: w * 0.06, y: h * 0.34, width: w * 0.23, height: h * 0.09))
                let rightPlate = Path(CGRect(x: w * 0.73, y: h * 0.36, width: w * 0.21, height: h * 0.08))
                ctx.fill(leftPlate, with: .color(metal.opacity(0.85)))
                ctx.fill(rightPlate, with: .color(metal.opacity(0.85)))
                ctx.stroke(leftPlate, with: .color(dark.opacity(0.7)), lineWidth: 3)
                ctx.stroke(rightPlate, with: .color(dark.opacity(0.7)), lineWidth: 3)

                // Glowing eyes
                for x in [w * 0.31, w * 0.70] {
                    let eyeOuter = CGRect(x: x - w * 0.105, y: h * 0.42, width: w * 0.21, height: w * 0.21)
                    ctx.fill(Path(ellipseIn: eyeOuter.insetBy(dx: -4, dy: -4)), with: .color(neon.opacity(0.18)))
                    ctx.fill(Path(ellipseIn: eyeOuter), with: .color(dark))
                    ctx.stroke(Path(ellipseIn: eyeOuter), with: .color(gold.opacity(0.8)), lineWidth: 3)
                    ctx.fill(Path(ellipseIn: eyeOuter.insetBy(dx: w * 0.035, dy: w * 0.035)), with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), neon]), center: CGPoint(x: x, y: h * 0.525), startRadius: 1, endRadius: w * 0.07))
                }

                // Mouth slot
                let mouth = CGRect(x: w * 0.45, y: h * 0.64, width: w * 0.12, height: h * 0.035)
                ctx.fill(Path(roundedRect: mouth, cornerRadius: 2), with: .color(dark.opacity(0.85)))

                // Gold grille / teeth
                for i in 0..<7 {
                    let x = w * 0.28 + CGFloat(i) * w * 0.07
                    let grille = CGRect(x: x, y: h * 0.73, width: w * 0.025, height: h * 0.13)
                    ctx.fill(Path(roundedRect: grille, cornerRadius: 2), with: .color(gold))
                    ctx.stroke(Path(roundedRect: grille, cornerRadius: 2), with: .color(dark.opacity(0.55)), lineWidth: 1)
                }

                // Small bolt arms
                for side in [w * 0.1, w * 0.9] {
                    var bolt = Path()
                    bolt.move(to: CGPoint(x: side, y: h * 0.78))
                    bolt.addLine(to: CGPoint(x: side + (side < w * 0.5 ? -w * 0.08 : w * 0.08), y: h * 0.84))
                    ctx.stroke(bolt, with: .color(gold.opacity(0.75)), lineWidth: 3)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

enum ConversationMode {
    case normal
    case research
}

struct Message: Identifiable {
    let id = UUID()
    let role: Role
    let mode: ConversationMode
    let text: String
    let thinking: String
    let sources: [WebSearchResult]
    let hasImage: Bool
    let image: UIImage?

    enum Role {
        case user
        case assistant
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var voice = VoiceInputManager()
    @StateObject private var chatGPT = ChatGPTCodexClient()
    @StateObject private var location = LocationService()
    @StateObject private var actions = AssistantActionService()
    @StateObject private var messageComposer = MessageComposeService()
    @State private var showSettings = false
    @State private var isAsking = false
    @State private var isSearching = false
    @State private var isLookingUp = false
    @State private var wikiResearchStatus = ""
    @State private var typedPrompt = ""
    @State private var messages: [Message] = []
    @State private var usedVoice = false
    @State private var lastQuestionId: UUID?
    @State private var questionScrollNonce = 0
    @State private var replyScrollNonce = 0
    @FocusState private var isFieldFocused: Bool
    @State private var searchMode = false

    private let gold = Color(red: 0.84, green: 0.87, blue: 0.88) // silver accent
    private let goldDim = Color(red: 0.34, green: 0.36, blue: 0.38) // dark silver
    private let eyeGreen = Color(red: 0.58, green: 1.0, blue: 0.26)
    private let darkBg = Color(red: 0.015, green: 0.016, blue: 0.018)

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [darkBg, Color(red: 0.09, green: 0.10, blue: 0.11), Color.black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissKeyboard() }

                VStack(spacing: 12) {
                    header
                    conversation
                    inputArea
                }
                .padding()
            }
            .task {
                chatGPT.resumeLoginIfNeeded()
                location.requestAccess()
                await voice.requestPermissions()
                startVoiceFromWidgetIfRequested()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    startVoiceFromWidgetIfRequested()
                }
            }
            .sheet(isPresented: $showSettings) {
                settingsSheet
            }
            .sheet(item: $messageComposer.draft, onDismiss: {
                messageComposer.cancelIfNeeded()
            }) { draft in
                LittleRipMessageComposer(draft: draft) { outcome in
                    messageComposer.finish(outcome)
                }
                .ignoresSafeArea()
            }
            .onChange(of: voice.isListening) { _, listening in
                if !listening && usedVoice {
                    usedVoice = false
                    let transcript = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !transcript.isEmpty && !isAsking {
                        typedPrompt = transcript
                        sendPrompt()
                    }
                }
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 5) {
                Image("RobotMinerIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.white.opacity(0.22), radius: 18)

                Text("LittleRip")
                    .font(.custom("Times New Roman", size: 34))
                    .foregroundColor(gold)

                Text(statusLabel)
                    .font(.custom("Times New Roman", size: 15))
                    .foregroundStyle(gold.opacity(0.5))
            }
            .offset(y: -8)
            .padding(.bottom, -8)
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }

            VStack(spacing: 5) {
                HStack {
                    Button {
                        guard !isAsking else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            searchMode.toggle()
                        }
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(searchMode ? Color.black : Color.white.opacity(0.95))
                            .frame(width: 36, height: 36)
                            .background(searchMode ? gold : Color.white.opacity(0.18), in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(gold.opacity(searchMode ? 0.75 : 0.35), lineWidth: 1)
                            )
                            .shadow(color: searchMode ? gold.opacity(0.6) : Color.black.opacity(0.35), radius: 8)
                    }
                    .accessibilityLabel("Wiki mode")

                    Spacer()

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.18), in: Circle())
                            .overlay(Circle().stroke(gold.opacity(0.35), lineWidth: 1))
                    }
                    .accessibilityLabel("ChatGPT settings")
                }
            }
        }
    }

    private func dismissKeyboard() {
        isFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func startVoiceFromWidgetIfRequested() {
        let defaults = UserDefaults(suiteName: "group.com.maxautomize.LittleRip")
        guard defaults?.bool(forKey: "littlerip.startVoice") == true else { return }
        defaults?.removeObject(forKey: "littlerip.startVoice")
        usedVoice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            voice.startListening()
        }
    }

    private var statusLabel: String {
        if voice.isListening { return "Listening" }
        if !wikiResearchStatus.isEmpty { return wikiResearchStatus }
        if isLookingUp { return "Looking it up" }
        if isSearching { return "Searching the web" }
        if isAsking { return "Thinking" }
        if searchMode { return "Searching, deep answers" }
        return "Ask anything, direct answers"
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        messageView(message)
                            .id(message.id)
                    }

                    if isSearching || isAsking {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(gold)
                            Text(statusLabel)
                                .foregroundStyle(gold.opacity(0.5))
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: questionScrollNonce) { _, _ in
                guard let questionId = lastQuestionId else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    proxy.scrollTo(questionId, anchor: .bottom)
                }
            }
            .onChange(of: replyScrollNonce) { _, _ in
                guard let questionId = lastQuestionId else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    proxy.scrollTo(questionId, anchor: .top)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
    }

    private func messageView(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 28)
                    VStack(alignment: .trailing, spacing: 6) {
                        if let img = message.image {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 133)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(gold.opacity(0.4), lineWidth: 1))
                        }

                        SelectableTextView(text: message.text, fontSize: 16, color: .white, onTap: dismissKeyboard)
                            .padding(12)
                            .background(goldDim.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    formattedAssistantText(message.text)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if !message.sources.isEmpty {
                        sourcesList(message.sources)
                    }

                }
            }
        }
    }

    private struct AssistantTextBlock: Identifiable {
        let id: Int
        let title: String?
        let body: String
    }

    private func assistantTextBlocks(from text: String) -> [AssistantTextBlock] {
        var blocks: [AssistantTextBlock] = []
        var title: String?
        var bodyLines: [String] = []

        func appendCurrentBlock() {
            let body = bodyLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard title != nil || !body.isEmpty else { return }
            blocks.append(AssistantTextBlock(id: blocks.count, title: title, body: body))
        }

        for line in text.components(separatedBy: .newlines) {
            if let header = headerInfo(for: line) {
                appendCurrentBlock()
                title = header.title
                bodyLines = header.body.isEmpty ? [] : [header.body]
            } else {
                bodyLines.append(line)
            }
        }
        appendCurrentBlock()
        return blocks
    }

    private func formattedAssistantText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(assistantTextBlocks(from: text)) { block in
                VStack(alignment: .leading, spacing: 3) {
                    if let title = block.title {
                        Text(title)
                            .font(.custom("Times New Roman", size: 18).bold())
                            .foregroundStyle(gold)
                            .textCase(.uppercase)
                            .tracking(1.2)
                    }

                    if !block.body.isEmpty {
                        SelectableTextView(text: block.body, fontSize: 16, color: UIColor.white.withAlphaComponent(0.92), onTap: dismissKeyboard)
                    }
                }
            }
        }
    }

    private func headerInfo(for line: String) -> (title: String, body: String)? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
        trimmed = trimmed.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "#")))
        trimmed = trimmed.replacingOccurrences(of: "^\\d+[.)]\\s*", with: "", options: .regularExpression)
        let upper = trimmed.uppercased()
        for title in ["REFINE", "VARIABLES", "EQUATION", "OPTIMIZE", "EVALUATION", "EXPLANATION", "SUMMARY", "IMPLICATION", "DEFINITION", "ANALOGY", "FIRST PRINCIPLES", "SOURCES", "SOURCE"] {
            if upper == title || upper == "\(title):" {
                return (title, "")
            }
            if upper.hasPrefix("\(title):") {
                let body = String(trimmed.dropFirst(title.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                return (title, body)
            }
        }
        return nil
    }

    private func sourcesList(_ sources: [WebSearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wikipedia articles")
                .font(.custom("Times New Roman", size: 17).bold())
                .foregroundStyle(gold)

            Text("Selected for this question, most useful first")
                .font(.custom("Times New Roman", size: 12))
                .foregroundStyle(.white.opacity(0.55))

            ForEach(Array(sources.prefix(6).enumerated()), id: \.element.id) { index, source in
                let destination = URL(string: source.url) ?? URL(string: "https://en.wikipedia.org")!
                VStack(alignment: .leading, spacing: 4) {
                    Link(destination: destination) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("\(index + 1).")
                                .foregroundStyle(gold.opacity(0.75))
                            Text(source.title)
                                .font(.custom("Times New Roman", size: 15).bold())
                                .foregroundStyle(.white.opacity(0.95))
                                .underline()
                        }
                    }

                    SelectableTextView(text: String(source.snippet.prefix(190)), fontSize: 12, color: UIColor.white.withAlphaComponent(0.64), onTap: dismissKeyboard)
                        .frame(maxHeight: 56)

                    Link(destination: destination) {
                        Label("Open on Wikipedia", systemImage: "arrow.up.right.square")
                            .font(.custom("Times New Roman", size: 12))
                            .foregroundStyle(gold.opacity(0.82))
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(12)
        .background(gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var inputArea: some View {
        VStack(spacing: 10) {
            if !voice.authorizationMessage.isEmpty {
                Text(voice.authorizationMessage)
                    .font(.custom("Times New Roman", size: 12))
                    .foregroundStyle(gold.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    dismissKeyboard()
                    if voice.isListening {
                        // Keeping usedVoice true lets the completion handler send the transcript.
                        voice.stopListening()
                    } else {
                        usedVoice = true
                        voice.startListening()
                    }
                } label: {
                    Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(voice.isListening ? Color.black : Color.white.opacity(0.95))
                        .frame(width: 44, height: 44)
                        .background(voice.isListening ? Color.red.opacity(0.9) : Color.white.opacity(0.18), in: Circle())
                        .overlay(Circle().stroke(gold.opacity(0.35), lineWidth: 1))
                }
                .accessibilityLabel(voice.isListening ? "Stop listening and send" : "Start voice input")

                TextField("Ask LittleRip", text: $typedPrompt, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .foregroundStyle(.white)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .submitLabel(.send)
                    .focused($isFieldFocused)
                    .onTapGesture {
                        usedVoice = false
                        isFieldFocused = true
                        if voice.isListening {
                            voice.stopListening()
                        }
                    }
                    .onSubmit {
                        usedVoice = false
                        sendPrompt()
                    }

                Button {
                    usedVoice = false
                    dismissKeyboard()
                    sendPrompt()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(canSend ? Color.black : Color.white.opacity(0.45))
                        .frame(width: 48, height: 48)
                        .background(canSend ? gold : gold.opacity(0.18), in: Circle())
                        .shadow(color: canSend ? gold.opacity(0.6) : .clear, radius: 12)
                }
                .disabled(!canSend)
            }
        }
    }

    private var canSend: Bool {
        !typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAsking
    }

    private var settingsSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [darkBg, Color(red: 0.09, green: 0.10, blue: 0.11), Color.black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    Text("GPT-5.6 Terra")
                        .font(.headline)
                        .foregroundStyle(gold)

                    Text(chatGPT.isAuthenticated ? "Connected to ChatGPT. Quick and Wiki use GPT-5.6 Terra." : "Connect ChatGPT to use GPT-5.6 Terra in every mode.")
                        .foregroundStyle(.white.opacity(0.8))

                    if chatGPT.isAuthenticated {
                        Button("Sign Out") { chatGPT.signOut() }
                            .buttonStyle(.bordered)
                    } else {
                        Button(chatGPT.isSigningIn ? "Connecting…" : "Connect ChatGPT") {
                            chatGPT.startLogin()
                        }
                        .disabled(chatGPT.isSigningIn)
                        .buttonStyle(.borderedProminent)
                        .tint(gold)

                        if let code = chatGPT.deviceCode {
                            Text("Enter code: \(code)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(gold)
                        }
                    }

                    if let error = chatGPT.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sendPrompt() {
        let prompt = typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty && !isAsking else { return }

        if voice.isListening {
            voice.stopListening()
            usedVoice = false
        }

        dismissKeyboard()
        let history = sessionContext()
        typedPrompt = ""

        let notificationIntent = actions.shouldPlanNotification(for: prompt)
        let requestMode: ConversationMode = searchMode && !notificationIntent ? .research : .normal
        let question = Message(role: .user, mode: requestMode, text: prompt, thinking: "", sources: [], hasImage: false, image: nil)
        lastQuestionId = question.id
        messages.append(question)
        questionScrollNonce += 1
        isAsking = true

        if notificationIntent {
            isSearching = false
            Task {
                let confirmation = await semanticActionResult(for: prompt, history: history)
                    ?? "I couldn’t understand that native action request. Tell me what to do and include any needed person, message, or time."
                await MainActor.run {
                    messages.append(Message(role: .assistant, mode: .normal, text: confirmation, thinking: "", sources: [], hasImage: false, image: nil))
                    isAsking = false
                    replyScrollNonce += 1
                }
            }
            return
        }

        if searchMode {
            isSearching = true
            wikiResearchStatus = "Understanding your question"

            Task {
                // Run the same hidden semantic action planner even in Wiki mode.
                // A notification request should never depend on trigger words or
                // accidentally turn into Wikipedia research.
                if let actionResult = await semanticActionResult(for: prompt, history: history) {
                    await MainActor.run {
                        messages.append(Message(role: .assistant, mode: .normal, text: actionResult, thinking: "", sources: [], hasImage: false, image: nil))
                        isSearching = false
                        wikiResearchStatus = ""
                        isAsking = false
                        replyScrollNonce += 1
                    }
                    return
                }

                // First use the reasoning model to understand the whole idea and
                // choose canonical article titles—not merely words in the prompt.
                let plannedTopics: [String]
                do {
                    plannedTopics = try await chatGPT.planWikipediaArticles(prompt: prompt, history: history)
                } catch {
                    plannedTopics = []
                }

                await MainActor.run {
                    wikiResearchStatus = plannedTopics.isEmpty
                        ? "Finding Wikipedia articles"
                        : "Reading selected Wikipedia articles"
                }
                let searchResults = await WebSearchClient.search(
                    prompt,
                    history: history,
                    plannedTopics: plannedTopics
                )
                await MainActor.run {
                    isSearching = false
                    wikiResearchStatus = "Writing from Wikipedia"
                }

                do {
                    let result = try await chatGPT.ask(prompt: prompt, history: history, mode: .wiki, sources: searchResults)
                    await MainActor.run {
                        messages.append(Message(role: .assistant, mode: .research, text: result.answer, thinking: result.thinking, sources: searchResults, hasImage: false, image: nil))
                        wikiResearchStatus = ""
                        isAsking = false
                        replyScrollNonce += 1
                    }
                } catch {
                    await MainActor.run {
                        messages.append(Message(role: .assistant, mode: .research, text: "Error: \(error.localizedDescription)", thinking: "", sources: [], hasImage: false, image: nil))
                        wikiResearchStatus = ""
                        isAsking = false
                        replyScrollNonce += 1
                    }
                }
            }
        } else {
            isSearching = false

            Task {
                do {
                    // Every non-keyword-matched prompt gets a semantic tool pass.
                    // If it resolves a notification action, return the native
                    // scheduler confirmation directly and skip normal chat.
                    if let actionResult = await semanticActionResult(for: prompt, history: history) {
                        await MainActor.run {
                            messages.append(Message(role: .assistant, mode: .normal, text: actionResult, thinking: "", sources: [], hasImage: false, image: nil))
                            isLookingUp = false
                            isAsking = false
                            replyScrollNonce += 1
                        }
                        return
                    }

                    let needsLookup = LiveLookupService.shouldLookup(prompt: prompt, history: history)
                    if needsLookup {
                        await MainActor.run { isLookingUp = true }
                    }
                    let lookupContext = await LiveLookupService.lookupContext(for: prompt, history: history, locationService: location)
                    await MainActor.run { isLookingUp = false }
                    let liveContext = lookupContext ?? ""
                    let result = try await chatGPT.ask(prompt: prompt, history: history, mode: .quick, liveLookupContext: liveContext.isEmpty ? nil : liveContext)
                    await MainActor.run {
                        messages.append(Message(role: .assistant, mode: .normal, text: result.answer, thinking: result.thinking, sources: [], hasImage: false, image: nil))
                        isLookingUp = false
                        isAsking = false
                        replyScrollNonce += 1
                    }
                } catch {
                    await MainActor.run {
                        messages.append(Message(role: .assistant, mode: .normal, text: "Error: \(error.localizedDescription)", thinking: "", sources: [], hasImage: false, image: nil))
                        isLookingUp = false
                        isAsking = false
                        replyScrollNonce += 1
                    }
                }
            }
        }
    }

    /// Uses the authenticated agent as a hidden tool planner. The visible model
    /// response never triggers an action: only a structured plan reaches the
    /// scheduler, and the returned text is the scheduler's post-success result.
    private func semanticActionResult(for prompt: String, history: String) async -> String? {
        let localPlan = actions.localPlan(for: prompt)
        let semanticPlan: AssistantActionPlan?
        switch localPlan {
        case .scheduleNotification, .composeMessage:
            semanticPlan = localPlan
        case .clarification, .none:
            semanticPlan = try? await chatGPT.planAssistantAction(prompt: prompt, history: history)
        }

        if case .composeMessage(let recipient, let body) = semanticPlan {
            return await messageComposer.compose(recipient: recipient, body: body)
        }
        return await actions.perform(for: prompt, semanticPlan: semanticPlan)
    }

    private func sessionContext() -> String {
        messages.suffix(12).map { message in
            let modeLabel: String
            switch message.mode {
            case .normal: modeLabel = "Normal Mode"
            case .research: modeLabel = "Deep Research"
            }

            switch message.role {
            case .user:
                let imageContext = message.hasImage ? ", included an image" : ""
                return "User [\(modeLabel)\(imageContext)]: \(message.text)"
            case .assistant:
                return "Assistant [\(modeLabel)]: \(message.text)"
            }
        }.joined(separator: "\n\n")
    }

}



#Preview {
    ContentView()
}