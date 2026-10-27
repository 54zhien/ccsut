import Foundation

@main struct ExamDateTests {
    static func main() throws {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        let exam = try JSONDecoder().decode(ExamItem.self, from: Data(
            #"{"id":"fixture","ksrq":"2026-10-27","qssj":"08:00"}"#.utf8))
        let text = exam.schoolDateText ?? ""
        guard text.contains("27"), text.contains("星期二") else {
            print("FAIL school exam date changed outside Shanghai: \(text)")
            exit(1)
        }
        print("PASS school exam date remains October 27, Tuesday outside Shanghai")
    }
}
