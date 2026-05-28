import SwiftUI
import UIKit

/// Coches / Buscador: pastilla de búsqueda + ordenar/filtros. Ajustes: pestaña inferior «Ajustes».
struct CarsBrowseHeaderBar: View {
    @Binding var searchText: String
    var hasActiveFilters: Bool
    @FocusState.Binding var searchFieldFocused: Bool
    var onSort: () -> Void
    var onFilter: () -> Void

    var body: some View {
        ChromeSearchTrailingHeaderRow(
            searchText: $searchText,
            prompt: Text(L10n.tr("cars.searchPrompt"))
                .foregroundStyle(Color.black),
            showsSearchClearButton: true,
            searchFieldFocused: $searchFieldFocused
        ) {
            HStack(spacing: AppChromeHeaderMetrics.hStackSpacing) {
                AppChromeHeaderCircleIconButton(
                    systemName: "arrow.up.arrow.down",
                    accessibilityLabel: LocalizedStringKey(L10n.tr("common.sort")),
                    action: onSort
                )

                ZStack(alignment: .topTrailing) {
                    AppChromeHeaderCircleIconButton(
                        systemName: "slider.horizontal.3",
                        accessibilityLabel: LocalizedStringKey(L10n.tr("common.filters")),
                        action: onFilter
                    )
                    if hasActiveFilters {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -3)
                    }
                }
            }
        }
    }
}

private struct CarsBrowseHeaderBarPreviewHost: View {
    @FocusState private var focused: Bool
    var body: some View {
        CarsBrowseHeaderBar(
            searchText: .constant(""),
            hasActiveFilters: true,
            searchFieldFocused: $focused,
            onSort: {},
            onFilter: {}
        )
        .padding()
        .background(Color.black)
    }
}

#Preview {
    CarsBrowseHeaderBarPreviewHost()
}
