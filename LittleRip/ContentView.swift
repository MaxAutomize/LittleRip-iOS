import AVFAudio
import SwiftUI
import UIKit

struct SelectableTextView: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let color: UIColor
    var onTap: () -> Void = {}

    final class Coordinator: NSObject {
        let onTap: () -> Void
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
        view.text = text
        view.font = UIFont(name: "Times New Roman", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        view.textColor = color
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

struct Message: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let thinking: String
    let sources: [WebSearchResult]

    enum Role {
        case user
        case assistant
    }
}

struct ContentView: View {
    @StateObject private var voice = VoiceInputManager()
    @State private var showSettings = false
    @State private var ollamaURL = "https://ollama.com"
    @State private var ollamaModel = "glm-5.1"
    @State private var isAsking = false
    @State private var isSearching = false
    @State private var typedPrompt = ""
    @State private var messages: [Message] = []
    @State private var usedVoice = false
    @State private var lastQuestionId: UUID?
    @State private var questionScrollNonce = 0
    @State private var replyScrollNonce = 0
    @FocusState private var isFieldFocused: Bool
    private let synthesizer = AVSpeechSynthesizer()

    private let gold = Color(red: 0.84, green: 0.87, blue: 0.88) // silver accent
    private let goldDim = Color(red: 0.34, green: 0.36, blue: 0.38) // dark silver
    private let eyeGreen = Color(red: 0.58, green: 1.0, blue: 0.26)
    private let darkBg = Color(red: 0.015, green: 0.016, blue: 0.018)

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [darkBg, Color(red: 0.09, green: 0.10, blue: 0.11), Color.black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    header
                    conversation
                    inputArea
                }
                .padding()
            }
            .task {
                UserDefaults.standard.set("https://ollama.com", forKey: "ollama.url")
                UserDefaults.standard.set("glm-5.1", forKey: "ollama.model")
                await voice.requestPermissions()
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
        VStack(spacing: 8) {
            Image("RobotMinerIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 124, height: 124)
                .shadow(color: Color.white.opacity(0.22), radius: 18)

            Text("LittleRip")
                .font(.custom("Times New Roman", size: 34))
                .foregroundColor(gold)

            Text(statusLabel)
                .font(.custom("Times New Roman", size: 15))
                .foregroundStyle(gold.opacity(0.5))
        }
        .padding(.top, 4)
        .contentShape(Rectangle())
        .onTapGesture { dismissKeyboard() }
    }

    private func dismissKeyboard() {
        isFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var statusLabel: String {
        if voice.isListening { return "Listening" }
        if isSearching { return "Searching the web" }
        if isAsking { return "Thinking" }
        return "Tap the microphone to speak, or type below"
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
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
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo(questionId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: replyScrollNonce) { _, _ in
                guard let questionId = lastQuestionId else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    withAnimation(.easeInOut(duration: 0.75)) {
                        proxy.scrollTo(questionId, anchor: .top)
                    }
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
                    SelectableTextView(text: message.text, fontSize: 16, color: .white, onTap: dismissKeyboard)
                        .padding(12)
                        .background(goldDim.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    formattedAssistantText(message.text)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if !message.sources.isEmpty {
                        sourcesList(message.sources)
                    }

                    if !message.thinking.isEmpty {
                        DisclosureGroup("Reasoning") {
                            SelectableTextView(text: message.thinking, fontSize: 13, color: UIColor.white.withAlphaComponent(0.55), onTap: dismissKeyboard)
                                .padding(10)
                                .background(gold.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .tint(gold.opacity(0.6))
                        .font(.custom("Times New Roman", size: 13))
                    }
                }
            }
        }
    }

    private func formattedAssistantText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                if let header = headerInfo(for: line) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(header.title)
                            .font(.custom("Times New Roman", size: 18).bold())
                            .foregroundStyle(gold)
                            .textCase(.uppercase)
                            .tracking(1.2)

                        if !header.body.isEmpty {
                            SelectableTextView(text: header.body, fontSize: 16, color: UIColor.white.withAlphaComponent(0.92), onTap: dismissKeyboard)
                        }
                    }
                    .padding(.top, 3)
                } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SelectableTextView(text: line, fontSize: 16, color: UIColor.white.withAlphaComponent(0.92), onTap: dismissKeyboard)
                }
            }
        }
    }

    private func headerInfo(for line: String) -> (title: String, body: String)? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.replacingOccurrences(of: "^\\d+[.)]\\s*", with: "", options: .regularExpression)
        let upper = trimmed.uppercased()
        for title in ["DEFINITION", "EXPLANATION", "ANALOGY", "FIRST PRINCIPLES", "SOURCES", "SOURCE"] {
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Wiki")
                .font(.custom("Times New Roman", size: 17).bold())
                .foregroundStyle(gold)

            ForEach(sources.prefix(5)) { source in
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.custom("Times New Roman", size: 14).bold())
                        .foregroundStyle(.white.opacity(0.9))
                    SelectableTextView(text: String(source.snippet.prefix(120)), fontSize: 12, color: UIColor.white.withAlphaComponent(0.6), onTap: dismissKeyboard)
                        .frame(maxHeight: 42)
                    Link(destination: URL(string: source.url) ?? URL(string: "https://example.com")!) {
                        Text(source.url)
                            .font(.custom("Times New Roman", size: 11))
                            .foregroundStyle(gold.opacity(0.7))
                            .underline()
                    }
                }
                .padding(.leading, 12)
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
                    if voice.isListening {
                        voice.stopListening()
                    } else {
                        usedVoice = true
                        dismissKeyboard()
                        voice.startListening()
                    }
                } label: {
                    Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(width: 48, height: 48)
                        .background(voice.isListening ? Color.red.opacity(0.78) : gold, in: Circle())
                        .shadow(color: voice.isListening ? Color.red.opacity(0.4) : gold.opacity(0.45), radius: 10)
                }
                .accessibilityLabel(voice.isListening ? "Stop listening" : "Start listening")

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
                        .shadow(color: canSend ? Color.white.opacity(0.45) : .clear, radius: 12)
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("AI Configuration")
                            .font(.headline)
                            .foregroundStyle(gold)

                        TextField("Ollama URL", text: $ollamaURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        TextField("Model", text: $ollamaModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            UserDefaults.standard.set(ollamaURL, forKey: "ollama.url")
                            UserDefaults.standard.set(ollamaModel, forKey: "ollama.model")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(gold)
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sendPrompt() {
        let prompt = typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isAsking else { return }

        if voice.isListening {
            voice.stopListening()
            usedVoice = false
        }

        dismissKeyboard()
        let history = sessionContext()
        typedPrompt = ""
        let question = Message(role: .user, text: prompt, thinking: "", sources: [])
        lastQuestionId = question.id
        messages.append(question)
        questionScrollNonce += 1
        isSearching = true
        isAsking = true

        Task {
            let searchResults = await WebSearchClient.search(prompt, history: history)

            await MainActor.run { isSearching = false }

            do {
                let client = try OllamaClient(baseURLString: ollamaURL, model: ollamaModel)
                let result = try await client.ask(prompt, sources: searchResults, history: history)
                await MainActor.run {
                    messages.append(Message(role: .assistant, text: result.answer, thinking: result.thinking, sources: result.sources))
                    isAsking = false
                    replyScrollNonce += 1
                }
            } catch {
                await MainActor.run {
                    messages.append(Message(role: .assistant, text: "Error: \(error.localizedDescription)", thinking: "", sources: []))
                    isAsking = false
                    replyScrollNonce += 1
                }
            }
        }
    }

    private func sessionContext() -> String {
        messages.suffix(12).map { message in
            switch message.role {
            case .user:
                return "User: \(message.text)"
            case .assistant:
                return "Assistant: \(message.text)"
            }
        }.joined(separator: "\n\n")
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}

#Preview {
    ContentView()
}