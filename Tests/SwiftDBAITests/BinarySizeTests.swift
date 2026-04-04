// BinarySizeTests.swift
// SwiftDBAI
//
// Validates that the SwiftDBAI package stays within its 2 MB binary size budget.
// This test suite uses source-level heuristics since we can't measure the actual
// compiled binary size in a unit test. The constraints ensure the package remains
// lightweight by checking:
//   1. Total source code size (proxy for compiled size)
//   2. No embedded binary assets or large resources
//   3. No unnecessary heavy dependencies
//   4. File count stays reasonable (no code bloat)

import Foundation
import Testing

@Suite("Binary Size Budget")
struct BinarySizeTests {

    /// The maximum allowed total source code size in bytes.
    /// At typical Swift optimized compilation ratios (2-4x), 500 KB of source
    /// compiles to roughly 1-2 MB of binary. We set the source budget at 500 KB
    /// to keep the compiled output well under 2 MB.
    private static let maxSourceSizeBytes: Int = 500_000 // 500 KB

    /// Maximum number of Swift source files allowed.
    /// More files generally means more code and larger binaries.
    private static let maxSourceFileCount: Int = 60

    /// Maximum size for any single source file in bytes.
    /// Large individual files often indicate code that should be split or
    /// contains embedded data that bloats the binary.
    private static let maxSingleFileSizeBytes: Int = 50_000 // 50 KB

