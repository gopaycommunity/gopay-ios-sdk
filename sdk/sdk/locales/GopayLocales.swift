import Foundation

/// Registry and resolver for ``GopayLocaleStrings`` used by the payment card form.
///
/// Ships 20 built-in translations keyed by ISO 639-1 language code. Host apps can add their own
/// with ``register(_:for:)`` (or via `GopaySDKConfig.customLocales`) and select a locale
/// explicitly, or rely on the default resolution: the SDK-wide preferred locale (set from
/// `GopaySDKConfig.locale`), else the device language, ultimately falling back to Czech
/// (``defaultLocale``).
public enum GopayLocales {

    /// Language code used as the final fallback when nothing else matches.
    public static let defaultLocale = "cs"

    // Placeholders / CVV label are not localized in the shared web locale set.
    private static let panPlaceholder = "1234 5678 9012 3456"
    private static let cvvLabelConst = "CVV"
    private static let cvvPlaceholder = "123"

    public static let cs = GopayLocaleStrings(
        panLabel: "Číslo karty",
        panPlaceholder: panPlaceholder,
        expLabel: "Platnost",
        expPlaceholder: "MM/RR",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Zaplatit",
        panErrorPattern: "Zadali jste nesprávné číslo karty",
        expErrorPattern: "Zadejte číslo měsíce a poslední dvě čísla roku expirace vaší karty.",
        cvvErrorPattern: "CVC/CVV musí obsahovat 3 číslice",
        patternErrorMessage: "Hodnota je v nesprávném tvaru",
        requiredErrorMessage: "Toto pole je povinné"
    )

    public static let en = GopayLocaleStrings(
        panLabel: "Card number",
        panPlaceholder: panPlaceholder,
        expLabel: "Expiration date",
        expPlaceholder: "MM/YY",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Pay",
        panErrorPattern: "You entered a wrong card number",
        expErrorPattern: "Enter the month number and the last two digits of your card's expiration year.",
        cvvErrorPattern: "CVV must be 3 digits",
        patternErrorMessage: "Value is in wrong format",
        requiredErrorMessage: "This field is required"
    )

    public static let de = GopayLocaleStrings(
        panLabel: "Kartennummer",
        panPlaceholder: panPlaceholder,
        expLabel: "Gültigkeit",
        expPlaceholder: "MM/JJ",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Bezahlen",
        panErrorPattern: "Sie haben eine falsche Kartennummer eingegeben",
        expErrorPattern: "Geben Sie die Monatsnummer und die letzten beiden Ziffern des Ablaufes Ihrer Karte ein.",
        cvvErrorPattern: "CVC/CVV muss 3 Ziffern enthalten",
        patternErrorMessage: "Falsches Format",
        requiredErrorMessage: "Dieses Feld ist erforderlich"
    )

    public static let es = GopayLocaleStrings(
        panLabel: "Número de Tarjeta",
        panPlaceholder: panPlaceholder,
        expLabel: "Fecha de vencimiento",
        expPlaceholder: "MM/AA",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Pagar",
        panErrorPattern: "Ingresó un número de tarjeta incorrecto",
        expErrorPattern: "Ingrese el número de mes y los dos últimos dígitos del año de vencimiento de su tarjeta.",
        cvvErrorPattern: "El CVC/CVV debe tener 3 dígitos",
        patternErrorMessage: "Formato de valor incorrecto",
        requiredErrorMessage: "Este campo es requerido"
    )

    public static let fr = GopayLocaleStrings(
        panLabel: "Numéro de carte",
        panPlaceholder: panPlaceholder,
        expLabel: "Validité",
        expPlaceholder: "MM/AA",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Payer",
        panErrorPattern: "Vous avez écrit un numéro de carte incorrect",
        expErrorPattern: "Écrivez le numéro du mois et les deux derniers numéros de l'année d'expiration de votre carte.",
        cvvErrorPattern: "CVC/CVV doit contenir 3 chiffres",
        patternErrorMessage: "Format erroné",
        requiredErrorMessage: "Ce champ est obligatoire"
    )

