import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }

            HistoryListView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            StatisticsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar")
                }
        }
    }
}
