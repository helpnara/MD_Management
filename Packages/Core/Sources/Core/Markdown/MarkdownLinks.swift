import Foundation
import Markdown

/// 본문에서 뽑은 링크 하나.
public struct ExtractedLink: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case image
        case link
    }

    /// 원문에 적힌 그대로 (퍼센트 인코딩도 그대로). 푸는 것은 `Paths.resolve` 가 한다.
    public let destination: String
    public let kind: Kind

    public init(destination: String, kind: Kind) {
        self.destination = destination
        self.kind = kind
    }
}

/// 본문의 링크를 뽑는다. 공유 묶음(§7.6)과 첨부 표시(§7.3)가 이것을 쓴다.
public enum MarkdownLinks {

    /// 머리말을 뗀 본문에서 이미지와 링크를 **나온 순서대로** 뽑는다.
    public static func extract(from markdown: String) -> [ExtractedLink] {
        let body = FrontMatterParser.parse(markdown).body
        let document = Document(parsing: body)
        var walker = LinkWalker()
        walker.visit(document)
        return walker.found
    }
}

private struct LinkWalker: MarkupWalker {
    var found: [ExtractedLink] = []

    mutating func visitLink(_ link: Markdown.Link) {
        if let destination = link.destination, !destination.isEmpty {
            found.append(ExtractedLink(destination: destination, kind: .link))
        }
        descendInto(link)
    }

    mutating func visitImage(_ image: Markdown.Image) {
        if let source = image.source, !source.isEmpty {
            found.append(ExtractedLink(destination: source, kind: .image))
        }
        descendInto(image)
    }
}
