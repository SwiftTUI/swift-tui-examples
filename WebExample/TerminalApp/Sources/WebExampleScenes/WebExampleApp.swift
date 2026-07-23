public import ThreeHostsDemoCore

/// The browser deployment intentionally runs the exact `CounterApp` shared by
/// the terminal and native SwiftUI hosts. The alias keeps the public
/// `WebExampleApp` entry point stable while avoiding a second authored app.
public typealias WebExampleApp = CounterApp
