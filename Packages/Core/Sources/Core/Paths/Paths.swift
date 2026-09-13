import Foundation

/// 링크가 가리키는 곳.
public enum LinkTarget: Equatable, Sendable {
    /// 빈 링크이거나 같은 문서 안 앵커(`#머리말`).
    case empty
    /// `https:` · `mailto:` 처럼 스킴이 있는 것. 공유 · 첨부 대상이 아니다.
    case external(String)
    /// `/` 로 시작하는 절대경로. 폴더 밖이므로 다루지 않는다.
    case absolute(String)
    /// `../` 로 폴더 밖을 가리키는 것. **zip 에 넣으면 받는 쪽에서 다른 폴더를 덮는다.**
    case outside(String)
    /// 폴더 기준 상대경로 (퍼센트 디코딩 + NFC 정규화를 마친 것).
    case relative(String)
}

/// 경로를 다루는 순수 함수들. Foundation 만 쓴다.
public enum Paths {

    // MARK: - 정규화

    /// 한글 파일명을 NFC 로 맞춘다.
    ///
    /// iCloud Drive · `Files` 앱 · 옵시디언 사이에서 한글 파일명이 NFD(자모 분리)로
    /// 오간다. 이것을 거치지 않으면 `assets/내 사진.jpg` 를 디스크에서 못 찾아
    /// **한글 이름 첨부가 전부 깨진 링크로 뜬다** (가정 A13 · 안정화 기준 S13).
    public static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    // MARK: - 파일 종류

