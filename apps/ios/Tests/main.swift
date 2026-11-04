import Foundation

print("Starting OFFGRID iOS Test Suite Execution...")

let persistenceTests = SQLitePersistenceTests()
let persistenceResult = persistenceTests.runAllTests()

let meshTests = MeshProtocolTests()
let meshResult = meshTests.runAllTests()

let fixtureTests = ContractV1FixtureTests()
let fixtureResult = fixtureTests.runAllTests()

let gatewayResult = GatewayQueueTests().runAllTests()
let totalPassed = gatewayResult.passed + persistenceResult.passed + meshResult.passed + fixtureResult.passed
let totalTests = gatewayResult.total + persistenceResult.total + meshResult.total + fixtureResult.total

print("\n===========================================")
print("  OFFGRID iOS TEST EXECUTION BREAKDOWN     ")
print("===========================================")
print("  - SQLite Persistence Tests:  \(persistenceResult.passed)/\(persistenceResult.total)")
print("  - Mesh Protocol Tests:       \(meshResult.passed)/\(meshResult.total)")
print("  - Contract v1 & Fix Tests:   \(fixtureResult.passed)/\(fixtureResult.total)")
print("-------------------------------------------")
print("  TOTAL PASSED: \(totalPassed)/\(totalTests)")
print("===========================================")

if totalPassed == totalTests {
    print("ALL TESTS PASSED SUCCESSFULLY! (\(totalPassed)/\(totalTests))")
    if let configPath=ProcessInfo.processInfo.environment["OFFGRID_ACCEPTANCE_CONFIG"] {
        Task { @MainActor in
            do {try await runGatewayHTTPAcceptance(configPath:configPath);exit(0)}
            catch {print("[FAIL] Native HTTP gateway acceptance: \(error)");exit(1)}
        }
        RunLoop.main.run()
    }
    exit(0)
} else {
    print("TEST SUITE FAILED! (\(totalPassed)/\(totalTests) passed)")
    exit(1)
}
