import Testing
@testable import Features

@Suite struct StorageViewTests {
    @Test func sizeReadsAsNumbers() {
        #expect(StorageView.size(0) == "0 KB")
        #expect(StorageView.size(116_800_000).contains("MB"))
        #expect(StorageView.size(2_000_000_000).contains("GB"))
    }
}
