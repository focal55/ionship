import CoreML
import Foundation

/// The bundled all-MiniLM-L6-v2 model (Apache-2.0), converted to Core ML with mean pooling
/// and L2 normalization built in. Runs on device.
public struct SentenceModelEmbedder: Embedder {
    public static let id = "minilm-l6-v2"
    private static let length = 128

    private let model: MLModel
    private let tokenizer: WordPieceTokenizer

    public init(compiledModelAt url: URL) throws {
        model = try MLModel(contentsOf: url)
        tokenizer = try WordPieceTokenizer.bundled()
    }

    public func vector(for text: String) -> [Float]? {
        let (ids, mask) = tokenizer.encode(text, length: Self.length)
        guard let idArray = try? MLMultiArray(ids), let maskArray = try? MLMultiArray(mask),
              let inputs = try? MLDictionaryFeatureProvider(dictionary: [
                  "input_ids": idArray.reshaped(to: [1, Self.length]), "attention_mask": maskArray.reshaped(to: [1, Self.length]),
              ]),
              let output = try? model.prediction(from: inputs).featureValue(for: "embedding")?.multiArrayValue else { return nil }
        return (0..<output.count).map { output[$0].floatValue }
    }
}

private extension MLMultiArray {
    convenience init(_ values: [Int32]) throws {
        try self.init(shape: [NSNumber(value: values.count)], dataType: .int32)
        for (index, value) in values.enumerated() { self[index] = NSNumber(value: value) }
    }

    func reshaped(to shape: [Int]) throws -> MLMultiArray {
        let result = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: dataType)
        for index in 0..<count { result[index] = self[index] }
        return result
    }
}
