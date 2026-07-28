import SwiftUI

// MARK: - Brand marks

/// The vendor behind a session, used to draw a logo instead of a text label.
///
/// Sessions are grouped by the CLI that wrote them (`claude` / `codex`), but a
/// Claude Code session can be driven by a non-Anthropic model — GLM speaks the
/// Anthropic-compatible API and lands in `~/.claude/projects` — so the model
/// name decides the mark whenever it names a different vendor.
enum BrandMark: Equatable {
    case claude
    case openAI
    /// Vendors without a logo we can ship fall back to a short wordmark.
    case wordmark(String, Color)

    static func resolve(source: String, model: String?) -> BrandMark {
        let m = (model ?? "").lowercased()
        if m.hasPrefix("glm") { return .wordmark("GLM", CostColors.cacheRead) }
        if m.hasPrefix("gpt") || m.hasPrefix("o1") || m.hasPrefix("o3") { return .openAI }
        if m.hasPrefix("claude") { return .claude }
        return source.lowercased() == "codex" ? .openAI : .claude
    }

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .openAI: return "OpenAI"
        case .wordmark(let text, _): return text
        }
    }

    var tint: Color {
        switch self {
        case .claude: return BrandColors.claude
        case .openAI: return .primary
        case .wordmark(_, let color): return color
        }
    }

    var glyph: String? {
        switch self {
        case .claude: return BrandPaths.claude
        case .openAI: return BrandPaths.openAI
        case .wordmark: return nil
        }
    }
}

enum BrandColors {
    /// Anthropic's clay orange.
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34) // #d97757
}

/// 24×24 logo outlines, verbatim from simple-icons (CC0). Trademarks belong to
/// their owners; they are drawn here only to identify the session's vendor.
private enum BrandPaths {
    static let claude = "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"

    static let openAI = "M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z"
}

// MARK: - Views

/// A logo drawn from 24×24 path data, scaled to fit and centered.
struct BrandGlyph: Shape {
    let data: String

    func path(in rect: CGRect) -> Path {
        SVGPath.path(data, viewBox: 24, in: rect)
    }
}

/// Vendor chip shown wherever a session's source used to be spelled out.
struct BrandBadge: View {
    let mark: BrandMark
    var size: CGFloat = 12

    var body: some View {
        Group {
            if let data = mark.glyph {
                BrandGlyph(data: data)
                    .fill(mark.tint)
                    .frame(width: size, height: size)
            } else {
                Text(mark.label)
                    .font(.system(size: size * 0.72, weight: .bold))
                    .foregroundStyle(mark.tint)
                    .frame(height: size)
            }
        }
        .accessibilityLabel(mark.label)
        .help(mark.label)
    }
}

// MARK: - SVG path data

/// Minimal SVG path-data parser covering `M L H V C S Q T A Z` in both absolute
/// and relative form — enough for the logo outlines above. SwiftUI cannot
/// render SVG and an SPM executable target cannot compile an asset catalog, so
/// the marks are parsed into a `Path` instead of shipped as image resources.
enum SVGPath {
    /// Parses `data` (authored in a `viewBox`-sized square) and scales it to fit
    /// `rect`, preserving aspect ratio.
    static func path(_ data: String, viewBox: CGFloat, in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        let side = viewBox * scale
        let transform = CGAffineTransform(
            translationX: rect.minX + (rect.width - side) / 2,
            y: rect.minY + (rect.height - side) / 2
        ).scaledBy(x: scale, y: scale)
        return parse(data).applying(transform)
    }