    public static let it = GopayLocaleStrings(
        panLabel: "Numero di carta",
        panPlaceholder: panPlaceholder,
        expLabel: "Validità",
        expPlaceholder: "MM/AA",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Paga",
        panErrorPattern: "Ha inserito numero di carta non corretto",
        expErrorPattern: "Inserire il numero di mese e ultimi due numeri della scadenza della vostra carta.",
        cvvErrorPattern: "CVC/CVV deve contenere 3 numeri",
        patternErrorMessage: "Formato errato",
        requiredErrorMessage: "Questo campo è obbligatorio"
    )

    public static let nl = GopayLocaleStrings(
        panLabel: "Kaartnummer",
        panPlaceholder: panPlaceholder,
        expLabel: "Vervaldatum",
        expPlaceholder: "MM/JJ",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Betalen",
        panErrorPattern: "U hebt een onjuist kaartnummer ingevoerd",
        expErrorPattern: "Voer het maandnummer in en de laatste twee cijfers van het vervaljaar van uw kaart.",
        cvvErrorPattern: "CVC/CVV moet uit 3 cijfers bestaan",
        patternErrorMessage: "De waarde is in een onjuist formaat",
        requiredErrorMessage: "Dit veld is verplicht"
    )

    public static let pl = GopayLocaleStrings(
        panLabel: "Numer karty",
        panPlaceholder: panPlaceholder,
        expLabel: "Ważność",
        expPlaceholder: "MM/RR",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Zapłać",
        panErrorPattern: "Podałeś nieprawidłowy numer karty",
        expErrorPattern: "Wprowadź numer miesiąca i dwie ostatnie cyfry roku ważności karty.",
        cvvErrorPattern: "Numer CVC/CVV musi zawierać 3 cyfry",
        patternErrorMessage: "Niewłaściwy format",
        requiredErrorMessage: "To pole jest obowiązkowe"
    )

    public static let pt = GopayLocaleStrings(
        panLabel: "Número do cartão",
        panPlaceholder: panPlaceholder,
        expLabel: "Data de validade",
        expPlaceholder: "MM/AA",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Pagar",
        panErrorPattern: "Introduziu um número de cartão errado",
        expErrorPattern: "Introduza o número do mês e os dois últimos dígitos do ano de validade do seu cartão.",
        cvvErrorPattern: "O CVC/CVV deve ter 3 dígitos",
        patternErrorMessage: "Formato errado do valor",
        requiredErrorMessage: "Este campo é obrigatório"
    )

    public static let bg = GopayLocaleStrings(
        panLabel: "Номер на картата",
        panPlaceholder: panPlaceholder,
        expLabel: "Валидност",
        expPlaceholder: "MM/RR",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Плати",
        panErrorPattern: "Въвели сте неправилен номер на картата",
        expErrorPattern: "Въведете номера на месеца и последните две числа на годината на изтичане на вашата карта.",
        cvvErrorPattern: "CVC/CVV трябва да съдържа 3 цифри",
        patternErrorMessage: "Неправилен формат",
        requiredErrorMessage: "Това поле е задължително"
    )

    public static let uk = GopayLocaleStrings(
        panLabel: "Номер картки",
        panPlaceholder: panPlaceholder,
        expLabel: "Термін дії",
        expPlaceholder: "ММ/РР",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Сплатити",
        panErrorPattern: "Ви ввели неправильний номер картки",
        expErrorPattern: "Введіть місяць та дві останні цифри року закінчення терміну дії вашої картки.",
        cvvErrorPattern: "CVC/CVV повинен містити 3 цифри",
        patternErrorMessage: "Невірний формат",
        requiredErrorMessage: "Це поле є обов'язковим"
    )

    public static let ru = GopayLocaleStrings(
        panLabel: "Номер карты",
        panPlaceholder: panPlaceholder,
        expLabel: "Срок действия",
        expPlaceholder: "ММ/ГГ",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Оплатить",
        panErrorPattern: "Вы ввели неправильный номер карты",
        expErrorPattern: "Введите номер месяца и последние два года срока действия Вашей карты.",
        cvvErrorPattern: "CVC/CVV должен содержать 3 цифры",
        patternErrorMessage: "Неверный формат",
        requiredErrorMessage: "Это поле является обязательным"
    )

