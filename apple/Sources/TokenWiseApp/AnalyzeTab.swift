import SwiftUI
import TokenWiseCore

/// Drives the local claude/codex CLI to produce an AI cost analysis of the
/// user's own usage (subscription auth, no API key).
struct AnalyzeTab: View {
    @EnvironmentObject var model: AppModel
    @State private var engine: AIEngine?
    /// Fix ids the user ticked, for copy / apply.
    @State private var selected: Set<Int> = []
    /// Transient feedback from a copy or launch.
    @State private var note: String?

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
                    let document = AnalysisDocument(report)
                    ScrollView {
                        AnalysisReportView(document: document, selected: $selected,
                                           onCopy: { fix in
                            FixApplier.copy([fix])
                            flash("Copied fix \(fix.number)")
                        }, onApply: { fix in
                            apply([fix])
                        })
                        .padding(4)
                    }
                    .onChange(of: report) { _, _ in selected.removeAll() }

                    reportActionBar(report: report)

                    if !document.fixes.isEmpty {
                        actionBar(for: document.fixes.filter { selected.contains($0.id) })
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

    private func actionBar(for fixes: [AnalysisFix]) -> some View {
        HStack(spacing: 10) {
            if fixes.isEmpty {
                Text("Tick the fixes you want to act on.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("\(fixes.count) selected").font(.callout).foregroundStyle(.secondary)
                Button("Clear") { selected.removeAll() }
                    .buttonStyle(.link)
            }

            if let note {
                Label(note, systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                FixApplier.copy(fixes)
                flash(fixes.count == 1 ? "Copied 1 fix" : "Copied \(fixes.count) fixes")
            } label: {
                Label("Copy \(fixes.count)", systemImage: "doc.on.doc")
            }
            .disabled(fixes.isEmpty)

            Button {
                do {
                    try FixApplier.launchClaude(with: fixes)
                    flash("Opened a Claude session in your home directory")
                } catch {
                    note = error.localizedDescription
                }
            } label: {
                Label("Apply \(fixes.count) with Claude", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(fixes.isEmpty || !FixApplier.canApply)
            .help(FixApplier.canApply
                  ? "Opens an interactive claude session seeded with these fixes — it proposes the edits, you approve them"
                  : "Requires the `claude` CLI")
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func reportActionBar(report: String) -> some View {
        HStack {
            Button {
                FixApplier.copyReport(report)
                flash("Copied the complete analysis")
            } label: {
                Label("Copy all", systemImage: "doc.on.doc")
            }
            .help("Copy the complete analysis report as Markdown")
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func apply(_ fixes: [AnalysisFix]) {
        do {
            try FixApplier.launchClaude(with: fixes)
            flash(fixes.count == 1 ? "Opened fix in Claude" : "Opened fixes in Claude")
        } catch {
            note = error.localizedDescription
        }
    }

    /// Transient status line for copy/launch feedback.
    private func flash(_ message: String) {
        note = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if note == message { note = nil }
        }
    }

}

// MARK: - Report rendering

/// Renders a parsed analysis report: headings as headings, and each numbered
/// fix as a row the user can tick or copy on its own.
struct AnalysisReportView: View {
    let document: AnalysisDocument
    @Binding var selected: Set<Int>
    var onCopy: (AnalysisFix) -> Void
    var onApply: (AnalysisFix) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(document.blocks) { block($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func block(_ block: AnalysisDocument.Block) -> some View {
        switch block {
        case let .heading(_, level, text):
            Text(text)
                .font(level <= 2 ? .title3.bold() : .headline)
                .padding(.top, 8)
        case let .fix(fix):
            fixRow(fix)
        case let .bullet(_, markdown):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(Self.inline(markdown)).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        case let .paragraph(_, markdown):
            Text(Self.inline(markdown))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fixRow(_ fix: AnalysisFix) -> some View {
        let isSelected = selected.contains(fix.id)
        return HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { on in toggle(fix.id, on: on) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("Select fix \(fix.number): \(fix.title)")

            Text("\(fix.number).")
                .font(.body.monospacedDigit().bold())
                .foregroundStyle(.secondary)

            Text(Self.inline(fix.markdown))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { onCopy(fix) } label: {
                Label("Copy prompt", systemImage: "doc.on.doc")
            }
                .buttonStyle(.borderless)
                .help("Copy this fix as a prompt")

            Button { onApply(fix) } label: {
                Label("Apply", systemImage: "sparkles")
            }
                .buttonStyle(.borderless)
                .disabled(!FixApplier.canApply)
                .help(FixApplier.canApply
                      ? "Open Claude with this fix as an interactive prompt"
                      : "Requires the `claude` CLI")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        // No row-wide tap target: the body text is selectable, and a gesture
        // over it would fight click-drag selection.
        .background(isSelected ? Color.accentColor.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    private func toggle(_ id: Int, on: Bool) {
        if on { selected.insert(id) } else { selected.remove(id) }
    }

    /// Bold, code spans and emphasis inside one block. Block structure is
    /// already handled by `AnalysisDocument`.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
