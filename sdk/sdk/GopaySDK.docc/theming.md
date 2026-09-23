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

## Parity with Android

The 29 parameters are identical on Android, name for name and type for type, and both SDKs mark an
invalid field the same way. These differ per platform:

- ``GopayCardFormTheme/inputBorderStyle`` keeps both web values so both platforms name the styles
  the same way, but `underline` is **not supported on iOS**, which has no native underlined text
  field; the value is accepted and the input renders as `boxed`. Android renders it with the native
  Material indicator.
- Marking the active field is native on each platform, so Android highlights it and iOS does not.
- The Android SDK adds `helperTextColor` and `helperFontSize` of its own, for a helper line neither
  the web form nor this SDK renders.

The defaults are the platform's, not the web's, so an untouched theme gives a native form on each
channel while the same values give a GoPay-styled one.

A weight is rounded to the nearest hundred here, because `Font.Weight` has nine steps; Android hands
the exact number to a variable font.

On iOS 13 the text inside an input keeps the system colors. ``GopayCardFormTheme/inputTextColor``
and ``GopayCardFormTheme/placeholderColor`` reach a `UITextField`, and turning a SwiftUI `Color`
into a `UIColor` needs iOS 14. Everything SwiftUI draws itself, the labels, the border and the
error text, is themed on iOS 13 too.

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
  has no such problem; ``GopayCardFormTheme/inputHeight`` is here to set a minimum.

They are simply not parameters of this type, so the compiler says so where you would have set
them.

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
frame inwards and never changes how much room the form takes. It stops at half the field's height,
past which a border would have nothing left to enclose.

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

``GopayCardFormTheme/inputHeight`` is the smallest height of the input, with the vertical padding
inside it rather than on top of it. It is a minimum on both platforms, not the fixed height it is
on the web, so a large font scale can still grow the field rather than overflow it.

Seven more keys were carried for part of the 2.0 work and removed with the move to native
rendering: `inputBorderCollapse`, `focusRingWidth`, `focusRingColor`, `focusGradientStart`,
`focusGradientEnd`, `inputLetterSpacing` and `inputLineHeight`. Setting one is a compile error now.
``GopayCardFormTheme/labelLetterSpacing`` and ``GopayCardFormTheme/inputHeight`` cover what is left
of the last two.

The full parity table, with the iOS and web defaults side by side, is in the README.

## Topics

### Theme

- ``GopayCardFormTheme``
- ``GopayCardFormBorderStyle``
