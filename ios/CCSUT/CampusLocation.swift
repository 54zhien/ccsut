import Foundation
@preconcurrency import CoreLocation

@MainActor final class CampusLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<(latitude: Double, longitude: Double), Error>?
    private var deadline: Task<Void, Never>?

    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func coordinate() async throws -> (latitude: Double, longitude: Double) {
        guard continuation == nil else { throw CampusFormError.validation("正在定位，请稍候") }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { callback in
                continuation = callback
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    self?.finish(.failure(CampusFormError.validation("定位超时，请稍后重试")))
                }
                authorize(manager.authorizationStatus)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func authorize(_ status: CLAuthorizationStatus) {
        guard continuation != nil else { return }
        switch status {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: finish(.failure(CampusFormError.validation("学校要求定位，请在系统设置中允许本 App 使用位置")))
        @unknown default: finish(.failure(CampusFormError.validation("暂时无法使用定位")))
        }
    }
    private func finish(_ result: Result<(latitude: Double, longitude: Double), Error>) {
        guard let callback = continuation else { return }
        continuation = nil; deadline?.cancel(); deadline = nil; manager.stopUpdatingLocation()
        callback.resume(with: result)
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.authorize(status) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude, longitude = location.coordinate.longitude
        let accuracy = location.horizontalAccuracy, recent = abs(location.timestamp.timeIntervalSinceNow) < 120
        Task { @MainActor [weak self] in
            guard recent, accuracy >= 0, accuracy <= 500 else {
                self?.finish(.failure(CampusFormError.validation("定位精度不足，请启用精确位置后重试"))); return
            }
            self?.finish(.success(CampusCoordinates.gcj02(latitude: latitude, longitude: longitude)))
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.finish(.failure(CampusFormError.validation("无法获取当前位置，请稍后重试"))) }
    }
}
