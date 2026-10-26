import Testing
@testable import ASBCore

@Test func everyBuiltInThemeCoversEveryState() {
    for (name, theme) in Theme.builtIn {
        for state in Config.themeStates {
            #expect(!theme.symbol(state).isEmpty, "\(name) has no icon for \(state)")
            #expect(Config.isValid(theme.color(state), for: "color_\(state)"), "\(name) color for \(state)")
        }
    }
}

@Test func theDefaultThemeMatchesTheShellPlugin() {
    let theme = Theme.resolve(Config())
    #expect(theme.symbol("idle") == "zzz" && theme.color("idle") == "#B25000,#FFD60A")
    #expect(theme.symbol("waiting") == "exclamationmark.circle.fill" && theme.color("waiting") == "#D70015,#FF453A")
    #expect(theme.symbol("busy") == "sparkle" && theme.color("busy") == "#6E6E73,#AEAEB2")
    #expect(theme.symbol("subagents") == "hourglass")
    #expect(theme.symbol("muted") == "bell.slash" && theme.color("muted") == "#8E8E93,#98989D")
    #expect(theme.color("none") == "#C7C7CC,#48484A")
}

@Test func theConfiguredThemeIsUsed() {
    let theme = Theme.resolve(Config.parse("theme=high_contrast"))
    #expect(theme.symbol("idle") == "moon.zzz.fill" && theme.color("idle") == "#C93400,#FFD60A")
    #expect(theme.symbol("subagents") == "hourglass.circle.fill")
}

@Test func anUnknownThemeFallsBackToTheDefault() {
    #expect(Theme.resolve(Config.parse("theme=nope")) == Theme.resolve(Config()))
}

@Test func theOlderIconKeySetsTheBusyAndEmptyIcon() {
    let theme = Theme.resolve(Config.parse("icon=bolt"))
    #expect(theme.symbol("busy") == "bolt" && theme.symbol("none") == "bolt")
    #expect(theme.symbol("idle") == "zzz")
}

@Test func perStateOverridesWinOverTheThemeAndTheIconKey() {
    let theme = Theme.resolve(Config.parse("theme=monochrome\nicon=bolt\nicon_idle=moon.zzz\ncolor_idle=#112233,#445566\nicon_busy=flame"))
    #expect(theme.symbol("idle") == "moon.zzz" && theme.color("idle") == "#112233,#445566")
    #expect(theme.symbol("busy") == "flame" && theme.symbol("none") == "bolt")
    #expect(theme.color("waiting") == "#1D1D1F,#F5F5F7")
}

@Test func aSubagentsOverrideFollowsTheTheme() {
    let theme = Theme.resolve(Config.parse("theme=high_contrast\ncolor_subagents=#112233"))
    #expect(theme.symbol("subagents") == "hourglass.circle.fill" && theme.color("subagents") == "#112233")
}
