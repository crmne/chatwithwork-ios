import HotwireNative
import UIKit
import WebKit

/// `search`: a native search bar under the navigation bar's title that
/// filters the page as you type.
///
/// Web → native: `connect` with `{placeholder?}`. Native → web: replies to
/// `connect` with `{query}` on every change. Joe Masilotti's contract, drawn
/// here so the bar lives with the rest of the app's navigation bar handling.
final class NavigationSearchComponent: BridgeComponent {
    override nonisolated class var name: String { "search" }

    private var searchController: UISearchController?
    private lazy var updater = SearchUpdater { [weak self] query in
        self?.reply(to: "connect", with: SearchQuery(query: query))
    }

    override func onReceive(message: Message) {
        guard message.event == "connect", let viewController = destinationViewController else { return }
        let data: SearchData? = message.data()

        let controller = searchController ?? UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchResultsUpdater = updater
        controller.searchBar.placeholder = data?.placeholder
        controller.searchBar.accessibilityIdentifier = "bridge.search"
        searchController = controller

        let navigationItem = viewController.navigationItem
        navigationItem.preferredSearchBarPlacement = .stacked
        navigationItem.searchController = controller
        navigationItem.hidesSearchBarWhenScrolling = true
        viewController.definesPresentationContext = true
        // The bar makes the navigation bar taller; AppNavigationController
        // keeps a page that sat at its top right under it (TopEdge).
    }
}

nonisolated struct SearchData: Decodable, Equatable {
    let placeholder: String?
}

nonisolated struct SearchQuery: Encodable, Equatable {
    let query: String?
}

private final class SearchUpdater: NSObject, UISearchResultsUpdating {
    let onChange: (String?) -> Void

    init(onChange: @escaping (String?) -> Void) {
        self.onChange = onChange
    }

    func updateSearchResults(for searchController: UISearchController) {
        onChange(searchController.searchBar.text)
    }
}
