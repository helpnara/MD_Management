// 240 — 공유 창이 쓰는 애플 링크 미리보기(LinkPresentation)가 주소마다 어떤 제목을 주는지 맥 러너에서 본다.
// 원격 세션은 유튜브에 접속할 수 없다 (네트워크 정책). `swift Tools/probe/title.swift <주소>…`
import Foundation
import LinkPresentation

let addresses = Array(CommandLine.arguments.dropFirst())
var remaining = addresses.count
var providers: [LPMetadataProvider] = []

for address in addresses {
    guard let url = URL(string: address) else { continue }
    let provider = LPMetadataProvider()
    provider.timeout = 15
    providers.append(provider)
    provider.startFetchingMetadata(for: url) { metadata, error in
        DispatchQueue.main.async {
            print("== \(address)")
            print("title: \(metadata?.title ?? "nil")")
            print("url: \(metadata?.url?.absoluteString ?? "nil") · original: \(metadata?.originalURL?.absoluteString ?? "nil")")
            if let error { print("error: \(error)") }
            if let metadata { print("describe: \(metadata.description.prefix(800))") }
            remaining -= 1
            if remaining == 0 { exit(0) }
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("timeout"); exit(1) }
dispatchMain()
