import Foundation

/// Standard API equivalent, not subscription spend or an invoice reconstruction.
public enum APICost {
    public static let revision = "2026-09-30-standard-v1"

    // USD per million tokens; sources and exclusions: technical-design-v0.1.ko.md §22.
    private static let rates: [String: (input: Double, cached: Double, write: Double, output: Double)] = [
        "gpt-6-astra": (10, 1, 12.5, 50),
        "gpt-6-sol": (2, 0.2, 2.5, 10),
        "gpt-6.1-sol": (2, 0.1, 2.5, 10),
        "gpt-6-luna": (0.1, 0.01, 0.125, 0.5),
        "gpt-5.6-sol": (4, 0.4, 5, 20),
        "gpt-5.6-terra": (2, 0.2, 2.5, 12),
        "gpt-5.6-luna": (0.2, 0.02, 0.25, 1.2)
    ]

    public static func estimate(usage: TokenUsage, model: String?, requestInputTokens: Int64?) -> Double? {
        guard let model, let rate = rates[model], let requestInputTokens,
              requestInputTokens == usage.inputTokens, usage.isValid,
              usage.cachedInputTokens <= usage.inputTokens,
              usage.cacheWriteInputTokens <= usage.inputTokens - usage.cachedInputTokens,
              usage.reasoningOutputTokens <= usage.outputTokens,
              usage.inputTokens <= Int64.max - usage.outputTokens,
              usage.totalTokens == usage.inputTokens + usage.outputTokens else { return nil }
        let regular = usage.inputTokens - usage.cachedInputTokens - usage.cacheWriteInputTokens
        let long = requestInputTokens > 272_000
        let inputCost = Double(regular) * rate.input
            + Double(usage.cachedInputTokens) * rate.cached
            + Double(usage.cacheWriteInputTokens) * rate.write
        // Reasoning is already included in output; never charge it twice.
        return (inputCost * (long ? 2 : 1)
            + Double(usage.outputTokens) * rate.output * (long ? 1.5 : 1)) / 1_000_000
    }
}

public struct CostSummary: Sendable, Equatable {
    public let usd: Double
    public let pricedTokens: Int64
    public let unpricedTokens: Int64

    public init(usd: Double, pricedTokens: Int64, unpricedTokens: Int64) {
        self.usd = usd
        self.pricedTokens = pricedTokens
        self.unpricedTokens = unpricedTokens
    }
}
