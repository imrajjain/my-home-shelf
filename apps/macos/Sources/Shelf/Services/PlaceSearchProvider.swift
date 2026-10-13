import Foundation
import MapKit
import ShelfCore

/// Apple Maps search for "places I want to go".
struct PlaceSearchProvider: SearchProvider {
    let name = "Apple Maps"
    let kinds: Set<ItemKind> = [.place]

    func search(_ query: String, kind: ItemKind) async throws -> [Metadata] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(8).compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            var m = Metadata(kind: .place, title: name, provider: self.name)
            m.subtitle = Self.address(item.placemark)
            m.creator = item.pointOfInterestCategory.map(Self.categoryName)
            m.extra["latitude"] = String(coordinate.latitude)
            m.extra["longitude"] = String(coordinate.longitude)
            let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            m.url = item.url ?? URL(string: "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(q)")
            m.externalID = "maps:\(coordinate.latitude),\(coordinate.longitude)"
            return m
        }
    }

    static func address(_ p: MKPlacemark) -> String? {
        let parts = [p.locality, p.administrativeArea, p.country].compactMap { $0 }
        return parts.isEmpty ? p.title : parts.joined(separator: ", ")
    }

    static func categoryName(_ c: MKPointOfInterestCategory) -> String {
        // "MKPOICategoryRestaurant" -> "Restaurant"
        let raw = c.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
        return raw.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }
}

/// Renders a soft map tile to use as a place's cover.
enum MapCover {
    static func snapshot(latitude: Double, longitude: Double) async -> Data? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: 1600, longitudinalMeters: 1600
        )
        options.size = CGSize(width: 600, height: 600)
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let image = snapshot.image
        // Drop a little pin in the middle.
        let composed = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            NSColor(hex: 0xC2577E).setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9)).fill()
            return true
        }
        return ImageCache.jpeg(composed, maxDimension: 600)
    }
}
