// DiscoverView.swift
import SwiftUI

/// D01 · Discover landing. (Screens land in the following commits.)
struct DiscoverView: View {
    var body: some View { PlaceholderScreen(title: "Discover") }
}

/// Every Discover push destination, kept out of MainShell so Discover changes don't touch it.
struct DiscoverDestination: View {
    let route: Route
    var body: some View { PlaceholderScreen(title: "Discover", canPop: true) }
}
