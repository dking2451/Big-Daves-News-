import WidgetKit
import SwiftUI

/// Entry point for the BDN widget extension.
/// Contains Headlines, Sports widgets, and the Sports Live Activity.
@main
struct BDNWidgetBundle: WidgetBundle {
    var body: some Widget {
        BDNHeadlineWidget()
        BDNSportsWidget()
        BDNLiveActivity()
    }
}
