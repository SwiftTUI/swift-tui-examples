import Foundation
import PackagePlugin

@main
struct LayoutSourceSnippetPlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext,
    target: Target
  ) throws -> [Command] {
    guard let sourceModule = target.sourceModule else {
      return []
    }

    let sourceFiles = sourceModule.sourceFiles.filter { sourceFile in
      sourceFile.url.pathExtension == "swift"
    }
    guard !sourceFiles.isEmpty else {
      return []
    }

    let outputURL = context.pluginWorkDirectoryURL
      .appendingPathComponent("LayoutSourceSnippets.generated.swift")
    let generator = try context.tool(named: "LayoutSnippetGenerator")

    return [
      .buildCommand(
        displayName: "Generating layout source snippets for \(target.name)",
        executable: generator.url,
        arguments: ["--output", outputURL.path] + sourceFiles.map(\.url.path),
        inputFiles: sourceFiles.map(\.url),
        outputFiles: [outputURL]
      )
    ]
  }
}