    public static let et = GopayLocaleStrings(
        panLabel: "Kaardi number",
        panPlaceholder: panPlaceholder,
        expLabel: "Aegumiskuupäev",
        expPlaceholder: "KK/AA",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Maksa",
        panErrorPattern: "Sisestasite vale kaardi numbri",
        expErrorPattern: "Sisestage oma kaardi aegumiskuu number ja aegumisaasta kaks viimast numbrit.",
        cvvErrorPattern: "CVC/CVV peab koosnema kolmest numbrist",
        patternErrorMessage: "Vale väärtuse vorming",
        requiredErrorMessage: "See väli on nõutav"
    )

    public static let hr = GopayLocaleStrings(
        panLabel: "Broj kartice",
        panPlaceholder: panPlaceholder,
        expLabel: "Važenje",
        expPlaceholder: "MM/GG",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Plati",
        panErrorPattern: "Unijeli ste pogrešan broj kartice",
        expErrorPattern: "Upišite broj mjeseca i zadnja dva broja prestanka važenja vaše kartice.",
        cvvErrorPattern: "CVC/CVV mora sadržati 3 broja",
        patternErrorMessage: "Neispravan format",
        requiredErrorMessage: "Ovo polje je obvezno"
    )

    public static let hu = GopayLocaleStrings(
        panLabel: "Kártyaszám",
        panPlaceholder: panPlaceholder,
        expLabel: "Érvényesség",
        expPlaceholder: "HH/ÉÉ",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Fizet",
        panErrorPattern: "Hibás kártyaszám",
        expErrorPattern: "Írja be a kártya lejáratának hónapját, valamint az év utolsó két számjegyét.",
        cvvErrorPattern: "A CVC/CVV -nek 3 számjegyből kell állnia",
        patternErrorMessage: "Hibás formátum",
        requiredErrorMessage: "Kötelező mező"
    )

    public static let lt = GopayLocaleStrings(
        panLabel: "Kortelės numeris",
        panPlaceholder: panPlaceholder,
        expLabel: "Galiojimo data",
        expPlaceholder: "MM/YY",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Moketi",
        panErrorPattern: "Įvedėte neteisingą kortelės numerį",
        expErrorPattern: "Įveskite mėnesio numerį ir paskutinius du kortelės galiojimo metų skaitmenis.",
        cvvErrorPattern: "CVC/CVV sudarytas iš 3 skaitmenų",
        patternErrorMessage: "Neteisingas vertės formatas",
        requiredErrorMessage: "Šį lauką būtina užpildyti"
    )

    public static let lv = GopayLocaleStrings(
        panLabel: "Kartes numurs",
        panPlaceholder: panPlaceholder,
        expLabel: "Derīguma termiņš",
        expPlaceholder: "MM/GG",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Maksāt",
        panErrorPattern: "Jūs ievadījāt nepareizu kartes numuru",
        expErrorPattern: "Ievadiet mēneša numuru un pēdējos divus ciparus no jūsu kartes derīguma termiņa beigu gada.",
        cvvErrorPattern: "CVC/CVV jābūt 3 cipariem",
        patternErrorMessage: "Nepareizs vērtības formāts",
        requiredErrorMessage: "Šis lauks ir nepieciešams"
    )

    public static let ro = GopayLocaleStrings(
        panLabel: "Numărul cardului",
        panPlaceholder: panPlaceholder,
        expLabel: "Valabilitate",
        expPlaceholder: "LL/AA",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Plătește",
        panErrorPattern: "Ați introdus un număr de card incorect",
        expErrorPattern: "Introduceți numărul lunii și ultimele două cifre ale anului de expirare a cardului.",
        cvvErrorPattern: "CVC/CVV trebuie să conțină 3 cifre",
        patternErrorMessage: "Format greșit",
        requiredErrorMessage: "Acest câmp este obligatoriu"
    )

    public static let sk = GopayLocaleStrings(
        panLabel: "Číslo karty",
        panPlaceholder: panPlaceholder,
        expLabel: "Platnosť",
        expPlaceholder: "MM/RR",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Zaplatiť",
        panErrorPattern: "Zadali ste nesprávne číslo karty",
        expErrorPattern: "Zadajte číslo mesiaca a posledné dve čísla roku exspirácie vašej karty.",
        cvvErrorPattern: "CVC/CVV musí obsahovať 3 číslice",
        patternErrorMessage: "Chybný formát",
        requiredErrorMessage: "Toto pole je povinné"
    )

