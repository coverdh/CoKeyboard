import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            TestView()
                .tabItem {
                    Label("Test", systemImage: "keyboard")
                }

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
