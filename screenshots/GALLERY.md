# SwiftDBAI Screenshots

## Query Results

Bar chart and data table from a natural language query against a GitHub stars database.

![Results with chart](results-chart.png)

## Customization

### Custom Theme

Purple accent, custom placeholder ("Search GitHub repos..."), custom empty state icon and text.

```swift
var config = ChatViewConfiguration.default
config.userBubbleColor = .purple
config.accentColor = .purple
config.inputPlaceholder = "Search GitHub repos..."
config.emptyStateTitle = "Explore GitHub Data"
config.emptyStateIcon = "star.circle"

DataChatView(databasePath: path, model: myLLM)
    .chatViewConfiguration(config)
```

| Empty state | With results |
|---|---|
| ![Custom empty](custom-theme.png) | ![Custom results](custom-results.png) |

### Dark Theme

```swift
DataChatView(databasePath: path, model: myLLM)
    .chatViewConfiguration(.dark)
```

![Dark theme](dark-theme.png)

### Compact Theme

```swift
DataChatView(databasePath: path, model: myLLM)
    .chatViewConfiguration(.compact)
```

![Compact theme](compact-theme.png)

## Presentation Modes

![Presentation modes](presentation-modes.png)

### Sheet

```swift
.sheet(isPresented: $showChat) {
    DataChatSheet(databasePath: path, model: myLLM, title: "GitHub Stars")
}
```

![Sheet presentation](sheet-presentation.png)
