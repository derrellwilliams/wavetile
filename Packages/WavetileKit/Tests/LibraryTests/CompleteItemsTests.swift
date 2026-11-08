import Foundation
import Testing
@testable import Library
@testable import JellyfinKit

struct CompleteItemsTests {
    private func item(_ id: String) -> BaseItemDto {
        var item = BaseItemDto()
        item.id = id
        return item
    }

    @Test func collectsAllPages() async throws {
        let first = item("a"), second = item("b")
        let result = try await completeItems { start, _ in
            BaseItemDtoQueryResult(items: [start == 0 ? first : second], startIndex: start, totalRecordCount: 2)
        }
        #expect(result.map(\.id) == ["a", "b"])
    }

    @Test func rejectsTruncatedAndMissingResponses() async {
        let first = item("a")
        await #expect(throws: URLError.self) {
            _ = try await completeItems { start, _ in
                BaseItemDtoQueryResult(items: start == 0 ? [first] : [], startIndex: start, totalRecordCount: 2)
            }
        }
        await #expect(throws: URLError.self) {
            _ = try await completeItems { _, _ in BaseItemDtoQueryResult(items: [], totalRecordCount: nil) }
        }
        await #expect(throws: URLError.self) {
            _ = try await completeItems { _, _ in BaseItemDtoQueryResult(items: nil, totalRecordCount: 0) }
        }
    }

    @Test func rejectsChangingTotalAndWrongOffset() async {
        let first = item("a")
        await #expect(throws: URLError.self) {
            _ = try await completeItems { start, _ in
                BaseItemDtoQueryResult(items: [first], startIndex: start, totalRecordCount: start == 0 ? 2 : 1)
            }
        }
        await #expect(throws: URLError.self) {
            _ = try await completeItems { _, _ in BaseItemDtoQueryResult(items: [first], startIndex: 1, totalRecordCount: 1) }
        }
    }
}
