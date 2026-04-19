import WidgetKit
import SwiftUI

/// Entry point for the BDN widget extension.
/// Contains both the Headlines and Sports widgets.
@main
struct BDNWidgetBundle: WidgetBundle {
    var body: some Widget {
        BDNHeadlineWidget()
        BDNSportsWidget()
    }
}
