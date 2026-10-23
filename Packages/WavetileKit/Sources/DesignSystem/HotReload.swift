// Hot reload for design iteration (Debug only; compiles to no-ops in Release).
//
// Setup once: install InjectionNext (https://github.com/johnno1962/InjectionNext), launch it,
// and run the app in the Simulator. Saving a Swift file re-renders screens that declare:
//
//     @ObserveInjection var inject
//     var body: some View { ... .enableInjection() }
//
// Top-level screens in Features already do this.
@_exported import Inject
