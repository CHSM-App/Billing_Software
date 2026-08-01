// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Vittam';

  @override
  String get languageName => 'English';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonOk => 'OK';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNext => 'Next';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSaving => 'Saving…';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonRequired => 'Required';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonManage => 'Manage';

  @override
  String get commonPrint => 'Print';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonEnterValidNumber => 'Enter a valid number';

  @override
  String commonErrorWithMessage(String message) {
    return 'Error: $message';
  }

  @override
  String get navBilling => 'Billing';

  @override
  String get navItems => 'Items';

  @override
  String get navTables => 'Tables';

  @override
  String get navHistory => 'History';

  @override
  String get navReports => 'Reports';

  @override
  String get navExpenses => 'Expenses';

  @override
  String get navKitchen => 'Kitchen';

  @override
  String get navOpenOrders => 'Open Orders';

  @override
  String get navSettings => 'Settings';

  @override
  String get navProfile => 'Profile';

  @override
  String get openOrdersTitle => 'Open Orders';

  @override
  String get openOrdersEmpty =>
      'No open orders. Saved drafts without a table appear here.';

  @override
  String openOrdersBillNumber(String number) {
    return 'Bill #$number';
  }

  @override
  String openOrdersItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get kitchenTitle => 'Kitchen';

  @override
  String get kitchenNoOrders => 'No orders in the kitchen right now.';

  @override
  String get kitchenReady => 'READY';

  @override
  String kitchenTable(String number) {
    return 'Table $number';
  }

  @override
  String get kitchenJustNow => 'Just now';

  @override
  String kitchenMinAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String get settingsTitle => 'Profile';

  @override
  String get settingsSectionActivity => 'ACTIVITY';

  @override
  String get settingsSectionReports => 'REPORTS';

  @override
  String get settingsHistory => 'History';

  @override
  String get settingsHistorySubtitle => 'View past bills and transactions';

  @override
  String get settingsReports => 'Reports';

  @override
  String get settingsReportsSubtitle => 'Sales insights and summaries';

  @override
  String get settingsExpenses => 'Expenses';

  @override
  String get settingsExpensesSubtitle => 'Track and manage expenses';

  @override
  String get settingsSectionBusiness => 'BUSINESS';

  @override
  String get settingsSectionTeam => 'TEAM';

  @override
  String get settingsSectionSync => 'SYNC';

  @override
  String get settingsSectionHardware => 'HARDWARE';

  @override
  String get settingsSectionPreferences => 'PREFERENCES';

  @override
  String get settingsBusinessProfile => 'Business Profile';

  @override
  String get settingsBusinessProfileSubtitle =>
      'Name, address, GST, billing settings';

  @override
  String get settingsSelfOrder => 'Customer QR Ordering';

  @override
  String get settingsSelfOrderSubtitle =>
      'Let customers scan a table QR to view the menu and order';

  @override
  String get settingsManageStaff => 'Manage Staff';

  @override
  String get settingsManageStaffSubtitle => 'Add, edit or remove cashiers';

  @override
  String get settingsPrinterSetup => 'Printer Setup';

  @override
  String get settingsPrinterSetupSubtitle => 'Configure your thermal printer';

  @override
  String get settingsSectionAbout => 'ABOUT & SUPPORT';

  @override
  String get settingsHelpCenter => 'Help Center';

  @override
  String get settingsHelpCenterSubtitle => 'Guides, FAQs and support';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsPrivacyPolicySubtitle => 'How we handle your data';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSubtitle => 'Choose your app language';

  @override
  String get settingsUnsyncedBills => 'Unsynced Bills';

  @override
  String settingsBillsNeedAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bills need attention',
      one: '1 bill needs attention',
    );
    return '$_temp0';
  }

  @override
  String get settingsAllBillsSynced => 'All bills synced';

  @override
  String settingsAppVersion(String version) {
    return 'Vittam Billing v$version';
  }

  @override
  String get languagePickerTitle => 'Choose language';

  @override
  String get languagePickerSubtitle =>
      'You can change this anytime in Settings.';

  @override
  String get logout => 'Logout';

  @override
  String get logoutConfirmTitle => 'Logout?';

  @override
  String get logoutConfirmBody =>
      'Are you sure you want to logout from your account?';

  @override
  String get businessTypeRetail => 'Retail Shop';

  @override
  String get businessTypeRestaurantTables => 'Restaurant (with tables)';

  @override
  String get businessTypeRestaurantTakeaway => 'Restaurant (takeaway)';

  @override
  String get appTagline => 'Smart Billing Solution';

  @override
  String get loginTitle => 'Welcome back';

  @override
  String get loginSubtitle => 'Sign in to your billing account';

  @override
  String get loginPhone => 'Phone number';

  @override
  String get loginPhoneHint => '10-digit mobile number';

  @override
  String get loginPhoneRequired => 'Phone is required';

  @override
  String get loginPhoneInvalid => 'Enter a valid 10-digit number';

  @override
  String get loginPin => 'PIN';

  @override
  String get loginPinHint => '4-digit PIN';

  @override
  String get loginPinRequired => 'PIN is required';

  @override
  String get loginPinInvalid => 'PIN must be 4 digits';

  @override
  String get loginSignIn => 'Sign In';

  @override
  String get loginForgotPin => 'Forgot PIN?';

  @override
  String get loginNoAccount => 'Don\'t have an account? ';

  @override
  String get loginRegister => 'Register';

  @override
  String get loginNoAccountFound => 'No account found with this phone number.';

  @override
  String get loginIncorrectPin => 'Incorrect PIN. Please try again.';

  @override
  String get loginAccountLocked =>
      'Account temporarily locked. Try again in 15 minutes.';

  @override
  String get loginGenericError => 'Something went wrong. Please try again.';

  @override
  String get loginConnectionError =>
      'Could not connect to server. Check your internet connection.';

  @override
  String get loginPendingTitle => 'Account not activated';

  @override
  String get loginPendingBody =>
      'Your account is pending activation. Please contact our support team to activate your account.';

  @override
  String get loginSupportEmail => 'support@vengurlatech.com';

  @override
  String get forgotPinTitle => 'Forgot PIN';

  @override
  String get forgotPinPhoneLabel => 'Registered phone number';

  @override
  String get forgotPinPhoneHint => '10-digit number';

  @override
  String get forgotPinPhoneInvalid => 'Enter 10-digit number';

  @override
  String get forgotPinSendOtp => 'Send OTP';

  @override
  String get forgotPinSendFailed => 'Failed to send OTP. Try again.';

  @override
  String get forgotPinSetNewTitle => 'Set New PIN';

  @override
  String get forgotPinNewLabel => 'New PIN';

  @override
  String get forgotPinConfirmLabel => 'Confirm PIN';

  @override
  String get forgotPinConfirmHint => 'Re-enter PIN';

  @override
  String get forgotPinMismatch => 'PINs do not match';

  @override
  String get forgotPinReset => 'Reset PIN';

  @override
  String get forgotPinResetSuccess => 'PIN reset successfully. Please log in.';

  @override
  String get forgotPinResetFailed => 'Reset failed. Try again.';

  @override
  String get otpTitle => 'Verify your number';

  @override
  String otpSubtitle(String phone) {
    return 'We sent a code to $phone';
  }

  @override
  String get otpEnterCode => 'Enter OTP';

  @override
  String get otpVerify => 'Verify';

  @override
  String get otpResend => 'Resend OTP';

  @override
  String otpResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get otpInvalid => 'Invalid OTP. Please try again.';

  @override
  String get otpAppBarVerifyIdentity => 'Verify Identity';

  @override
  String get otpAppBarVerifyPhone => 'Verify Phone';

  @override
  String otpSentTo(String phone) {
    return 'We sent a 6-digit OTP to\n+91 $phone via WhatsApp';
  }

  @override
  String get otpEnterAllDigits => 'Please enter all 6 digits';

  @override
  String get otpVerifyButton => 'Verify OTP';

  @override
  String get otpVerifyFailed => 'Verification failed. Check your connection.';

  @override
  String get otpResendSuccess => 'OTP resent successfully';

  @override
  String get otpResendFailed => 'Failed to resend OTP. Try again.';

  @override
  String otpResendCooldown(int seconds) {
    return 'Resend OTP in ${seconds}s';
  }

  @override
  String get registerTitle => 'Create your account';

  @override
  String get registerSubtitle => 'Set up your business in a minute';

  @override
  String get registerOwnerName => 'Your name';

  @override
  String get registerBusinessName => 'Business name';

  @override
  String get registerBusinessType => 'Business type';

  @override
  String get registerPhone => 'Phone number';

  @override
  String get registerInventory => 'Track inventory / stock';

  @override
  String get registerBarcodeScanner => 'I have a barcode scanner';

  @override
  String get registerSubmit => 'Create account';

  @override
  String get registerHaveAccount => 'Already have an account?';

  @override
  String get registerLoginNow => 'Login';

  @override
  String get registerFailed => 'Registration failed. Please try again.';

  @override
  String get registerAppBarTitle => 'Register Business';

  @override
  String get registerSectionBusinessDetails => 'Business Details';

  @override
  String get registerSectionBusinessType => 'Business Type';

  @override
  String get registerSectionOwnerDetails => 'Owner Details';

  @override
  String get registerBusinessNameHint => 'e.g. Sharma General Store';

  @override
  String get registerBusinessPhone => 'Business phone';

  @override
  String get registerBusinessPhoneHint => '10-digit number';

  @override
  String get registerAddress => 'Address (optional)';

  @override
  String get registerAddressHint => 'Shop address';

  @override
  String get registerTypeRestaurantTakeaway =>
      'Restaurant (takeaway / counter)';

  @override
  String get registerInventoryTitle => 'Enable inventory tracking';

  @override
  String get registerInventorySubtitle => 'Track stock quantities per item';

  @override
  String get registerScannerTitle => 'Has USB barcode scanner';

  @override
  String get registerScannerSubtitle => 'Auto-add items via scanner';

  @override
  String get registerOwnerNameHint => 'Full name';

  @override
  String get registerOwnerPhone => 'Your phone number';

  @override
  String get registerOwnerPhoneHint => '10-digit number (used to log in)';

  @override
  String get registerConfirmPin => 'Confirm PIN';

  @override
  String get registerCreateAccount => 'Create Account';

  @override
  String get registerOtpSendFailed =>
      'Could not send OTP. Check your internet connection.';

  @override
  String get registerSuccessTitle => 'Welcome to Vittam!';

  @override
  String get registerSuccessBody =>
      'Registration successful. Your 4-day free trial has started.\n\nLog in now to start billing.';

  @override
  String get registerBackToLogin => 'Back to Login';

  @override
  String get receiptPhonePrefix => 'Ph:';

  @override
  String get receiptBillNo => 'Bill#:';

  @override
  String get receiptTable => 'Table:';

  @override
  String get receiptDate => 'Date:';

  @override
  String get receiptCustomer => 'Cust:';

  @override
  String get receiptCustomerPhone => 'Ph:';

  @override
  String get receiptColItem => 'Item';

  @override
  String get receiptColQty => 'Qty';

  @override
  String get receiptColPrice => 'Price';

  @override
  String get receiptColTotal => 'Total';

  @override
  String get receiptSubtotal => 'Subtotal:';

  @override
  String get receiptTax => 'Tax:';

  @override
  String get receiptDiscount => 'Discount:';

  @override
  String get receiptTotal => 'TOTAL:';

  @override
  String get receiptPayment => 'Payment:';

  @override
  String get receiptThankYou => 'Thank you, visit again!';

  @override
  String get receiptDefaultBusiness => 'BUSINESS';

  @override
  String get billingTitle => 'Billing';

  @override
  String get billingSearchItems => 'Search items…';

  @override
  String get billingCartEmpty => 'Cart is empty';

  @override
  String get billingCartEmptyHint => 'Tap an item to add it to the bill';

  @override
  String get billingAddAtLeastOneItem => 'Add at least one item to the cart';

  @override
  String get billingAddAtLeastOneItemFirst => 'Add at least one item first';

  @override
  String get billingSubtotal => 'Subtotal';

  @override
  String get billingTax => 'Tax';

  @override
  String get billingDiscount => 'Discount';

  @override
  String get billingTotal => 'Total';

  @override
  String get billingCustomerName => 'Customer name (optional)';

  @override
  String get billingCustomerPhone => 'Customer phone (optional)';

  @override
  String get billingDiscountAmount => 'Discount amount';

  @override
  String get billingPaymentMode => 'Payment Mode';

  @override
  String get billingGenerateBill => 'Generate Bill';

  @override
  String get billingSaveDraft => 'Save Draft';

  @override
  String get billingClearCart => 'Clear selected items';

  @override
  String billingTableNumber(String number) {
    return 'Table $number';
  }

  @override
  String get billingReleaseTable => 'Discard Draft';

  @override
  String get billingReleaseTableTitle => 'Discard Draft?';

  @override
  String get billingReleaseTableBody =>
      'Clearing all items will discard this saved draft. This cannot be undone.';

  @override
  String get billingReleaseTableFailed => 'Failed to discard draft.';

  @override
  String get billingDraftOfflineError => 'Cannot save draft while offline';

  @override
  String get billingDraftSaved => 'Draft saved.';

  @override
  String get billingSaveFailed => 'Failed to save. Check your connection.';

  @override
  String get billingGenerateFailed =>
      'Failed to generate bill. Check your connection.';

  @override
  String billingSavedOffline(String error) {
    return 'Failed to save bill offline: $error';
  }

  @override
  String billingItemNotFoundBarcode(String barcode) {
    return 'Item not found for barcode: $barcode';
  }

  @override
  String get billingPrintSuccess => 'Bill printed successfully';

  @override
  String billingPrintFailed(String error) {
    return 'Print failed: $error';
  }

  @override
  String get billingWhatsappSent => 'Receipt link sent to WhatsApp';

  @override
  String get billingWhatsappNeedsPhone =>
      'Add the customer\'s phone number to send on WhatsApp';

  @override
  String get billingWhatsappFailed => 'Could not send WhatsApp message';

  @override
  String billingChooseSize(String name) {
    return 'Choose variant — $name';
  }

  @override
  String get billingOutOfStock => 'Out of stock';

  @override
  String get billingInsufficientStock => 'Insufficient Stock';

  @override
  String get billingInsufficientStockBody =>
      'The following items do not have enough stock:';

  @override
  String billingStockAvailable(String available) {
    return 'Available: $available';
  }

  @override
  String billingStockAvailableAsked(String available, String requested) {
    return 'Available: $available / Asked: $requested';
  }

  @override
  String get billingUnknownItem => 'Unknown';

  @override
  String billingWhatsappFailedWithError(String error) {
    return 'WhatsApp failed: $error';
  }

  @override
  String get billingCart => 'Cart';

  @override
  String billingCartWithCount(int count) {
    return 'Cart ($count)';
  }

  @override
  String get billingNoItemsFound => 'No items found';

  @override
  String get billingOrder => 'Order';

  @override
  String get billingNoItemsAddedYet => 'No items added yet';

  @override
  String get billingCustomerDetails => 'Customer details (optional)';

  @override
  String get billingCustomerNameLabel => 'Customer name';

  @override
  String get billingCustomerPhoneLabel => 'Customer phone';

  @override
  String get billingPhoneInvalid => 'Customer No. must be 10 digits.';

  @override
  String get billingDiscountPercent => 'Discount %';

  @override
  String get billingDiscountRupees => 'Discount ₹';

  @override
  String get billingTotalAmount => 'Total Amount';

  @override
  String billingSubtotalPlusGst(String subtotal, String tax) {
    return '₹$subtotal + ₹$tax GST';
  }

  @override
  String get billingDiscountApplied => 'Discount Applied';

  @override
  String get billingNetPayable => 'Net Payable';

  @override
  String get billingWhatsapp => 'WhatsApp';

  @override
  String get billingColItem => 'Item';

  @override
  String get billingColPrice => 'Price';

  @override
  String get billingColQty => 'Qty';

  @override
  String billingStalePricesFrom(String age) {
    return 'Prices from $age';
  }

  @override
  String get billingStalePrices => 'Stale prices';

  @override
  String get billingStaleVeryOld => 'Very old cache — prices may be inaccurate';

  @override
  String get billingStaleConnectToRefresh => 'Connect to refresh pricing';

  @override
  String get commonClear => 'Clear';

  @override
  String get splitSelectSecondTable => 'Select Second Table';

  @override
  String get splitNoOtherTables => 'No other available tables';

  @override
  String get paymentCash => 'Cash';

  @override
  String get paymentUpi => 'UPI';

  @override
  String get paymentCard => 'Card';

  @override
  String get paymentCredit => 'Credit';

  @override
  String get paymentOther => 'Other';

  @override
  String get itemsTitle => 'Items / Menu';

  @override
  String get menuPhotosTitle => 'Menu Photos';

  @override
  String get menuPhotosTooltip => 'Menu photos';

  @override
  String get menuPhotosSubtitle =>
      'Photos shown to customers on the QR order menu.';

  @override
  String get menuPhotosSearch => 'Search dishes…';

  @override
  String get menuPhotosEmpty =>
      'No items yet. Add items first, then add their photos here.';

  @override
  String get menuPhotosAdd => 'Add photo';

  @override
  String get menuPhotosChange => 'Change photo';

  @override
  String get menuPhotosRemove => 'Remove photo';

  @override
  String get menuPhotosPickCamera => 'Take photo';

  @override
  String get menuPhotosPickGallery => 'Choose from gallery';

  @override
  String get menuPhotosUploading => 'Uploading…';

  @override
  String get menuPhotosUploadFailed => 'Could not upload photo';

  @override
  String get menuPhotosRemoveFailed => 'Could not remove photo';

  @override
  String get menuPhotosRemoveConfirm => 'Remove this photo?';

  @override
  String get itemsSearch => 'Search items…';

  @override
  String get itemsStockOverview => 'Available Stock';

  @override
  String get itemsAddItem => 'Add Item';

  @override
  String get itemsEditItem => 'Edit Item';

  @override
  String get itemsEditItemTooltip => 'Edit item';

  @override
  String get itemsNoneYetOwner => 'No items yet. Tap + to add your first item.';

  @override
  String get itemsNoneFound => 'No items found.';

  @override
  String get itemsDeleteTitle => 'Delete item';

  @override
  String itemsDeleteBody(String name) {
    return 'Delete \"$name\"? It will no longer appear in billing.';
  }

  @override
  String get itemsFieldName => 'Name';

  @override
  String get itemsFieldCategory => 'Category';

  @override
  String get itemsFieldCategoryHint => 'e.g. Beverages';

  @override
  String get itemsFieldPrice => 'Price (₹)';

  @override
  String get itemsFieldTaxRate => 'Tax rate % (optional)';

  @override
  String get itemsFieldTaxRateHint => 'e.g. 5, 12, 18';

  @override
  String get itemsFieldBarcode => 'Barcode (optional)';

  @override
  String get itemsFieldStock => 'Stock quantity';

  @override
  String get itemsFieldUnit => 'Unit';

  @override
  String get itemsUnitPiece => 'Piece';

  @override
  String get itemsUnitKg => 'Kilogram (kg)';

  @override
  String get itemsUnitGram => 'Gram (g)';

  @override
  String get itemsUnitLitre => 'Litre (L)';

  @override
  String get itemsUnitMl => 'Millilitre (ml)';

  @override
  String get itemsUnitMetre => 'Metre (m)';

  @override
  String get itemsUnitDozen => 'Dozen';

  @override
  String get itemsUnitPlate => 'Plate';

  @override
  String get itemsManageSizes => 'Add variants';

  @override
  String itemsManageSizesCount(int count) {
    return 'Manage variants ($count)';
  }

  @override
  String itemsSizesTitle(String name) {
    return 'Variants — $name';
  }

  @override
  String get itemsSizeLabel => 'Variant label (e.g. XL, Half, 500ml)';

  @override
  String get itemsSizePrice => 'Price (blank = item price)';

  @override
  String get itemsSizeStock => 'Stock';

  @override
  String get itemsAddSize => 'Add variant';

  @override
  String get itemsNoSizesYet => 'No variants yet. Add one below.';

  @override
  String get itemsStockPerSizeHint =>
      'Stock is tracked per variant. Tap the item to update each variant\'s stock.';

  @override
  String itemsSizeDeleteConfirm(String label) {
    return 'Remove variant \"$label\"?';
  }

  @override
  String itemsStockLabel(String qty) {
    return 'Stock: $qty';
  }

  @override
  String get itemsLowStock => 'Low stock';

  @override
  String get itemsCurrentStock => 'Current stock';

  @override
  String get itemsAddQuantity => 'Add quantity';

  @override
  String get itemsTotalAfterAdding => 'Total after adding';

  @override
  String get itemsInventoryDisabled => 'Inventory tracking is disabled.';

  @override
  String get itemsBarcodePrintTitle => 'Print Barcode';

  @override
  String get itemsBarcodeGenerateTitle => 'Generate & Print Barcode';

  @override
  String get itemsBarcodeGeneratedNote =>
      'This item has no barcode. A barcode has been generated. You can edit it before printing.';

  @override
  String get itemsBarcodeValue => 'Barcode value';

  @override
  String get itemsBarcodeCopies => 'Copies';

  @override
  String get itemsBarcodeSentToPrinter => 'Barcode label sent to printer';

  @override
  String get tablesTitle => 'Tables';

  @override
  String get tablesEmpty => 'Empty';

  @override
  String get tablesOccupied => 'Occupied';

  @override
  String get tablesBilled => 'Billed';

  @override
  String get tablesNoTables => 'No tables set up yet.';

  @override
  String get tablesAddTable => 'Add Table';

  @override
  String tablesTableLabel(String number) {
    return 'Table $number';
  }

  @override
  String get tablesNoTablesYet => 'No tables yet';

  @override
  String get tablesBilledOrderBody =>
      'This table has a billed order. What would you like to do?';

  @override
  String get tablesMarkPaidEmpty => 'Mark as Paid / Empty';

  @override
  String get tablesVoidBill => 'Void Bill';

  @override
  String get tablesTableNumberLabel => 'Table number (e.g. T1, A2)';

  @override
  String get tablesDeleteTitle => 'Delete Table';

  @override
  String tablesDeleteBody(String number) {
    return 'Delete table \"$number\"?';
  }

  @override
  String get tablesShowQr => 'Show / Print QR';

  @override
  String get tablesShowQrSubtitle =>
      'Customers scan to view the menu and order';

  @override
  String get tablesQrNotReady => 'QR code is not ready for this table yet.';

  @override
  String tablesQrTitle(String number) {
    return 'Table $number — Order QR';
  }

  @override
  String get tablesQrHint =>
      'Stick this on the table. Customers scan it to see the menu and order to this table.';

  @override
  String get tablesRotateQr => 'Rotate QR';

  @override
  String get tablesRotateQrBody =>
      'This makes the old printed QR stop working. Print and place a new one after rotating. Continue?';

  @override
  String get tablesQrRotated => 'QR code rotated. Please reprint the sticker.';

  @override
  String get commonShare => 'Share';

  @override
  String get tablesPrintQr => 'Print';

  @override
  String tablesQrShareText(String number) {
    return 'Scan to order at Table $number';
  }

  @override
  String get tablesQrShareFailed => 'Could not share the QR code.';

  @override
  String get tablesQrPrinted => 'QR sent to printer.';

  @override
  String get tablesQrPrintFailed => 'Could not print the QR code.';

  @override
  String get historyTitle => 'History';

  @override
  String get historyNoBills => 'No bills yet.';

  @override
  String get historySearchHint => 'Search by bill no. or customer…';

  @override
  String historyBillNumber(String number) {
    return 'Bill #$number';
  }

  @override
  String get historyReprint => 'Reprint';

  @override
  String get historyShare => 'Share';

  @override
  String get historyPending => 'Pending';

  @override
  String get historySynced => 'Synced';

  @override
  String get historyFailed => 'Failed';

  @override
  String get historyBillHistoryTitle => 'Bill History';

  @override
  String get historySearchBillOrPhone => 'Search bill no. or phone…';

  @override
  String get historyNoBillsForPeriod => 'No bills found for this period.';

  @override
  String get historyFilterToday => 'Today';

  @override
  String get historyFilterYesterday => 'Yesterday';

  @override
  String get historyFilterThisMonth => 'This Month';

  @override
  String get historyFilterLastMonth => 'Last Month';

  @override
  String get historyFilterAll => 'All';

  @override
  String get historyFilterCustom => 'Custom';

  @override
  String get historyStatusFinalized => 'Finalized';

  @override
  String get historyStatusVoided => 'Voided';

  @override
  String get historyStatusDraft => 'Draft';

  @override
  String historyItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String historyBillMeta(String time, String payment, String items) {
    return '$time  ·  $payment  ·  $items';
  }

  @override
  String get historyVoidBill => 'Void Bill';

  @override
  String get historyVoid => 'Void';

  @override
  String historyVoidConfirmBody(String number) {
    return 'Void bill $number? This cannot be undone.';
  }

  @override
  String get historyNoPrinterConfigured =>
      'No printer configured. Set one up in Settings.';

  @override
  String get historyPayment => 'Payment';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get reportsToday => 'Today';

  @override
  String get reportsWeek => 'This Week';

  @override
  String get reportsMonth => 'This Month';

  @override
  String get reportsTotalSales => 'Total Sales';

  @override
  String get reportsBillCount => 'Bills';

  @override
  String get reportsAverageBill => 'Average Bill';

  @override
  String get reportsTopItems => 'Top Items';

  @override
  String get reportsNoData => 'No data for this period.';

  @override
  String get reportsYear => 'Year';

  @override
  String get reportsChangePeriod => 'Change period';

  @override
  String get reportsNetRevenue => 'Net Revenue';

  @override
  String get reportsExpenses => 'Expenses';

  @override
  String reportsBills(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bills',
      one: '1 bill',
    );
    return '$_temp0';
  }

  @override
  String reportsBillsWithDiscount(String bills, String discount) {
    return '$bills · −Rs. $discount disc';
  }

  @override
  String reportsCategoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count categories',
      one: '1 category',
    );
    return '$_temp0';
  }

  @override
  String get reportsNoExpenses => 'No expenses';

  @override
  String get reportsRevenueByPaymentMode => 'Revenue by Payment Mode';

  @override
  String get reportsExpensesByCategory => 'Expenses by Category';

  @override
  String get reportsDailyBreakdown => 'Daily Breakdown';

  @override
  String get expensesTitle => 'Expenses';

  @override
  String get expensesTabThisMonth => 'This Month';

  @override
  String get expensesTabRecurring => 'Recurring';

  @override
  String get expensesNoneThisMonth =>
      'No expenses this month.\nTap + to add one.';

  @override
  String get expensesAddExpense => 'Add Expense';

  @override
  String get expensesEditExpense => 'Edit Expense';

  @override
  String get expensesUpdateExpense => 'Update Expense';

  @override
  String get expensesAddRecurring => 'Add Recurring';

  @override
  String get expensesAddRecurringExpense => 'Add Recurring Expense';

  @override
  String get expensesEditRecurringExpense => 'Edit Recurring Expense';

  @override
  String get expensesSaveRecurring => 'Save Recurring Expense';

  @override
  String get expensesRecurringNote => 'These appear every month as a reminder.';

  @override
  String get expensesMonthly => 'Monthly';

  @override
  String get expensesAddAllToMonth => 'Add All to This Month';

  @override
  String get expensesCategory => 'Category';

  @override
  String get expensesCustomCategory => 'Custom Category';

  @override
  String get expensesCustomCategoryHint => 'e.g. Insurance';

  @override
  String get expensesAmount => 'Amount (Rs.)';

  @override
  String get expensesAmountRequired => 'Amount is required';

  @override
  String get expensesAmountInvalid => 'Enter a valid amount';

  @override
  String get expensesDescription => 'Description (optional)';

  @override
  String get expensesDetailsTitle => 'Expense Details';

  @override
  String get expensesPaymentMode => 'Payment Mode';

  @override
  String get expensesExpenseDate => 'Date';

  @override
  String get expensesAddedBy => 'Added By';

  @override
  String get expensesDeleteTitle => 'Delete Expense?';

  @override
  String expensesDeleteBody(String category, String amount) {
    return 'Delete $category of Rs. $amount?';
  }

  @override
  String get expensesRemoveRecurringTitle => 'Remove Recurring Expense?';

  @override
  String expensesRemoveRecurringBody(String category) {
    return 'Remove \"$category\" from recurring list? This won\'t delete past entries.';
  }

  @override
  String get expensesNoRecurringYet =>
      'No recurring expenses yet.\nAdd expenses that repeat every month\n(e.g. Rent, Salary).';

  @override
  String get expensesCustomChip => '+ Custom';

  @override
  String expensesPendingRecurring(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recurring expenses not yet added this month',
      one: '1 recurring expense not yet added this month',
    );
    return '$_temp0';
  }

  @override
  String expensesRecurringAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recurring expenses added',
      one: '1 recurring expense added',
    );
    return '$_temp0';
  }

  @override
  String get expensesCatRent => 'Rent';

  @override
  String get expensesCatSalary => 'Salary';

  @override
  String get expensesCatUtilities => 'Utilities';

  @override
  String get expensesCatStockPurchase => 'Stock Purchase';

  @override
  String get expensesCatTransport => 'Transport';

  @override
  String get expensesCatMarketing => 'Marketing';

  @override
  String get expensesCatMaintenance => 'Maintenance';

  @override
  String get expensesCatTaxes => 'Taxes';

  @override
  String get expensesCatOther => 'Other';

  @override
  String get staffTitle => 'Manage Staff';

  @override
  String get staffAddStaff => 'Add Staff';

  @override
  String get staffEditStaff => 'Edit Staff';

  @override
  String get staffNone => 'No staff added yet.';

  @override
  String get staffName => 'Name';

  @override
  String get staffPhone => 'Phone number';

  @override
  String get staffRole => 'Role';

  @override
  String get staffRoleOwner => 'Owner';

  @override
  String get staffRoleCashier => 'Cashier';

  @override
  String get staffRoleWaiter => 'Waiter';

  @override
  String get staffRoleServer => 'Server';

  @override
  String get staffRoleKitchen => 'Kitchen Chef';

  @override
  String get staffAddKitchen => 'Add Kitchen Chef';

  @override
  String get staffSectionWaiters => 'WAITERS & CASHIERS';

  @override
  String get staffSectionKitchen => 'KITCHEN';

  @override
  String get staffDeleteTitle => 'Remove staff?';

  @override
  String staffDeleteBody(String name) {
    return 'Remove \"$name\" from your team?';
  }

  @override
  String get staffRemoveTitle => 'Remove Staff';

  @override
  String staffRemoveBody(String name) {
    return 'Remove \"$name\"?';
  }

  @override
  String staffLoadFailed(String error) {
    return 'Failed to load staff: $error';
  }

  @override
  String get staffNoCashiers => 'No cashiers added yet.';

  @override
  String get staffSearchHint => 'Search staff by name or phone…';

  @override
  String get staffNoMatch => 'No staff match your search.';

  @override
  String get staffPhoneInvalid => '10-digit number required';

  @override
  String get staffPinNew => 'New PIN (leave blank to keep)';

  @override
  String get staffPinNewLabel => 'PIN (4 digits)';

  @override
  String get staffPinInvalid => 'PIN must be 4 digits';

  @override
  String get businessProfileTitle => 'Business Profile';

  @override
  String get businessProfileName => 'Business name';

  @override
  String get businessProfileAddress => 'Address';

  @override
  String get businessProfilePhone => 'Phone';

  @override
  String get businessProfileGst => 'GSTIN (optional)';

  @override
  String get businessProfileFooter => 'Receipt footer note';

  @override
  String get businessProfileSaved => 'Business profile updated';

  @override
  String get businessProfileSaveFailed =>
      'Could not save. Check your connection.';

  @override
  String get businessProfileSaveButton => 'Save Profile';

  @override
  String get businessProfileNoChanges => 'No changes to save';

  @override
  String get businessProfileUpdated => 'Profile updated successfully';

  @override
  String get businessProfileSectionAccount => 'ACCOUNT';

  @override
  String get businessProfileOwnerName => 'Name';

  @override
  String get businessProfileOwnerPhone => 'Phone';

  @override
  String get businessProfileSectionBasic => 'BASIC INFO';

  @override
  String get businessProfileSectionAddress => 'ADDRESS';

  @override
  String get businessProfileSectionTax => 'TAX INFO';

  @override
  String get businessProfileSectionBilling => 'BILLING';

  @override
  String get businessProfileNameLabel => 'Business Name';

  @override
  String get businessProfileNameHint => 'e.g. Kamble Provisions';

  @override
  String get businessProfilePhoneHint => '10-digit mobile number';

  @override
  String get businessProfilePhoneInvalid => 'Must be 10 digits';

  @override
  String get businessProfileEmail => 'Email (optional)';

  @override
  String get businessProfileEmailHint => 'owner@example.com';

  @override
  String get businessProfileEmailInvalid => 'Invalid email address';

  @override
  String get businessProfileWebsite => 'Website (optional)';

  @override
  String get businessProfileWebsiteHint => 'https://example.com';

  @override
  String get businessProfileType => 'Business Type';

  @override
  String get businessProfileStreet => 'Street Address';

  @override
  String get businessProfileStreetHint => 'Shop No. 5, Market Road';

  @override
  String get businessProfileCity => 'City';

  @override
  String get businessProfileCityHint => 'Vengurla';

  @override
  String get businessProfileState => 'State';

  @override
  String get businessProfileStateHint => 'Maharashtra';

  @override
  String get businessProfilePincode => 'Pincode';

  @override
  String get businessProfilePincodeHint => '416523';

  @override
  String get businessProfilePincodeInvalid => '6-digit pincode';

  @override
  String get businessProfileGstHint => '27ABCDE1234F1Z5';

  @override
  String get businessProfileGstInvalid => 'Invalid GSTIN format';

  @override
  String get businessProfilePan => 'PAN (optional)';

  @override
  String get businessProfilePanHint => 'ABCDE1234F';

  @override
  String get businessProfilePanInvalid => 'Invalid PAN format';

  @override
  String get businessProfileBillPrefix => 'Bill Number Prefix';

  @override
  String get businessProfileBillPrefixHelper =>
      'Bills will be numbered INV-0001, INV-0002, …';

  @override
  String get businessProfileBillPrefixInvalid =>
      'Letters, numbers, hyphens, slashes only';

  @override
  String get businessProfileFooterNote => 'Bill Footer Note (optional)';

  @override
  String get businessProfileFooterNoteHint => 'Thank you for shopping with us!';

  @override
  String get printerSetupTitle => 'Printer Setup';

  @override
  String get printerSetupScan => 'Scan for printers';

  @override
  String get printerSetupScanning => 'Scanning…';

  @override
  String get printerSetupNoPrinters =>
      'No printers found. Make sure your printer is on and paired.';

  @override
  String get printerSetupConnected => 'Connected';

  @override
  String get printerSetupConnect => 'Connect';

  @override
  String get printerSetupDisconnect => 'Disconnect';

  @override
  String get printerSetupTestPrint => 'Test print';

  @override
  String get printerSetupNotConfigured => 'No printer configured';

  @override
  String get conflictTitle => 'Unsynced Bills';

  @override
  String get conflictNone => 'Nothing needs your attention.';

  @override
  String get conflictKeepMine => 'Keep mine';

  @override
  String get conflictKeepServer => 'Keep server copy';

  @override
  String get conflictResolved => 'Conflict resolved';

  @override
  String get licenseBlockedTitle => 'Subscription required';

  @override
  String get licenseBlockedOffline =>
      'Please go online to verify your subscription.';

  @override
  String get licenseBlockedSubscription =>
      'Your subscription has expired. Renew to continue billing.';

  @override
  String get licenseBlockedPending => 'Your account is pending activation.';

  @override
  String get licenseContactSupport => 'Contact support';

  @override
  String get licenseCheckAgain => 'Check again';

  @override
  String get licenseGraceLastDay =>
      'Last day! Go online today to keep using the app.';

  @override
  String licenseGraceDaysLeft(int days) {
    return '$days days left — go online soon to verify your subscription.';
  }

  @override
  String get updateTitle => 'Update available';

  @override
  String get updateBody => 'A new version of Vittam is available.';

  @override
  String get updateNow => 'Update now';

  @override
  String get updateLater => 'Later';

  @override
  String get offlineBanner =>
      'You are offline. Bills will sync when you reconnect.';

  @override
  String get licenseTitleOffline => 'Go Online to Continue';

  @override
  String get licenseTitlePending => 'Account Pending Activation';

  @override
  String get licenseTitleExpired => 'Subscription Expired';

  @override
  String get licenseSubtitleOffline =>
      'You\'ve been offline too long.\nConnect to the internet to verify your subscription.';

  @override
  String get licenseSubtitlePending =>
      'Your account is under review.\nContact support to activate your subscription.';

  @override
  String get licenseSubtitleExpired =>
      'Your subscription has expired or been suspended.\nContact support to renew.';

  @override
  String get licenseChecking => 'Checking…';

  @override
  String get licenseConnectFailed =>
      'Could not connect. Check your internet and try again.';

  @override
  String get licenseMsgSubscription =>
      'Your subscription has expired or been suspended. Please contact support.';

  @override
  String get licenseMsgPending =>
      'Your account is pending activation. Please contact support.';

  @override
  String get licenseMsgStillOffline =>
      'Still offline. Connect to the internet and try again.';

  @override
  String get licenseMsgVerifyFailed =>
      'Could not verify subscription. Please try again.';

  @override
  String get licenseBrandFooter => 'Vittam Billing';

  @override
  String get printerSetupPermissionDenied =>
      'Bluetooth permission denied. Grant it in app settings.';

  @override
  String get printerSetupNoPaired =>
      'No paired printers found. Pair your printer in phone Bluetooth settings first.';

  @override
  String printerSetupLoadFailed(String error) {
    return 'Failed to load printers: $error';
  }

  @override
  String printerSetupSelectedSnack(String name) {
    return 'Printer \"$name\" selected';
  }

  @override
  String get printerSetupCleared => 'Printer cleared';

  @override
  String get printerSetupTestSent => 'Test page sent!';

  @override
  String printerSetupPrintFailed(String error) {
    return 'Print failed: $error';
  }

  @override
  String get printerSetupActivePrinter => 'Active Printer';

  @override
  String get printerSetupUnknown => 'Unknown';

  @override
  String get printerSetupActiveBadge => 'Active';

  @override
  String get printerSetupAvailablePrinters => 'Available Printers';

  @override
  String get printerSetupScanButton => 'Scan for Printers';

  @override
  String get printerSetupScanHint =>
      'Shows printers already paired in your phone\'s Bluetooth settings. Pair the printer there first, then tap Scan.';

  @override
  String get printerSetupTapScan => 'Tap \"Scan\" to find printers';

  @override
  String get printerSetupUnknownPrinter => 'Unknown Printer';

  @override
  String get printerSetupSelectedBadge => 'Selected';

  @override
  String get printerSetupSelect => 'Select';

  @override
  String get printerSetupNotes => 'Notes';

  @override
  String get printerSetupNoteBluetooth =>
      'Android/iPhone: pair the printer in phone Bluetooth settings first, then tap Scan here';

  @override
  String get printerSetupNoteWindows =>
      'Windows: uses BLE or USB — printer must be powered on during scan';

  @override
  String get printerSetupNoteUsb =>
      'USB on Windows requires WinUSB driver installed for the printer';

  @override
  String get printerSetupNoteThermal =>
      'Only 80mm thermal printers are supported';

  @override
  String get conflictQueuedForRetry => 'Bill queued for retry';

  @override
  String get conflictDismissed => 'Bill dismissed';

  @override
  String conflictSyncedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bills synced',
      one: '1 bill synced',
    );
    return '$_temp0';
  }

  @override
  String conflictRemainCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conflicts remain',
      one: '1 conflict remains',
    );
    return '$_temp0';
  }

  @override
  String get conflictNothingSynced => 'Nothing synced';

  @override
  String get conflictDismissTitle => 'Dismiss bill?';

  @override
  String get conflictDismissBody =>
      'This bill will be permanently removed from the queue. It will not be recorded in the system.';

  @override
  String get conflictDismiss => 'Dismiss';

  @override
  String get conflictTabConflicts => 'Conflicts';

  @override
  String conflictTabConflictsCount(int count) {
    return 'Conflicts ($count)';
  }

  @override
  String get conflictTabFailed => 'Failed';

  @override
  String conflictTabFailedCount(int count) {
    return 'Failed ($count)';
  }

  @override
  String get conflictRetryAll => 'Retry All';

  @override
  String get conflictNoConflicts => 'No stock conflicts — all clear.';

  @override
  String get conflictNoFailed => 'No permanently failed bills.';

  @override
  String get conflictStockConflict => 'Stock conflict';

  @override
  String conflictFailedAfterRetries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Failed after $count retries',
      one: 'Failed after 1 retry',
    );
    return '$_temp0';
  }

  @override
  String conflictMoreItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count more items',
      one: '+1 more item',
    );
    return '$_temp0';
  }

  @override
  String conflictItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get conflictUnknownError => 'Unknown error';

  @override
  String get conflictJustNow => 'Just now';

  @override
  String conflictMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String conflictHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String get updateForceNote =>
      'This update is required. Please update to continue.';

  @override
  String get splashTagline => 'Smart Billing for Indian Businesses';

  @override
  String get noInternetTitle => 'No Internet Connection';

  @override
  String get noInternetBody =>
      'Connect to the network to get started.\nYour data will load automatically.';

  @override
  String get errorSomethingWentWrong => 'Something went wrong';

  @override
  String get itemsTabItems => 'Items';

  @override
  String get itemsTabRawMaterials => 'Raw Materials';

  @override
  String get itemsAddRawMaterial => 'Add raw material';

  @override
  String get itemsEditRawMaterial => 'Edit raw material';

  @override
  String get itemsRawMaterialsEmpty =>
      'No raw materials yet.\nAdd ingredients to track their stock.';

  @override
  String get itemsRawMaterialDeleteTitle => 'Delete raw material?';

  @override
  String itemsRawMaterialDeleteBody(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String get itemsLowStockThreshold => 'Low-stock alert at';

  @override
  String get itemsManageRecipe => 'Manage recipe (raw materials)';

  @override
  String itemsRecipeTitle(String name) {
    return 'Recipe · $name';
  }

  @override
  String get itemsRecipeHint =>
      'Set how much of each raw material this dish uses per unit sold. Leave blank to skip.';

  @override
  String get itemsRecipeNoMaterials =>
      'Add raw materials first, then set the recipe.';
}
