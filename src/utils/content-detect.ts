const EXT_TO_LANG: Record<string, string> = {
  ts: "typescript", tsx: "tsx", js: "javascript", jsx: "jsx",
  rs: "rust", py: "python", rb: "ruby", go: "go", java: "java",
  kt: "kotlin", swift: "swift", c: "c", cpp: "cpp", h: "c", hpp: "cpp",
  cs: "csharp", php: "php", sh: "bash", bash: "bash", zsh: "bash",
  json: "json", yaml: "yaml", yml: "yaml", toml: "toml",
  html: "html", css: "css", scss: "scss", less: "less",
  sql: "sql", md: "markdown", xml: "xml", vue: "vue", svelte: "svelte",
  dockerfile: "dockerfile", makefile: "makefile",
  lock: "text", txt: "text", log: "text", env: "text",
};

export function detectLang(source: string | null, category: string): string {
  if (source) {
    const match = source.match(/\.([a-zA-Z0-9]+)$/);
    if (match) {
      const ext = match[1].toLowerCase();
      if (EXT_TO_LANG[ext]) return EXT_TO_LANG[ext];
    }
    const basename = source.split("/").pop()?.toLowerCase() ?? "";
    if (basename === "dockerfile") return "dockerfile";
    if (basename === "makefile") return "makefile";
  }
  if (category === "Shell Commands") return "bash";
  if (category === "Web Content") return "html";
  return "text";
}

export function stripAnsiCodes(content: string): string {
  // eslint-disable-next-line no-control-regex
  return content.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").replace(/\x1b\].*?(\x07|\x1b\\)/g, "");
}

export function stripLineNumbers(content: string): string {
  const lines = content.split("\n");
  if (lines.length < 2) return content;
  const pattern = /^\s*\d+[\t\u2192]/;
  const matchCount = lines.filter((l) => pattern.test(l) || l.trim() === "").length;
  if (matchCount / lines.length > 0.7) {
    return lines.map((l) => l.replace(/^\s*\d+[\t\u2192]/, "")).join("\n");
  }
  return content;
}

export function looksLikeMarkdown(text: string): boolean {
  const mdPatterns = /^#{1,6}\s|^\*\*.*\*\*|^\d+\.\s|^[-*+]\s|^```|^\|.*\|/m;
  return mdPatterns.test(text);
}

export function extractThinking(content: string): string | null {
  try {
    const parsed = JSON.parse(content);
    if (parsed?.type === "thinking" && typeof parsed.thinking === "string") {
      return parsed.thinking;
    }
  } catch { /* not JSON */ }
  return null;
}

export function extractJsonText(content: string): string | null {
  try {
    const parsed = JSON.parse(content);
    if (typeof parsed?.text === "string") return parsed.text;
  } catch { /* not JSON */ }
  return null;
}

export interface FileEditInfo {
  file_path: string;
  old_string: string;
  new_string: string;
}

export function extractFileEdit(content: string): FileEditInfo | null {
  try {
    const parsed = JSON.parse(content);
    if (typeof parsed?.old_string === "string" && typeof parsed?.new_string === "string") {
      return { file_path: parsed.file_path ?? "", old_string: parsed.old_string, new_string: parsed.new_string };
    }
  } catch { /* not JSON */ }
  return null;
}

const RE_XML_DECL = /^<\?xml\s/i;
const RE_OPEN_TAG = /^<[a-z][\w-]*[\s>]/i;
const RE_CLOSE_TAG = /<\/[a-z][\w-]*\s*>/i;
const RE_HTML_DOCTYPE = /^<!doctype\s+html/i;
const RE_HTML_ROOT = /^<html[\s>]/i;
const RE_HTML_TAGS = /<\/(head|body|div|span|p|a|table|form)>/i;
const RE_YAML_FRONT = /^---\s*$/m;
const RE_YAML_KV = /^[a-zA-Z_][\w.-]*:\s/m;
const RE_YAML_LINE = /^\s*(#.*|[a-zA-Z_][\w.-]*:\s|[-]\s|$)/;
const RE_TOML_SECTION = /^\[[\w.-]+\]\s*$/m;
const RE_TOML_KV = /^[\w.-]+\s*=\s*/m;
const RE_SQL_KW = /^\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|WITH|EXPLAIN)\s/im;
const RE_CSS_RULE = /[.#@]?[\w-]+\s*\{[^}]*?:[^}]*?\}/s;
const RE_JS_KW = /\bfunction\b|\breturn\b|\bconst\b|\blet\b|\bvar\b/;

export function detectContentLang(content: string): { lang: string; formatted: string } | null {
  const trimmed = content.trim();
  if (!trimmed) return null;

  if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
    try {
      const parsed = JSON.parse(trimmed);
      return { lang: "json", formatted: JSON.stringify(parsed, null, 2) };
    } catch { /* not JSON, check JSONL below */ }

    if (trimmed.includes("\n")) {
      const lines = trimmed.split("\n").filter(l => l.trim());
      if (lines.length > 0 && lines.every(l => { try { JSON.parse(l); return true; } catch { return false; } })) {
        const formatted = lines.map(l => JSON.stringify(JSON.parse(l), null, 2)).join("\n---\n");
        return { lang: "jsonl", formatted };
      }
    }
  }

  if (trimmed.startsWith("<")) {
    if (RE_XML_DECL.test(trimmed) || (RE_OPEN_TAG.test(trimmed) && RE_CLOSE_TAG.test(trimmed))) {
      const isHtml = RE_HTML_DOCTYPE.test(trimmed) || RE_HTML_ROOT.test(trimmed) || RE_HTML_TAGS.test(trimmed);
      return { lang: isHtml ? "html" : "xml", formatted: trimmed };
    }
  }

  if (trimmed.includes("\n")) {
    const lines = trimmed.split("\n");
    if (RE_YAML_FRONT.test(trimmed) || (RE_YAML_KV.test(trimmed) && !/[;{}]/.test(lines[0]))) {
      const yamlLines = lines.filter(l => RE_YAML_LINE.test(l));
      if (yamlLines.length / lines.length > 0.6) {
        return { lang: "yaml", formatted: trimmed };
      }
    }
  }

  if (RE_TOML_SECTION.test(trimmed) && RE_TOML_KV.test(trimmed)) {
    return { lang: "toml", formatted: trimmed };
  }

  if (RE_SQL_KW.test(trimmed)) {
    return { lang: "sql", formatted: trimmed };
  }

  if (RE_CSS_RULE.test(trimmed) && !RE_JS_KW.test(trimmed)) {
    return { lang: "css", formatted: trimmed };
  }

  return null;
}
