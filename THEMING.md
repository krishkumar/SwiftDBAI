# Theming

SwiftDBAI's chat interface is customizable through `ChatViewConfiguration`. Pass it via the `.chatViewConfiguration()` view modifier -- it propagates through the entire view hierarchy via SwiftUI environment.

## Built-in Presets

### Default

The standard look. Blue user bubbles, system-colored assistant bubbles, standard fonts.

```swift
DataChatView(databasePath: path, model: myLLM)
// .chatViewConfiguration(.default) is implicit
```

![Default](screenshots/results-chart.png)

### Dark

Muted colors for dark backgrounds. Dark gray bubbles, light text, black background.

```swift
DataChatView(databasePath: path, model: myLLM)
    .chatViewConfiguration(.dark)
```

![Dark](screenshots/dark-theme.png)

### Compact

Smaller fonts, tighter padding, no SQL disclosure. Good for embedded or secondary views.

```swift
DataChatView(databasePath: path, model: myLLM)
    .chatViewConfiguration(.compact)
```

![Compact](screenshots/compact-theme.png)

## Custom Configuration

Start from any preset and override what you need:

```swift
var config = ChatViewConfiguration.default
config.userBubbleColor = .purple
config.userTextColor = .white
config.accentColor = .purple
config.inputPlaceholder = "Search GitHub repos..."
config.emptyStateTitle = "Explore GitHub Data"
config.emptyStateSubtitle = "Ask about stars, forks, languages, and trends"
config.emptyStateIcon = "star.circle"

DataChatView(databasePath: path, model: myLLM)
    .chatViewConfiguration(config)
```

| Custom empty state | Custom with results |
|---|---|
| ![Custom empty](screenshots/custom-theme.png) | ![Custom results](screenshots/custom-results.png) |

## Available Properties

### Colors

| Property | Default | Description |
|---|---|---|
| `userBubbleColor` | `.accentColor` | Background of user message bubbles |
| `userTextColor` | `.white` | Text color in user bubbles |
| `assistantBubbleColor` | System secondary | Background of assistant bubbles |
| `assistantTextColor` | `.primary` | Text color in assistant bubbles |
| `backgroundColor` | `.clear` | Overall chat view background |
| `inputBarBackgroundColor` | `.clear` | Input bar area background |
| `accentColor` | `.accentColor` | Send button and interactive elements |
| `errorColor` | `.red` | Error message icon and border |

### Typography

| Property | Default | Description |
|---|---|---|
| `messageFont` | `.body` | Chat message text |
| `summaryFont` | `.body` | Natural language summary |
| `sqlFont` | `.caption monospaced` | SQL query display |
| `inputFont` | `.body` | Text input field |

### Layout & Content

| Property | Default | Description |
|---|---|---|
| `messagePadding` | `14` | Padding inside message bubbles |
| `bubbleCornerRadius` | `16` | Corner radius of bubbles |
| `showTimestamps` | `false` | Show timestamps on messages |
| `showSQLDisclosure` | `true` | Show the "</> SQL Query" expandable section |
| `inputPlaceholder` | `"Ask about your data..."` | Placeholder text in input field |
| `emptyStateTitle` | `"Ask a question about your data"` | Title when no messages |
| `emptyStateSubtitle` | `"Try something like..."` | Subtitle when no messages |
| `emptyStateIcon` | `"bubble.left.and.text.bubble.right"` | SF Symbol for empty state |

### Avatar

| Property | Default | Description |
|---|---|---|
| `assistantAvatarIcon` | `nil` | SF Symbol for assistant avatar (e.g. `"sparkles"`, `"person.crop.circle.fill"`) |
| `assistantAvatarColor` | `.accentColor` | Background color of the avatar circle |

When set, a circular avatar appears next to every assistant message:

```swift
config.assistantAvatarIcon = "sparkles"
config.assistantAvatarColor = .purple
```

![Custom with avatar](screenshots/custom-results.png)

## Works with All Presentation Modes

The configuration propagates through sheets, navigation, and UIKit bridges:

```swift
// Sheet
.sheet(isPresented: $show) {
    DataChatSheet(databasePath: path, model: myLLM)
        .chatViewConfiguration(.dark)
}

// UIKit
let vc = DataChatViewController(databasePath: path, model: myLLM)
// Configuration can be set on the rootView before presenting
```

![Sheet presentation](screenshots/sheet-presentation.png)
