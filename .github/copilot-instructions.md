# Code Quality & Structure Guidelines

## Architecture

The project follows a layered architecture. Each layer has a strict responsibility:

```
data/         → repositories, classes, enums, constants
logic/        → cubits, services, helpers
presentation/ → screens, widgets, theme, routing
```

Never skip layers. Cubits do not make HTTP/API calls directly — only repositories do.

---

## Data Layer

### Repositories

- Every repository method that makes a network or API call must return `Future<APIResponse>`.
- Use `APIResponse.success(data)` on success and `APIResponse.error(e)` in every `catch` block.
- `APIResponse.error(e)` automatically logs via `HelperMethods.printDebug` — never log separately in
  the repository.
- No try/catch should be left without an `APIResponse.error(e)` wrapping it.

```dart
// ✅ Correct
Future<APIResponse> fetchSomething() async {
  try {
    final result = await _client.from('table').select();
    return APIResponse.success(result);
  } catch (e) {
    return APIResponse.error(e);
  }
}

// ❌ Wrong — throws instead of returning APIResponse
Future<String> fetchSomething() async {
  return await _client.from('table').select();
}
```

### Classes (`data/classes/`)

- Pure data classes that are **used across multiple files or layers** live in `data/classes/`.
- Classes used only within a single cubit (e.g. state helpers) may live alongside that cubit.
- Each class gets its own file named in `snake_case` matching the class name.

### Enums (`data/enums/`)

- All enums that are shared across the codebase live in `data/enums/`.
- Enums local to a single file (e.g. a private `_SelectorMode`) may stay in that file.

---

## Logic Layer

### Cubits

- Cubits call repositories and check `response.success`. They never make API calls directly.
- On failure: read `response.error` and emit the error state.
- On success: read `response.data`, cast it, and emit the success state.
- Use `HelperMethods.printDebug('[CubitName] context: $detail')` to log unexpected failures at the
  cubit level (e.g. a failed sign-out that shouldn't normally fail).
- If a cubit's logic becomes too complex (many events, complex transitions), switch to a full `Bloc`
  with explicit `Event` classes instead.

```dart
// ✅ Correct
Future<void> signIn({required String email, required String password}) async {
  emit(state.copyWith(isProcessing: true));
  final response = await _repo.signIn(email: email, password: password);
  if (!response.success) {
    HelperMethods.printDebug('[AuthCubit] signIn failed: ${response.error}');
    emit(state.copyWith(isProcessing: false, error: response.error));
    return;
  }
  final user = response.data as User;
  emit(state.copyWith(isProcessing: false, isSignedIn: true, email: user.email));
}

// ❌ Wrong — catches exceptions and makes API calls in the cubit
Future<void> signIn
(...) async {
try {
final user = await _supabaseClient.auth.signInWithPassword(...);
emit(...);
} on AuthException catch (e) {
emit(state.copyWith(error: e.message));
}
}
```

### Services

- Services (e.g. `SoundService`) are singletons accessed via `instance`.
- Errors in services are logged with `debugPrint` or `HelperMethods.printDebug` and swallowed — they
  must never crash the app.

---

## Presentation Layer

### File Structure

- Top-level screens live in `presentation/screens/<screen>/` (e.g. `onboarding/`, `home/`).
- Features that belong inside the home screen live in `presentation/screens/home/<feature>/`.
- If a screen file grows large, extract widgets into a `widgets/` subfolder within the screen's
  folder.
- Common reusable widgets (used across multiple screens) live in `presentation/common/`.
- Theme constants live in `presentation/theme/`.

### Widget Rules

- No business logic in widgets. Widgets only read cubit state and call cubit methods.
- Private widgets within a file are prefixed with `_`.
- Widgets that are reused across more than one screen are promoted to `presentation/common/`.

---

## Logging

- Use `HelperMethods.printDebug(message)` everywhere — it only prints in debug mode.
- Never use bare `print()`.
- `debugPrint` is acceptable in legacy code but prefer `HelperMethods.printDebug` for consistency.
- `APIResponse.error(e)` handles repository-level logging automatically — no additional log call
  needed.
