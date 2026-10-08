import CoreML
import Foundation
import Testing
@testable import IonshipCore

/// Runs only when IONSHIP_MODEL_PATH points at MiniLM.mlpackage; the model is too large for
/// the test bundle. Expected similarities come from the reference PyTorch model.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["IONSHIP_MODEL_PATH"] != nil))
struct SentenceModelEmbedderTests {
    @Test func reproducesReferenceSimilarities() throws {
        let package = URL(fileURLWithPath: ProcessInfo.processInfo.environment["IONSHIP_MODEL_PATH"]!)
        let embedder = try SentenceModelEmbedder(compiledModelAt: try MLModel.compileModel(at: package))
        func similarity(_ a: String, _ b: String) throws -> Float {
            let x = try #require(embedder.vector(for: a)), y = try #require(embedder.vector(for: b))
            return zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let related = try similarity("send you the big sur photos", "did you ever find those pictures from the coast trip")
        let unrelated = try similarity("send you the big sur photos", "what time is dinner on sunday")
        #expect(abs(related - 0.496) < 0.01)
        #expect(abs(unrelated - 0.066) < 0.01)
    }
}