    /// 확장자를 소문자로 돌려준다. 없으면 빈 문자열.
    /// `.gitignore` 처럼 점으로 시작하는 이름은 확장자가 없는 것으로 본다.
    public static func fileExtension(_ path: String) -> String {
        let name: Substring
        if let slash = path.lastIndex(of: "/") {
            name = path[path.index(after: slash)...]
        } else {
            name = path[...]
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    /// 확장자를 뗀 이름 (NFC 정규화). 목록의 기본 제목으로 쓴다.
    public static func baseName(_ path: String) -> String {
        let name = normalized(path.split(separator: "/").last.map(String.init) ?? path)
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[name.startIndex..<dot])
    }

    /// 라이브 편집기가 여는 파일인가.
    public static func isNoteFile(_ path: String) -> Bool {
        ["md", "markdown", "txt"].contains(fileExtension(path))
    }

    /// 공유할 때 **한 단계만** 따라가는 대상인가 (`.txt` 는 제외).
    public static func isMarkdownFile(_ path: String) -> Bool {
        ["md", "markdown"].contains(fileExtension(path))
    }

    /// 목록에서 감출 것인가 — 옵시디언 볼트의 `.obsidian/`, 우리 `.trash/` 등.
    public static func isHidden(_ path: String) -> Bool {
        normalized(path).split(separator: "/").contains { $0.hasPrefix(".") }
    }

    // MARK: - 경로 조립

    /// 상대경로가 들어 있는 폴더. 최상위면 빈 문자열.
    public static func directory(of relativePath: String) -> String {
        let p = normalized(relativePath)
        guard let slash = p.lastIndex(of: "/") else { return "" }
        return String(p[p.startIndex..<slash])
    }

    /// `base` 폴더 기준으로 `relative` 를 풀어 폴더 기준 상대경로를 만든다.
    /// 폴더 밖으로 나가면 `nil`.
    public static func join(base: String, relative: String) -> String? {
        var stack: [String] = normalized(base)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        for raw in normalized(relative).split(separator: "/", omittingEmptySubsequences: true) {
            let part = String(raw)
            if part == "." { continue }
            if part == ".." {
                if stack.isEmpty { return nil }   // 폴더 밖으로 나갔다
                stack.removeLast()
                continue
            }
            stack.append(part)
        }
        return stack.isEmpty ? nil : stack.joined(separator: "/")
    }

    // MARK: - 링크 해석

    /// 마크다운 링크 하나를 노트 위치 기준으로 푼다.
    ///
    /// 세 가지를 한다 (설계서 §7.3):
    /// 1. `<...>` 와 앵커(`#...`)를 걷어낸다
    /// 2. **퍼센트 인코딩을 푼다** — `assets/내%20사진.jpg` 와 `assets/내 사진.jpg` 를 같게 본다
    /// 3. **NFC 로 정규화한다**
    public static func resolve(link raw: String, fromNoteAt notePath: String) -> LinkTarget {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // `<경로>` 꼴을 벗긴다.
        if text.hasPrefix("<") && text.hasSuffix(">") && text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        if text.isEmpty { return .empty }

        // 스킴이 있으면 외부 링크다. (앵커만 있는 `#머리말` 보다 먼저 본다 —
        // `https://…#절` 의 `#` 을 잘라 내면 안 되기 때문이다.)
        if hasScheme(text) { return .external(text) }

        // 같은 문서 안 앵커.
        if text.hasPrefix("#") { return .empty }

        // 문서 안 앵커를 떼어 낸다: `노트.md#머리말` → `노트.md`
        if let hash = text.firstIndex(of: "#") {
            text = String(text[text.startIndex..<hash])
        }
        if text.isEmpty { return .empty }

        let decoded = text.removingPercentEncoding ?? text
        if decoded.hasPrefix("/") { return .absolute(normalized(decoded)) }

        guard let joined = join(base: directory(of: notePath), relative: decoded) else {
            return .outside(normalized(decoded))
        }
        return .relative(joined)
    }

    // MARK: - 파일명 안전화

    /// 제목을 파일명으로 쓸 수 있게 바꾼다. 공유 zip 이름(`<제목>.zip`)에 쓴다.
    public static func safeFileName(_ raw: String, fallback: String = "제목 없음") -> String {
        let forbidden: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        var out = ""
        for ch in normalized(raw) {
            if forbidden.contains(ch) {
                out.append("-")
            } else if ch.isNewline || (ch.unicodeScalars.count == 1 && ch.unicodeScalars.first!.value < 0x20) {
                out.append(" ")
            } else {
                out.append(ch)
            }
        }
        // 앞뒤의 공백과 점을 없앤다. 끝에 점이 남으면 일부 파일 시스템이 싫어한다.
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        // 연속 공백을 하나로.
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        if out.isEmpty { return fallback }
        // **구분 기호만 남았으면 이름이 아니다.** `///` 는 `---` 가 되는데,
        // 그대로 두면 공유 파일이 `---.zip` 으로 나간다.
        if out.allSatisfy({ $0 == "-" || $0 == "_" || $0 == " " || $0 == "." }) { return fallback }
        return truncate(out, maxUTF8Bytes: 200)
    }

    /// UTF-8 바이트 기준으로 자른다 (파일 시스템 제한은 글자 수가 아니라 바이트다).
    public static func truncate(_ text: String, maxUTF8Bytes: Int) -> String {
        if text.utf8.count <= maxUTF8Bytes { return text }
        var out = ""
        var used = 0
        for ch in text {
            let size = String(ch).utf8.count
            if used + size > maxUTF8Bytes { break }
            out.append(ch)
            used += size
        }
        return out
    }

    // MARK: - 속

    /// `스킴:` 으로 시작하는가. RFC 3986 의 scheme 문법을 따른다.
    static func hasScheme(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard let first = scalars.first, isAlpha(first) else { return false }
        var i = 1
        while i < scalars.count {
            let c = scalars[i]
            if c == ":" { return true }
            if isAlpha(c) || isDigit(c) || c == "+" || c == "-" || c == "." {
                i += 1
                continue
            }
            return false
        }
        return false
    }

    private static func isAlpha(_ c: Unicode.Scalar) -> Bool {
        (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122)
    }

    private static func isDigit(_ c: Unicode.Scalar) -> Bool {
        c.value >= 48 && c.value <= 57
    }
}
