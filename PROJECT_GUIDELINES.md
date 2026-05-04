# GUI Localization Rule

All user-facing GUI text must always be localized.

Rules:
- Never hardcode a GUI string in only one language.
- Every visible GUI label, button text, menu entry, tooltip, status text, dialog title, dialog body, placeholder, and empty state must come from a translation table.
- German (`de`) must always be present.
- English (`en`) must always be present as the default fallback.
- If additional languages are introduced, every GUI string must be translated for all supported languages before the change is considered complete.
- New GUI features are not complete until their localization entries exist for every supported language.
- Refactors must preserve localization coverage.

Implementation expectation:
- Centralize GUI strings in one translation structure.
- Resolve the active UI language from the system locale or explicit app setting.
- Fall back to English if a locale is unsupported.
