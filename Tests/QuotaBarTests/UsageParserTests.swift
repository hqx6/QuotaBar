import XCTest
@testable import QuotaBar

final class UsageParserTests: XCTestCase {
    func testCodexUsesMainBucketAndTightestWindow() throws {
        let value: [String: Any] = ["rateLimitsByLimitId": [
            "codex": ["primary": ["usedPercent": 12, "windowDurationMins": 300, "resetsAt": 1_800_000_000],
                      "secondary": ["usedPercent": 43, "windowDurationMins": 10080]],
            "review": ["primary": ["usedPercent": 99]]
        ], "rateLimits": ["primary": ["usedPercent": 100]]]
        let result = try UsageParser.codex(value)
        XCTAssertEqual(result.summaryRemaining, 57)
        XCTAssertEqual(result.quotas.count, 3)
        XCTAssertEqual(result.quotas.first?.label, "5 小时额度")
        XCTAssertEqual(result.quotas.first?.resetsAt?.timeIntervalSince1970, 1_800_000_000)
    }

    func testCodexLegacyAndNullWindow() throws {
        let value: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 20], "secondary": NSNull()]]
        let result = try UsageParser.codex(value)
        XCTAssertEqual(result.summaryRemaining, 80)
        XCTAssertEqual(result.quotas.count, 1)
        XCTAssertNil(result.quotas.first?.resetsAt)
    }

    func testMissingCodexDoesNotMeanFullQuota() {
        XCTAssertThrowsError(try UsageParser.codex(["rateLimits": NSNull()]))
        XCTAssertThrowsError(try UsageParser.codex(["rateLimits": ["primary": ["usedPercent": NSNull()]]]))
    }

    func testCursorTotalPercentageWinsOverLegacyDollarLimit() throws {
        // Actual client response has two different allowance bases.
        let root: [String: Any] = ["billingCycleEnd": "1794187366000", "planUsage": [
            "includedSpend": 1796, "remaining": 204, "limit": 2000,
            "totalPercentUsed": 3.628282828, "autoPercentUsed": 3.991111111, "apiPercentUsed": 0
        ]]
        let result = try UsageParser.cursor(root)
        XCTAssertEqual(result.summaryRemaining, 96.371717172, accuracy: 0.000001)
        XCTAssertEqual(result.quotas.count, 3)
        XCTAssertEqual(result.quotas.last?.remaining, 100)
        XCTAssertEqual(result.quotas.first?.resetsAt?.timeIntervalSince1970, 1794187366)
        XCTAssertTrue(result.note?.contains("$2.04 / $20.00") == true)
    }

    func testCursorLegacyFallback() throws {
        let result = try UsageParser.cursor(["planUsage": ["includedSpend": 750, "limit": 2000]])
        XCTAssertEqual(result.summaryRemaining, 62.5)
        XCTAssertEqual(result.quotas.first?.label, "基础套餐额度")
    }

    func testCursorDoesNotInventMissingPoolQuota() throws {
        let result = try UsageParser.cursor(["planUsage": ["apiPercentUsed": 75]])
        XCTAssertEqual(result.quotas.count, 1)
        XCTAssertEqual(result.summaryRemaining, 25)
        XCTAssertThrowsError(try UsageParser.cursor([:]))
        XCTAssertThrowsError(try UsageParser.cursor(["planUsage": [:]]))
        XCTAssertThrowsError(try UsageParser.cursor(["planUsage": ["limit": 2000]]))
    }

    func testClampOverageAndInvalidNumbers() throws {
        let result = try UsageParser.cursor(["planUsage": ["totalPercentUsed": 120]])
        XCTAssertEqual(result.summaryRemaining, 0)
        XCTAssertNil(UsageParser.number(true))
        XCTAssertNil(UsageParser.number(Double.nan))
        XCTAssertNil(UsageParser.number(NSNull()))
    }
}
