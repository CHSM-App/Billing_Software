// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class AppLocalizationsMr extends AppLocalizations {
  AppLocalizationsMr([String locale = 'mr']) : super(locale);

  @override
  String get appName => 'वित्तम';

  @override
  String get languageName => 'मराठी';

  @override
  String get commonCancel => 'रद्द करा';

  @override
  String get commonSave => 'जतन करा';

  @override
  String get commonAdd => 'जोडा';

  @override
  String get commonEdit => 'बदल करा';

  @override
  String get commonDelete => 'हटवा';

  @override
  String get commonUpdate => 'अपडेट करा';

  @override
  String get commonRemove => 'काढून टाका';

  @override
  String get commonOk => 'ठीक आहे';

  @override
  String get commonClose => 'बंद करा';

  @override
  String get commonRetry => 'पुन्हा प्रयत्न करा';

  @override
  String get commonBack => 'मागे जा ';

  @override
  String get commonNext => 'पुढे जा ';

  @override
  String get commonDone => 'पूर्ण';

  @override
  String get commonSaving => 'जतन करत आहे…';

  @override
  String get commonLoading => 'लोड करत आहे…';

  @override
  String get commonRequired => 'आवश्यक';

  @override
  String get commonSearch => 'शोधा';

  @override
  String get commonYes => 'होय';

  @override
  String get commonNo => 'नाही';

  @override
  String get commonManage => 'व्यवस्थापित करा';

  @override
  String get commonPrint => 'प्रिंट करा';

  @override
  String get commonRefresh => 'रिफ्रेश करा';

  @override
  String get commonEnterValidNumber => 'योग्य अंक टाका';

  @override
  String commonErrorWithMessage(String message) {
    return 'त्रुटी: $message';
  }

  @override
  String get navBilling => 'बिलिंग';

  @override
  String get navItems => 'वस्तू';

  @override
  String get navTables => 'टेबल';

  @override
  String get navHistory => 'इतिहास';

  @override
  String get navReports => 'अहवाल';

  @override
  String get navExpenses => 'खर्च';

  @override
  String get navKitchen => 'किचन';

  @override
  String get navOpenOrders => 'खुल्या ऑर्डर';

  @override
  String get navSettings => 'सेटिंग्ज';

  @override
  String get navProfile => 'प्रोफाइल';

  @override
  String get openOrdersTitle => 'खुल्या ऑर्डर';

  @override
  String get openOrdersEmpty =>
      'कोणत्याही खुल्या ऑर्डर नाहीत. टेबलशिवाय जतन केलेले ड्राफ्ट येथे दिसतात.';

  @override
  String openOrdersBillNumber(String number) {
    return 'बिल #$number';
  }

  @override
  String openOrdersItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count वस्तू',
      one: '1 वस्तू',
    );
    return '$_temp0';
  }

  @override
  String get kitchenTitle => 'किचन';

  @override
  String get kitchenNoOrders => 'सध्या किचनमध्ये कोणतीही ऑर्डर नाही.';

  @override
  String get kitchenReady => 'तयार';

  @override
  String kitchenTable(String number) {
    return 'टेबल $number';
  }

  @override
  String get kitchenJustNow => 'आत्ताच';

  @override
  String kitchenMinAgo(int minutes) {
    return '$minutes मिनिटांपूर्वी';
  }

  @override
  String get settingsTitle => 'प्रोफाइल';

  @override
  String get settingsSectionActivity => 'कार्य';

  @override
  String get settingsSectionReports => 'अहवाल';

  @override
  String get settingsHistory => 'इतिहास';

  @override
  String get settingsHistorySubtitle => 'मागील बिले आणि व्यवहार पहा';

  @override
  String get settingsReports => 'अहवाल';

  @override
  String get settingsReportsSubtitle => 'विक्री माहिती आणि सारांश';

  @override
  String get settingsExpenses => 'खर्च';

  @override
  String get settingsExpensesSubtitle =>
      'खर्चाचा मागोवा घ्या आणि व्यवस्थापित करा';

  @override
  String get settingsSectionBusiness => 'व्यवसाय';

  @override
  String get settingsSectionTeam => 'कर्मचारी';

  @override
  String get settingsSectionSync => 'सिंक';

  @override
  String get settingsSectionHardware => 'हार्डवेअर';

  @override
  String get settingsSectionPreferences => 'प्राधान्ये';

  @override
  String get settingsBusinessProfile => 'व्यवसाय प्रोफाइल';

  @override
  String get settingsBusinessProfileSubtitle =>
      'नाव, पत्ता, जीएसटी, बिलिंग सेटिंग्ज';

  @override
  String get settingsSelfOrder => 'ग्राहक QR ऑर्डरिंग';

  @override
  String get settingsSelfOrderSubtitle =>
      'ग्राहकांना टेबल QR स्कॅन करून मेनू पाहू आणि ऑर्डर करू द्या';

  @override
  String get settingsManageStaff => 'कर्मचारी व्यवस्थापन';

  @override
  String get settingsManageStaffSubtitle => 'कॅशियर जोडा, बदला किंवा काढा';

  @override
  String get settingsPrinterSetup => 'प्रिंटर सेटअप';

  @override
  String get settingsPrinterSetupSubtitle => 'तुमचा थर्मल प्रिंटर कॉन्फिगर करा';

  @override
  String get settingsSectionAbout => 'माहिती आणि मदत';

  @override
  String get settingsHelpCenter => 'मदत केंद्र';

  @override
  String get settingsHelpCenterSubtitle => 'मार्गदर्शक, प्रश्न आणि सहाय्य';

  @override
  String get settingsPrivacyPolicy => 'गोपनीयता धोरण';

  @override
  String get settingsPrivacyPolicySubtitle => 'आम्ही तुमचा डेटा कसा हाताळतो';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get settingsLanguageSubtitle => 'तुमची अ‍ॅप भाषा निवडा';

  @override
  String get settingsUnsyncedBills => 'सिंक न झालेली बिले';

  @override
  String settingsBillsNeedAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बिलांकडे लक्ष द्या',
      one: '1 बिलाकडे लक्ष द्या',
    );
    return '$_temp0';
  }

  @override
  String get settingsAllBillsSynced => 'सर्व बिले सिंक झाली';

  @override
  String settingsAppVersion(String version) {
    return 'वित्तम बिलिंग v$version';
  }

  @override
  String get languagePickerTitle => 'भाषा निवडा';

  @override
  String get languagePickerSubtitle =>
      'तुम्ही ही कधीही सेटिंग्जमध्ये बदलू शकता.';

  @override
  String get logout => 'लॉगआउट';

  @override
  String get logoutConfirmTitle => 'लॉगआउट करायचे?';

  @override
  String get logoutConfirmBody => 'तुम्हाला खात्यातून लॉगआउट करायचे आहे का?';

  @override
  String get businessTypeRetail => 'किरकोळ दुकान';

  @override
  String get businessTypeRestaurantTables => 'रेस्टॉरंट (टेबलसह)';

  @override
  String get businessTypeRestaurantTakeaway => 'रेस्टॉरंट (पार्सल)';

  @override
  String get appTagline => 'स्मार्ट बिलिंग सोल्युशन';

  @override
  String get loginTitle => 'पुन्हा स्वागत आहे';

  @override
  String get loginSubtitle => 'तुमच्या बिलिंग खात्यात साइन इन करा';

  @override
  String get loginPhone => 'मोबाइल नंबर';

  @override
  String get loginPhoneHint => '१० अंकी मोबाइल नंबर';

  @override
  String get loginPhoneRequired => 'मोबाइल नंबर आवश्यक आहे';

  @override
  String get loginPhoneInvalid => 'वैध १० अंकी नंबर टाका';

  @override
  String get loginPin => 'पिन';

  @override
  String get loginPinHint => '४ अंकी पिन';

  @override
  String get loginPinRequired => 'पिन आवश्यक आहे';

  @override
  String get loginPinInvalid => 'पिन ४ अंकी असावा';

  @override
  String get loginSignIn => 'साइन इन करा';

  @override
  String get loginForgotPin => 'पिन विसरलात?';

  @override
  String get loginNoAccount => 'खाते नाही? ';

  @override
  String get loginRegister => 'नोंदणी करा';

  @override
  String get loginNoAccountFound => 'या मोबाइल नंबरचे खाते सापडले नाही.';

  @override
  String get loginIncorrectPin => 'चुकीचा पिन. पुन्हा प्रयत्न करा.';

  @override
  String get loginAccountLocked =>
      'खाते तात्पुरते बंद आहे. १५ मिनिटांनी पुन्हा प्रयत्न करा.';

  @override
  String get loginGenericError => 'काहीतरी चूक झाली. पुन्हा प्रयत्न करा.';

  @override
  String get loginConnectionError =>
      'सर्व्हरशी संपर्क होऊ शकला नाही. तुमचे इंटरनेट कनेक्शन तपासा.';

  @override
  String get loginPendingTitle => 'खाते सक्रिय नाही';

  @override
  String get loginPendingBody =>
      'तुमचे खाते सक्रिय होण्याच्या प्रतीक्षेत आहे. खाते सक्रिय करण्यासाठी आमच्या सपोर्ट टीमशी संपर्क साधा.';

  @override
  String get loginSupportEmail => 'support@vengurlatech.com';

  @override
  String get forgotPinTitle => 'पिन विसरलात';

  @override
  String get forgotPinPhoneLabel => 'नोंदणीकृत मोबाइल नंबर';

  @override
  String get forgotPinPhoneHint => '१० अंकी नंबर';

  @override
  String get forgotPinPhoneInvalid => '१० अंकी नंबर टाका';

  @override
  String get forgotPinSendOtp => 'ओटीपी पाठवा';

  @override
  String get forgotPinSendFailed =>
      'ओटीपी पाठवता आला नाही. पुन्हा प्रयत्न करा.';

  @override
  String get forgotPinSetNewTitle => 'नवीन पिन सेट करा';

  @override
  String get forgotPinNewLabel => 'नवीन पिन';

  @override
  String get forgotPinConfirmLabel => 'पिनची खात्री करा';

  @override
  String get forgotPinConfirmHint => 'पिन पुन्हा टाका';

  @override
  String get forgotPinMismatch => 'पिन जुळत नाहीत';

  @override
  String get forgotPinReset => 'पिन रीसेट करा';

  @override
  String get forgotPinResetSuccess =>
      'पिन यशस्वीरित्या रीसेट झाला. आता लॉगिन करा.';

  @override
  String get forgotPinResetFailed => 'रीसेट अयशस्वी. पुन्हा प्रयत्न करा.';

  @override
  String get otpTitle => 'तुमचा नंबर पडताळा';

  @override
  String otpSubtitle(String phone) {
    return 'आम्ही $phone वर कोड पाठवला आहे';
  }

  @override
  String get otpEnterCode => 'ओटीपी टाका';

  @override
  String get otpVerify => 'पडताळा';

  @override
  String get otpResend => 'ओटीपी पुन्हा पाठवा';

  @override
  String otpResendIn(int seconds) {
    return '$seconds सेकंदात पुन्हा पाठवा';
  }

  @override
  String get otpInvalid => 'चुकीचा ओटीपी. पुन्हा प्रयत्न करा.';

  @override
  String get otpAppBarVerifyIdentity => 'ओळख पडताळा';

  @override
  String get otpAppBarVerifyPhone => 'मोबाइल नंबर पडताळा';

  @override
  String otpSentTo(String phone) {
    return 'आम्ही ६ अंकी ओटीपी\n+91 $phone वर व्हॉट्सअ‍ॅपद्वारे पाठवला आहे';
  }

  @override
  String get otpEnterAllDigits => 'कृपया सर्व ६ अंक टाका';

  @override
  String get otpVerifyButton => 'ओटीपी पडताळा';

  @override
  String get otpVerifyFailed => 'पडताळणी अयशस्वी. तुमचे कनेक्शन तपासा.';

  @override
  String get otpResendSuccess => 'ओटीपी पुन्हा पाठवला';

  @override
  String get otpResendFailed =>
      'ओटीपी पुन्हा पाठवता आला नाही. पुन्हा प्रयत्न करा.';

  @override
  String otpResendCooldown(int seconds) {
    return '$seconds सेकंदात ओटीपी पुन्हा पाठवा';
  }

  @override
  String get registerTitle => 'तुमचे खाते तयार करा';

  @override
  String get registerSubtitle => 'एका मिनिटात तुमचा व्यवसाय सेट करा';

  @override
  String get registerOwnerName => 'तुमचे नाव';

  @override
  String get registerBusinessName => 'व्यवसायाचे नाव';

  @override
  String get registerBusinessType => 'व्यवसायाचा प्रकार';

  @override
  String get registerPhone => 'मोबाइल नंबर';

  @override
  String get registerInventory => 'स्टॉक / माल नोंद ठेवा';

  @override
  String get registerBarcodeScanner => 'माझ्याकडे बारकोड स्कॅनर आहे';

  @override
  String get registerSubmit => 'खाते तयार करा';

  @override
  String get registerHaveAccount => 'आधीच खाते आहे?';

  @override
  String get registerLoginNow => 'लॉगिन करा';

  @override
  String get registerFailed => 'नोंदणी अयशस्वी. पुन्हा प्रयत्न करा.';

  @override
  String get registerAppBarTitle => 'व्यवसाय नोंदणी';

  @override
  String get registerSectionBusinessDetails => 'व्यवसायाची माहिती';

  @override
  String get registerSectionBusinessType => 'व्यवसायाचा प्रकार';

  @override
  String get registerSectionOwnerDetails => 'मालकाची माहिती';

  @override
  String get registerBusinessNameHint => 'उदा. शर्मा जनरल स्टोअर';

  @override
  String get registerBusinessPhone => 'व्यवसायाचा मोबाइल नंबर';

  @override
  String get registerBusinessPhoneHint => '१० अंकी नंबर';

  @override
  String get registerAddress => 'पत्ता (ऐच्छिक)';

  @override
  String get registerAddressHint => 'दुकानाचा पत्ता';

  @override
  String get registerTypeRestaurantTakeaway => 'रेस्टॉरंट (पार्सल / काउंटर)';

  @override
  String get registerInventoryTitle => 'स्टॉक नोंद सुरू करा';

  @override
  String get registerInventorySubtitle => 'प्रत्येक वस्तूचा स्टॉक मोजा';

  @override
  String get registerScannerTitle => 'यूएसबी बारकोड स्कॅनर आहे';

  @override
  String get registerScannerSubtitle => 'स्कॅनरने वस्तू आपोआप जोडा';

  @override
  String get registerOwnerNameHint => 'पूर्ण नाव';

  @override
  String get registerOwnerPhone => 'तुमचा मोबाइल नंबर';

  @override
  String get registerOwnerPhoneHint => '१० अंकी नंबर (लॉगिनसाठी वापरला जाईल)';

  @override
  String get registerConfirmPin => 'पिनची खात्री करा';

  @override
  String get registerCreateAccount => 'खाते तयार करा';

  @override
  String get registerOtpSendFailed =>
      'ओटीपी पाठवता आला नाही. तुमचे इंटरनेट कनेक्शन तपासा.';

  @override
  String get registerSuccessTitle => 'वित्तममध्ये आपले स्वागत आहे!';

  @override
  String get registerSuccessBody =>
      'नोंदणी यशस्वी झाली. तुमची ४ दिवसांची मोफत चाचणी सुरू झाली आहे.\n\nबिलिंग सुरू करण्यासाठी आता लॉगिन करा.';

  @override
  String get registerBackToLogin => 'लॉगिनवर परत जा';

  @override
  String get receiptPhonePrefix => 'फोन:';

  @override
  String get receiptBillNo => 'बिल क्र.:';

  @override
  String get receiptTable => 'टेबल:';

  @override
  String get receiptDate => 'दिनांक:';

  @override
  String get receiptCustomer => 'ग्राहक:';

  @override
  String get receiptCustomerPhone => 'फोन:';

  @override
  String get receiptColItem => 'वस्तू';

  @override
  String get receiptColQty => 'नग';

  @override
  String get receiptColPrice => 'दर';

  @override
  String get receiptColTotal => 'एकूण';

  @override
  String get receiptSubtotal => 'उप-बेरीज:';

  @override
  String get receiptTax => 'कर:';

  @override
  String get receiptDiscount => 'सूट:';

  @override
  String get receiptTotal => 'एकूण:';

  @override
  String get receiptPayment => 'पेमेंट:';

  @override
  String get receiptThankYou => 'धन्यवाद, पुन्हा भेट द्या!';

  @override
  String get receiptDefaultBusiness => 'व्यवसाय';

  @override
  String get billingTitle => 'बिलिंग';

  @override
  String get billingSearchItems => 'वस्तू शोधा…';

  @override
  String get billingCartEmpty => 'कार्ट रिकामी आहे';

  @override
  String get billingCartEmptyHint => 'बिलात जोडण्यासाठी वस्तूवर टॅप करा';

  @override
  String get billingAddAtLeastOneItem => 'कार्टमध्ये किमान एक वस्तू जोडा';

  @override
  String get billingAddAtLeastOneItemFirst => 'आधी किमान एक वस्तू जोडा';

  @override
  String get billingSubtotal => 'उप-बेरीज';

  @override
  String get billingTax => 'कर';

  @override
  String get billingDiscount => 'सूट';

  @override
  String get billingTotal => 'एकूण';

  @override
  String get billingCustomerName => 'ग्राहकाचे नाव (ऐच्छिक)';

  @override
  String get billingCustomerPhone => 'ग्राहकाचा मोबाइल (ऐच्छिक)';

  @override
  String get billingDiscountAmount => 'सूट रक्कम';

  @override
  String get billingPaymentMode => 'पेमेंट पद्धत';

  @override
  String get billingGenerateBill => 'बिल तयार करा';

  @override
  String get billingSaveDraft => 'ड्राफ्ट जतन करा';

  @override
  String get billingClearCart => 'निवडलेल्या वस्तू काढा';

  @override
  String billingTableNumber(String number) {
    return 'टेबल $number';
  }

  @override
  String get billingReleaseTable => 'ड्राफ्ट काढून टाका';

  @override
  String get billingReleaseTableTitle => 'ड्राफ्ट काढून टाकायचा?';

  @override
  String get billingReleaseTableBody =>
      'सर्व वस्तू काढल्यास हा जतन केलेला ड्राफ्ट रद्द होईल. हे पूर्ववत करता येणार नाही.';

  @override
  String get billingReleaseTableFailed => 'ड्राफ्ट काढता आला नाही.';

  @override
  String get billingDraftOfflineError =>
      'ऑफलाइन असताना ड्राफ्ट जतन करता येणार नाही';

  @override
  String get billingDraftSaved => 'ड्राफ्ट जतन झाला.';

  @override
  String get billingSaveFailed => 'जतन करता आले नाही. तुमचे कनेक्शन तपासा.';

  @override
  String get billingGenerateFailed =>
      'बिल तयार करता आले नाही. तुमचे कनेक्शन तपासा.';

  @override
  String billingSavedOffline(String error) {
    return 'बिल ऑफलाइन जतन करता आले नाही: $error';
  }

  @override
  String billingItemNotFoundBarcode(String barcode) {
    return 'या बारकोडची वस्तू सापडली नाही: $barcode';
  }

  @override
  String get billingPrintSuccess => 'बिल यशस्वीरित्या प्रिंट झाले';

  @override
  String billingPrintFailed(String error) {
    return 'प्रिंट अयशस्वी: $error';
  }

  @override
  String get billingWhatsappSent => 'पावतीची लिंक व्हॉट्सअ‍ॅपवर पाठवली';

  @override
  String get billingWhatsappNeedsPhone =>
      'व्हॉट्सअ‍ॅपवर पाठवण्यासाठी ग्राहकाचा फोन नंबर टाका';

  @override
  String get billingWhatsappFailed => 'व्हॉट्सअ‍ॅप संदेश पाठवता आला नाही';

  @override
  String billingChooseSize(String name) {
    return 'प्रकार निवडा — $name';
  }

  @override
  String get billingOutOfStock => 'स्टॉक संपला';

  @override
  String get billingInsufficientStock => 'स्टॉक अपुरा आहे';

  @override
  String get billingInsufficientStockBody =>
      'खालील वस्तूंचा पुरेसा स्टॉक नाही:';

  @override
  String billingStockAvailable(String available) {
    return 'उपलब्ध: $available';
  }

  @override
  String billingStockAvailableAsked(String available, String requested) {
    return 'उपलब्ध: $available / मागणी: $requested';
  }

  @override
  String get billingUnknownItem => 'अज्ञात';

  @override
  String billingWhatsappFailedWithError(String error) {
    return 'व्हॉट्सअ‍ॅप अयशस्वी: $error';
  }

  @override
  String get billingCart => 'कार्ट';

  @override
  String billingCartWithCount(int count) {
    return 'कार्ट ($count)';
  }

  @override
  String get billingNoItemsFound => 'वस्तू सापडल्या नाहीत';

  @override
  String get billingOrder => 'ऑर्डर';

  @override
  String get billingNoItemsAddedYet => 'अजून वस्तू जोडलेल्या नाहीत';

  @override
  String get billingCustomerDetails => 'ग्राहकाची माहिती (ऐच्छिक)';

  @override
  String get billingCustomerNameLabel => 'ग्राहकाचे नाव';

  @override
  String get billingCustomerPhoneLabel => 'ग्राहकाचा मोबाइल';

  @override
  String get billingPhoneInvalid => 'ग्राहक क्रमांक १० अंकी असणे आवश्यक आहे.';

  @override
  String get billingDiscountPercent => 'सूट %';

  @override
  String get billingDiscountRupees => 'सूट ₹';

  @override
  String get billingTotalAmount => 'एकूण रक्कम';

  @override
  String billingSubtotalPlusGst(String subtotal, String tax) {
    return '₹$subtotal + ₹$tax जीएसटी';
  }

  @override
  String get billingDiscountApplied => 'दिलेली सूट';

  @override
  String get billingNetPayable => 'देय रक्कम';

  @override
  String get billingWhatsapp => 'व्हॉट्सअ‍ॅप';

  @override
  String get billingColItem => 'वस्तू';

  @override
  String get billingColPrice => 'किंमत';

  @override
  String get billingColQty => 'संख्या';

  @override
  String billingStalePricesFrom(String age) {
    return '$age च्या किमती';
  }

  @override
  String get billingStalePrices => 'जुन्या किमती';

  @override
  String get billingStaleVeryOld =>
      'खूप जुनी माहिती — किमती चुकीच्या असू शकतात';

  @override
  String get billingStaleConnectToRefresh => 'किमती अपडेट करण्यासाठी ऑनलाइन या';

  @override
  String get commonClear => 'काढा';

  @override
  String get splitSelectSecondTable => 'दुसरे टेबल निवडा';

  @override
  String get splitNoOtherTables => 'दुसरे कोणतेही टेबल उपलब्ध नाही';

  @override
  String get paymentCash => 'रोख';

  @override
  String get paymentUpi => 'यूपीआय';

  @override
  String get paymentCard => 'कार्ड';

  @override
  String get paymentCredit => 'उधार';

  @override
  String get paymentOther => 'इतर';

  @override
  String get itemsTitle => 'वस्तू / मेनू';

  @override
  String get menuPhotosTitle => 'मेनू फोटो';

  @override
  String get menuPhotosTooltip => 'मेनू फोटो';

  @override
  String get menuPhotosSubtitle => 'QR ऑर्डर मेनूवर ग्राहकांना दिसणारे फोटो.';

  @override
  String get menuPhotosSearch => 'पदार्थ शोधा…';

  @override
  String get menuPhotosEmpty =>
      'अजून वस्तू नाहीत. आधी वस्तू जोडा, नंतर येथे त्यांचे फोटो जोडा.';

  @override
  String get menuPhotosAdd => 'फोटो जोडा';

  @override
  String get menuPhotosChange => 'फोटो बदला';

  @override
  String get menuPhotosRemove => 'फोटो काढा';

  @override
  String get menuPhotosPickCamera => 'फोटो काढा';

  @override
  String get menuPhotosPickGallery => 'गॅलरीमधून निवडा';

  @override
  String get menuPhotosUploading => 'अपलोड होत आहे…';

  @override
  String get menuPhotosUploadFailed => 'फोटो अपलोड करता आला नाही';

  @override
  String get menuPhotosRemoveFailed => 'फोटो काढता आला नाही';

  @override
  String get menuPhotosRemoveConfirm => 'हा फोटो काढायचा?';

  @override
  String get itemsSearch => 'वस्तू शोधा…';

  @override
  String get itemsStockOverview => 'उपलब्ध साठा';

  @override
  String get itemsAddItem => 'वस्तू जोडा';

  @override
  String get itemsEditItem => 'वस्तूमधे बदल करा';

  @override
  String get itemsEditItemTooltip => 'वस्तूमधे बदल करा';

  @override
  String get itemsNoneYetOwner =>
      'अजून वस्तू नाहीत. पहिली वस्तू जोडण्यासाठी + दाबा.';

  @override
  String get itemsNoneFound => 'वस्तू सापडल्या नाहीत.';

  @override
  String get itemsDeleteTitle => 'वस्तू हटवा';

  @override
  String itemsDeleteBody(String name) {
    return '\"$name\" हटवायची? ती यापुढे बिलिंगमध्ये दिसणार नाही.';
  }

  @override
  String get itemsFieldName => 'नाव';

  @override
  String get itemsFieldCategory => 'श्रेणी';

  @override
  String get itemsFieldCategoryHint => 'उदा. शीतपेये';

  @override
  String get itemsFieldPrice => 'किंमत (₹)';

  @override
  String get itemsFieldTaxRate => 'कर दर % (ऐच्छिक)';

  @override
  String get itemsFieldTaxRateHint => 'उदा. ५, १२, १८';

  @override
  String get itemsFieldBarcode => 'बारकोड (ऐच्छिक)';

  @override
  String get itemsFieldStock => 'स्टॉक संख्या';

  @override
  String get itemsFieldUnit => 'एकक';

  @override
  String get itemsUnitPiece => 'नग';

  @override
  String get itemsUnitKg => 'किलोग्रॅम (kg)';

  @override
  String get itemsUnitGram => 'ग्रॅम (g)';

  @override
  String get itemsUnitLitre => 'लिटर (L)';

  @override
  String get itemsUnitMl => 'मिलिलिटर (ml)';

  @override
  String get itemsUnitMetre => 'मीटर (m)';

  @override
  String get itemsUnitDozen => 'डझन';

  @override
  String get itemsUnitPlate => 'प्लेट';

  @override
  String get itemsManageSizes => 'प्रकार जोडा';

  @override
  String itemsManageSizesCount(int count) {
    return 'प्रकार व्यवस्थापित करा ($count)';
  }

  @override
  String itemsSizesTitle(String name) {
    return 'प्रकार — $name';
  }

  @override
  String get itemsSizeLabel => 'प्रकार नाव (उदा. XL, हाफ, 500ml)';

  @override
  String get itemsSizePrice => 'किंमत (रिक्त = वस्तूची किंमत)';

  @override
  String get itemsSizeStock => 'स्टॉक';

  @override
  String get itemsAddSize => 'प्रकार जोडा';

  @override
  String get itemsNoSizesYet => 'अद्याप प्रकार नाहीत. खाली एक जोडा.';

  @override
  String get itemsStockPerSizeHint =>
      'स्टॉक प्रत्येक प्रकारानुसार ठेवला जातो. प्रत्येक प्रकाराचा स्टॉक अद्ययावत करण्यासाठी वस्तूवर टॅप करा.';

  @override
  String itemsSizeDeleteConfirm(String label) {
    return '\"$label\" प्रकार काढायचा?';
  }

  @override
  String itemsStockLabel(String qty) {
    return 'स्टॉक: $qty';
  }

  @override
  String get itemsLowStock => 'स्टॉक कमी';

  @override
  String get itemsCurrentStock => 'सध्याचा स्टॉक';

  @override
  String get itemsAddQuantity => 'संख्या जोडा';

  @override
  String get itemsTotalAfterAdding => 'जोडल्यानंतर एकूण';

  @override
  String get itemsInventoryDisabled => 'स्टॉक नोंद बंद आहे.';

  @override
  String get itemsBarcodePrintTitle => 'बारकोड प्रिंट करा';

  @override
  String get itemsBarcodeGenerateTitle => 'बारकोड तयार करा आणि प्रिंट करा';

  @override
  String get itemsBarcodeGeneratedNote =>
      'या वस्तूला बारकोड नाही. नवीन बारकोड तयार केला आहे. प्रिंट करण्यापूर्वी तुम्ही तो बदलू शकता.';

  @override
  String get itemsBarcodeValue => 'बारकोड क्रमांक';

  @override
  String get itemsBarcodeCopies => 'प्रती';

  @override
  String get itemsBarcodeSentToPrinter => 'बारकोड लेबल प्रिंटरकडे पाठवले';

  @override
  String get tablesTitle => 'टेबल';

  @override
  String get tablesEmpty => 'रिकामे';

  @override
  String get tablesOccupied => 'व्यापलेले';

  @override
  String get tablesBilled => 'बिल झाले';

  @override
  String get tablesNoTables => 'अजून टेबल सेट केलेली नाहीत.';

  @override
  String get tablesAddTable => 'टेबल जोडा';

  @override
  String tablesTableLabel(String number) {
    return 'टेबल $number';
  }

  @override
  String get tablesNoTablesYet => 'अजून टेबल नाहीत';

  @override
  String get tablesBilledOrderBody =>
      'या टेबलचे बिल झाले आहे. तुम्हाला काय करायचे आहे?';

  @override
  String get tablesMarkPaidEmpty => 'पैसे मिळाले / टेबल रिकामे करा';

  @override
  String get tablesVoidBill => 'बिल रद्द करा';

  @override
  String get tablesTableNumberLabel => 'टेबल क्रमांक (उदा. T1, A2)';

  @override
  String get tablesDeleteTitle => 'टेबल हटवा';

  @override
  String tablesDeleteBody(String number) {
    return '\"$number\" टेबल हटवायचे?';
  }

  @override
  String get tablesShowQr => 'QR दाखवा / प्रिंट करा';

  @override
  String get tablesShowQrSubtitle =>
      'ग्राहक स्कॅन करून मेनू पाहू आणि ऑर्डर करू शकतात';

  @override
  String get tablesQrNotReady => 'या टेबलसाठी QR कोड अजून तयार नाही.';

  @override
  String tablesQrTitle(String number) {
    return 'टेबल $number — ऑर्डर QR';
  }

  @override
  String get tablesQrHint =>
      'हा QR टेबलावर लावा. ग्राहक स्कॅन करून मेनू पाहतात आणि याच टेबलावर ऑर्डर करतात.';

  @override
  String get tablesRotateQr => 'QR बदला';

  @override
  String get tablesRotateQrBody =>
      'यामुळे जुना प्रिंट केलेला QR बंद होईल. बदलल्यानंतर नवीन QR प्रिंट करून लावा. पुढे जायचे?';

  @override
  String get tablesQrRotated => 'QR कोड बदलला. कृपया स्टिकर पुन्हा प्रिंट करा.';

  @override
  String get commonShare => 'शेअर करा';

  @override
  String get tablesPrintQr => 'प्रिंट करा';

  @override
  String tablesQrShareText(String number) {
    return 'टेबल $number वर ऑर्डर करण्यासाठी स्कॅन करा';
  }

  @override
  String get tablesQrShareFailed => 'QR कोड शेअर करता आला नाही.';

  @override
  String get tablesQrPrinted => 'QR प्रिंटरला पाठवला.';

  @override
  String get tablesQrPrintFailed => 'QR कोड प्रिंट करता आला नाही.';

  @override
  String get historyTitle => 'इतिहास';

  @override
  String get historyNoBills => 'अजून बिले नाहीत.';

  @override
  String get historySearchHint => 'बिल क्रमांक किंवा ग्राहकाने शोधा…';

  @override
  String historyBillNumber(String number) {
    return 'बिल #$number';
  }

  @override
  String get historyReprint => 'पुन्हा प्रिंट करा';

  @override
  String get historyShare => 'शेअर करा';

  @override
  String get historyPending => 'प्रलंबित';

  @override
  String get historySynced => 'सिंक झाले';

  @override
  String get historyFailed => 'अयशस्वी';

  @override
  String get historyBillHistoryTitle => 'बिल इतिहास';

  @override
  String get historySearchBillOrPhone =>
      'बिल क्रमांक किंवा मोबाइल नंबरने शोधा…';

  @override
  String get historyNoBillsForPeriod => 'या कालावधीत कोणतेही बिल नाही.';

  @override
  String get historyFilterToday => 'आज';

  @override
  String get historyFilterYesterday => 'काल';

  @override
  String get historyFilterThisMonth => 'या महिन्यात';

  @override
  String get historyFilterLastMonth => 'मागील महिना';

  @override
  String get historyFilterAll => 'सर्व';

  @override
  String get historyFilterCustom => 'सानुकूल';

  @override
  String get historyStatusFinalized => 'पूर्ण झाले';

  @override
  String get historyStatusVoided => 'रद्द केले';

  @override
  String get historyStatusDraft => 'ड्राफ्ट';

  @override
  String historyItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count वस्तू',
      one: '1 वस्तू',
    );
    return '$_temp0';
  }

  @override
  String historyBillMeta(String time, String payment, String items) {
    return '$time  ·  $payment  ·  $items';
  }

  @override
  String get historyVoidBill => 'बिल रद्द करा';

  @override
  String get historyVoid => 'रद्द करा';

  @override
  String historyVoidConfirmBody(String number) {
    return 'बिल $number रद्द करायचे? हे पुन्हा बदलता येणार नाही.';
  }

  @override
  String get historyNoPrinterConfigured =>
      'प्रिंटर सेट केलेला नाही. सेटिंग्जमध्ये जाऊन सेट करा.';

  @override
  String get historyPayment => 'पेमेंट';

  @override
  String get reportsTitle => 'अहवाल';

  @override
  String get reportsToday => 'आज';

  @override
  String get reportsWeek => 'हा आठवडा';

  @override
  String get reportsMonth => 'हा महिना';

  @override
  String get reportsTotalSales => 'एकूण विक्री';

  @override
  String get reportsBillCount => 'बिले';

  @override
  String get reportsAverageBill => 'सरासरी बिल';

  @override
  String get reportsTopItems => 'सर्वाधिक विकल्या वस्तू';

  @override
  String get reportsNoData => 'या कालावधीसाठी माहिती नाही.';

  @override
  String get reportsYear => 'वर्ष';

  @override
  String get reportsChangePeriod => 'कालावधी बदला';

  @override
  String get reportsNetRevenue => 'निव्वळ उत्पन्न';

  @override
  String get reportsExpenses => 'खर्च';

  @override
  String reportsBills(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बिले',
      one: '1 बिल',
    );
    return '$_temp0';
  }

  @override
  String reportsBillsWithDiscount(String bills, String discount) {
    return '$bills · −रु. $discount सूट';
  }

  @override
  String reportsCategoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count श्रेणी',
      one: '1 श्रेणी',
    );
    return '$_temp0';
  }

  @override
  String get reportsNoExpenses => 'खर्च नाही';

  @override
  String get reportsRevenueByPaymentMode => 'पेमेंट पद्धतीनुसार उत्पन्न';

  @override
  String get reportsExpensesByCategory => 'श्रेणीनुसार खर्च';

  @override
  String get reportsDailyBreakdown => 'दैनिक तपशील';

  @override
  String get expensesTitle => 'खर्च';

  @override
  String get expensesTabThisMonth => 'हा महिना';

  @override
  String get expensesTabRecurring => 'दरमहा खर्च';

  @override
  String get expensesNoneThisMonth =>
      'या महिन्यात खर्च नाही.\nजोडण्यासाठी + दाबा.';

  @override
  String get expensesAddExpense => 'खर्च जोडा';

  @override
  String get expensesEditExpense => 'खर्च संपादित करा';

  @override
  String get expensesUpdateExpense => 'खर्च अपडेट करा';

  @override
  String get expensesAddRecurring => 'दरमहा खर्च जोडा';

  @override
  String get expensesAddRecurringExpense => 'दरमहा खर्च जोडा';

  @override
  String get expensesEditRecurringExpense => 'दरमहा खर्च संपादित करा';

  @override
  String get expensesSaveRecurring => 'दरमहा खर्च जतन करा';

  @override
  String get expensesRecurringNote =>
      'हे दर महिन्याला स्मरणपत्र म्हणून दिसतील.';

  @override
  String get expensesMonthly => 'दरमहा';

  @override
  String get expensesAddAllToMonth => 'सर्व या महिन्यात जोडा';

  @override
  String get expensesCategory => 'श्रेणी';

  @override
  String get expensesCustomCategory => 'स्वतःची श्रेणी';

  @override
  String get expensesCustomCategoryHint => 'उदा. विमा';

  @override
  String get expensesAmount => 'रक्कम (रु.)';

  @override
  String get expensesAmountRequired => 'रक्कम आवश्यक आहे';

  @override
  String get expensesAmountInvalid => 'वैध रक्कम टाका';

  @override
  String get expensesDescription => 'तपशील (ऐच्छिक)';

  @override
  String get expensesDetailsTitle => 'खर्चाचा तपशील';

  @override
  String get expensesPaymentMode => 'पेमेंट पद्धत';

  @override
  String get expensesExpenseDate => 'तारीख';

  @override
  String get expensesAddedBy => 'जोडणारा';

  @override
  String get expensesDeleteTitle => 'खर्च हटवायचा?';

  @override
  String expensesDeleteBody(String category, String amount) {
    return 'रु. $amount चा $category खर्च हटवायचा?';
  }

  @override
  String get expensesRemoveRecurringTitle => 'दरमहा खर्च काढायचा?';

  @override
  String expensesRemoveRecurringBody(String category) {
    return '\"$category\" दरमहा यादीतून काढायचा? यामुळे जुन्या नोंदी हटणार नाहीत.';
  }

  @override
  String get expensesNoRecurringYet =>
      'अजून दरमहा खर्च नाहीत.\nदर महिन्याला येणारे खर्च जोडा\n(उदा. भाडे, पगार).';

  @override
  String get expensesCustomChip => '+ स्वतःची';

  @override
  String expensesPendingRecurring(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count दरमहा खर्च या महिन्यात अजून जोडलेले नाहीत',
      one: '1 दरमहा खर्च या महिन्यात अजून जोडलेला नाही',
    );
    return '$_temp0';
  }

  @override
  String expensesRecurringAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count दरमहा खर्च जोडले',
      one: '1 दरमहा खर्च जोडला',
    );
    return '$_temp0';
  }

  @override
  String get expensesCatRent => 'भाडे';

  @override
  String get expensesCatSalary => 'पगार';

  @override
  String get expensesCatUtilities => 'वीज / पाणी बिल';

  @override
  String get expensesCatStockPurchase => 'माल खरेदी';

  @override
  String get expensesCatTransport => 'वाहतूक';

  @override
  String get expensesCatMarketing => 'जाहिरात';

  @override
  String get expensesCatMaintenance => 'देखभाल';

  @override
  String get expensesCatTaxes => 'कर';

  @override
  String get expensesCatOther => 'इतर';

  @override
  String get staffTitle => 'कर्मचारी व्यवस्थापन';

  @override
  String get staffAddStaff => 'कर्मचारी जोडा';

  @override
  String get staffEditStaff => 'कर्मचारी संपादित करा';

  @override
  String get staffNone => 'अजून कर्मचारी जोडलेले नाहीत.';

  @override
  String get staffName => 'नाव';

  @override
  String get staffPhone => 'मोबाइल नंबर';

  @override
  String get staffRole => 'भूमिका';

  @override
  String get staffRoleOwner => 'मालक';

  @override
  String get staffRoleCashier => 'कॅशियर';

  @override
  String get staffRoleWaiter => 'वेटर';

  @override
  String get staffRoleServer => 'सर्व्हर';

  @override
  String get staffRoleKitchen => 'किचन शेफ';

  @override
  String get staffAddKitchen => 'किचन शेफ जोडा';

  @override
  String get staffSectionWaiters => 'वेटर आणि कॅशियर';

  @override
  String get staffSectionKitchen => 'किचन';

  @override
  String get staffDeleteTitle => 'कर्मचारी काढायचा?';

  @override
  String staffDeleteBody(String name) {
    return '\"$name\" यांना तुमच्या टीममधून काढायचे?';
  }

  @override
  String get staffRemoveTitle => 'कर्मचारी काढा';

  @override
  String staffRemoveBody(String name) {
    return '\"$name\" यांना काढायचे?';
  }

  @override
  String staffLoadFailed(String error) {
    return 'कर्मचारी माहिती आणता आली नाही: $error';
  }

  @override
  String get staffNoCashiers => 'अजून कॅशियर जोडलेले नाहीत.';

  @override
  String get staffSearchHint => 'नाव किंवा फोनने कर्मचारी शोधा…';

  @override
  String get staffNoMatch => 'तुमच्या शोधाशी जुळणारे कर्मचारी नाहीत.';

  @override
  String get staffPhoneInvalid => '१० अंकी नंबर आवश्यक आहे';

  @override
  String get staffPinNew => 'नवीन पिन (जुना ठेवायचा असल्यास रिकामे ठेवा)';

  @override
  String get staffPinNewLabel => 'पिन (४ अंकी)';

  @override
  String get staffPinInvalid => 'पिन ४ अंकी असावा';

  @override
  String get businessProfileTitle => 'व्यवसाय प्रोफाइल';

  @override
  String get businessProfileName => 'व्यवसायाचे नाव';

  @override
  String get businessProfileAddress => 'पत्ता';

  @override
  String get businessProfilePhone => 'मोबाइल';

  @override
  String get businessProfileGst => 'जीएसटीआयएन (ऐच्छिक)';

  @override
  String get businessProfileFooter => 'पावतीवरील तळटीप';

  @override
  String get businessProfileSaved => 'व्यवसाय प्रोफाइल अपडेट झाले';

  @override
  String get businessProfileSaveFailed =>
      'जतन करता आले नाही. तुमचे कनेक्शन तपासा.';

  @override
  String get businessProfileSaveButton => 'प्रोफाइल जतन करा';

  @override
  String get businessProfileNoChanges => 'जतन करण्यासारखा बदल नाही';

  @override
  String get businessProfileUpdated => 'प्रोफाइल यशस्वीरित्या अपडेट झाले';

  @override
  String get businessProfileSectionAccount => 'खाते';

  @override
  String get businessProfileOwnerName => 'नाव';

  @override
  String get businessProfileOwnerPhone => 'मोबाइल';

  @override
  String get businessProfileSectionBasic => 'मूलभूत माहिती';

  @override
  String get businessProfileSectionAddress => 'पत्ता';

  @override
  String get businessProfileSectionTax => 'कर माहिती';

  @override
  String get businessProfileSectionBilling => 'बिलिंग';

  @override
  String get businessProfileNameLabel => 'व्यवसायाचे नाव';

  @override
  String get businessProfileNameHint => 'उदा. कांबळे प्रोव्हिजन्स';

  @override
  String get businessProfilePhoneHint => '१० अंकी मोबाइल नंबर';

  @override
  String get businessProfilePhoneInvalid => '१० अंकी असणे आवश्यक';

  @override
  String get businessProfileEmail => 'ईमेल (ऐच्छिक)';

  @override
  String get businessProfileEmailHint => 'owner@example.com';

  @override
  String get businessProfileEmailInvalid => 'ईमेल पत्ता चुकीचा आहे';

  @override
  String get businessProfileWebsite => 'वेबसाइट (ऐच्छिक)';

  @override
  String get businessProfileWebsiteHint => 'https://example.com';

  @override
  String get businessProfileType => 'व्यवसायाचा प्रकार';

  @override
  String get businessProfileStreet => 'पत्ता';

  @override
  String get businessProfileStreetHint => 'दुकान नं. ५, मार्केट रोड';

  @override
  String get businessProfileCity => 'शहर';

  @override
  String get businessProfileCityHint => 'वेंगुर्ला';

  @override
  String get businessProfileState => 'राज्य';

  @override
  String get businessProfileStateHint => 'महाराष्ट्र';

  @override
  String get businessProfilePincode => 'पिनकोड';

  @override
  String get businessProfilePincodeHint => '416523';

  @override
  String get businessProfilePincodeInvalid => '६ अंकी पिनकोड';

  @override
  String get businessProfileGstHint => '27ABCDE1234F1Z5';

  @override
  String get businessProfileGstInvalid => 'जीएसटीआयएन चुकीचा आहे';

  @override
  String get businessProfilePan => 'पॅन (ऐच्छिक)';

  @override
  String get businessProfilePanHint => 'ABCDE1234F';

  @override
  String get businessProfilePanInvalid => 'पॅन क्रमांक चुकीचा आहे';

  @override
  String get businessProfileBillPrefix => 'बिल क्रमांकाचा प्रिफिक्स';

  @override
  String get businessProfileBillPrefixHelper =>
      'बिलांना INV-0001, INV-0002, … असे क्रमांक मिळतील';

  @override
  String get businessProfileBillPrefixInvalid =>
      'फक्त अक्षरे, अंक, हायफन आणि स्लॅश चालतील';

  @override
  String get businessProfileFooterNote => 'बिलावरील तळमजकूर (ऐच्छिक)';

  @override
  String get businessProfileFooterNoteHint =>
      'आमच्याकडे खरेदी केल्याबद्दल धन्यवाद!';

  @override
  String get printerSetupTitle => 'प्रिंटर सेटअप';

  @override
  String get printerSetupScan => 'प्रिंटर शोधा';

  @override
  String get printerSetupScanning => 'शोधत आहे…';

  @override
  String get printerSetupNoPrinters =>
      'प्रिंटर सापडला नाही. प्रिंटर चालू आणि जोडलेला असल्याची खात्री करा.';

  @override
  String get printerSetupConnected => 'जोडलेले';

  @override
  String get printerSetupConnect => 'जोडा';

  @override
  String get printerSetupDisconnect => 'वेगळे करा';

  @override
  String get printerSetupTestPrint => 'चाचणी प्रिंट';

  @override
  String get printerSetupNotConfigured => 'प्रिंटर सेट केलेला नाही';

  @override
  String get conflictTitle => 'सिंक न झालेली बिले';

  @override
  String get conflictNone => 'तुमच्या लक्षाची गरज असलेले काही नाही.';

  @override
  String get conflictKeepMine => 'माझी प्रत ठेवा';

  @override
  String get conflictKeepServer => 'सर्व्हरची प्रत ठेवा';

  @override
  String get conflictResolved => 'मतभेद सोडवला';

  @override
  String get licenseBlockedTitle => 'सदस्यता आवश्यक';

  @override
  String get licenseBlockedOffline => 'तुमची सदस्यता पडताळण्यासाठी ऑनलाइन या.';

  @override
  String get licenseBlockedSubscription =>
      'तुमची सदस्यता संपली आहे. बिलिंग सुरू ठेवण्यासाठी नूतनीकरण करा.';

  @override
  String get licenseBlockedPending =>
      'तुमचे खाते सक्रिय होण्याच्या प्रतीक्षेत आहे.';

  @override
  String get licenseContactSupport => 'सपोर्टशी संपर्क साधा';

  @override
  String get licenseCheckAgain => 'पुन्हा तपासा';

  @override
  String get licenseGraceLastDay =>
      'शेवटचा दिवस! अ‍ॅप वापरणे सुरू ठेवण्यासाठी आज ऑनलाइन या.';

  @override
  String licenseGraceDaysLeft(int days) {
    return '$days दिवस शिल्लक — सदस्यता पडताळण्यासाठी लवकर ऑनलाइन या.';
  }

  @override
  String get updateTitle => 'अपडेट उपलब्ध आहे';

  @override
  String get updateBody => 'वित्तमची नवीन आवृत्ती उपलब्ध आहे.';

  @override
  String get updateNow => 'आता अपडेट करा';

  @override
  String get updateLater => 'नंतर';

  @override
  String get offlineBanner =>
      'तुम्ही ऑफलाइन आहात. पुन्हा कनेक्ट झाल्यावर बिले सिंक होतील.';

  @override
  String get licenseTitleOffline => 'पुढे जाण्यासाठी ऑनलाइन या';

  @override
  String get licenseTitlePending => 'खाते सक्रिय होण्याच्या प्रतीक्षेत';

  @override
  String get licenseTitleExpired => 'सदस्यता संपली';

  @override
  String get licenseSubtitleOffline =>
      'तुम्ही खूप वेळ ऑफलाइन आहात.\nसदस्यता पडताळण्यासाठी इंटरनेटला जोडा.';

  @override
  String get licenseSubtitlePending =>
      'तुमचे खाते तपासले जात आहे.\nसदस्यता सुरू करण्यासाठी सपोर्टशी संपर्क साधा.';

  @override
  String get licenseSubtitleExpired =>
      'तुमची सदस्यता संपली आहे किंवा बंद केली आहे.\nनूतनीकरणासाठी सपोर्टशी संपर्क साधा.';

  @override
  String get licenseChecking => 'तपासत आहे…';

  @override
  String get licenseConnectFailed =>
      'कनेक्ट होऊ शकले नाही. तुमचे इंटरनेट तपासा आणि पुन्हा प्रयत्न करा.';

  @override
  String get licenseMsgSubscription =>
      'तुमची सदस्यता संपली आहे किंवा बंद केली आहे. कृपया सपोर्टशी संपर्क साधा.';

  @override
  String get licenseMsgPending =>
      'तुमचे खाते सक्रिय होण्याच्या प्रतीक्षेत आहे. कृपया सपोर्टशी संपर्क साधा.';

  @override
  String get licenseMsgStillOffline =>
      'अजूनही ऑफलाइन आहात. इंटरनेटला जोडा आणि पुन्हा प्रयत्न करा.';

  @override
  String get licenseMsgVerifyFailed =>
      'सदस्यता पडताळता आली नाही. पुन्हा प्रयत्न करा.';

  @override
  String get licenseBrandFooter => 'वित्तम बिलिंग';

  @override
  String get printerSetupPermissionDenied =>
      'ब्लूटूथ परवानगी नाकारली. अ‍ॅप सेटिंग्जमध्ये ती द्या.';

  @override
  String get printerSetupNoPaired =>
      'जोडलेला प्रिंटर सापडला नाही. आधी फोनच्या ब्लूटूथ सेटिंग्जमध्ये प्रिंटर जोडा.';

  @override
  String printerSetupLoadFailed(String error) {
    return 'प्रिंटर मिळवता आले नाहीत: $error';
  }

  @override
  String printerSetupSelectedSnack(String name) {
    return '\"$name\" प्रिंटर निवडला';
  }

  @override
  String get printerSetupCleared => 'प्रिंटर काढला';

  @override
  String get printerSetupTestSent => 'चाचणी पान पाठवले!';

  @override
  String printerSetupPrintFailed(String error) {
    return 'प्रिंट अयशस्वी: $error';
  }

  @override
  String get printerSetupActivePrinter => 'सध्याचा प्रिंटर';

  @override
  String get printerSetupUnknown => 'अज्ञात';

  @override
  String get printerSetupActiveBadge => 'सुरू';

  @override
  String get printerSetupAvailablePrinters => 'उपलब्ध प्रिंटर';

  @override
  String get printerSetupScanButton => 'प्रिंटर शोधा';

  @override
  String get printerSetupScanHint =>
      'तुमच्या फोनच्या ब्लूटूथ सेटिंग्जमध्ये आधीच जोडलेले प्रिंटर दाखवले जातात. आधी तिथे प्रिंटर जोडा, मग इथे शोधा दाबा.';

  @override
  String get printerSetupTapScan => 'प्रिंटर शोधण्यासाठी \"शोधा\" दाबा';

  @override
  String get printerSetupUnknownPrinter => 'अज्ञात प्रिंटर';

  @override
  String get printerSetupSelectedBadge => 'निवडलेला';

  @override
  String get printerSetupSelect => 'निवडा';

  @override
  String get printerSetupNotes => 'सूचना';

  @override
  String get printerSetupNoteBluetooth =>
      'अँड्रॉइड/आयफोन: आधी फोनच्या ब्लूटूथ सेटिंग्जमध्ये प्रिंटर जोडा, मग इथे शोधा दाबा';

  @override
  String get printerSetupNoteWindows =>
      'विंडोज: बीएलई किंवा यूएसबी वापरते — शोधताना प्रिंटर चालू असावा';

  @override
  String get printerSetupNoteUsb =>
      'विंडोजवर यूएसबीसाठी प्रिंटरचा WinUSB ड्रायव्हर इन्स्टॉल असणे आवश्यक आहे';

  @override
  String get printerSetupNoteThermal => 'फक्त ८० मिमी थर्मल प्रिंटर चालतात';

  @override
  String get conflictQueuedForRetry => 'बिल पुन्हा प्रयत्नासाठी रांगेत ठेवले';

  @override
  String get conflictDismissed => 'बिल काढून टाकले';

  @override
  String conflictSyncedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बिले सिंक झाली',
      one: '1 बिल सिंक झाले',
    );
    return '$_temp0';
  }

  @override
  String conflictRemainCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count मतभेद शिल्लक आहेत',
      one: '1 मतभेद शिल्लक आहे',
    );
    return '$_temp0';
  }

  @override
  String get conflictNothingSynced => 'काहीही सिंक झाले नाही';

  @override
  String get conflictDismissTitle => 'बिल काढून टाकायचे?';

  @override
  String get conflictDismissBody =>
      'हे बिल रांगेतून कायमचे काढले जाईल. ते सिस्टीममध्ये नोंदवले जाणार नाही.';

  @override
  String get conflictDismiss => 'काढून टाका';

  @override
  String get conflictTabConflicts => 'मतभेद';

  @override
  String conflictTabConflictsCount(int count) {
    return 'मतभेद ($count)';
  }

  @override
  String get conflictTabFailed => 'अयशस्वी';

  @override
  String conflictTabFailedCount(int count) {
    return 'अयशस्वी ($count)';
  }

  @override
  String get conflictRetryAll => 'सर्व पुन्हा पाठवा';

  @override
  String get conflictNoConflicts => 'स्टॉकचे मतभेद नाहीत — सर्व ठीक आहे.';

  @override
  String get conflictNoFailed => 'कायमची अयशस्वी बिले नाहीत.';

  @override
  String get conflictStockConflict => 'स्टॉक मतभेद';

  @override
  String conflictFailedAfterRetries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count प्रयत्नांनंतर अयशस्वी',
      one: '1 प्रयत्नानंतर अयशस्वी',
    );
    return '$_temp0';
  }

  @override
  String conflictMoreItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'आणखी $count वस्तू',
      one: 'आणखी 1 वस्तू',
    );
    return '$_temp0';
  }

  @override
  String conflictItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count वस्तू',
      one: '1 वस्तू',
    );
    return '$_temp0';
  }

  @override
  String get conflictUnknownError => 'अज्ञात त्रुटी';

  @override
  String get conflictJustNow => 'आत्ताच';

  @override
  String conflictMinutesAgo(int minutes) {
    return '$minutes मिनिटांपूर्वी';
  }

  @override
  String conflictHoursAgo(int hours) {
    return '$hours तासांपूर्वी';
  }

  @override
  String get updateForceNote =>
      'हे अपडेट आवश्यक आहे. पुढे जाण्यासाठी कृपया अपडेट करा.';

  @override
  String get splashTagline => 'भारतीय व्यवसायांसाठी स्मार्ट बिलिंग';

  @override
  String get noInternetTitle => 'इंटरनेट कनेक्शन नाही';

  @override
  String get noInternetBody =>
      'सुरू करण्यासाठी नेटवर्कला जोडा.\nतुमची माहिती आपोआप लोड होईल.';

  @override
  String get errorSomethingWentWrong => 'काहीतरी चूक झाली';

  @override
  String get itemsTabItems => 'वस्तू';

  @override
  String get itemsTabRawMaterials => 'कच्चा माल';

  @override
  String get itemsAddRawMaterial => 'कच्चा माल जोडा';

  @override
  String get itemsEditRawMaterial => 'कच्चा माल बदला';

  @override
  String get itemsRawMaterialsEmpty =>
      'अजून कच्चा माल नाही.\nसाठा तपासण्यासाठी प्रथम घटक जोडा.';

  @override
  String get itemsRawMaterialDeleteTitle => 'कच्चा माल हटवायचा?';

  @override
  String itemsRawMaterialDeleteBody(String name) {
    return '\"$name\" हटवायचे? हे पूर्ववत करता येणार नाही.';
  }

  @override
  String get itemsLowStockThreshold => 'कमी साठा इशारा यावर';

  @override
  String get itemsManageRecipe => 'पाककृती व्यवस्थापित करा (कच्चा माल)';

  @override
  String itemsRecipeTitle(String name) {
    return 'पाककृती · $name';
  }

  @override
  String get itemsRecipeHint =>
      'प्रत्येक विक्रीमागे हा पदार्थ किती कच्चा माल वापरतो ते स्थापित करा. वगळण्यासाठी रिकामे ठेवा.';

  @override
  String get itemsRecipeNoMaterials =>
      'आधी कच्चा माल जोडा, नंतर पाककृती पाककृती सेट करा.';
}
