import MapKit
import SwiftUI

/// A full address picked from the suggestions.
struct AddressParts: Equatable {
    var street: String
    var city: String
    /// Two-letter code, e.g. "GA".
    var state: String
    var postalCode: String
}

/// Address suggestions as the user types, from Apple Maps (no API key, no location permission).
/// Results lean towards Georgia and South Carolina, where most claims are.
@MainActor
@Observable
final class AddressAutocomplete: NSObject {
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    private(set) var isResolving = false
    private let completer = MKLocalSearchCompleter()
    /// The text the last pick filled in, so it doesn't immediately suggest itself again.
    private var filledStreet: String?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.4, longitude: -82.0),
            span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 8)
        )
    }

    /// Call when the street text changes.
    func update(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3, query != filledStreet else {
            completer.cancel()
            suggestions = []
            return
        }
        completer.queryFragment = query
    }

    func clear() {
        completer.cancel()
        suggestions = []
    }

    /// Looks up the full address for a suggestion.
    func resolve(_ completion: MKLocalSearchCompletion) async -> AddressParts? {
        isResolving = true
        defer { isResolving = false }
        suggestions = []
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first else {
            return nil
        }
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = AddressParts(
            street: street.isEmpty ? completion.title : street,
            city: placemark.locality ?? "",
            state: placemark.administrativeArea ?? "",
            postalCode: String((placemark.postalCode ?? "").prefix(5))
        )
        filledStreet = parts.street
        return parts
    }

}

// MapKit calls the delegate on the main thread.
extension AddressAutocomplete: @preconcurrency MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Georgia and South Carolina first (the region is only a hint to Apple Maps).
        let local = completer.results.filter(Self.isLocal)
        let other = completer.results.filter { !Self.isLocal($0) }
        suggestions = Array((local + other).prefix(5))
    }

    private static func isLocal(_ completion: MKLocalSearchCompletion) -> Bool {
        let text = completion.title + ", " + completion.subtitle
        return [", GA", ", SC", "Georgia", "South Carolina"].contains { text.contains($0) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}

/// True while a StreetAddressField is showing suggestions, so screens can move floating bars aside.
struct AddressSuggestionsShowing: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// The Street field with suggestions under it, for a Form section. Picking one calls `fill`.
struct StreetAddressField: View {
    @Binding var street: String
    let fill: (AddressParts) -> Void
    @State private var autocomplete = AddressAutocomplete()
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Street", text: $street)
            .textContentType(.fullStreetAddress)
            .autocorrectionDisabled()
            .focused($focused)
            .accessibilityIdentifier("streetAddress")
            .preference(key: AddressSuggestionsShowing.self, value: !autocomplete.suggestions.isEmpty)
            .onChange(of: street) { _, text in
                if focused { autocomplete.update(text) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { autocomplete.clear() }
            }
        if autocomplete.isResolving {
            HStack {
                ProgressView()
                Text("Filling in the address…").foregroundStyle(Color.textSecondary)
            }
        }
        ForEach(autocomplete.suggestions, id: \.self) { suggestion in
            Button {
                Task {
                    if let parts = await autocomplete.resolve(suggestion) {
                        fill(parts)
                        focused = false
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Color.brandPrimary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .foregroundStyle(Color.textPrimary)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .frame(minHeight: Theme.minTapTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Fills in the address")
            .accessibilityIdentifier("addressSuggestion")
        }
    }
}
