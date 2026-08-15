import Foundation

public enum AIEngine: String, CaseIterable {
    case claude
    case codex

    var binaryName: String { rawValue }
}

public struct AIAnalysisResult {
    public let engine: AIEngine
    public let report: String
}

public enum AIAnalyzerError: Error, CustomStringConvertible {
    case noEngineFound
    case engineUnavailable(AIEngine)
    case timedOut
    case failed(String)

    public var description: String {
        switch self {
        case .noEngineFound: return "No `claude` or `codex` CLI found on this machine."
        case let .engineUnavailable(e): return "`\(e.binaryName)` CLI was not found on PATH or in common install locations."
        case .timedOut: return "The analysis timed out."
        case let .failed(m): return "Analysis failed: \(m)"
        }
    }
}

/// Discovers the installed `claude`/`codex` CLIs and drives them headlessly
/// (subscription auth — no API key) to turn a usage summary into actionable
/// config fixes plus a narrative report.
public enum AIAnalyzer {
    // MARK: Discovery

    /// Locate a CLI by scanning PATH plus common install dirs, so it works both
    /// from a shell-launched CLI and a bundled .app with a minimal PATH.
    public static func locate(_ engine: AIEngine) -> URL? {
        let fm = FileManager.default
        var dirs: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs += path.split(separator: ":").map(String.init)
        }
        let home = Paths.home.path
        dirs += [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
            "\(home)/.local/bin", "\(home)/.bun/bin", "\(home)/.claude/local",
            "\(home)/.deno/bin",
        ]
        // Node version managers (nvm/fnm/volta) install under versioned dirs.
        for base in ["\(home)/.nvm/versions/node", "\(home)/.fnm/node-versions", "\(home)/.volta/bin"] {
            if let subs = try? fm.contentsOfDirectory(atPath: base) {
                for s in subs { dirs.append("\(base)/\(s)/bin"); dirs.append("\(base)/\(s)/installation/bin") }
            } else {
                dirs.append(base)
            }
        }
        for dir in dirs {
            let candidate = "\(dir)/\(engine.binaryName)"
            if fm.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        }
        return nil
    }

    public static func availableEngines() -> [AIEngine] {
        AIEngine.allCases.filter { locate($0) != nil }
    }

    // MARK: Analysis

    public static func analyze(overview: OverviewMetrics, sessions: [SessionSummary],
                               engine: AIEngine? = nil, model: String? = nil,
                               timeout: TimeInterval = 180) throws -> AIAnalysisResult {
        let chosen: AIEngine
        if let engine {
            guard locate(engine) != nil else { throw AIAnalyzerError.engineUnavailable(engine) }
            chosen = engine
        } else {
            guard let first = availableEngines().first else { throw AIAnalyzerError.noEngineFound }
            chosen = first
        }
        guard let binary = locate(chosen) else { throw AIAnalyzerError.engineUnavailable(chosen) }

        let prompt = buildPrompt(overview: overview, sessions: sessions)
        let report: String
        switch chosen {
        case .claude:
            // Claude Code reads the prompt as an argument in print mode.
            var args = ["-p", prompt]
            if let model { args += ["--model", model] }
            report = try runProcess(binary: binary, args: args, stdin: nil, timeout: timeout)
        case .codex:
            // `codex exec` writes a wrapped transcript to stdout; `-o` captures
            // just the final message. `--skip-git-repo-check` + read-only sandbox
            // let it run from anywhere without side effects.
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("token-wise-\(UInt64(Date().timeIntervalSince1970 * 1000)).md")
            var args = ["exec", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never",
                        "-o", tmp.path]
            if let model { args += ["-c", "model=\"\(model)\""] }
            args.append("-")  // read prompt from stdin
            let stdout = try runProcess(binary: binary, args: args, stdin: prompt, timeout: timeout)
            report = (try? String(contentsOf: tmp, encoding: .utf8)) ?? stdout
            try? FileManager.default.removeItem(at: tmp)
        }
        return AIAnalysisResult(engine: chosen, report: report.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Prompt

    static func buildPrompt(overview: OverviewMetrics, sessions: [SessionSummary]) -> String {
        let bd = overview.costBreakdown
        let total = max(bd.totalCost, 0.0001)
        let claudeSessions = sessions.filter { $0.source == "claude" }
        let shortExpensive = claudeSessions.filter { $0.messageCount <= 4 && $0.estimatedCostUsd > 0.5 }.count
        let lowCache = claudeSessions.filter { $0.cacheHitRate < 0.5 }.count

        let topProjects = overview.projectSummaries.prefix(8).map {
            "  - \(Format.path($0.project)): \(Format.cost($0.totalCostUsd)) across \($0.sessionCount) sessions, cache hit \(Format.percent($0.avgCacheHitRate))"
        }.joined(separator: "\n")

        var modelCost: [String: Double] = [:]
        for s in sessions { modelCost[s.model ?? "unknown", default: 0] += s.estimatedCostUsd }
        let topModels = modelCost.sorted { $0.value > $1.value }.prefix(6)
            .map { "  - \($0.key): \(Format.cost($0.value))" }.joined(separator: "\n")

        return """
        You are a cost-optimization analyst for AI coding-agent usage (Claude Code, Codex, and OpenCode). \
        Below is a factual summary of the user's own usage, computed locally from their \
        `~/.claude` transcripts, `~/.codex` history, and `~/.local/share/opencode` history. Analyze it and respond in GitHub-flavored \
        Markdown with EXACTLY these two sections and nothing else before them:

        ## Actionable fixes
        A prioritized list (most impactful first) of concrete, specific changes the user can make \
        to reduce spend without losing capability. Ground every item in the numbers below. Prefer \
        specifics like trimming CLAUDE.md / skills / MCP tool definitions (they inflate the \
        per-session cache-write "tax"), batching short sessions, raising cache hit rate, and \
        switching models where the cheaper tier would do. Give an estimated $ or % impact when you can.

        ## Narrative
        A short (3-6 sentence) plain-English summary of where the money goes and the single biggest \
        opportunity.

        Do not invent data. If something can't be determined from the summary, say so briefly.

        === USAGE SUMMARY ===
        Total spend: \(Format.cost(overview.totalCostUsd)) across \(overview.totalSessions) sessions
        Cost breakdown:
          - Input: \(Format.cost(bd.inputCost)) (\(Format.percent(bd.inputCost / total)))
          - Output: \(Format.cost(bd.outputCost)) (\(Format.percent(bd.outputCost / total)))
          - Cache write: \(Format.cost(bd.cacheWriteCost)) (\(Format.percent(bd.cacheWriteCost / total)))
          - Cache read: \(Format.cost(bd.cacheReadCost)) (\(Format.percent(bd.cacheReadCost / total)))
        Overall cache hit rate: \(Format.percent(overview.avgCacheHitRate)) (higher is better)
        Estimated system overhead: \(Format.tokens(overview.estimatedSystemOverheadTokens)) tokens/session \
        (CLAUDE.md + skills + tool definitions + system prompt, paid on every session start)
        Tokens: input \(Format.tokens(overview.totalInputTokens)), output \(Format.tokens(overview.totalOutputTokens)), \
        cache write \(Format.tokens(overview.totalCacheWriteTokens)), cache read \(Format.tokens(overview.totalCacheReadTokens))
        Short expensive Claude sessions (<=4 msgs, >$0.50): \(shortExpensive)
        Claude sessions with <50% cache hit: \(lowCache) of \(claudeSessions.count)

        Top projects by cost:
        \(topProjects.isEmpty ? "  (none)" : topProjects)

        Top models by cost:
        \(topModels.isEmpty ? "  (none)" : topModels)
        === END SUMMARY ===
        """
    }

    // MARK: Process runner

    static func runProcess(binary: URL, args: [String], stdin: String?, timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        // Ensure child processes (node, etc.) can resolve their own runtime.
        var env = ProcessInfo.processInfo.environment
        let extra = "\(binary.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = (env["PATH"].map { "\($0):\(extra)" }) ?? extra
        process.environment = env

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        do { try process.run() } catch { throw AIAnalyzerError.failed(error.localizedDescription) }

        if let stdin { inPipe.fileHandleForWriting.write(Data(stdin.utf8)) }
        inPipe.fileHandleForWriting.closeFile()

        let deadline = DispatchTime.now() + timeout
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: timer)

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()

        let out = String(data: outData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 && out.isEmpty {
            let err = String(data: errData, encoding: .utf8) ?? ""
            if process.terminationReason == .uncaughtSignal { throw AIAnalyzerError.timedOut }
            throw AIAnalyzerError.failed(err.isEmpty ? "exit code \(process.terminationStatus)" : err)
        }
        return out
    }
}
