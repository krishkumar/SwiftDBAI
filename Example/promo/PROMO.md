# SwiftDBAI -- Promotional Materials

## Dataset: GitHub Stars (Live Data)

The demo uses **real GitHub star counts** for the top ~2,000 most-starred repositories, fetched live from the GitHub API on April 5, 2026. This data is:

- **Real** -- actual star counts, not made up
- **Up to date** -- fetched hours ago, changes daily
- **LLM-proof** -- no LLM has these exact numbers memorized (they change constantly)
- **Verifiable** -- anyone can check github.com to confirm the numbers
- **Relatable** -- every developer knows these repos

## Assets

### Screenshots (iPad)
| File | Description |
|------|-------------|
| `01-empty-state.png` | Clean empty state with onboarding prompt |
| `02-github-top-repos.png` | Bar chart of most-starred repos with data table (full_name, stars, forks, language) |
| `03-language-breakdown.png` | Language popularity breakdown: Python 359, TypeScript 312, JavaScript 248... with bar chart |

### Screenshots (iPhone 16 Pro Max)
| File | Description |
|------|-------------|
| `iphone-01-empty.png` | Clean empty state on iPhone form factor |

### Video
| File | Description |
|------|-------------|
| `demo-github.mp4` | Full demo flow with GitHub stars data |

---

## Social Copy

### Twitter / X (Short)

**Chat with any SQLite database. One line of Swift.**

SwiftDBAI turns natural language into SQL. We pointed it at a database of GitHub stars -- real data, real numbers, updated today.

"What are the most starred repos?" → instant bar chart.
"Which languages are most popular?" → Python 359, TypeScript 312, JS 248.

Verify every number on github.com.

github.com/<org>/SwiftDBAI

---

### Twitter / X (Thread)

**1/4** We built a Swift library that lets you chat with any SQLite database.

To prove it works, we pointed it at a real database: the top 2,000 GitHub repos with live star counts. Every number is verifiable.

**2/4** One line of code:

```swift
DataChatView(databasePath: path, model: myLLM)
```

Ask "What are the most starred repos?" and get an instant bar chart with real numbers. codecrafters-io/build-your-own-x at 486K stars. Check it yourself.

**3/4** "Which programming languages are most popular?"

→ Python: 359 repos, 16M total stars
→ TypeScript: 312 repos, 13.6M total stars
→ JavaScript: 248 repos

The aggregation proves it's a database query, not LLM memory. No LLM knows these exact counts.

**4/4** Works with any LLM -- OpenAI, Anthropic, Ollama, or fully local with llama.cpp.

Read-only by default. Your data stays safe.

Open source, MIT licensed. Swift 6.1+

---

### LinkedIn / Blog Post

**Introducing SwiftDBAI: Natural Language Queries for Any SQLite Database**

We built a Swift library that adds a chat interface to any SQLite database. One SwiftUI view. One line of code. Any LLM provider.

To demonstrate it, we didn't use fake data. We pointed it at a real database of the top 2,000 most-starred GitHub repositories -- with live star counts from today.

Ask "What are the most starred repos on GitHub?" and get an instant bar chart with real numbers anyone can verify. Ask "Which programming languages are most popular?" and see Python leading with 359 repos and 16M total stars.

The exact numbers change daily. No LLM has them memorized. That's the point -- you're watching a real database query, not AI guessing.

**Features:**
- Drop-in SwiftUI chat view: `DataChatView(databasePath:model:)`
- Works with OpenAI, Anthropic, Gemini, Ollama, or local models
- Auto-generated charts and data tables
- Read-only by default with configurable safety policies
- Headless `ChatEngine` for programmatic use

Open source, MIT licensed. Swift 6.1+, iOS 17+, macOS 14+, visionOS 1+.

---

### Product Hunt

**Tagline:** "Chat with any SQLite database -- one line of Swift, any LLM, real results"

**Description:** SwiftDBAI adds a natural language query interface to any SQLite database in your iOS or macOS app. One SwiftUI view, one line of code. Users ask questions in plain English and get instant results with auto-generated charts and tables. Works with any LLM provider. Read-only safe by default. We demo'd it with live GitHub star counts -- every number verifiable on github.com.

---

## Screenshot Captions

1. **Empty State**: "Ask anything about your data"
2. **Top Repos Chart**: "Real GitHub star counts. Every number verifiable."
3. **Language Breakdown**: "Aggregation queries with auto-generated charts"
