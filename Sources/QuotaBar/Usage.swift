import Foundation

struct Quota: Identifiable, Codable {
    var id: String
    var label: String
    var remaining: Double
    var resetsAt: Date?
    var detail: String?

    var formatted: String {
        remaining == remaining.rounded() ? String(format: "%.0f%%", remaining) : String(format: "%.1f%%", remaining)
    }
}

struct UsageSnapshot: Codable {
    var provider: String
    var plan: String?
    var quotas: [Quota]
    var summaryRemaining: Double
    var note: String?
    var fetchedAt = Date()

    var summary: String { String(format: "%.0f%%", summaryRemaining) }
}

enum UsageError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

enum UsageParser {
    static func remaining(_ used: Double) -> Double { max(0, min(100, 100 - used)) }

    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite { return n.doubleValue }
        if let s = value as? String, let n = Double(s), n.isFinite { return n }
        return nil
    }

    static func date(_ value: Any?, milliseconds: Bool = false) -> Date? {
        guard let n = number(value), n > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds ? n / 1000 : n)
    }

    static func codex(_ root: [String: Any]) throws -> UsageSnapshot {
        var quotas: [Quota] = []
        var plan: String?
        let buckets: [String: Any]
        if let multi = root["rateLimitsByLimitId"] as? [String: Any], !multi.isEmpty {
            buckets = multi
        } else if let legacy = root["rateLimits"] as? [String: Any] {
            buckets = ["codex": legacy]
        } else { throw UsageError.message("Codex 未返回额度，请确认已用 ChatGPT 账号登录。") }
        for key in buckets.keys.sorted(by: { ($0 == "codex" ? "" : $0) < ($1 == "codex" ? "" : $1) }) {
            guard let bucket = buckets[key] as? [String: Any] else { continue }
            plan = plan ?? bucket["planType"] as? String
            for windowKey in ["primary", "secondary"] {
                guard let w = bucket[windowKey] as? [String: Any], let used = number(w["usedPercent"]) else { continue }
                let minutes = number(w["windowDurationMins"])
                let label: String
                if minutes == 10080 { label = "每周额度" }
                else if let m = minutes, m > 0 {
                    label = m >= 60 ? String(format: "%g 小时额度", m / 60) : String(format: "%g 分钟额度", m)
                } else { label = windowKey == "primary" ? "短周期额度" : "长周期额度" }
                let name = bucket["limitName"] as? String ?? key
                quotas.append(Quota(id: "\(key).\(windowKey)", label: key == "codex" ? label : "\(name) · \(label)", remaining: remaining(used), resetsAt: date(w["resetsAt"])))
            }
        }
        guard !quotas.isEmpty else { throw UsageError.message("Codex 当前账号没有可读取的订阅额度。") }
        let main = quotas.filter { $0.id.hasPrefix("codex.") }
        return UsageSnapshot(provider: "Codex", plan: plan?.capitalized, quotas: quotas,
                             summaryRemaining: (main.isEmpty ? quotas : main).map(\.remaining).min()!,
                             note: "菜单栏显示主额度各窗口中较低的剩余比例。")
    }

    static func cursor(_ root: [String: Any], plan: String? = nil) throws -> UsageSnapshot {
        guard let p = root["planUsage"] as? [String: Any] else {
            throw UsageError.message("Cursor 未返回套餐额度，请在 Cursor 中确认登录和订阅状态。")
        }
        let reset = date(root["billingCycleEnd"], milliseconds: true)
        var quotas: [Quota] = []
        // Prefer the percentages used by the current Cursor client. The legacy dollar
        // limit can differ from the total model-pool allowance; never combine the two.
        if let used = number(p["totalPercentUsed"]) {
            quotas.append(Quota(id: "total", label: "总额度", remaining: remaining(used), resetsAt: reset))
        }
        for (key, label, id) in [("autoPercentUsed", "Cursor 模型池", "auto"), ("apiPercentUsed", "其他模型池", "api")] {
            if let used = number(p[key]) {
                quotas.append(Quota(id: id, label: label, remaining: remaining(used), resetsAt: reset))
            }
        }
        let limit = number(p["limit"])
        let included = number(p["includedSpend"]) ?? {
            if let limit, let remaining = number(p["remaining"]) { return limit - remaining }
            return nil
        }()
        var note: String?
        if let limit, let included, limit > 0 {
            let dollars = max(0, number(p["remaining"]) ?? (limit - included)) / 100
            note = String(format: "基础额度剩余 $%.2f / $%.2f；与总额度比例口径不同。", dollars, limit / 100)
            if quotas.isEmpty {
                quotas.append(Quota(id: "included", label: "基础套餐额度", remaining: remaining(included / limit * 100), resetsAt: reset,
                                    detail: String(format: "剩余 $%.2f / $%.2f", dollars, limit / 100)))
                note = "服务未提供模型池比例，显示基础套餐额度。"
            }
        }
        guard !quotas.isEmpty else { throw UsageError.message("Cursor 未提供可计算的剩余额度。") }
        if p["remainingBonus"] as? Bool == true { note = (note ?? "") + " 另有赠送用量可用。" }
        let summary = quotas.first(where: { $0.id == "total" })?.remaining ?? quotas.map(\.remaining).min()!
        return UsageSnapshot(provider: "Cursor", plan: plan, quotas: quotas, summaryRemaining: summary, note: note)
    }
}

import CoreFoundation