    /// Disallowed file extensions in the Sources directory that would bloat the binary.
    private static let disallowedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff",
        "mp3", "mp4", "wav", "mov",
        "mlmodel", "mlmodelc", "mlpackage",
        "sqlite", "db",
        "zip", "tar", "gz",
        "bin", "dat",
        "framework", "dylib", "a"
    ]

    // MARK: - Helper

    /// Recursively finds all files in the Sources/SwiftDBAI directory.
    private func findSourceFiles() throws -> [URL] {
        let sourcesDir = findSourcesDirectory()
        guard let sourcesDir else {
            Issue.record("Could not locate Sources/SwiftDBAI directory")
            return []
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourcesDir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Issue.record("Could not enumerate Sources/SwiftDBAI directory")
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files
    }

    /// Locates the Sources/SwiftDBAI directory by walking up from the test bundle.
    private func findSourcesDirectory() -> URL? {
        // Try common locations relative to the build directory
        let fileManager = FileManager.default

        // In SPM test runs, we can find the package root by checking known paths
        var candidateURL = URL(fileURLWithPath: #filePath)
        // Walk up from Tests/SwiftDBAITests/BinarySizeTests.swift to package root
        for _ in 0..<3 {
            candidateURL = candidateURL.deletingLastPathComponent()
        }
        let sourcesDir = candidateURL.appendingPathComponent("Sources/SwiftDBAI")
        if fileManager.fileExists(atPath: sourcesDir.path) {
            return sourcesDir
        }

        // Fallback: check current working directory
        let cwdSources = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Sources/SwiftDBAI")
        if fileManager.fileExists(atPath: cwdSources.path) {
            return cwdSources
        }

        return nil
    }

    // MARK: - Tests

    @Test("Total source code size stays under 500 KB budget")
    func totalSourceCodeSizeUnderBudget() throws {
        let files = try findSourceFiles()
        let swiftFiles = files.filter { $0.pathExtension == "swift" }

        var totalSize: Int = 0
        for file in swiftFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let fileSize = attributes[.size] as? Int ?? 0
            totalSize += fileSize
        }

        #expect(totalSize < Self.maxSourceSizeBytes,
            """
            Total Swift source size (\(totalSize) bytes) exceeds \(Self.maxSourceSizeBytes) byte budget.
            At typical 2-4x compilation ratio, this would produce a binary larger than 2 MB.
            Consider removing unused code or splitting into optional sub-targets.
            """)

        // Log the actual size for visibility
        let sizeKB = Double(totalSize) / 1024.0
        let budgetKB = Double(Self.maxSourceSizeBytes) / 1024.0
        print("📦 SwiftDBAI source size: \(String(format: "%.1f", sizeKB)) KB / \(String(format: "%.0f", budgetKB)) KB budget (\(String(format: "%.0f", (sizeKB / budgetKB) * 100))% used)")
    }

    @Test("Source file count stays reasonable")
    func sourceFileCountUnderLimit() throws {
        let files = try findSourceFiles()
        let swiftFiles = files.filter { $0.pathExtension == "swift" }

        #expect(swiftFiles.count <= Self.maxSourceFileCount,
            """
            Swift source file count (\(swiftFiles.count)) exceeds limit of \(Self.maxSourceFileCount).
            More files generally means more code and larger binaries.
            """)

        print("📦 SwiftDBAI file count: \(swiftFiles.count) / \(Self.maxSourceFileCount) max")
    }

    @Test("No individual source file exceeds 50 KB")
    func noOversizedSourceFiles() throws {
        let files = try findSourceFiles()
        let swiftFiles = files.filter { $0.pathExtension == "swift" }

        for file in swiftFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let fileSize = attributes[.size] as? Int ?? 0

            #expect(fileSize < Self.maxSingleFileSizeBytes,
                """
                File \(file.lastPathComponent) is \(fileSize) bytes, exceeding the \(Self.maxSingleFileSizeBytes) byte limit.
                Large files may contain embedded data or code that should be split.
                """)
        }
    }

    @Test("No binary assets or heavy resources in Sources directory")
    func noBinaryAssetsInSources() throws {
        let files = try findSourceFiles()

        let disallowedFiles = files.filter { file in
            Self.disallowedExtensions.contains(file.pathExtension.lowercased())
        }

        #expect(disallowedFiles.isEmpty,
            """
            Found \(disallowedFiles.count) disallowed file(s) in Sources directory:
            \(disallowedFiles.map(\.lastPathComponent).joined(separator: "\n"))
            These file types bloat the binary. Remove them or move to a separate resource bundle.
            """)
    }

    @Test("Package has no resource bundles that could bloat binary")
    func noResourceBundles() throws {
        let files = try findSourceFiles()

        let resourceFiles = files.filter { file in
            let ext = file.pathExtension.lowercased()
            return ["xcassets", "storyboard", "xib", "nib", "xcdatamodeld"].contains(ext)
        }

        #expect(resourceFiles.isEmpty,
            """
            Found resource bundle files that could bloat the binary:
            \(resourceFiles.map(\.lastPathComponent).joined(separator: "\n"))
            SwiftDBAI should be pure code — no bundled resources.
            """)
    }

    @Test("Only expected dependencies declared (GRDB + AnyLanguageModel)")
    func minimalDependencies() throws {
        // Read Package.swift to verify we only have the expected dependencies
        var packageURL = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            packageURL = packageURL.deletingLastPathComponent()
        }
        let packageSwiftURL = packageURL.appendingPathComponent("Package.swift")

        guard FileManager.default.fileExists(atPath: packageSwiftURL.path) else {
            // Skip if we can't find Package.swift (CI environments etc.)
            return
        }

        let packageContents = try String(contentsOf: packageSwiftURL, encoding: .utf8)

        // Count .package() declarations (dependencies)
        let packageDeclarations = packageContents.components(separatedBy: ".package(")
            .count - 1 // subtract 1 because the first segment is before any .package(

        #expect(packageDeclarations <= 3,
            """
            Found \(packageDeclarations) package dependencies, expected at most 4 (GRDB + AnyLanguageModel + ViewInspector for tests).
            Additional dependencies increase binary size. Evaluate if they're truly needed.
            """)

        // Verify the expected dependencies are present
        #expect(packageContents.contains("GRDB"), "Expected GRDB dependency")
        #expect(packageContents.contains("AnyLanguageModel"), "Expected AnyLanguageModel dependency")

        print("📦 SwiftDBAI dependencies: \(packageDeclarations) (GRDB + AnyLanguageModel)")
    }

    @Test("Estimated binary size under 2 MB")
    func estimatedBinarySizeUnderLimit() throws {
        let files = try findSourceFiles()
        let swiftFiles = files.filter { $0.pathExtension == "swift" }

        var totalSize: Int = 0
        for file in swiftFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let fileSize = attributes[.size] as? Int ?? 0
            totalSize += fileSize
        }

        // Conservative estimate: optimized Swift binary is typically 2-4x source size.
        // Use 4x as worst case multiplier for safety margin.
        let worstCaseMultiplier = 4.0
        let estimatedBinarySize = Double(totalSize) * worstCaseMultiplier
        let maxBinarySize: Double = 2.0 * 1024.0 * 1024.0 // 2 MB

        #expect(estimatedBinarySize < maxBinarySize,
            """
            Estimated binary size (\(String(format: "%.1f", estimatedBinarySize / 1024.0)) KB) exceeds 2 MB limit.
            Source: \(totalSize) bytes × \(worstCaseMultiplier)x multiplier = \(String(format: "%.1f", estimatedBinarySize / 1024.0)) KB
            Note: This is the SwiftDBAI module only — excludes GRDB and AnyLanguageModel
            which are existing dependencies the developer already includes.
            """)

        let estimatedMB = estimatedBinarySize / (1024.0 * 1024.0)
        print("📦 Estimated SwiftDBAI binary size: \(String(format: "%.2f", estimatedMB)) MB / 2.00 MB limit (worst case \(worstCaseMultiplier)x)")
    }
}
