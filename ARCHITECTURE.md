# Architecture Overview

## Design Philosophy

> **"Build the simplest thing that works. Complexity is earned, not assumed."**

This app follows pragmatic MVVM without over-engineering.

## Flow Diagram

```
┌─────────────┐
│   RootView  │  Decides which screen to show
└──────┬──────┘
       │
   ┌───┴────┐
   │        │
   ▼        ▼
┌──────┐ ┌──────────┐
│ Auth │ │ Main Tab │
└──────┘ └──────────┘
   │         │
   ├─Login   ├─Journal List
   └─Signup  └─Profile
```

## Layer Responsibilities

### View Layer (SwiftUI)
- Renders UI
- Handles user interaction
- Observes ViewModel via `@ObservedObject` / `@StateObject`
- **Zero business logic**

**Examples:**
- `LoginView.swift`
- `JournalListView.swift`
- `JournalEditorView.swift`

### ViewModel Layer
- Manages view state
- Coordinates service calls
- Transforms data for display
- Publishes changes via `@Published`

**Examples:**
- `AuthViewModel.swift` - Manages auth state
- `JournalListViewModel.swift` - Manages entry list
- `JournalEditorViewModel.swift` - Manages editor state

### Service Layer
- Direct Firebase communication
- CRUD operations
- Error handling
- **No UI concerns**

**Examples:**
- `AuthService.swift` - Firebase Auth
- `JournalService.swift` - Firestore operations

### Model Layer
- Data structures
- Serialization/deserialization
- Computed properties

**Examples:**
- `JournalEntry.swift` - Entry model + Firestore mapping
- `AppUser.swift` - User model

## Data Flow

### Read Flow
```
User Action → View → ViewModel.load() → Service.fetch() → Firebase
                ↑                                              │
                └────── Published @State ←────────────────────┘
```

### Write Flow
```
User Input → View → ViewModel.save() → Service.create() → Firebase
                                              │
                                              ├─ Success → Published state
                                              └─ Error → Show error
```

### Offline Flow
```
User writes while offline
         ↓
Service.create() → Firestore local cache (queued)
         ↓
ViewModel state updated (optimistic)
         ↓
Network restored → Firestore auto-syncs → Firebase
```

## Authentication Flow

```
App Launch
    ↓
Firebase Auth Listener
    ↓
┌───────────┴───────────┐
│                       │
User exists          No user
    ↓                   ↓
Fetch profile      Show Login/Signup
    ↓                   ↓
Show Main App      Auth → Fetch → Main App
```

## Key Design Decisions

### ✅ What We DID

1. **MVVM without protocols**
   - Services are concrete classes
   - Add protocols when writing tests

2. **Firestore-only storage**
   - Built-in offline cache
   - No Core Data sync needed

3. **Flat folder structure**
   - Feature-based organization
   - Easy navigation

4. **Single source of truth**
   - Model = Domain model = Data model
   - No mapping layer

### ❌ What We AVOIDED

1. **Clean Architecture layers**
   - No Use Cases
   - No Repositories
   - No Domain/Data split

2. **Core Data**
   - Would require sync engine
   - Firestore already caches

3. **Coordinators**
   - SwiftUI NavigationStack is enough
   - Add if routing gets complex

4. **Deep nesting**
   - No `Core/Feature/Layer/Type/`
   - Just `Feature/File.swift`

## Offline Architecture

Firestore's offline support does this automatically:

```
┌─────────────────────────────────────┐
│         Your App Code               │
│  (No offline logic needed!)         │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│    Firestore SDK                    │
│  ┌─────────────┐  ┌──────────────┐ │
│  │   Cache     │  │  Sync Queue  │ │
│  │  (100MB)    │  │  (Writes)    │ │
│  └─────────────┘  └──────────────┘ │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│         Firebase Cloud              │
└─────────────────────────────────────┘
```

**How it works:**
- Reads hit cache first (instant)
- Writes queue automatically when offline
- On reconnect, syncs in background
- Handles conflicts automatically

## Security Model

```
Firebase Auth
     ↓
Authenticated User ID
     ↓
Firestore Rules Check
     ↓
users/{userId}/entries/{entryId}
     ↓
Grant if request.auth.uid == userId
```

