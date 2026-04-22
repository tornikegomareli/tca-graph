import Foundation
import TCAGraphModel

public struct DiscoveryResult {
  public let modules: [Module]
  public let fileToModule: [String: String]   // absolute file path -> module id
  public let allSwiftFiles: [URL]
}

public enum PackageDiscovery {

  public static func discover(root: URL) throws -> DiscoveryResult {
    var modules: [Module] = []
    var fileToModule: [String: String] = [:]

    let manifests = findPackageManifests(root: root)

    for manifest in manifests {
      if let dump = try? dumpPackage(at: manifest.deletingLastPathComponent()) {
        let pkgRoot = manifest.deletingLastPathComponent()
        for target in dump.targets {
          let targetPath = resolveTargetPath(packageRoot: pkgRoot, target: target)
          let moduleID = "mod:\(target.name)"
          modules.append(
            Module(
              id: moduleID,
              name: target.name,
              kind: .spmTarget,
              path: targetPath.path,
              packageManifest: manifest.path
            )
          )
          for file in swiftFiles(under: targetPath) {
            fileToModule[file.path] = moduleID
          }
        }
      }
    }

    let allSwiftFiles = swiftFiles(under: root)

    // Fallback: any .swift file not yet mapped gets a folder-based module
    // (top-level directory under root).
    for file in allSwiftFiles where fileToModule[file.path] == nil {
      let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
      let top = relative.split(separator: "/").first.map(String.init) ?? "Root"
      let moduleID = "mod:\(top)"
      if !modules.contains(where: { $0.id == moduleID }) {
        modules.append(
          Module(
            id: moduleID,
            name: top,
            kind: .folder,
            path: root.appendingPathComponent(top).path
          )
        )
      }
      fileToModule[file.path] = moduleID
    }

    return DiscoveryResult(
      modules: modules,
      fileToModule: fileToModule,
      allSwiftFiles: allSwiftFiles
    )
  }

  // MARK: - Helpers

  private static func findPackageManifests(root: URL) -> [URL] {
    var result: [URL] = []
    let fm = FileManager.default
    guard
      let enumerator = fm.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }
    for case let url as URL in enumerator {
      if url.lastPathComponent == "Package.swift" {
        result.append(url)
      }
      // Skip common noise
      if url.lastPathComponent == ".build"
          || url.lastPathComponent == "DerivedData"
          || url.pathExtension == "xcodeproj" {
        enumerator.skipDescendants()
      }
    }
    return result
  }

  private static func swiftFiles(under url: URL) -> [URL] {
    var result: [URL] = []
    let fm = FileManager.default
    guard
      let enumerator = fm.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }
    for case let fileURL as URL in enumerator {
      if fileURL.pathExtension == "swift"
          && fileURL.lastPathComponent != "Package.swift" {
        result.append(fileURL)
      }
      if fileURL.lastPathComponent == ".build"
          || fileURL.lastPathComponent == "DerivedData" {
        enumerator.skipDescendants()
      }
    }
    return result
  }

  private static func resolveTargetPath(packageRoot: URL, target: DumpedTarget) -> URL {
    if let path = target.path, !path.isEmpty {
      return packageRoot.appendingPathComponent(path)
    }
    // Default SPM layout: Sources/<TargetName> or Tests/<TargetName>
    let sources = packageRoot.appendingPathComponent("Sources").appendingPathComponent(target.name)
    let tests = packageRoot.appendingPathComponent("Tests").appendingPathComponent(target.name)
    if FileManager.default.fileExists(atPath: sources.path) { return sources }
    if FileManager.default.fileExists(atPath: tests.path) { return tests }
    return sources
  }

  // MARK: - swift package dump-package

  private struct DumpedPackage: Decodable {
    let name: String
    let targets: [DumpedTarget]
  }

  private struct DumpedTarget: Decodable {
    let name: String
    let path: String?
    let type: String?
  }

  private static func dumpPackage(at directory: URL) throws -> DumpedPackage {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "package", "dump-package"]
    process.currentDirectoryURL = directory

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    try process.run()
    process.waitUntilExit()

    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
      let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw NSError(
        domain: "tca-graph.dump-package",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: err]
      )
    }
    return try JSONDecoder().decode(DumpedPackage.self, from: data)
  }
}