    public static let sl = GopayLocaleStrings(
        panLabel: "Številka kartice",
        panPlaceholder: panPlaceholder,
        expLabel: "Veljavnost",
        expPlaceholder: "MM/LL",
        cvvLabel: cvvLabelConst,
        cvvPlaceholder: cvvPlaceholder,
        pay: "Plačaj",
        panErrorPattern: "Vnesli ste napačno številko kartice",
        expErrorPattern: "Vnesite številko meseca in zadnji dve številki leta poteka veljavnosti svoje kartice.",
        cvvErrorPattern: "CVC/CVV mora vsebovati 3 številke",
        patternErrorMessage: "Napačna oblika",
        requiredErrorMessage: "To polje je obvezno"
    )

    /// All built-in locales keyed by ISO 639-1 language code.
    public static let builtIn: [String: GopayLocaleStrings] = [
        "bg": bg, "cs": cs, "de": de, "en": en, "es": es,
        "et": et, "fr": fr, "hr": hr, "hu": hu, "it": it,
        "lt": lt, "lv": lv, "nl": nl, "pl": pl, "pt": pt,
        "ro": ro, "ru": ru, "sk": sk, "sl": sl, "uk": uk,
    ]

    // MARK: - Mutable registry (thread-safe)

    private static let lock = NSLock()
    /// Host-registered custom locales; take priority over ``builtIn`` for the same code.
    private static var custom: [String: GopayLocaleStrings] = [:]
    /// SDK-wide preferred locale code, set from `GopaySDKConfig.locale`. `nil` means "use system".
    private static var defaultLocaleCode: String?

    /// Registers (or overrides) a locale under `code`. A registered locale shadows any built-in of
    /// the same code. Codes are matched case-insensitively on the language part only.
    public static func register(_ strings: GopayLocaleStrings, for code: String) {
        lock.lock(); defer { lock.unlock() }
        custom[normalize(code)] = strings
    }

    /// Registers all entries of `locales`. Convenience for `GopaySDKConfig.customLocales`.
    public static func registerAll(_ locales: [String: GopayLocaleStrings]) {
        lock.lock(); defer { lock.unlock() }
        for (code, strings) in locales { custom[normalize(code)] = strings }
    }

    /// Removes all host-registered custom locales. Built-ins are unaffected.
    public static func clearCustom() {
        lock.lock(); defer { lock.unlock() }
        custom.removeAll()
    }

    /// Sets the SDK-wide preferred locale code (`nil` = use the device language).
    public static func setDefaultLocale(_ code: String?) {
        lock.lock(); defer { lock.unlock() }
        defaultLocaleCode = code.map(normalize)
    }

    /// All selectable locale codes — built-in plus host-registered custom — sorted alphabetically.
    public static func availableCodes() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Set(builtIn.keys).union(custom.keys).sorted()
    }

    /// The device language code, e.g. `"cs"` for a Czech device.
    public static func systemLanguage() -> String {
        normalize(Locale.preferredLanguages.first ?? Locale.current.identifier)
    }

    /// Resolves the ``GopayLocaleStrings`` to use, in priority order:
    /// 1. `preferred` if non-nil and known,
    /// 2. the SDK-wide default (``setDefaultLocale(_:)``) if known,
    /// 3. the device language (``systemLanguage()``) if known,
    /// 4. ``defaultLocale`` (Czech).
    ///
    /// A code is "known" if a custom locale or a built-in exists for its language part.
    public static func resolve(_ preferred: String? = nil) -> GopayLocaleStrings {
        lock.lock()
        let defaultCode = defaultLocaleCode
        let customSnapshot = custom
        lock.unlock()

        func lookup(_ code: String?) -> GopayLocaleStrings? {
            guard let code = code else { return nil }
            let key = normalize(code)
            return customSnapshot[key] ?? builtIn[key]
        }

        return lookup(preferred)
            ?? lookup(defaultCode)
            ?? lookup(systemLanguage())
            ?? builtIn[defaultLocale]!
    }

    /// Reduces a locale tag to its lowercase language part, e.g. `"cs-CZ"` / `"cs_CZ"` -> `"cs"`.
    private static func normalize(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        let languagePart = trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? trimmed
        return languagePart.lowercased()
    }
}