    /// Parses path data in its own coordinate space.
    static func parse(_ data: String) -> Path {
        var path = Path()
        var reader = Reader(data)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        // Set only by curve commands; `isCubic` tells `S` from `T` which kind of
        // predecessor it is allowed to mirror.
        var lastControl: (point: CGPoint, isCubic: Bool)?
        var previous: Character = " "

        while true {
            let command: Character
            if let c = reader.command() {
                command = c
            } else if reader.hasNumber, previous != " " {
                // Repeated argument sets reuse the last command; a repeat after
                // `M`/`m` is a line, per the SVG grammar.
                command = previous == "M" ? "L" : (previous == "m" ? "l" : previous)
            } else {
                break
            }
            previous = command

            let relative = command.isLowercase
            func point() -> CGPoint? {
                guard let x = reader.number(), let y = reader.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            /// Smooth curves mirror the preceding control point about the
            /// current point; without a matching predecessor the control point
            /// is the current point.
            func reflected(cubic: Bool) -> CGPoint {
                guard let last = lastControl, last.isCubic == cubic else { return current }
                return CGPoint(x: 2 * current.x - last.point.x, y: 2 * current.y - last.point.y)
            }

            switch command {
            case "M", "m":
                guard let p = point() else { return path }
                current = p
                subpathStart = p
                lastControl = nil
                path.move(to: p)
            case "L", "l":
                guard let p = point() else { return path }
                current = p
                lastControl = nil
                path.addLine(to: p)
            case "H", "h":
                guard let x = reader.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                lastControl = nil
                path.addLine(to: current)
            case "V", "v":
                guard let y = reader.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                lastControl = nil
                path.addLine(to: current)
            case "C", "c":
                guard let c1 = point(), let c2 = point(), let end = point() else { return path }
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = (c2, true)
                current = end
            case "S", "s":
                let c1 = reflected(cubic: true)
                guard let c2 = point(), let end = point() else { return path }
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = (c2, true)
                current = end
            case "Q", "q":
                guard let c = point(), let end = point() else { return path }
                path.addQuadCurve(to: end, control: c)
                lastControl = (c, false)
                current = end
            case "T", "t":
                let c = reflected(cubic: false)
                guard let end = point() else { return path }
                path.addQuadCurve(to: end, control: c)
                lastControl = (c, false)
                current = end
            case "A", "a":
                guard let rx = reader.number(), let ry = reader.number(), let rotation = reader.number(),
                      let largeArc = reader.flag(), let sweep = reader.flag(), let end = point()
                else { return path }
                for segment in arcCurves(from: current, to: end, rx: rx, ry: ry,
                                         rotation: rotation, largeArc: largeArc, sweep: sweep) {
                    path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
                }
                lastControl = nil
                current = end
            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil
            default:
                return path
            }
        }
        return path
    }

    // MARK: Arc conversion

    private struct CurveSegment {
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
    }

    /// Endpoint-to-center arc parameterization from the SVG spec's
    /// implementation notes, emitted as ≤90° cubic segments.
    private static func arcCurves(from start: CGPoint, to end: CGPoint,
                                  rx: CGFloat, ry: CGFloat, rotation: CGFloat,
                                  largeArc: Bool, sweep: Bool) -> [CurveSegment] {
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, start != end else {
            return [CurveSegment(control1: start, control2: end, end: end)]
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy

        // Grow radii that are too small to span the endpoints.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }

        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let numerator = max(0, rx * rx * ry * ry - denominator)
        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let cx1 = coefficient * rx * y1 / ry
        let cy1 = -coefficient * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let length = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            guard length > 0 else { return 0 }
            var a = acos(min(1, max(-1, (ux * vx + uy * vy) / length)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let ux = (x1 - cx1) / rx, uy = (y1 - cy1) / ry
        let vx = (-x1 - cx1) / rx, vy = (-y1 - cy1) / ry
        let theta = angle(1, 0, ux, uy)
        var sweepAngle = angle(ux, uy, vx, vy)
        if !sweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        let count = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let step = sweepAngle / CGFloat(count)
        let alpha = 4.0 / 3.0 * tan(step / 4)

        func onArc(_ a: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cosPhi * cos(a) - ry * sinPhi * sin(a),
                    y: cy + rx * sinPhi * cos(a) + ry * cosPhi * sin(a))
        }
        func tangent(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * cosPhi * sin(a) - ry * sinPhi * cos(a),
                    y: -rx * sinPhi * sin(a) + ry * cosPhi * cos(a))
        }

        var segments: [CurveSegment] = []
        var from = start
        var a1 = theta
        for _ in 0..<count {
            let a2 = a1 + step
            let to = onArc(a2)
            let d1 = tangent(a1), d2 = tangent(a2)
            segments.append(CurveSegment(
                control1: CGPoint(x: from.x + alpha * d1.x, y: from.y + alpha * d1.y),
                control2: CGPoint(x: to.x - alpha * d2.x, y: to.y - alpha * d2.y),
                end: to
            ))
            from = to
            a1 = a2
        }
        return segments
    }

    // MARK: Tokenizer

    private struct Reader {
        private let characters: [Character]
        private var index = 0

        init(_ string: String) { characters = Array(string) }

        private mutating func skipSeparators() {
            while index < characters.count, characters[index] == " " || characters[index] == ","
                || characters[index] == "\n" || characters[index] == "\r" || characters[index] == "\t" {
                index += 1
            }
        }

        mutating func command() -> Character? {
            skipSeparators()
            guard index < characters.count, characters[index].isLetter else { return nil }
            defer { index += 1 }
            return characters[index]
        }

        var hasNumber: Bool {
            mutating get {
                skipSeparators()
                guard index < characters.count else { return false }
                let c = characters[index]
                return c.isNumber || c == "-" || c == "+" || c == "."
            }
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var text = ""
            if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                text.append(characters[index])
                index += 1
            }
            var seenDot = false, seenExponent = false
            while index < characters.count {
                let c = characters[index]
                if c.isNumber {
                    text.append(c)
                } else if c == ".", !seenDot, !seenExponent {
                    seenDot = true
                    text.append(c)
                } else if c == "e" || c == "E", !seenExponent {
                    seenExponent = true
                    text.append(c)
                    index += 1
                    if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                        text.append(characters[index])
                    } else {
                        continue
                    }
                } else {
                    break
                }
                index += 1
            }
            return Double(text).map { CGFloat($0) }
        }

        /// Arc flags are single digits and may be packed without separators
        /// ("0 0 1" and "001" are the same three flags).
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < characters.count, characters[index] == "0" || characters[index] == "1" else {
                return nil
            }
            defer { index += 1 }
            return characters[index] == "1"
        }
    }
}
