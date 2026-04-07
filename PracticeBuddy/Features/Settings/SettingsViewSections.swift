import SwiftUI

extension SettingsView {
    var settingsForm: some View {
        ScrollViewReader { proxy in
            Form {
                goalsSection
                appearanceSection
                generalSection
                accountSection
                toolAccessSection
                notificationsSection
                #if DEBUG
                if canShowAdsDebugSection {
                    adsSection
                }
                #endif
                historySection
                AboutSectionView()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onChange(of: scrollAnchorTarget) { _, target in
                guard let target else { return }
                withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(.clear)
    }

    var goalsSection: some View {
        Section {
            settingsSectionCard {
                Picker("Goal period", selection: goalScopeBinding) {
                    ForEach(GoalScope.allCases) { scope in
                        Text(LocalizedStringKey(scope.title)).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(value: $goalMinutes, in: 0...600, step: 5) {
                    HStack {
                        Text("Goal")
                            .font(type.body)
                        Spacer()
                        if goalMinutes == 0 {
                            Text("Off")
                                .font(type.body)
                                .foregroundStyle(palette.textSecondary)
                        } else {
                            let scope = GoalScope(rawValue: goalScopeRaw) ?? .today
                            Text(
                                L10n.f(
                                    "%@ min / %@",
                                    "\(goalMinutes)",
                                    String(localized: String.LocalizationValue(scope.title))
                                )
                            )
                            .font(type.body)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                        }
                    }
                }

                Text(goalMinutes == 0 ? "Turn this on to track progress." : "Progress is tracked for the selected period.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        } header: {
            PBSectionHeaderLabel(title: "Goals")
        }
        .id(SettingsAnchor.goals)
    }

    var appearanceSection: some View {
        Section {
            settingsSectionCard {
                NavigationLink { PBLazyView(ThemePickerView()) } label: {
                    settingsLabel("Themes", systemImage: "paintpalette")
                }
            }

            settingsSectionCard {
                NavigationLink { PBLazyView(FontPickerView()) } label: {
                    settingsLabel("Fonts", systemImage: "textformat")
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Appearance")
        }
        .id(SettingsAnchor.appearance)
    }

    var generalSection: some View {
        Section {
            settingsSectionCard {
                Picker("Language", selection: appLanguageBinding) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(LocalizedStringKey(lang.titleKey)).tag(lang)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    tutorialReplayToken = Int(Date().timeIntervalSince1970)
                } label: {
                    settingsLabel("Replay Tutorial", systemImage: "sparkles.rectangle.stack")
                }
                .buttonStyle(.plain)

                Text("Reopens the quick in-app walkthrough.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        } header: {
            PBSectionHeaderLabel(title: "General")
        }
    }

    var toolAccessSection: some View {
        Section {
            settingsSectionCard {
                Picker("Primary focus", selection: Binding(
                    get: { purchaseManager.primaryFocus },
                    set: { purchaseManager.setPrimaryFocus($0) }
                )) {
                    ForEach(PBPrimaryFocus.allCases) { focus in
                        Text(LocalizedStringKey(focus.title)).tag(focus)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Student Tools", isOn: Binding(
                    get: { purchaseManager.canAccessStudentTools },
                    set: { purchaseManager.setShowStudentTools($0) }
                ))
                .font(type.body)

                Toggle("Teacher Tools", isOn: Binding(
                    get: { purchaseManager.canAccessTeacherTools },
                    set: { purchaseManager.setShowTeacherTools($0) }
                ))
                .font(type.body)

                Text("Studio Manager is available under Teacher Tools.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        } header: {
            PBSectionHeaderLabel(title: "Tool Access")
        }
    }

    var accountSection: some View {
        Section {
            settingsSectionCard {
                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(Color.red)
                        Text("Sign Out")
                            .font(type.body)
                            .foregroundStyle(Color.red)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                Text("Sign out to switch accounts.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        } header: {
            PBSectionHeaderLabel(title: "Account")
        }
    }

    var notificationsSection: some View {
        Section {
            settingsSectionCard {
                if notificationAuthorizationStatus != .authorized && notificationAuthorizationStatus != .provisional && notificationAuthorizationStatus != .ephemeral {
                    Button("Enable iOS Notifications") {
                        Task {
                            _ = await PBNotificationCenter.requestAuthorizationIfNeeded()
                            await refreshNotificationAuthorizationStatus()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Group {
                    Toggle("Duel challenges", isOn: $notifyDuels)
                        .font(type.body)
                    Toggle("Messages", isOn: $notifyMessages)
                        .font(type.body)
                    Toggle("Goal reached", isOn: $notifyGoals)
                        .font(type.body)
                    Toggle("Friend requests", isOn: $notifyFriendRequests)
                        .font(type.body)
                    Toggle("Studio invites", isOn: $notifyStudioInvites)
                        .font(type.body)
                }

                Toggle("Assignments", isOn: $notifyAssignments)
                    .font(type.body)
                Toggle("Buddies", isOn: $notifyBuddies)
                    .font(type.body)

                Text("Use iPhone Settings to control lock-screen/banner style. In-app toggles choose which categories you receive.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)

                Button("Open iOS Notification Settings") {
                    PBNotificationCenter.openSystemNotificationSettings()
                }
                .buttonStyle(.bordered)

                #if DEBUG
                if canShowAdsDebugSection {
                    Button("Send Test Push") {
                        Task { await sendPushTestNotification() }
                    }
                    .buttonStyle(.bordered)

                    if let pushTestStatus {
                        Text(pushTestStatus)
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                #endif
            }
        } header: {
            PBSectionHeaderLabel(title: "Notifications")
        }
        .id(SettingsAnchor.notifications)
    }

    var historySection: some View {
        Section {
            settingsSectionCard {
                NavigationLink {
                    PBLazyView(HistoryRetentionPickerView(selection: $historyRetention))
                } label: {
                    HStack {
                        Text("Keep history")
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)

                        Spacer()

                        Text(LocalizedStringKey(historyRetentionDisplay))
                            .font(type.body)
                            .foregroundStyle(historyRetentionDisplayStyle)
                            .monospacedDigit()
                    }
                }

                Text(historyRetention == 0
                     ? "Your practice history is kept indefinitely."
                     : "Older sessions are automatically deleted after you exceed \(historyRetention) sessions.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
            }
        } header: {
            PBSectionHeaderLabel(title: "History")
        }
    }

    var adsSection: some View {
        Section {
            settingsSectionCard {
                Toggle(
                    "Show Ad Placeholders",
                    isOn: Binding(
                        get: { adsManager.showPlaceholders },
                        set: { adsManager.setShowPlaceholders($0) }
                    )
                )
                .font(type.body)

                Toggle(
                    "Enable Banner Ads",
                    isOn: Binding(
                        get: { adsManager.enableBannerAds },
                        set: { adsManager.setEnableBannerAds($0) }
                    )
                )
                .font(type.body)

                Toggle(
                    "Enable Rewarded Duel Ads",
                    isOn: Binding(
                        get: { adsManager.enableRewardedDuels },
                        set: { adsManager.setEnableRewardedDuels($0) }
                    )
                )
                .font(type.body)

                Toggle(
                    "Enable Real Ad SDK (Test IDs)",
                    isOn: Binding(
                        get: { adsManager.enableRealAdSDK },
                        set: { adsManager.setEnableRealAdSDK($0) }
                    )
                )
                .font(type.body)

                Toggle(
                    "Allow Ads",
                    isOn: Binding(
                        get: { adsManager.consentAllowsAds },
                        set: { adsManager.setConsentAllowsAds($0) }
                    )
                )
                .font(type.body)

                Text(adsManager.adsEnabled ? "Ads are currently enabled for this account." : "Ads are disabled (Ad-Free active or ads turned off).")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)

                Text(adsManager.sdkStatusLine)
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        } header: {
            PBSectionHeaderLabel(title: "Ads")
        }
    }

    var settingsShortcutRow: some View {
        PBShortcutBar(items: settingsShortcutItems, palette: palette)
            .padding(.horizontal, PBLayout.padSM)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .offset(y: animateHeader ? 0 : 10)
            .opacity(animateHeader ? 1 : 0)
    }

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(type.appTitle)
                .tracking(type.heroTracking)
                .foregroundStyle(palette.textPrimary)

            Text("Personalize your practice flow, notifications, and app experience.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padLG)
        .pbFlatCard(palette: palette)
        .padding(.horizontal, PBLayout.padSM)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .offset(y: animateHeader ? 0 : 12)
        .opacity(animateHeader ? 1 : 0)
    }

    @ViewBuilder
    func settingsLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(palette.accent)
            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
        }
    }
}
