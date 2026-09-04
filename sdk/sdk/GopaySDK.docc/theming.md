# Theming the Card Form

Style ``GopayCardForm`` with the same parameter names the GoPay web card form uses.

## Overview

``GopayCardFormTheme`` is a flat set of parameters named after the web card form theme (cc-v4), so
one design decision covers the web, iOS and Android. Every parameter is optional and **defaults to
the web form's value**, so an untouched form is laid out the same on all three channels. Colors are
the exception and stay on the system palette, so the form keeps following light and dark mode; the
focus gradient is the one color taken from the web, because the system has no equivalent for it.

```swift
GopayCardForm(
    theme: GopayCardFormTheme(
        labelUppercase: true,
        inputBorderStyle: .underline,
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
color, a negative length and an unknown ``GopayCardFormTheme/inputBorderStyle``; the font weights
also accept the CSS keywords `bold` and `normal`. Every dropped key is reported as a warning in the
SDK debug log (`GopaySDKConfig.enableDebugLogging`), so a typo in a theme is noticed without the
theme failing.

Colors restored from hex are plain colors: unlike a `Color` written in Swift, they no longer follow
light and dark mode on their own. Encoding needs iOS 14, because SwiftUI cannot read a `Color` back
on iOS 13, where every color comes out as `"transparent"`. Decoding works on every supported
version.

## Parity with Android

The 36 parameters are identical on Android, name for name and type for type, and both SDKs resolve
focus, error and collapsed borders the same way. The Android SDK adds `helperTextColor` and
`helperFontSize` of its own, for a helper line neither the web form nor this SDK renders.

A weight is rounded to the nearest hundred here, because `Font.Weight` has nine steps; Android hands
the exact number to a variable font. ``GopayCardFormTheme/inputHeight`` is a fixed height and does
not grow with Dynamic Type, so leave it unset unless the design needs the field pinned.

## What the web has and this SDK does not

Eight of the 44 web keys have no counterpart here.

- The seven `submit*` keys style a button this SDK never draws. You own the submit button and call
  `submitCardForm()`, the same arrangement as the web form's `submitMode: 'external'`.
- `errorHidden` is a parameter of the form rather than of the theme: the default
  `validation: .hidden` renders no inline errors and reports validity through the `isValid` binding.

``GopayCardFormTheme/inputLineHeight`` is accepted and ignored. It exists on the web to pin the input
height across browser engines; here the height follows the font, the padding and
``GopayCardFormTheme/inputHeight``.

## Focus and error states

- resting: ``GopayCardFormTheme/inputBorderColor``
- focused: ``GopayCardFormTheme/focusGradientStart`` as a solid boxed border, or a gradient to
  ``GopayCardFormTheme/focusGradientEnd`` under an underlined input, plus the optional ring from
  ``GopayCardFormTheme/focusRingWidth`` and ``GopayCardFormTheme/focusRingColor``
- invalid: ``GopayCardFormTheme/inputErrorBorderColor``, on an unfocused field only — focus wins

The error border only appears while the form draws inline errors, so the default
`validation: .hidden` leaves the border untouched.

The web animates the focus gradient of an underlined input; here it is static. The underline follows
the rounded bottom corners of the input, the way a CSS `border-bottom` does under a `border-radius`,
so with the default ``GopayCardFormTheme/inputBorderRadius`` of `0` it is straight and a larger
radius curves it up at both ends. A browser tapers that curve to a point where the side border would
take over; this line keeps its full width around the corner.

Collapsing applies to the boxed style; on the default underline it has no effect.

Inside a block collapsed by ``GopayCardFormTheme/inputBorderCollapse``, a field that is focused or
invalid recolors the lines it shares with its neighbours as well, so its state reads as one closed
box and each seam still shows a single line. Lines are shared only where two fields actually touch:
any gap, including an inline error shown under the card number, makes the fields on both sides draw
a full frame for as long as it is there.

## Migrating a 1.x theme

Version 2.0 renamed every parameter and split the composite ones, without aliases.

| 1.x | 2.0 |
| --- | --- |
| `textColor` | `labelColor` and `inputTextColor` |
| `backgroundColor` | `inputBackgroundColor` |
| `borderColor` | `inputBorderColor` |
| `focusedBorderColor` | `focusGradientStart` |
| `errorColor` | `errorTextColor` |
| `borderWidth` | `inputBorderWidth` |
| `cornerRadius` | `inputBorderRadius` |
| `labelFont` | `labelFontSize` and `labelFontWeight` (and `fontFamily`) |
| `font` | removed — it never reached the inputs; `fontFamily`, `inputFontSize` and `inputFontWeight` style them now |
| `spacing` | `groupSpacing` |
| `textFieldPadding` | `inputPaddingVertical` and `inputPaddingHorizontal` |

The full parity table of all 44 web keys, with the iOS and web defaults side by side, is in the
README.

## Topics

### Theme

- ``GopayCardFormTheme``
- ``GopayCardFormBorderStyle``
