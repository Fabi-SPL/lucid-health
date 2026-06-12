import SwiftUI
import VisionKit

/// DataScannerViewController wrapper — fires once per valid barcode.
struct BarcodeScannerView: UIViewControllerRepresentable {
    /// When set, the scanned product is returned as a DetectedItem WITHOUT saving
    /// (meal-builder mode). When nil, it saves a standalone barcode entry.
    var onItem: ((DetectedItem) -> Void)? = nil
    let onEntry: (FoodEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BarcodeScannerView
        private var didFire = false

        init(_ parent: BarcodeScannerView) { self.parent = parent }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didFire else { return }
            if case .barcode(let barcode) = addedItems.first,
               let code = barcode.payloadStringValue {
                didFire = true
                dataScanner.stopScanning()
                Task { @MainActor in
                    await parent.lookup(code: code, scanner: dataScanner)
                }
            }
        }
    }

    @MainActor
    private func lookup(code: String, scanner: DataScannerViewController) async {
        do {
            let product = try await OpenFoodFactsClient.shared.lookup(barcode: code)
            if let onItem {
                onItem(SupabaseClient.shared.barcodeItem(from: product))
            } else {
                onEntry(try await SupabaseClient.shared.saveBarcodeEntry(product: product))
            }
            dismiss()
        } catch {
            // Lookup failed (not found / network) — just close.
            dismiss()
        }
    }
}

// MARK: - Barcode Scanner Sheet (full-screen wrapper)

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onEntry: (FoodEntry) -> Void

    @State private var scannedCode: String?
    @State private var product: OpenFoodFactsProduct?
    @State private var isLooking = false
    @State private var lookupError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground()

                if let product {
                    BarcodeResultView(product: product) { entry in
                        onEntry(entry)
                        dismiss()
                    }
                } else if isLooking {
                    VStack(spacing: DS.Spacing.md) {
                        ProgressView().tint(DS.Colors.violet)
                        Text("Produkt suchen…")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                } else if let err = lookupError {
                    VStack(spacing: DS.Spacing.md) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 48))
                            .foregroundStyle(DS.Colors.textMuted)
                        Text(err)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            lookupError = nil; scannedCode = nil
                        }
                        .foregroundStyle(DS.Colors.violet)
                    }
                    .padding(DS.Spacing.xl)
                } else {
                    // Live scanner overlay
                    BarcodeScannerView { entry in
                        onEntry(entry)
                        dismiss()
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        Text("Barcode anvisieren")
                            .font(DS.Font.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(8)
                            .background(.black.opacity(0.4))
                            .clipShape(Capsule())
                            .padding(.top, DS.Spacing.md)
                    }
                }
            }
            .navigationTitle("Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func lookup(code: String) {
        isLooking = true
        lookupError = nil
        Task {
            do {
                product = try await OpenFoodFactsClient.shared.lookup(barcode: code)
            } catch {
                lookupError = error.localizedDescription
            }
            isLooking = false
        }
    }
}
