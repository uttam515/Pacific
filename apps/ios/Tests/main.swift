import Foundation

print("Starting OFFGRID iOS Test Suite Execution...")

let persistenceTests = SQLitePersistenceTests()
let persistencePassed = persistenceTests.runAllTests()

let meshTests = MeshProtocolTests()
let meshPassed = meshTests.runAllTests()

if persistencePassed && meshPassed {
    print("ALL TESTS PASSED SUCCESSFULLY! (15/15)")
    exit(0)
} else {
    print("TEST SUITE FAILED!")
    exit(1)
}
