import SwiftUI
import TokenWiseCore

/// Drives the local claude/codex CLI to produce an AI cost analysis of the
/// user's own usage (subscription auth, no API key).
struct AnalyzeTab: View {
    @EnvironmentObject var model: AppModel
    @State private var engine: AIEngine?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let engines = model.availableEngines
            if engines.isEmpty {
                ContentUnavailableView(
                    "No AI CLI found",
                    systemImage: "sparkles",
                    description: Text("Install the `claude` or `codex` CLI to analyze your usage. Token Wise runs it headlessly with your existing subscription — no API key needed.")
                )
            } else {
                HStack(spacing: 12) {
                    Picker("Engine", selection: $engine) {
                        ForEach(engines, id: \.self) { e in Text(e.rawValue.capitalized).tag(Optional(e)) }
                    }
                    .frame(width: 200)
                    .onAppear { if engine == nil { engine = engines.first } }

                    Button {
                        model.runAnalysis(engine: engine)
                    } label: {
                        Label(model.analyzing ? "Analyzing…" : "Analyze my usage", systemImage: "sparkles")
                    }
                    .disabled(model.analyzing)

                    if model.analyzing { ProgressView().controlSize(.small) }
                    Spacer()
                    if let e = model.analysisEngine, model.analysisReport != nil {
                        Text("via \(e)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Text("Runs the CLI locally against a summary of your `~/.claude` and `~/.codex` usage, then returns actionable fixes and a narrative. Nothing leaves your machine except the aggregate summary you send to your own model.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                if let error = model.analysisError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else if let report = model.analysisReport {
                    ScrollView {
                        Text(markdown(report))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                } else if model.analyzing {
                    Text("Asking \(engine?.rawValue ?? "the model") to analyze your usage… this usually takes 20–90 seconds.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Click “Analyze my usage” to get AI-generated cost-optimization advice grounded in your real numbers.")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
