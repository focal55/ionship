import Foundation
import FoundationModels
import IonshipCore

@Generable
enum LoopStatus {
    case open
    case done
    case unclear
}

@Generable
struct LoopVerdict {
    @Guide(description: "True only if 'You' committed to do something specific for or with the other person. Plans to show up or quick replies are not promises.")
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
        You read short excerpts of a text conversation between 'You' and someone else. Decide whether \
        You's first message is a promise to do something, and whether the messages after it show it was done. \
        Be conservative: when in doubt it is not a promise.
        """

    /// Runs entirely on device. Each candidate gets a fresh session so the small context
    /// window only ever holds one excerpt.
    static func evaluate(_ candidates: [OpenLoopCandidate], name: (String?) -> String, limit: Int = 15) async -> OpenLoops {
        let recent = Array(candidates.prefix(limit))
        guard SystemLanguageModel.default.isAvailable else {
            return .unjudged(recent.map { OpenLoop(id: $0.id, task: $0.message.text ?? "", date: $0.message.date, isConfirmed: false) })
        }
        var loops: [OpenLoop] = []
        for candidate in recent {
            let session = LanguageModelSession(instructions: instructions)
            guard let verdict = try? await session.respond(to: excerpt(candidate, name: name), generating: LoopVerdict.self).content,
                  verdict.isPromise, verdict.status != .done else { continue }
            loops.append(OpenLoop(id: candidate.id, task: verdict.task, date: candidate.message.date,
                                  isConfirmed: verdict.status == .open))
        }
        return .judged(loops)
    }

    private static func excerpt(_ candidate: OpenLoopCandidate, name: (String?) -> String) -> String {
        ([candidate.message] + candidate.following).map { message in
            let speaker = message.isFromMe ? "You" : name(message.sender)
            return "\(speaker): \((message.text ?? "[attachment]").prefix(280))"
        }
        .joined(separator: "\n")
    }
}
