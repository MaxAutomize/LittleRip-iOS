import Contacts
import Foundation
import MessageUI
import SwiftUI

struct LittleRipMessageDraft: Identifiable {
    let id = UUID()
    let recipientName: String
    let address: String
    let body: String
}

enum LittleRipMessageOutcome {
    case sent
    case cancelled
    case failed
}

/// Resolves a person entirely from the iPhone's local Contacts database, then
/// presents Apple's standard Messages composer. Apple intentionally requires the
/// user to review the message and tap Send; LittleRip never sends silently.
@MainActor
final class MessageComposeService: ObservableObject {
    @Published var draft: LittleRipMessageDraft?

    private let contacts = CNContactStore()
    private var continuation: CheckedContinuation<LittleRipMessageOutcome, Never>?

    func compose(recipient recipientQuery: String, body rawBody: String) async -> String {
        let recipient = recipientQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !recipient.isEmpty else { return "Who should I message?" }
        guard !body.isEmpty else { return "What should the message to \(recipient) say?" }
        guard MFMessageComposeViewController.canSendText() else {
            return "Messages is not available on this iPhone."
        }
        guard continuation == nil, draft == nil else {
            return "Finish or cancel the message that is already open first."
        }

        let resolved: ResolvedRecipient
        do {
            if let direct = directPhoneNumber(recipient) {
                resolved = ResolvedRecipient(displayName: recipient, address: direct)
            } else {
                guard await contactsAccessIsAvailable() else {
                    return "LittleRip needs Contacts access to find \(recipient). Open Settings → Privacy & Security → Contacts → LittleRip, then try again."
                }
                resolved = try resolveRecipient(recipient)
            }
        } catch let error as RecipientResolutionError {
            return error.userMessage
        } catch {
            return "LittleRip could not read Contacts: \(error.localizedDescription)"
        }

        let outcome = await withCheckedContinuation { continuation in
            self.continuation = continuation
            draft = LittleRipMessageDraft(
                recipientName: resolved.displayName,
                address: resolved.address,
                body: body
            )
        }

        switch outcome {
        case .sent:
            return "Message sent\n\nTo \(resolved.displayName)\n\n“\(body)”"
        case .cancelled:
            return "Message cancelled. Nothing was sent."
        case .failed:
            return "Messages reported that it could not send the message to \(resolved.displayName)."
        }
    }

    func finish(_ outcome: LittleRipMessageOutcome) {
        guard let continuation else { return }
        self.continuation = nil
        draft = nil
        continuation.resume(returning: outcome)
    }

    func cancelIfNeeded() {
        guard let continuation else { return }
        self.continuation = nil
        draft = nil
        continuation.resume(returning: .cancelled)
    }

