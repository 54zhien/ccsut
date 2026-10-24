import Foundation

extension APIClient {
    func timetableContext() async throws -> TimetableContext {
        let page = try await scheduleHTML()
        return try AcademicCalendarParser.timetable(page)
    }

    func availableExamTerms() async throws -> [String] {
        let page = try await html("/admin/xsd/kwglXsdKscx/kslist", query: [
            URLQueryItem(name: "role", value: "xs"), URLQueryItem(name: "cpdx", value: "")
        ])
        return try AcademicCalendarParser.examTerms(page)
    }
}
