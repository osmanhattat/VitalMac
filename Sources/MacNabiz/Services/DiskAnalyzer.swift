import Foundation

/// Disk üzerinde bir öğe (dosya veya klasör) ve boyutu.
struct DiskItem: Identifiable {
    let id = UUID()
    var name: String
    var url: URL
    var size: Int64
    var isDirectory: Bool
}

/// Klasör boyutu hesaplama ve doğrudan alt öğeleri listeleme yardımcıları.
/// Ağır iş `DiskScanner` (fts) üzerinden yapılır.
enum DiskAnalyzer {

    /// Bir klasörün toplam ayrılan disk alanı (gizli dosyalar dahil).
    static func directorySize(_ url: URL) -> Int64 {
        DiskScanner.allocatedSize(url.path)
    }

    /// Verilen klasörün doğrudan alt öğelerini boyutlarıyla (büyükten küçüğe) döndürür.
    /// Alt öğeler tüm çekirdeklerde paralel ölçülür.
    static func topLevel(_ url: URL) -> [DiskItem] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
        ) else { return [] }
        guard !children.isEmpty else { return [] }

        var sizes = [Int64](repeating: 0, count: children.count)
        var dirs = [Bool](repeating: false, count: children.count)
        sizes.withUnsafeMutableBufferPointer { sizeBuf in
            dirs.withUnsafeMutableBufferPointer { dirBuf in
                // Her indeks yalnız bir iş parçacığınca yazılır; yarış yok.
                let sizePtr = sizeBuf.baseAddress!, dirPtr = dirBuf.baseAddress!
                DispatchQueue.concurrentPerform(iterations: children.count) { i in
                    let values = try? children[i].resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    let isDir = values?.isDirectory == true && values?.isSymbolicLink != true
                    dirPtr[i] = isDir
                    sizePtr[i] = DiskScanner.allocatedSize(children[i].path)
                }
            }
        }
        return children.indices
            .map { DiskItem(name: children[$0].lastPathComponent, url: children[$0],
                            size: sizes[$0], isDirectory: dirs[$0]) }
            .sorted { $0.size > $1.size }
    }
}