    private func contactsAccessIsAvailable() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                contacts.requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func resolveRecipient(_ rawQuery: String) throws -> ResolvedRecipient {
        var query = normalizedName(rawQuery)
        query = query.replacingOccurrences(of: #"^(?:my|the)\s+"#, with: "", options: .regularExpression)
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true

        var candidates: [ContactCandidate] = []
        try contacts.enumerateContacts(with: request) { contact, _ in
            guard !contact.phoneNumbers.isEmpty else { return }
            let displayName = CNContactFormatter.string(from: contact, style: .fullName)
                ?? contact.nickname.nonEmpty
                ?? contact.organizationName.nonEmpty
                ?? "Unnamed contact"
            let fields = [
                displayName,
                contact.givenName,
                contact.middleName,
                contact.familyName,
                contact.nickname,
                contact.organizationName
            ].map(normalizedName)
            let score = matchScore(query: query, fields: fields)
            guard score > 0 else { return }
            candidates.append(ContactCandidate(contact: contact, displayName: displayName, score: score))
        }

        guard !candidates.isEmpty else {
            throw RecipientResolutionError.notFound(rawQuery)
        }
        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        let topScore = candidates[0].score
        let top = candidates.filter { $0.score == topScore }
        let distinctNames = Array(Set(top.map(\.displayName))).sorted()
        guard distinctNames.count == 1, let chosen = top.first else {
            throw RecipientResolutionError.ambiguousContact(rawQuery, Array(distinctNames.prefix(4)))
        }

        let phones = chosen.contact.phoneNumbers.map { labeled in
            PhoneCandidate(
                address: labeled.value.stringValue,
                label: CNLabeledValue<NSString>.localizedString(forLabel: labeled.label ?? "other"),
                preference: phonePreference(label: labeled.label)
            )
        }.filter { !$0.address.isEmpty }
        guard !phones.isEmpty else {
            throw RecipientResolutionError.noPhoneNumber(chosen.displayName)
        }

        let bestPreference = phones.map(\.preference).max() ?? 0
        let preferred = phones.filter { $0.preference == bestPreference }
        let distinctAddresses = Array(Set(preferred.map(\.address)))
        guard distinctAddresses.count == 1, let phone = preferred.first else {
            let labels = preferred.map { "\($0.label) ending \(lastFourDigits($0.address))" }
            throw RecipientResolutionError.ambiguousNumber(chosen.displayName, labels)
        }

        return ResolvedRecipient(displayName: chosen.displayName, address: phone.address)
    }

    private func directPhoneNumber(_ text: String) -> String? {
        let allowed = text.filter { $0.isNumber || $0 == "+" }
        let digitCount = allowed.filter(\.isNumber).count
        return digitCount >= 7 ? allowed : nil
    }

    private func normalizedName(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchScore(query: String, fields: [String]) -> Int {
        let nonempty = fields.filter { !$0.isEmpty }
        if nonempty.contains(query) { return 100 }
        if nonempty.contains(where: { $0.hasPrefix(query + " ") || $0.hasPrefix(query) }) { return 80 }
        let queryWords = Set(query.split(separator: " ").map(String.init))
        if !queryWords.isEmpty,
           nonempty.contains(where: { field in
               let fieldWords = Set(field.split(separator: " ").map(String.init))
               return queryWords.isSubset(of: fieldWords)
           }) {
            return 70
        }
        if query.count >= 3, nonempty.contains(where: { $0.contains(query) }) { return 50 }
        return 0
    }

    private func phonePreference(label: String?) -> Int {
        guard let label else { return 0 }
        let localized = CNLabeledValue<NSString>.localizedString(forLabel: label).lowercased()
        if localized.contains("iphone") || localized.contains("mobile") { return 3 }
        if localized.contains("main") { return 2 }
        if localized.contains("home") { return 1 }
        return 0
    }

    private func lastFourDigits(_ phone: String) -> String {
        String(phone.filter(\.isNumber).suffix(4))
    }
}

struct LittleRipMessageComposer: UIViewControllerRepresentable {
    let draft: LittleRipMessageDraft
    let onFinish: (LittleRipMessageOutcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = [draft.address]
        controller.body = draft.body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (LittleRipMessageOutcome) -> Void

        init(onFinish: @escaping (LittleRipMessageOutcome) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            switch result {
            case .sent:
                onFinish(.sent)
            case .cancelled:
                onFinish(.cancelled)
            case .failed:
                onFinish(.failed)
            @unknown default:
                onFinish(.failed)
            }
        }
    }
}

private struct ResolvedRecipient {
    let displayName: String
    let address: String
}

private struct ContactCandidate {
    let contact: CNContact
    let displayName: String
    let score: Int
}

private struct PhoneCandidate {
    let address: String
    let label: String
    let preference: Int
}

private enum RecipientResolutionError: Error {
    case notFound(String)
    case ambiguousContact(String, [String])
    case noPhoneNumber(String)
    case ambiguousNumber(String, [String])

    var userMessage: String {
        switch self {
        case .notFound(let query):
            return "I couldn’t find \(query) in Contacts. Try their full contact name or a phone number."
        case .ambiguousContact(let query, let names):
            return "I found more than one contact for \(query): \(names.joined(separator: ", ")). Which full name should I use?"
        case .noPhoneNumber(let name):
            return "\(name) does not have a phone number in Contacts."
        case .ambiguousNumber(let name, let choices):
            return "\(name) has multiple matching numbers: \(choices.joined(separator: ", ")). Tell me which label to use."
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
