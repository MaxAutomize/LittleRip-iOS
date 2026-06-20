import SwiftUI

struct ContentView: View {
    @State private var showSettings = false
    @State private var email = UserDefaults(suiteName: SmartRentClient.appGroup)?.string(forKey: "smartrent.email") ?? ""
    @State private var password = UserDefaults(suiteName: SmartRentClient.appGroup)?.string(forKey: "smartrent.password") ?? ""
    @State private var status = ""
    @State private var isWorking = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .blue.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 4)

                Text("LittleRip")
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .foregroundColor(.white)
                Spacer()
            }

        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .blue.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    TextField("SmartRent email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    SecureField("SmartRent password", text: $password)
                        .textFieldStyle(.roundedBorder)

                    Button("Save Credentials") {
                        SmartRentClient.saveCredentials(email: email, password: password)
                        status = "Saved."
                    }
                    .buttonStyle(.borderedProminent)

                    Button(isWorking ? "Working..." : "Test Unlock Front Door") {
                        Task { await testUnlock() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)

                    if !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Smart Home")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func testUnlock() async {
        isWorking = true
        defer { isWorking = false }
        do {
            SmartRentClient.saveCredentials(email: email, password: password)
            let client = SmartRentClient(email: email, password: password)
            try await client.unlockFrontDoor()
            status = "Unlock command sent."
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}