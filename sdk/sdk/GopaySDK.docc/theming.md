# Theming the Card Form

Style ``GopayCardForm`` with the same parameter names the GoPay web card form uses.

## Overview

**An untouched form looks like an iOS form**: the system font and colors, a plain bordered field,
sentence-case labels, ordinary spacing. The web card form is a page of its own; this one sits inside
a merchant's screen, so nobody should have to undo an SDK style to make it fit. Theming is fully
available, it is a choice rather than the starting point.

``GopayCardFormTheme`` is **a subset of the web card form theme (cc-v4)**, carrying its parameter
names so one design decision covers the web, iOS and Android. The subset is the part a native field
can carry: every parameter is a property of the text field itself or of the layout around it, and
the SDK draws nothing of its own.

```swift
// Nothing here is required; each line moves the form one step away from the platform default.
GopayCardForm(
    theme: GopayCardFormTheme(
        labelUppercase: true,
        inputBorderRadius: 0,
        inputPaddingHorizontal: 0,
        errorMinHeight: 14
    ),
    validation: .live,
    isValid: $isCardValid
)
```

## Carrying a theme as JSON

The type is `Codable`, with colors written as `"#RGB"`, `"#RGBA"`, `"#RRGGBB"`, `"#RRGGBBAA"` or
`"transparent"`. The leading `#` is required, as in CSS.
Decoding is deliberately tolerant, so a full web theme decodes without error: keys the SDK does not
know are ignored, a key the document omits keeps the value of the theme it is applied over (the SDK
default only when the theme is decoded on its own), and a key whose value cannot be used is dropped on
its own while the rest of the document applies. That covers a value of the wrong type, an unparsable
color and a negative length; the font weights also accept the CSS keywords `bold` and `normal`.
Every dropped key is reported as a warning in the SDK debug log
(`GopaySDKConfig.enableDebugLogging`), so a typo in a theme is noticed without the theme failing.

Colors restored from hex are plain colors: unlike a `Color` written in Swift, they no longer follow
light and dark mode on their own. Encoding needs iOS 14, because SwiftUI cannot read a `Color` back
on iOS 13, where every color comes out as `"transparent"`. Decoding works on every supported
version.

## Parity with Android

The 29 parameters are identical on Android, name for name and type for type, and both SDKs mark an
invalid field the same way. These differ per platform:

- ``GopayCardFormTheme/inputBorderStyle`` keeps both web values so a document travels unchanged, but
  `underline` is **not supported on iOS**, which has no native underlined text field; the value is
  accepted and the input renders as `boxed`. Android renders it with the native Material indicator.
- Marking the active field is native on each platform, so Android highlights it and iOS does not.
- ``GopayCardFormTheme/inputHeight`` is the whole height of the field here and replaces
  ``GopayCardFormTheme/inputPaddingVertical``; Android reads it as a minimum and adds the padding
  on top, so a shared document gives a taller field there. It does not grow with Dynamic Type, so
  leave it unset unless the design needs the field pinned.
- The Android SDK adds `helperTextColor` and `helperFontSize` of its own, for a helper line neither
  the web form nor this SDK renders.

The defaults are the platform's, not the web's, so the same document produces a GoPay-styled form
everywhere while an empty one produces a native form on each channel.

A weight is rounded to the nearest hundred here, because `Font.Weight` has nine steps; Android hands
the exact number to a variable font.

## What the web has and this SDK does not

Some web keys have no counterpart here.

- The seven `submit*` keys style a button this SDK never draws. You own the submit button and call
  `submitCardForm()`, the same arrangement as the web form's `submitMode: 'external'`.
- `errorHidden` is a parameter of the form rather than of the theme: the default
  `validation: .hidden` renders no inline errors and reports validity through the `isValid` binding.
- `focusGradientStart`, `focusGradientEnd`, `focusRingWidth`, `focusRingColor` and
  `inputBorderCollapse` describe something a browser paints around a field: a gradient, a glow
  outside the frame, one shared line between two neighbours. A native text field has none of them.
- `inputLetterSpacing` would have to override how the field measures itself.
  ``GopayCardFormTheme/labelLetterSpacing`` stays, because a label is ordinary text.
- `inputLineHeight` pins the height of a field across browser engines. A single-line native field
  has no such problem; ``GopayCardFormTheme/inputHeight`` is here for a fixed height.

A theme document may still carry any of them: unknown keys are ignored, so a web theme moves over
unchanged and only the keys this SDK understands take effect.

``GopayCardFormTheme/placeholderColor`` is worth setting whenever a theme paints the form dark:
unset, it follows the system's light or dark appearance rather than the theme's, so the hint text
can come out dark on a dark field.

## The error and focus states

- valid: ``GopayCardFormTheme/inputBorderColor``
- invalid: ``GopayCardFormTheme/inputErrorBorderColor``

The error border only appears while the form draws inline errors, so the default
`validation: .hidden` leaves the border untouched.

Marking the active field is left to the platform, which is why it looks different on each: Android
shows it, because its Material field highlights the indicator itself, and iOS does not, because a
native text field marks focus with the caret and the keyboard rather than its frame. There is no
theme parameter for it on either.

The border runs inside the field, so raising ``GopayCardFormTheme/inputBorderWidth`` thickens the
frame inwards and never changes how much room the form takes.

## Migrating a 1.x theme

Version 2.0 renamed every parameter and split the composite ones, without aliases. The values carry
over as they are, and 2.0 keeps almost all of the platform defaults 1.x had. One default changed:
``GopayCardFormTheme/inputBackgroundColor`` is now `.clear` where 1.x filled the inputs with
`Color(.systemBackground)`, so the surface behind the form shows through.

| 1.x | 2.0 |
| --- | --- |
| `textColor` | `labelColor` and `inputTextColor` |
| `backgroundColor` | `inputBackgroundColor` |
| `borderColor` | `inputBorderColor` |
| `focusedBorderColor` | removed — the border no longer changes color on focus |
| `errorColor` | `errorTextColor` |
| `borderWidth` | `inputBorderWidth` |
| `cornerRadius` | `inputBorderRadius` |
| `labelFont` | `labelFontSize` and `labelFontWeight` (and `fontFamily`) |
| `font` | removed — it never reached the inputs; `fontFamily`, `inputFontSize` and `inputFontWeight` style them now |
| `spacing` | `groupSpacing` |
| `textFieldPadding` | `inputPaddingVertical` and `inputPaddingHorizontal` |

Seven more keys were carried for part of the 2.0 work and removed with the move to native
rendering: `inputBorderCollapse`, `focusRingWidth`, `focusRingColor`, `focusGradientStart`,
`focusGradientEnd`, `inputLetterSpacing` and `inputLineHeight`. A document may still set them; they
are ignored and named in the debug log. ``GopayCardFormTheme/labelLetterSpacing`` and
``GopayCardFormTheme/inputHeight`` cover what is left of the last two.

The full parity table, with the iOS and web defaults side by side, is in the README.

## Topics

### Theme

- ``GopayCardFormTheme``
- ``GopayCardFormBorderStyle``
