import Foundation

@main
struct ReleasePreviewTests {
    static func main() {
        // This runner is compiled without DEBUG and deliberately gets preview arguments.
        guard !InterfacePreview.enabled, InterfacePreview.page.isEmpty else {
            print("FAIL release builds must ignore preview arguments")
            exit(1)
        }
        print("PASS release builds ignore simulator preview arguments")
    }
}
