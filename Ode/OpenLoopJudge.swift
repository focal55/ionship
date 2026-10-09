import Foundation
import FoundationModels
import OdeCore

@Generable
enum LoopStatus {
    case open
    case done
    case unclear
}

@Generable
struct LoopVerdict {
    @Guide(description: "True if 'You' committed to do something specific for or with the others, including offers like 'let me ask…' or 'I'll check…'. Saying you are on your way, and quick acknowledgements, are not promises.")
    var isPromise: Bool

    @Guide(description: "The promised task in six words or fewer, starting with a verb, for example 'Send the Big Sur photos'.")
    var task: String

    @Guide(description: "done if a later message shows it happened, open if nothing shows it happened, unclear if you cannot tell.")
    var status: LoopStatus
}

struct OpenLoop: Identifiable, Equatable {
    let id: Int64
    let task: String
    let date: Date
    let isConfirmed: Bool
}

enum OpenLoops: Equatable {
    case judged([OpenLoop])
    case unjudged([OpenLoop])
}

enum OpenLoopJudge {
    private static let instructions = """
        You read short excerpts of a text conversation between 'You' and one or more other people, sometimes a \
        group chat. Decide whether You's first message is a promise to do something for or with them, and whether \
        the messages after it show it was done. Judge only from the excerpt.
        """

    /// Runs entirely on device. Each candidate gets a fresh session so the small context
    /// window only ever holds one excerpt.
    static func evaluate(_ candidates: [OpenLoopCandidate], name: (String?) -> String, limit: Int = 15,
                         cloud: CloudRunner? = nil) async -> OpenLoops {
        let recent = Array(candidates.prefix(limit))
        guard cloud != nil || SystemLanguageModel.default.isAvailable else {
            return .unjudged(recent.map { OpenLoop(id: $0.id, task: $0.message.text ?? "", date: $0.message.date, isConfirmed: false) })
        }
        var loops: [OpenLoop] = []
        for candidate in recent {
            let prompt = excerpt(candidate, name: name)
            guard let verdict = await judge(prompt, cloud: cloud) else {
                // The safety filter blocks some ordinary messages at random; show these unjudged rather than drop them.
                loops.append(OpenLoop(id: candidate.id, task: String((candidate.message.text ?? "").prefix(120)),
                                      date: candidate.message.date, isConfirmed: false))
                continue
            }
            guard verdict.isPromise, verdict.status != .done else { continue }
            loops.append(OpenLoop(id: candidate.id, task: verdict.task, date: candidate.message.date,
                                  isConfirmed: verdict.status == .open))
        }
        return .judged(loops)
    }

    /// The routed cloud model first; then the on-device model with one retry, since its
    /// guardrail blocks on this kind of text are intermittent.
    private static func judge(_ prompt: String, cloud: CloudRunner?) async -> (isPromise: Bool, task: String, status: LoopStatus)? {
        if let cloud, let data = await cloud(CloudRequest(system: instructions, prompt: prompt, schemaName: "verdict", schema: CloudSchemas.verdict)),
           let verdict = try? JSONDecoder().decode(CloudSchemas.Verdict.self, from: data) {
            let status: LoopStatus = verdict.status == "done" ? .done : verdict.status == "open" ? .open : .unclear
            return (verdict.isPromise, verdict.task, status)
        }
        guard SystemLanguageModel.default.isAvailable else { return nil }
        for _ in 0..<2 {
            let session = LanguageModelSession(instructions: instructions)
            if let verdict = try? await session.respond(to: prompt, generating: LoopVerdict.self).content {
                return (verdict.isPromise, verdict.task, verdict.status)
            }
        }
        return nil
    }

    private static func excerpt(_ candidate: OpenLoopCandidate, name: (String?) -> String) -> String {
        ([candidate.message] + candidate.following).map { message in
            let speaker = message.isFromMe ? "You" : name(message.sender)
            return "\(speaker): \((message.text ?? "[attachment]").prefix(280))"
        }
        .joined(separator: "\n")
    }
}