**Rules enforce:**
- Users can only access their own data
- All operations require authentication
- No cross-user data access

## State Management

### App-level State
```swift
@StateObject var authViewModel = AuthViewModel()
```
- Created at app launch
- Injected via `@EnvironmentObject`
- Lives entire app lifetime

### Screen-level State
```swift
@StateObject var viewModel = JournalListViewModel(userId: userId)
```
- Created when screen appears
- Owns screen state
- Destroyed when screen dismissed

### Transient State
```swift
@State var searchText = ""
@FocusState var isFieldFocused: Bool
```
- UI-only state
- Not persisted
- Resets on navigation

## Error Handling

```
Service throws error
       ↓
ViewModel catches
       ↓
Published to @Published var errorMessage: String?
       ↓
View shows ErrorBanner
```

**Strategy:**
- Services throw detailed errors
- ViewModels catch and convert to user-friendly messages
- Views display via UI components

## Dependency Injection

**Current approach: Constructor injection**

```swift
class JournalListViewModel {
    private let service = JournalService()
    // Simple and works
}
```

**For testing (when needed):**

```swift
class JournalListViewModel {
    private let service: JournalService
    
    init(service: JournalService = JournalService()) {
        self.service = service
    }
}
```

## Navigation Architecture

SwiftUI's built-in navigation:

```swift
NavigationStack {
    List {
        ForEach(entries) { entry in
            NavigationLink(destination: EditorView(entry: entry)) {
                CardView(entry: entry)
            }
        }
    }
}
```

**Sheet presentation:**
```swift
.sheet(isPresented: $showingEditor) {
    EditorView(userId: userId)
}
```

Simple and declarative - no coordinators needed.

## Performance Considerations

### Firestore Queries
- Index on `createdAt` (automatic)
- Fetch all user entries (small dataset)
- Cache makes reads instant

### View Optimization
- Use `Identifiable` for ForEach
- Lazy loading with `ScrollView { LazyVStack }`
- Minimal re-renders via `@Published`

### Memory
- 100MB Firestore cache
- Images not yet implemented
- Entries are text-only (lightweight)

## Scaling Considerations

**What breaks at scale:**

| Count | What breaks | Solution |
|-------|-------------|----------|
| 1K entries | List performance | Add pagination |
| 10K entries | Load time | Incremental fetch |
| Photos | Storage cost | Add compression |
| Analytics | Query cost | Pre-aggregate |

**Current limit: ~1000 entries per user works fine**

## Testing Strategy

**Phase 1 (MVP): Manual testing**
- Test on device
- TestFlight beta

**Phase 2 (Growth): Add unit tests**
```swift
protocol JournalServiceProtocol {
    func fetchEntries(for userId: String) async throws -> [JournalEntry]
}

class MockJournalService: JournalServiceProtocol {
    // Test doubles
}
```

**Phase 3 (Scale): Full test suite**
- Unit tests for ViewModels
- Integration tests for Services
- UI tests for critical flows

## Code Organization Principles

1. **Feature folders** - All files for a feature together
2. **No deep nesting** - Maximum 2 levels
3. **Explicit names** - `JournalListViewModel` not `ListVM`
4. **Single responsibility** - One file, one thing
5. **Shared components** - Reusable UI in `Components/`

## Migration Paths

### When to add protocols
- Writing unit tests
- Multiple implementations needed
- Swapping dependencies

### When to add Repository layer
- Multiple data sources (Firestore + iCloud)
- Complex caching logic
- Cross-feature data needs

### When to add Coordinator
- Deep navigation hierarchies
- Complex routing logic
- Deeplink handling

## Summary

**Current architecture:**
- MVVM with Services
- SwiftUI + Firebase
- Flat structure
- Pragmatic, not dogmatic

**Complexity added when:**
- Tests require it (protocols)
- Scale requires it (pagination)
- Features require it (image handling)

**Never added:**
- Abstraction for abstraction's sake
- Layers without clear purpose
- Patterns from other contexts

---

**This architecture ships products. That's the only metric that matters.**