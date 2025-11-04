//
//  ContentView.swift
//  tab restore
//
//  Created by Wayne Yao on 11/4/25.
//

import SwiftUI
import AppKit

/// Root view that lists the recently closed Safari windows and allows the user to restore tabs.
struct ContentView: View {
    @StateObject private var viewModel = RestoreTabsViewModel()
    @State private var showingWindowWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recently Closed Safari Tabs")
                .font(.title2)
                .bold()

            if viewModel.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading tabs…")
                }
            } else if let error = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Button("Try Again") {
                        viewModel.load()
                    }
                }
            } else if viewModel.windows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No recently closed windows or tabs were found.")
                        .foregroundColor(.secondary)
                    Button("Reload") {
                        viewModel.load()
                    }
                }
            } else {
                windowsList
            }

            statusSection
            actionButtons
        }
        .padding()
        .frame(minWidth: 580, minHeight: 480)
        .onAppear {
            viewModel.load()
            viewModel.showWarningCallback = {
                showingWindowWarning = true
            }
        }
        .alert("Too Many Windows Warning", isPresented: $showingWindowWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Continue Anyway") {
                viewModel.forceRestoreSelectedTabs()
            }
        } message: {
            Text("You're about to open more than 10 windows simultaneously. This may cause Safari to become unresponsive or slow. Are you sure you want to continue?")
        }
    }

    /// Scrollable list that groups the recovered tabs by the window they belonged to.
    private var windowsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.windows) { window in
                    VStack(alignment: .leading, spacing: 12) {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { viewModel.isWindowExpanded(window.id) },
                                set: { viewModel.setWindowExpanded(window.id, expanded: $0) }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(window.tabs) { tab in
                                    Toggle(isOn: Binding(
                                        get: { viewModel.isTabSelected(windowID: window.id, tabID: tab.id) },
                                        set: { viewModel.setTabSelected(windowID: window.id, tabID: tab.id, isSelected: $0) }
                                    )) {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text(tab.displayTitle)
                                                .fontWeight(.semibold)
                                                .lineLimit(1)
                                            Text(tab.url)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.top, 6)
                            .padding(.leading, 4)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Toggle(isOn: Binding(
                                    get: { viewModel.areAllTabsSelected(in: window.id) },
                                    set: { viewModel.setAllTabs(in: window.id, isSelected: $0) }
                                )) {
                                    Text(viewModel.windowLabel(for: window.id))
                                        .font(.headline)
                                }
                                .toggleStyle(.checkbox)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer()
                                Text(viewModel.selectionSummary(for: window.id))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 300)
    }

    /// Shows feedback related to the most recent restore attempt.
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let status = viewModel.statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            }
            if let error = viewModel.operationError {
                Label(error, systemImage: "xmark.octagon")
                    .foregroundColor(.red)
            }
        }
    }

    /// Provides batch selection and restore controls.
    private var actionButtons: some View {
        HStack {
            Button(viewModel.isFullySelected ? "Deselect All" : "Select All") {
                viewModel.toggleSelectAll()
            }
            Button("Clear Selection") {
                viewModel.clearSelection()
            }
            Spacer()
            Button("Restore Selected") {
                viewModel.restoreSelectedTabs()
            }
            .disabled(!viewModel.hasSelection)
            .keyboardShortcut(.defaultAction)
        }
    }
}
