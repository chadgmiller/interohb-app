import SwiftUI

// Lightweight marker protocol used by custom tab builders
protocol TabContent { }

// Allow Card views to be used in TabContent builder contexts
extension Card: TabContent where Content: View { }
