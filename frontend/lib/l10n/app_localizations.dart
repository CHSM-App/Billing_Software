import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_mr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('mr')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Vittam'**
  String get appName;

  /// No description provided for @languageName.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageName;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get commonSaving;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @commonRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get commonRequired;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get commonManage;

  /// No description provided for @commonPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get commonPrint;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonEnterValidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get commonEnterValidNumber;

  /// No description provided for @commonErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String commonErrorWithMessage(String message);

  /// No description provided for @navBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get navBilling;

  /// No description provided for @navItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get navItems;

  /// No description provided for @navTables.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get navTables;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get navExpenses;

  /// No description provided for @navKitchen.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get navKitchen;

  /// No description provided for @navOpenOrders.
  ///
  /// In en, this message translates to:
  /// **'Open Orders'**
  String get navOpenOrders;

  /// No description provided for @navOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get navOrders;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @ordersTabTables.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get ordersTabTables;

  /// No description provided for @ordersTabOpenOrders.
  ///
  /// In en, this message translates to:
  /// **'Open Orders'**
  String get ordersTabOpenOrders;

  /// No description provided for @ordersTabCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get ordersTabCredit;

  /// No description provided for @billingCreditCustomerRequired.
  ///
  /// In en, this message translates to:
  /// **'Customer name and phone are required for a credit bill.'**
  String get billingCreditCustomerRequired;

  /// No description provided for @billingPrevCreditDue.
  ///
  /// In en, this message translates to:
  /// **'Previous credit due: ₹{amount} ({count} bill(s))'**
  String billingPrevCreditDue(String amount, int count);

  /// No description provided for @billingClearPrevCredit.
  ///
  /// In en, this message translates to:
  /// **'Clear previous credit with this bill'**
  String get billingClearPrevCredit;

  /// No description provided for @billingPreviousDue.
  ///
  /// In en, this message translates to:
  /// **'Previous Due'**
  String get billingPreviousDue;

  /// No description provided for @creditTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get creditTitle;

  /// No description provided for @creditEmpty.
  ///
  /// In en, this message translates to:
  /// **'No credit due. Customers who owe money appear here.'**
  String get creditEmpty;

  /// No description provided for @creditOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get creditOutstanding;

  /// No description provided for @creditUnpaidBills.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unpaid bill} other{{count} unpaid bills}}'**
  String creditUnpaidBills(int count);

  /// No description provided for @creditNoPhone.
  ///
  /// In en, this message translates to:
  /// **'No phone'**
  String get creditNoPhone;

  /// No description provided for @creditCustomerBillsTitle.
  ///
  /// In en, this message translates to:
  /// **'Unpaid bills'**
  String get creditCustomerBillsTitle;

  /// No description provided for @creditSelectedTotal.
  ///
  /// In en, this message translates to:
  /// **'Selected: ₹{amount}'**
  String creditSelectedTotal(String amount);

  /// No description provided for @creditMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark paid'**
  String get creditMarkPaid;

  /// No description provided for @creditSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get creditSelectAll;

  /// No description provided for @creditPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get creditPrint;

  /// No description provided for @creditSendWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get creditSendWhatsapp;

  /// No description provided for @creditChoosePaymentMode.
  ///
  /// In en, this message translates to:
  /// **'How was it paid?'**
  String get creditChoosePaymentMode;

  /// No description provided for @creditSettleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Settle {count} bill(s) as paid?'**
  String creditSettleConfirm(int count);

  /// No description provided for @creditSettledSuccess.
  ///
  /// In en, this message translates to:
  /// **'Marked as paid.'**
  String get creditSettledSuccess;

  /// No description provided for @creditSettleFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not settle. Please try again.'**
  String get creditSettleFailed;

  /// No description provided for @creditSelectAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Select at least one bill.'**
  String get creditSelectAtLeastOne;

  /// No description provided for @openOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Orders'**
  String get openOrdersTitle;

  /// No description provided for @openOrdersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No open orders. Saved drafts without a table appear here.'**
  String get openOrdersEmpty;

  /// No description provided for @openOrdersBillNumber.
  ///
  /// In en, this message translates to:
  /// **'Bill #{number}'**
  String openOrdersBillNumber(String number);

  /// No description provided for @openOrdersItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String openOrdersItemCount(int count);

  /// No description provided for @kitchenTitle.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get kitchenTitle;

  /// No description provided for @kitchenNoOrders.
  ///
  /// In en, this message translates to:
  /// **'No orders in the kitchen right now.'**
  String get kitchenNoOrders;

  /// No description provided for @kitchenReady.
  ///
  /// In en, this message translates to:
  /// **'READY'**
  String get kitchenReady;

  /// No description provided for @kitchenTable.
  ///
  /// In en, this message translates to:
  /// **'Table {number}'**
  String kitchenTable(String number);

  /// No description provided for @kitchenJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get kitchenJustNow;

  /// No description provided for @kitchenMinAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String kitchenMinAgo(int minutes);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settingsTitle;

  /// No description provided for @settingsSectionActivity.
  ///
  /// In en, this message translates to:
  /// **'ACTIVITY'**
  String get settingsSectionActivity;

  /// No description provided for @settingsSectionReports.
  ///
  /// In en, this message translates to:
  /// **'REPORTS'**
  String get settingsSectionReports;

  /// No description provided for @settingsHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get settingsHistory;

  /// No description provided for @settingsHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'View past bills and transactions'**
  String get settingsHistorySubtitle;

  /// No description provided for @settingsReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get settingsReports;

  /// No description provided for @settingsReportsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sales insights and summaries'**
  String get settingsReportsSubtitle;

  /// No description provided for @settingsExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get settingsExpenses;

  /// No description provided for @settingsExpensesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track and manage expenses'**
  String get settingsExpensesSubtitle;

  /// No description provided for @settingsSectionBusiness.
  ///
  /// In en, this message translates to:
  /// **'BUSINESS'**
  String get settingsSectionBusiness;

  /// No description provided for @settingsSectionTeam.
  ///
  /// In en, this message translates to:
  /// **'TEAM'**
  String get settingsSectionTeam;

  /// No description provided for @settingsSectionSync.
  ///
  /// In en, this message translates to:
  /// **'SYNC'**
  String get settingsSectionSync;

  /// No description provided for @settingsSectionHardware.
  ///
  /// In en, this message translates to:
  /// **'HARDWARE'**
  String get settingsSectionHardware;

  /// No description provided for @settingsSectionPreferences.
  ///
  /// In en, this message translates to:
  /// **'PREFERENCES'**
  String get settingsSectionPreferences;

  /// No description provided for @settingsBusinessProfile.
  ///
  /// In en, this message translates to:
  /// **'Business Profile'**
  String get settingsBusinessProfile;

  /// No description provided for @settingsBusinessProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name, address, GST, billing settings'**
  String get settingsBusinessProfileSubtitle;

  /// No description provided for @settingsSelfOrder.
  ///
  /// In en, this message translates to:
  /// **'Customer QR Ordering'**
  String get settingsSelfOrder;

  /// No description provided for @settingsSelfOrderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Let customers scan a table QR to view the menu and order'**
  String get settingsSelfOrderSubtitle;

  /// No description provided for @settingsInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory Tracking'**
  String get settingsInventory;

  /// No description provided for @settingsInventorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track stock and reduce it automatically on each sale'**
  String get settingsInventorySubtitle;

  /// No description provided for @settingsGst.
  ///
  /// In en, this message translates to:
  /// **'GST Invoices'**
  String get settingsGst;

  /// No description provided for @settingsGstSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add tax rate & HSN/SAC to items and show CGST/SGST on bills'**
  String get settingsGstSubtitle;

  /// No description provided for @settingsManageStaff.
  ///
  /// In en, this message translates to:
  /// **'Manage Staff'**
  String get settingsManageStaff;

  /// No description provided for @settingsManageStaffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add, edit or remove cashiers'**
  String get settingsManageStaffSubtitle;

  /// No description provided for @settingsPrinterSetup.
  ///
  /// In en, this message translates to:
  /// **'Printer Setup'**
  String get settingsPrinterSetup;

  /// No description provided for @settingsPrinterSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure your thermal printer'**
  String get settingsPrinterSetupSubtitle;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'ABOUT & SUPPORT'**
  String get settingsSectionAbout;

  /// No description provided for @settingsHelpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get settingsHelpCenter;

  /// No description provided for @settingsHelpCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Guides, FAQs and support'**
  String get settingsHelpCenterSubtitle;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsPrivacyPolicySubtitle.
  ///
  /// In en, this message translates to:
  /// **'How we handle your data'**
  String get settingsPrivacyPolicySubtitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your app language'**
  String get settingsLanguageSubtitle;

  /// No description provided for @settingsUnsyncedBills.
  ///
  /// In en, this message translates to:
  /// **'Unsynced Bills'**
  String get settingsUnsyncedBills;

  /// No description provided for @settingsBillsNeedAttention.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 bill needs attention} other{{count} bills need attention}}'**
  String settingsBillsNeedAttention(int count);

  /// No description provided for @settingsAllBillsSynced.
  ///
  /// In en, this message translates to:
  /// **'All bills synced'**
  String get settingsAllBillsSynced;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'Vittam Billing v{version}'**
  String settingsAppVersion(String version);

  /// No description provided for @languagePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get languagePickerTitle;

  /// No description provided for @languagePickerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You can change this anytime in Settings.'**
  String get languagePickerSubtitle;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Logout?'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout from your account?'**
  String get logoutConfirmBody;

  /// No description provided for @businessTypeRetail.
  ///
  /// In en, this message translates to:
  /// **'Retail Shop'**
  String get businessTypeRetail;

  /// No description provided for @businessTypeRestaurantTables.
  ///
  /// In en, this message translates to:
  /// **'Restaurant (with tables)'**
  String get businessTypeRestaurantTables;

  /// No description provided for @businessTypeRestaurantTakeaway.
  ///
  /// In en, this message translates to:
  /// **'Restaurant (takeaway)'**
  String get businessTypeRestaurantTakeaway;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Smart Billing Solution'**
  String get appTagline;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your billing account'**
  String get loginSubtitle;

  /// No description provided for @loginPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get loginPhone;

  /// No description provided for @loginPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'10-digit mobile number'**
  String get loginPhoneHint;

  /// No description provided for @loginPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone is required'**
  String get loginPhoneRequired;

  /// No description provided for @loginPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 10-digit number'**
  String get loginPhoneInvalid;

  /// No description provided for @loginPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get loginPin;

  /// No description provided for @loginPinHint.
  ///
  /// In en, this message translates to:
  /// **'4-digit PIN'**
  String get loginPinHint;

  /// No description provided for @loginPinRequired.
  ///
  /// In en, this message translates to:
  /// **'PIN is required'**
  String get loginPinRequired;

  /// No description provided for @loginPinInvalid.
  ///
  /// In en, this message translates to:
  /// **'PIN must be 4 digits'**
  String get loginPinInvalid;

  /// No description provided for @loginSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get loginSignIn;

  /// No description provided for @loginForgotPin.
  ///
  /// In en, this message translates to:
  /// **'Forgot PIN?'**
  String get loginForgotPin;

  /// No description provided for @loginNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get loginNoAccount;

  /// No description provided for @loginRegister.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get loginRegister;

  /// No description provided for @loginNoAccountFound.
  ///
  /// In en, this message translates to:
  /// **'No account found with this phone number.'**
  String get loginNoAccountFound;

  /// No description provided for @loginIncorrectPin.
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN. Please try again.'**
  String get loginIncorrectPin;

  /// No description provided for @loginAccountLocked.
  ///
  /// In en, this message translates to:
  /// **'Account temporarily locked. Try again in 15 minutes.'**
  String get loginAccountLocked;

  /// No description provided for @loginGenericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get loginGenericError;

  /// No description provided for @loginConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to server. Check your internet connection.'**
  String get loginConnectionError;

  /// No description provided for @loginPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Account not activated'**
  String get loginPendingTitle;

  /// No description provided for @loginPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Your account is pending activation. Please contact our support team to activate your account.'**
  String get loginPendingBody;

  /// No description provided for @loginSupportEmail.
  ///
  /// In en, this message translates to:
  /// **'support@vengurlatech.com'**
  String get loginSupportEmail;

  /// No description provided for @supportPhone.
  ///
  /// In en, this message translates to:
  /// **'9422229951'**
  String get supportPhone;

  /// No description provided for @supportEmail.
  ///
  /// In en, this message translates to:
  /// **'support@vengurlatech.com'**
  String get supportEmail;

  /// No description provided for @forgotPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot PIN'**
  String get forgotPinTitle;

  /// No description provided for @forgotPinPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Registered phone number'**
  String get forgotPinPhoneLabel;

  /// No description provided for @forgotPinPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'10-digit number'**
  String get forgotPinPhoneHint;

  /// No description provided for @forgotPinPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter 10-digit number'**
  String get forgotPinPhoneInvalid;

  /// No description provided for @forgotPinSendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get forgotPinSendOtp;

  /// No description provided for @forgotPinSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send OTP. Try again.'**
  String get forgotPinSendFailed;

  /// No description provided for @forgotPinSetNewTitle.
  ///
  /// In en, this message translates to:
  /// **'Set New PIN'**
  String get forgotPinSetNewTitle;

  /// No description provided for @forgotPinNewLabel.
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get forgotPinNewLabel;

  /// No description provided for @forgotPinConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get forgotPinConfirmLabel;

  /// No description provided for @forgotPinConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Re-enter PIN'**
  String get forgotPinConfirmHint;

  /// No description provided for @forgotPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'PINs do not match'**
  String get forgotPinMismatch;

  /// No description provided for @forgotPinReset.
  ///
  /// In en, this message translates to:
  /// **'Reset PIN'**
  String get forgotPinReset;

  /// No description provided for @forgotPinResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'PIN reset successfully. Please log in.'**
  String get forgotPinResetSuccess;

  /// No description provided for @forgotPinResetFailed.
  ///
  /// In en, this message translates to:
  /// **'Reset failed. Try again.'**
  String get forgotPinResetFailed;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your number'**
  String get otpTitle;

  /// No description provided for @otpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We sent a code to {phone}'**
  String otpSubtitle(String phone);

  /// No description provided for @otpEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Enter OTP'**
  String get otpEnterCode;

  /// No description provided for @otpVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get otpVerify;

  /// No description provided for @otpResend.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP'**
  String get otpResend;

  /// No description provided for @otpResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String otpResendIn(int seconds);

  /// No description provided for @otpInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid OTP. Please try again.'**
  String get otpInvalid;

  /// No description provided for @otpAppBarVerifyIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify Identity'**
  String get otpAppBarVerifyIdentity;

  /// No description provided for @otpAppBarVerifyPhone.
  ///
  /// In en, this message translates to:
  /// **'Verify Phone'**
  String get otpAppBarVerifyPhone;

  /// No description provided for @otpSentTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit OTP to\n+91 {phone} via WhatsApp'**
  String otpSentTo(String phone);

  /// No description provided for @otpEnterAllDigits.
  ///
  /// In en, this message translates to:
  /// **'Please enter all 6 digits'**
  String get otpEnterAllDigits;

  /// No description provided for @otpVerifyButton.
  ///
  /// In en, this message translates to:
  /// **'Verify OTP'**
  String get otpVerifyButton;

  /// No description provided for @otpVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Verification failed. Check your connection.'**
  String get otpVerifyFailed;

  /// No description provided for @otpResendSuccess.
  ///
  /// In en, this message translates to:
  /// **'OTP resent successfully'**
  String get otpResendSuccess;

  /// No description provided for @otpResendFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to resend OTP. Try again.'**
  String get otpResendFailed;

  /// No description provided for @otpResendCooldown.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP in {seconds}s'**
  String otpResendCooldown(int seconds);

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get registerTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your business in a minute'**
  String get registerSubtitle;

  /// No description provided for @registerOwnerName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get registerOwnerName;

  /// No description provided for @registerBusinessName.
  ///
  /// In en, this message translates to:
  /// **'Business name'**
  String get registerBusinessName;

  /// No description provided for @registerBusinessType.
  ///
  /// In en, this message translates to:
  /// **'Business type'**
  String get registerBusinessType;

  /// No description provided for @registerPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get registerPhone;

  /// No description provided for @registerInventory.
  ///
  /// In en, this message translates to:
  /// **'Track inventory / stock'**
  String get registerInventory;

  /// No description provided for @registerBarcodeScanner.
  ///
  /// In en, this message translates to:
  /// **'I have a barcode scanner'**
  String get registerBarcodeScanner;

  /// No description provided for @registerSubmit.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerSubmit;

  /// No description provided for @registerHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get registerHaveAccount;

  /// No description provided for @registerLoginNow.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get registerLoginNow;

  /// No description provided for @registerFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed. Please try again.'**
  String get registerFailed;

  /// No description provided for @registerAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Register Business'**
  String get registerAppBarTitle;

  /// No description provided for @registerSectionBusinessDetails.
  ///
  /// In en, this message translates to:
  /// **'Business Details'**
  String get registerSectionBusinessDetails;

  /// No description provided for @registerSectionBusinessType.
  ///
  /// In en, this message translates to:
  /// **'Business Type'**
  String get registerSectionBusinessType;

  /// No description provided for @registerSectionOwnerDetails.
  ///
  /// In en, this message translates to:
  /// **'Owner Details'**
  String get registerSectionOwnerDetails;

  /// No description provided for @registerBusinessNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Sharma General Store'**
  String get registerBusinessNameHint;

  /// No description provided for @registerBusinessPhone.
  ///
  /// In en, this message translates to:
  /// **'Business phone'**
  String get registerBusinessPhone;

  /// No description provided for @registerBusinessPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'10-digit number'**
  String get registerBusinessPhoneHint;

  /// No description provided for @registerAddress.
  ///
  /// In en, this message translates to:
  /// **'Address (optional)'**
  String get registerAddress;

  /// No description provided for @registerAddressHint.
  ///
  /// In en, this message translates to:
  /// **'Shop address'**
  String get registerAddressHint;

  /// No description provided for @registerTypeRestaurantTakeaway.
  ///
  /// In en, this message translates to:
  /// **'Restaurant (takeaway / counter)'**
  String get registerTypeRestaurantTakeaway;

  /// No description provided for @registerInventoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable inventory tracking'**
  String get registerInventoryTitle;

  /// No description provided for @registerInventorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track stock quantities per item'**
  String get registerInventorySubtitle;

  /// No description provided for @registerScannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Has USB barcode scanner'**
  String get registerScannerTitle;

  /// No description provided for @registerScannerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-add items via scanner'**
  String get registerScannerSubtitle;

  /// No description provided for @registerOwnerNameHint.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get registerOwnerNameHint;

  /// No description provided for @registerOwnerPhone.
  ///
  /// In en, this message translates to:
  /// **'Your phone number'**
  String get registerOwnerPhone;

  /// No description provided for @registerOwnerPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'10-digit number (used to log in)'**
  String get registerOwnerPhoneHint;

  /// No description provided for @registerConfirmPin.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get registerConfirmPin;

  /// No description provided for @registerCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get registerCreateAccount;

  /// No description provided for @registerOtpSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send OTP. Check your internet connection.'**
  String get registerOtpSendFailed;

  /// No description provided for @registerSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Vittam!'**
  String get registerSuccessTitle;

  /// No description provided for @registerSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Registration successful. Your 4-day free trial has started.\n\nLog in now to start billing.'**
  String get registerSuccessBody;

  /// No description provided for @registerBackToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to Login'**
  String get registerBackToLogin;

  /// No description provided for @receiptPhonePrefix.
  ///
  /// In en, this message translates to:
  /// **'Ph:'**
  String get receiptPhonePrefix;

  /// No description provided for @receiptBillNo.
  ///
  /// In en, this message translates to:
  /// **'Bill#:'**
  String get receiptBillNo;

  /// No description provided for @receiptTable.
  ///
  /// In en, this message translates to:
  /// **'Table:'**
  String get receiptTable;

  /// No description provided for @receiptDate.
  ///
  /// In en, this message translates to:
  /// **'Date:'**
  String get receiptDate;

  /// No description provided for @receiptCustomer.
  ///
  /// In en, this message translates to:
  /// **'Cust:'**
  String get receiptCustomer;

  /// No description provided for @receiptCustomerPhone.
  ///
  /// In en, this message translates to:
  /// **'Ph:'**
  String get receiptCustomerPhone;

  /// No description provided for @receiptColItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get receiptColItem;

  /// No description provided for @receiptColQty.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get receiptColQty;

  /// No description provided for @receiptColPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get receiptColPrice;

  /// No description provided for @receiptColTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get receiptColTotal;

  /// No description provided for @receiptSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal:'**
  String get receiptSubtotal;

  /// No description provided for @receiptTax.
  ///
  /// In en, this message translates to:
  /// **'Tax:'**
  String get receiptTax;

  /// No description provided for @receiptCgst.
  ///
  /// In en, this message translates to:
  /// **'CGST:'**
  String get receiptCgst;

  /// No description provided for @receiptSgst.
  ///
  /// In en, this message translates to:
  /// **'SGST:'**
  String get receiptSgst;

  /// No description provided for @receiptGstin.
  ///
  /// In en, this message translates to:
  /// **'GSTIN:'**
  String get receiptGstin;

  /// No description provided for @receiptDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount:'**
  String get receiptDiscount;

  /// No description provided for @receiptTotal.
  ///
  /// In en, this message translates to:
  /// **'TOTAL:'**
  String get receiptTotal;

  /// No description provided for @receiptPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment:'**
  String get receiptPayment;

  /// No description provided for @receiptThankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you, visit again!'**
  String get receiptThankYou;

  /// No description provided for @receiptDefaultBusiness.
  ///
  /// In en, this message translates to:
  /// **'BUSINESS'**
  String get receiptDefaultBusiness;

  /// No description provided for @billingTitle.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get billingTitle;

  /// No description provided for @billingSearchItems.
  ///
  /// In en, this message translates to:
  /// **'Search items…'**
  String get billingSearchItems;

  /// No description provided for @billingCartEmpty.
  ///
  /// In en, this message translates to:
  /// **'Cart is empty'**
  String get billingCartEmpty;

  /// No description provided for @billingCartEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap an item to add it to the bill'**
  String get billingCartEmptyHint;

  /// No description provided for @billingAddAtLeastOneItem.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item to the cart'**
  String get billingAddAtLeastOneItem;

  /// No description provided for @billingAddAtLeastOneItemFirst.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item first'**
  String get billingAddAtLeastOneItemFirst;

  /// No description provided for @billingSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get billingSubtotal;

  /// No description provided for @billingTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get billingTax;

  /// No description provided for @billingDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get billingDiscount;

  /// No description provided for @billingTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get billingTotal;

  /// No description provided for @billingCustomerName.
  ///
  /// In en, this message translates to:
  /// **'Customer name (optional)'**
  String get billingCustomerName;

  /// No description provided for @billingCustomerPhone.
  ///
  /// In en, this message translates to:
  /// **'Customer phone (optional)'**
  String get billingCustomerPhone;

  /// No description provided for @billingDiscountAmount.
  ///
  /// In en, this message translates to:
  /// **'Discount amount'**
  String get billingDiscountAmount;

  /// No description provided for @billingPaymentMode.
  ///
  /// In en, this message translates to:
  /// **'Payment Mode'**
  String get billingPaymentMode;

  /// No description provided for @billingGenerateBill.
  ///
  /// In en, this message translates to:
  /// **'Generate Bill'**
  String get billingGenerateBill;

  /// No description provided for @billingSaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save Draft'**
  String get billingSaveDraft;

  /// No description provided for @billingClearCart.
  ///
  /// In en, this message translates to:
  /// **'Clear selected items'**
  String get billingClearCart;

  /// No description provided for @billingTableNumber.
  ///
  /// In en, this message translates to:
  /// **'Table {number}'**
  String billingTableNumber(String number);

  /// No description provided for @billingReleaseTable.
  ///
  /// In en, this message translates to:
  /// **'Discard Draft'**
  String get billingReleaseTable;

  /// No description provided for @billingReleaseTableTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard Draft?'**
  String get billingReleaseTableTitle;

  /// No description provided for @billingReleaseTableBody.
  ///
  /// In en, this message translates to:
  /// **'Clearing all items will discard this saved draft. This cannot be undone.'**
  String get billingReleaseTableBody;

  /// No description provided for @billingReleaseTableFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to discard draft.'**
  String get billingReleaseTableFailed;

  /// No description provided for @billingDraftOfflineError.
  ///
  /// In en, this message translates to:
  /// **'Cannot save draft while offline'**
  String get billingDraftOfflineError;

  /// No description provided for @billingDraftPendingSync.
  ///
  /// In en, this message translates to:
  /// **'This order is still saving. Reconnect to edit or finalize it.'**
  String get billingDraftPendingSync;

  /// No description provided for @billingDraftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved.'**
  String get billingDraftSaved;

  /// No description provided for @billingSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save. Check your connection.'**
  String get billingSaveFailed;

  /// No description provided for @billingGenerateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate bill. Check your connection.'**
  String get billingGenerateFailed;

  /// No description provided for @billingSavedOffline.
  ///
  /// In en, this message translates to:
  /// **'Failed to save bill offline: {error}'**
  String billingSavedOffline(String error);

  /// No description provided for @billingItemNotFoundBarcode.
  ///
  /// In en, this message translates to:
  /// **'Item not found for barcode: {barcode}'**
  String billingItemNotFoundBarcode(String barcode);

  /// No description provided for @billingPrintSuccess.
  ///
  /// In en, this message translates to:
  /// **'Bill printed successfully'**
  String get billingPrintSuccess;

  /// No description provided for @billingPrintFailed.
  ///
  /// In en, this message translates to:
  /// **'Print failed: {error}'**
  String billingPrintFailed(String error);

  /// No description provided for @billingWhatsappSent.
  ///
  /// In en, this message translates to:
  /// **'Receipt link sent to WhatsApp'**
  String get billingWhatsappSent;

  /// No description provided for @billingWhatsappNeedsPhone.
  ///
  /// In en, this message translates to:
  /// **'Add the customer\'s phone number to send on WhatsApp'**
  String get billingWhatsappNeedsPhone;

  /// No description provided for @billingWhatsappFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send WhatsApp message'**
  String get billingWhatsappFailed;

  /// No description provided for @billingChooseSize.
  ///
  /// In en, this message translates to:
  /// **'Choose variant — {name}'**
  String billingChooseSize(String name);

  /// No description provided for @billingOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get billingOutOfStock;

  /// No description provided for @billingInsufficientStock.
  ///
  /// In en, this message translates to:
  /// **'Insufficient Stock'**
  String get billingInsufficientStock;

  /// No description provided for @billingInsufficientStockBody.
  ///
  /// In en, this message translates to:
  /// **'The following items do not have enough stock:'**
  String get billingInsufficientStockBody;

  /// No description provided for @billingStockAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available: {available}'**
  String billingStockAvailable(String available);

  /// No description provided for @billingStockAvailableAsked.
  ///
  /// In en, this message translates to:
  /// **'Available: {available} / Asked: {requested}'**
  String billingStockAvailableAsked(String available, String requested);

  /// No description provided for @billingUnknownItem.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get billingUnknownItem;

  /// No description provided for @billingWhatsappFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp failed: {error}'**
  String billingWhatsappFailedWithError(String error);

  /// No description provided for @billingCart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get billingCart;

  /// No description provided for @billingCartWithCount.
  ///
  /// In en, this message translates to:
  /// **'Cart ({count})'**
  String billingCartWithCount(int count);

  /// No description provided for @billingNoItemsFound.
  ///
  /// In en, this message translates to:
  /// **'No items found'**
  String get billingNoItemsFound;

  /// No description provided for @billingOrder.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get billingOrder;

  /// No description provided for @billingNoItemsAddedYet.
  ///
  /// In en, this message translates to:
  /// **'No items added yet'**
  String get billingNoItemsAddedYet;

  /// No description provided for @billingCustomerDetails.
  ///
  /// In en, this message translates to:
  /// **'Customer details (optional)'**
  String get billingCustomerDetails;

  /// No description provided for @billingCustomerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get billingCustomerNameLabel;

  /// No description provided for @billingCustomerPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer phone'**
  String get billingCustomerPhoneLabel;

  /// No description provided for @billingPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Customer No. must be 10 digits.'**
  String get billingPhoneInvalid;

  /// No description provided for @billingDiscountPercent.
  ///
  /// In en, this message translates to:
  /// **'Discount %'**
  String get billingDiscountPercent;

  /// No description provided for @billingDiscountRupees.
  ///
  /// In en, this message translates to:
  /// **'Discount ₹'**
  String get billingDiscountRupees;

  /// No description provided for @billingTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get billingTotalAmount;

  /// No description provided for @billingSubtotalPlusGst.
  ///
  /// In en, this message translates to:
  /// **'₹{subtotal} + ₹{tax} GST'**
  String billingSubtotalPlusGst(String subtotal, String tax);

  /// No description provided for @billingCgst.
  ///
  /// In en, this message translates to:
  /// **'CGST ({rate}%)'**
  String billingCgst(String rate);

  /// No description provided for @billingSgst.
  ///
  /// In en, this message translates to:
  /// **'SGST ({rate}%)'**
  String billingSgst(String rate);

  /// No description provided for @billingDiscountApplied.
  ///
  /// In en, this message translates to:
  /// **'Discount Applied'**
  String get billingDiscountApplied;

  /// No description provided for @billingNetPayable.
  ///
  /// In en, this message translates to:
  /// **'Net Payable'**
  String get billingNetPayable;

  /// No description provided for @billingWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get billingWhatsapp;

  /// No description provided for @billingPrinterNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Printer not connected.'**
  String get billingPrinterNotConnected;

  /// No description provided for @billingPrinterConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get billingPrinterConnect;

  /// No description provided for @billingColItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get billingColItem;

  /// No description provided for @billingColPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get billingColPrice;

  /// No description provided for @billingColQty.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get billingColQty;

  /// No description provided for @billingStalePricesFrom.
  ///
  /// In en, this message translates to:
  /// **'Prices from {age}'**
  String billingStalePricesFrom(String age);

  /// No description provided for @billingStalePrices.
  ///
  /// In en, this message translates to:
  /// **'Stale prices'**
  String get billingStalePrices;

  /// No description provided for @billingStaleVeryOld.
  ///
  /// In en, this message translates to:
  /// **'Very old cache — prices may be inaccurate'**
  String get billingStaleVeryOld;

  /// No description provided for @billingStaleConnectToRefresh.
  ///
  /// In en, this message translates to:
  /// **'Connect to refresh pricing'**
  String get billingStaleConnectToRefresh;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @splitSelectSecondTable.
  ///
  /// In en, this message translates to:
  /// **'Select Second Table'**
  String get splitSelectSecondTable;

  /// No description provided for @splitNoOtherTables.
  ///
  /// In en, this message translates to:
  /// **'No other available tables'**
  String get splitNoOtherTables;

  /// No description provided for @paymentCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentCash;

  /// No description provided for @paymentUpi.
  ///
  /// In en, this message translates to:
  /// **'UPI'**
  String get paymentUpi;

  /// No description provided for @paymentCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get paymentCard;

  /// No description provided for @paymentCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get paymentCredit;

  /// No description provided for @paymentOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get paymentOther;

  /// No description provided for @itemsTitle.
  ///
  /// In en, this message translates to:
  /// **'Items / Menu'**
  String get itemsTitle;

  /// No description provided for @menuPhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Menu Photos'**
  String get menuPhotosTitle;

  /// No description provided for @menuPhotosTooltip.
  ///
  /// In en, this message translates to:
  /// **'Menu photos'**
  String get menuPhotosTooltip;

  /// No description provided for @menuPhotosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Photos shown to customers on the QR order menu.'**
  String get menuPhotosSubtitle;

  /// No description provided for @menuPhotosSearch.
  ///
  /// In en, this message translates to:
  /// **'Search dishes…'**
  String get menuPhotosSearch;

  /// No description provided for @menuPhotosEmpty.
  ///
  /// In en, this message translates to:
  /// **'No items yet. Add items first, then add their photos here.'**
  String get menuPhotosEmpty;

  /// No description provided for @menuPhotosAdd.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get menuPhotosAdd;

  /// No description provided for @menuPhotosChange.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get menuPhotosChange;

  /// No description provided for @menuPhotosRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get menuPhotosRemove;

  /// No description provided for @menuPhotosPickCamera.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get menuPhotosPickCamera;

  /// No description provided for @menuPhotosPickGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get menuPhotosPickGallery;

  /// No description provided for @menuPhotosUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get menuPhotosUploading;

  /// No description provided for @menuPhotosUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not upload photo'**
  String get menuPhotosUploadFailed;

  /// No description provided for @menuPhotosRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove photo'**
  String get menuPhotosRemoveFailed;

  /// No description provided for @menuPhotosRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this photo?'**
  String get menuPhotosRemoveConfirm;

  /// No description provided for @itemsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search items…'**
  String get itemsSearch;

  /// No description provided for @itemsStockOverview.
  ///
  /// In en, this message translates to:
  /// **'Available Stock'**
  String get itemsStockOverview;

  /// No description provided for @itemsAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get itemsAddItem;

  /// No description provided for @itemsEditItem.
  ///
  /// In en, this message translates to:
  /// **'Edit Item'**
  String get itemsEditItem;

  /// No description provided for @itemsEditItemTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get itemsEditItemTooltip;

  /// No description provided for @itemsNoneYetOwner.
  ///
  /// In en, this message translates to:
  /// **'No items yet. Tap + to add your first item.'**
  String get itemsNoneYetOwner;

  /// No description provided for @itemsNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No items found.'**
  String get itemsNoneFound;

  /// No description provided for @itemsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete item'**
  String get itemsDeleteTitle;

  /// No description provided for @itemsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? It will no longer appear in billing.'**
  String itemsDeleteBody(String name);

  /// No description provided for @itemsFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get itemsFieldName;

  /// No description provided for @itemsFieldCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get itemsFieldCategory;

  /// No description provided for @itemsFieldCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Beverages'**
  String get itemsFieldCategoryHint;

  /// No description provided for @itemsFieldPrice.
  ///
  /// In en, this message translates to:
  /// **'Price (₹)'**
  String get itemsFieldPrice;

  /// No description provided for @itemsFieldTaxRate.
  ///
  /// In en, this message translates to:
  /// **'Tax rate % (optional)'**
  String get itemsFieldTaxRate;

  /// No description provided for @itemsFieldTaxRateHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 5, 12, 18'**
  String get itemsFieldTaxRateHint;

  /// No description provided for @itemsFieldHsn.
  ///
  /// In en, this message translates to:
  /// **'HSN/SAC code (optional)'**
  String get itemsFieldHsn;

  /// No description provided for @itemsFieldHsnHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 9963 for restaurant service'**
  String get itemsFieldHsnHint;

  /// No description provided for @itemsFieldBarcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode (optional)'**
  String get itemsFieldBarcode;

  /// No description provided for @itemsFieldStock.
  ///
  /// In en, this message translates to:
  /// **'Stock quantity'**
  String get itemsFieldStock;

  /// No description provided for @itemsFieldUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get itemsFieldUnit;

  /// No description provided for @itemsUnitPiece.
  ///
  /// In en, this message translates to:
  /// **'Piece'**
  String get itemsUnitPiece;

  /// No description provided for @itemsUnitKg.
  ///
  /// In en, this message translates to:
  /// **'Kilogram (kg)'**
  String get itemsUnitKg;

  /// No description provided for @itemsUnitGram.
  ///
  /// In en, this message translates to:
  /// **'Gram (g)'**
  String get itemsUnitGram;

  /// No description provided for @itemsUnitLitre.
  ///
  /// In en, this message translates to:
  /// **'Litre (L)'**
  String get itemsUnitLitre;

  /// No description provided for @itemsUnitMl.
  ///
  /// In en, this message translates to:
  /// **'Millilitre (ml)'**
  String get itemsUnitMl;

  /// No description provided for @itemsUnitMetre.
  ///
  /// In en, this message translates to:
  /// **'Metre (m)'**
  String get itemsUnitMetre;

  /// No description provided for @itemsUnitDozen.
  ///
  /// In en, this message translates to:
  /// **'Dozen'**
  String get itemsUnitDozen;

  /// No description provided for @itemsUnitPlate.
  ///
  /// In en, this message translates to:
  /// **'Plate'**
  String get itemsUnitPlate;

  /// No description provided for @itemsManageSizes.
  ///
  /// In en, this message translates to:
  /// **'Add variants'**
  String get itemsManageSizes;

  /// No description provided for @itemsManageSizesCount.
  ///
  /// In en, this message translates to:
  /// **'Manage variants ({count})'**
  String itemsManageSizesCount(int count);

  /// No description provided for @itemsSizesTitle.
  ///
  /// In en, this message translates to:
  /// **'Variants — {name}'**
  String itemsSizesTitle(String name);

  /// No description provided for @itemsSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Variant label (e.g. XL, Half, 500ml)'**
  String get itemsSizeLabel;

  /// No description provided for @itemsSizePrice.
  ///
  /// In en, this message translates to:
  /// **'Price (blank = item price)'**
  String get itemsSizePrice;

  /// No description provided for @itemsSizeStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get itemsSizeStock;

  /// No description provided for @itemsSizeBarcodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Barcode (optional)'**
  String get itemsSizeBarcodeOptional;

  /// No description provided for @itemsSizeBarcodeEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Barcode — {label}'**
  String itemsSizeBarcodeEditTitle(String label);

  /// No description provided for @itemsAddSize.
  ///
  /// In en, this message translates to:
  /// **'Add variant'**
  String get itemsAddSize;

  /// No description provided for @itemsNoSizesYet.
  ///
  /// In en, this message translates to:
  /// **'No variants yet. Add one below.'**
  String get itemsNoSizesYet;

  /// No description provided for @itemsStockPerSizeHint.
  ///
  /// In en, this message translates to:
  /// **'Stock is tracked per variant. Tap the item to update each variant\'s stock.'**
  String get itemsStockPerSizeHint;

  /// No description provided for @itemsSizeDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove variant \"{label}\"?'**
  String itemsSizeDeleteConfirm(String label);

  /// No description provided for @itemsStockLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock: {qty}'**
  String itemsStockLabel(String qty);

  /// No description provided for @itemsLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get itemsLowStock;

  /// No description provided for @itemsCurrentStock.
  ///
  /// In en, this message translates to:
  /// **'Current stock'**
  String get itemsCurrentStock;

  /// No description provided for @itemsAddQuantity.
  ///
  /// In en, this message translates to:
  /// **'Add quantity'**
  String get itemsAddQuantity;

  /// No description provided for @itemsTotalAfterAdding.
  ///
  /// In en, this message translates to:
  /// **'Total after adding'**
  String get itemsTotalAfterAdding;

  /// No description provided for @itemsInventoryDisabled.
  ///
  /// In en, this message translates to:
  /// **'Inventory tracking is disabled.'**
  String get itemsInventoryDisabled;

  /// No description provided for @itemsBarcodePrintTitle.
  ///
  /// In en, this message translates to:
  /// **'Print Barcode'**
  String get itemsBarcodePrintTitle;

  /// No description provided for @itemsBarcodeGenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate & Print Barcode'**
  String get itemsBarcodeGenerateTitle;

  /// No description provided for @itemsBarcodeGeneratedNote.
  ///
  /// In en, this message translates to:
  /// **'This item has no barcode. A barcode has been generated. You can edit it before printing.'**
  String get itemsBarcodeGeneratedNote;

  /// No description provided for @itemsBarcodeValue.
  ///
  /// In en, this message translates to:
  /// **'Barcode value'**
  String get itemsBarcodeValue;

  /// No description provided for @itemsBarcodeCopies.
  ///
  /// In en, this message translates to:
  /// **'Copies'**
  String get itemsBarcodeCopies;

  /// No description provided for @itemsBarcodeSentToPrinter.
  ///
  /// In en, this message translates to:
  /// **'Barcode label sent to printer'**
  String get itemsBarcodeSentToPrinter;

  /// No description provided for @tablesTitle.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get tablesTitle;

  /// No description provided for @tablesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get tablesEmpty;

  /// No description provided for @tablesOccupied.
  ///
  /// In en, this message translates to:
  /// **'Occupied'**
  String get tablesOccupied;

  /// No description provided for @tablesBilled.
  ///
  /// In en, this message translates to:
  /// **'Billed'**
  String get tablesBilled;

  /// No description provided for @tablesNoTables.
  ///
  /// In en, this message translates to:
  /// **'No tables set up yet.'**
  String get tablesNoTables;

  /// No description provided for @tablesAddTable.
  ///
  /// In en, this message translates to:
  /// **'Add Table'**
  String get tablesAddTable;

  /// No description provided for @tablesTableLabel.
  ///
  /// In en, this message translates to:
  /// **'Table {number}'**
  String tablesTableLabel(String number);

  /// No description provided for @tablesNoTablesYet.
  ///
  /// In en, this message translates to:
  /// **'No tables yet'**
  String get tablesNoTablesYet;

  /// No description provided for @tablesBilledOrderBody.
  ///
  /// In en, this message translates to:
  /// **'This table has a billed order. What would you like to do?'**
  String get tablesBilledOrderBody;

  /// No description provided for @tablesMarkPaidEmpty.
  ///
  /// In en, this message translates to:
  /// **'Mark as Paid / Empty'**
  String get tablesMarkPaidEmpty;

  /// No description provided for @tablesVoidBill.
  ///
  /// In en, this message translates to:
  /// **'Void Bill'**
  String get tablesVoidBill;

  /// No description provided for @tablesTableNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Table number (e.g. T1, A2)'**
  String get tablesTableNumberLabel;

  /// No description provided for @tablesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Table'**
  String get tablesDeleteTitle;

  /// No description provided for @tablesDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete table \"{number}\"?'**
  String tablesDeleteBody(String number);

  /// No description provided for @tablesShowQr.
  ///
  /// In en, this message translates to:
  /// **'Show / Print QR'**
  String get tablesShowQr;

  /// No description provided for @tablesShowQrSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customers scan to view the menu and order'**
  String get tablesShowQrSubtitle;

  /// No description provided for @tablesQrNotReady.
  ///
  /// In en, this message translates to:
  /// **'QR code is not ready for this table yet.'**
  String get tablesQrNotReady;

  /// No description provided for @tablesQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Table {number} — Order QR'**
  String tablesQrTitle(String number);

  /// No description provided for @tablesQrHint.
  ///
  /// In en, this message translates to:
  /// **'Stick this on the table. Customers scan it to see the menu and order to this table.'**
  String get tablesQrHint;

  /// No description provided for @tablesRotateQr.
  ///
  /// In en, this message translates to:
  /// **'Rotate QR'**
  String get tablesRotateQr;

  /// No description provided for @tablesRotateQrBody.
  ///
  /// In en, this message translates to:
  /// **'This makes the old printed QR stop working. Print and place a new one after rotating. Continue?'**
  String get tablesRotateQrBody;

  /// No description provided for @tablesQrRotated.
  ///
  /// In en, this message translates to:
  /// **'QR code rotated. Please reprint the sticker.'**
  String get tablesQrRotated;

  /// No description provided for @commonShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// No description provided for @tablesPrintQr.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get tablesPrintQr;

  /// No description provided for @tablesQrShareText.
  ///
  /// In en, this message translates to:
  /// **'Scan to order at Table {number}'**
  String tablesQrShareText(String number);

  /// No description provided for @tablesQrShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not share the QR code.'**
  String get tablesQrShareFailed;

  /// No description provided for @tablesQrPrinted.
  ///
  /// In en, this message translates to:
  /// **'QR sent to printer.'**
  String get tablesQrPrinted;

  /// No description provided for @tablesQrPrintFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not print the QR code.'**
  String get tablesQrPrintFailed;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyNoBills.
  ///
  /// In en, this message translates to:
  /// **'No bills yet.'**
  String get historyNoBills;

  /// No description provided for @historySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by bill no. or customer…'**
  String get historySearchHint;

  /// No description provided for @historyBillNumber.
  ///
  /// In en, this message translates to:
  /// **'Bill #{number}'**
  String historyBillNumber(String number);

  /// No description provided for @historyReprint.
  ///
  /// In en, this message translates to:
  /// **'Reprint'**
  String get historyReprint;

  /// No description provided for @historyShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get historyShare;

  /// No description provided for @historyPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get historyPending;

  /// No description provided for @historySynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get historySynced;

  /// No description provided for @historyFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get historyFailed;

  /// No description provided for @historyBillHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Bill History'**
  String get historyBillHistoryTitle;

  /// No description provided for @historySearchBillOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Search bill no. or phone…'**
  String get historySearchBillOrPhone;

  /// No description provided for @historyNoBillsForPeriod.
  ///
  /// In en, this message translates to:
  /// **'No bills found for this period.'**
  String get historyNoBillsForPeriod;

  /// No description provided for @historyFilterToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get historyFilterToday;

  /// No description provided for @historyFilterYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get historyFilterYesterday;

  /// No description provided for @historyFilterThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get historyFilterThisMonth;

  /// No description provided for @historyFilterLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last Month'**
  String get historyFilterLastMonth;

  /// No description provided for @historyFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get historyFilterAll;

  /// No description provided for @historyFilterCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get historyFilterCustom;

  /// No description provided for @historyStatusFinalized.
  ///
  /// In en, this message translates to:
  /// **'Finalized'**
  String get historyStatusFinalized;

  /// No description provided for @historyStatusVoided.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get historyStatusVoided;

  /// No description provided for @historyStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get historyStatusDraft;

  /// No description provided for @historyItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String historyItemCount(int count);

  /// No description provided for @historyBillMeta.
  ///
  /// In en, this message translates to:
  /// **'{time}  ·  {payment}  ·  {items}'**
  String historyBillMeta(String time, String payment, String items);

  /// No description provided for @historyVoidBill.
  ///
  /// In en, this message translates to:
  /// **'Void Bill'**
  String get historyVoidBill;

  /// No description provided for @historyVoid.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get historyVoid;

  /// No description provided for @historyVoidConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Void bill {number}? This cannot be undone.'**
  String historyVoidConfirmBody(String number);

  /// No description provided for @historyNoPrinterConfigured.
  ///
  /// In en, this message translates to:
  /// **'No printer configured. Set one up in Settings.'**
  String get historyNoPrinterConfigured;

  /// No description provided for @historyPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get historyPayment;

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// No description provided for @reportsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get reportsToday;

  /// No description provided for @reportsWeek.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get reportsWeek;

  /// No description provided for @reportsMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get reportsMonth;

  /// No description provided for @reportsTotalSales.
  ///
  /// In en, this message translates to:
  /// **'Total Sales'**
  String get reportsTotalSales;

  /// No description provided for @reportsBillCount.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get reportsBillCount;

  /// No description provided for @reportsAverageBill.
  ///
  /// In en, this message translates to:
  /// **'Average Bill'**
  String get reportsAverageBill;

  /// No description provided for @reportsTopItems.
  ///
  /// In en, this message translates to:
  /// **'Top Items'**
  String get reportsTopItems;

  /// No description provided for @reportsNoData.
  ///
  /// In en, this message translates to:
  /// **'No data for this period.'**
  String get reportsNoData;

  /// No description provided for @reportsYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get reportsYear;

  /// No description provided for @reportsChangePeriod.
  ///
  /// In en, this message translates to:
  /// **'Change period'**
  String get reportsChangePeriod;

  /// No description provided for @reportsNetRevenue.
  ///
  /// In en, this message translates to:
  /// **'Net Revenue'**
  String get reportsNetRevenue;

  /// No description provided for @reportsExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get reportsExpenses;

  /// No description provided for @reportsBills.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 bill} other{{count} bills}}'**
  String reportsBills(int count);

  /// No description provided for @reportsBillsWithDiscount.
  ///
  /// In en, this message translates to:
  /// **'{bills} · −Rs. {discount} disc'**
  String reportsBillsWithDiscount(String bills, String discount);

  /// No description provided for @reportsCategoryCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 category} other{{count} categories}}'**
  String reportsCategoryCount(int count);

  /// No description provided for @reportsNoExpenses.
  ///
  /// In en, this message translates to:
  /// **'No expenses'**
  String get reportsNoExpenses;

  /// No description provided for @reportsRevenueByPaymentMode.
  ///
  /// In en, this message translates to:
  /// **'Revenue by Payment Mode'**
  String get reportsRevenueByPaymentMode;

  /// No description provided for @reportsExpensesByCategory.
  ///
  /// In en, this message translates to:
  /// **'Expenses by Category'**
  String get reportsExpensesByCategory;

  /// No description provided for @reportsDailyBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Daily Breakdown'**
  String get reportsDailyBreakdown;

  /// No description provided for @reportsTotalSalesToday.
  ///
  /// In en, this message translates to:
  /// **'Total sales today'**
  String get reportsTotalSalesToday;

  /// No description provided for @reportsTotalSalesPeriod.
  ///
  /// In en, this message translates to:
  /// **'Total sales'**
  String get reportsTotalSalesPeriod;

  /// No description provided for @reportsOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get reportsOrders;

  /// No description provided for @reportsAvgBill.
  ///
  /// In en, this message translates to:
  /// **'Avg bill'**
  String get reportsAvgBill;

  /// No description provided for @reportsLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get reportsLast7Days;

  /// No description provided for @reportsTopSellingItems.
  ///
  /// In en, this message translates to:
  /// **'Top selling items'**
  String get reportsTopSellingItems;

  /// No description provided for @reportsRecentBills.
  ///
  /// In en, this message translates to:
  /// **'Recent bills'**
  String get reportsRecentBills;

  /// No description provided for @reportsSoldCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sold'**
  String reportsSoldCount(int count);

  /// No description provided for @reportsParcel.
  ///
  /// In en, this message translates to:
  /// **'Parcel'**
  String get reportsParcel;

  /// No description provided for @reportsTableLabel.
  ///
  /// In en, this message translates to:
  /// **'Table {number}'**
  String reportsTableLabel(String number);

  /// No description provided for @expensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesTitle;

  /// No description provided for @expensesTabThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get expensesTabThisMonth;

  /// No description provided for @expensesTabRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get expensesTabRecurring;

  /// No description provided for @expensesNoneThisMonth.
  ///
  /// In en, this message translates to:
  /// **'No expenses this month.\nTap + to add one.'**
  String get expensesNoneThisMonth;

  /// No description provided for @expensesAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Add Expense'**
  String get expensesAddExpense;

  /// No description provided for @expensesEditExpense.
  ///
  /// In en, this message translates to:
  /// **'Edit Expense'**
  String get expensesEditExpense;

  /// No description provided for @expensesUpdateExpense.
  ///
  /// In en, this message translates to:
  /// **'Update Expense'**
  String get expensesUpdateExpense;

  /// No description provided for @expensesAddRecurring.
  ///
  /// In en, this message translates to:
  /// **'Add Recurring'**
  String get expensesAddRecurring;

  /// No description provided for @expensesAddRecurringExpense.
  ///
  /// In en, this message translates to:
  /// **'Add Recurring Expense'**
  String get expensesAddRecurringExpense;

  /// No description provided for @expensesEditRecurringExpense.
  ///
  /// In en, this message translates to:
  /// **'Edit Recurring Expense'**
  String get expensesEditRecurringExpense;

  /// No description provided for @expensesSaveRecurring.
  ///
  /// In en, this message translates to:
  /// **'Save Recurring Expense'**
  String get expensesSaveRecurring;

  /// No description provided for @expensesRecurringNote.
  ///
  /// In en, this message translates to:
  /// **'These appear every month as a reminder.'**
  String get expensesRecurringNote;

  /// No description provided for @expensesMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get expensesMonthly;

  /// No description provided for @expensesAddAllToMonth.
  ///
  /// In en, this message translates to:
  /// **'Add All to This Month'**
  String get expensesAddAllToMonth;

  /// No description provided for @expensesCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get expensesCategory;

  /// No description provided for @expensesCustomCategory.
  ///
  /// In en, this message translates to:
  /// **'Custom Category'**
  String get expensesCustomCategory;

  /// No description provided for @expensesCustomCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Insurance'**
  String get expensesCustomCategoryHint;

  /// No description provided for @expensesAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount (Rs.)'**
  String get expensesAmount;

  /// No description provided for @expensesAmountRequired.
  ///
  /// In en, this message translates to:
  /// **'Amount is required'**
  String get expensesAmountRequired;

  /// No description provided for @expensesAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get expensesAmountInvalid;

  /// No description provided for @expensesDescription.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get expensesDescription;

  /// No description provided for @expensesDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Expense Details'**
  String get expensesDetailsTitle;

  /// No description provided for @expensesPaymentMode.
  ///
  /// In en, this message translates to:
  /// **'Payment Mode'**
  String get expensesPaymentMode;

  /// No description provided for @expensesExpenseDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get expensesExpenseDate;

  /// No description provided for @expensesAddedBy.
  ///
  /// In en, this message translates to:
  /// **'Added By'**
  String get expensesAddedBy;

  /// No description provided for @expensesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Expense?'**
  String get expensesDeleteTitle;

  /// No description provided for @expensesDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete {category} of Rs. {amount}?'**
  String expensesDeleteBody(String category, String amount);

  /// No description provided for @expensesRemoveRecurringTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Recurring Expense?'**
  String get expensesRemoveRecurringTitle;

  /// No description provided for @expensesRemoveRecurringBody.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{category}\" from recurring list? This won\'t delete past entries.'**
  String expensesRemoveRecurringBody(String category);

  /// No description provided for @expensesNoRecurringYet.
  ///
  /// In en, this message translates to:
  /// **'No recurring expenses yet.\nAdd expenses that repeat every month\n(e.g. Rent, Salary).'**
  String get expensesNoRecurringYet;

  /// No description provided for @expensesCustomChip.
  ///
  /// In en, this message translates to:
  /// **'+ Custom'**
  String get expensesCustomChip;

  /// No description provided for @expensesPendingRecurring.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recurring expense not yet added this month} other{{count} recurring expenses not yet added this month}}'**
  String expensesPendingRecurring(int count);

  /// No description provided for @expensesRecurringAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recurring expense added} other{{count} recurring expenses added}}'**
  String expensesRecurringAdded(int count);

  /// No description provided for @expensesCatRent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get expensesCatRent;

  /// No description provided for @expensesCatSalary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get expensesCatSalary;

  /// No description provided for @expensesCatUtilities.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get expensesCatUtilities;

  /// No description provided for @expensesCatStockPurchase.
  ///
  /// In en, this message translates to:
  /// **'Stock Purchase'**
  String get expensesCatStockPurchase;

  /// No description provided for @expensesCatTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get expensesCatTransport;

  /// No description provided for @expensesCatMarketing.
  ///
  /// In en, this message translates to:
  /// **'Marketing'**
  String get expensesCatMarketing;

  /// No description provided for @expensesCatMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get expensesCatMaintenance;

  /// No description provided for @expensesCatTaxes.
  ///
  /// In en, this message translates to:
  /// **'Taxes'**
  String get expensesCatTaxes;

  /// No description provided for @expensesCatOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get expensesCatOther;

  /// No description provided for @staffTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Staff'**
  String get staffTitle;

  /// No description provided for @staffAddStaff.
  ///
  /// In en, this message translates to:
  /// **'Add Staff'**
  String get staffAddStaff;

  /// No description provided for @staffEditStaff.
  ///
  /// In en, this message translates to:
  /// **'Edit Staff'**
  String get staffEditStaff;

  /// No description provided for @staffNone.
  ///
  /// In en, this message translates to:
  /// **'No staff added yet.'**
  String get staffNone;

  /// No description provided for @staffName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get staffName;

  /// No description provided for @staffPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get staffPhone;

  /// No description provided for @staffRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get staffRole;

  /// No description provided for @staffRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get staffRoleOwner;

  /// No description provided for @staffRoleCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get staffRoleCashier;

  /// No description provided for @staffRoleWaiter.
  ///
  /// In en, this message translates to:
  /// **'Waiter'**
  String get staffRoleWaiter;

  /// No description provided for @staffRoleServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get staffRoleServer;

  /// No description provided for @staffRoleKitchen.
  ///
  /// In en, this message translates to:
  /// **'Kitchen Chef'**
  String get staffRoleKitchen;

  /// No description provided for @staffAddKitchen.
  ///
  /// In en, this message translates to:
  /// **'Add Kitchen Chef'**
  String get staffAddKitchen;

  /// No description provided for @staffSectionWaiters.
  ///
  /// In en, this message translates to:
  /// **'WAITERS & CASHIERS'**
  String get staffSectionWaiters;

  /// No description provided for @staffSectionKitchen.
  ///
  /// In en, this message translates to:
  /// **'KITCHEN'**
  String get staffSectionKitchen;

  /// No description provided for @staffDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove staff?'**
  String get staffDeleteTitle;

  /// No description provided for @staffDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from your team?'**
  String staffDeleteBody(String name);

  /// No description provided for @staffRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Staff'**
  String get staffRemoveTitle;

  /// No description provided for @staffRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\"?'**
  String staffRemoveBody(String name);

  /// No description provided for @staffLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load staff: {error}'**
  String staffLoadFailed(String error);

  /// No description provided for @staffNoCashiers.
  ///
  /// In en, this message translates to:
  /// **'No cashiers added yet.'**
  String get staffNoCashiers;

  /// No description provided for @staffSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search staff by name or phone…'**
  String get staffSearchHint;

  /// No description provided for @staffNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No staff match your search.'**
  String get staffNoMatch;

  /// No description provided for @staffPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'10-digit number required'**
  String get staffPhoneInvalid;

  /// No description provided for @staffPinNew.
  ///
  /// In en, this message translates to:
  /// **'New PIN (leave blank to keep)'**
  String get staffPinNew;

  /// No description provided for @staffPinNewLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN (4 digits)'**
  String get staffPinNewLabel;

  /// No description provided for @staffPinInvalid.
  ///
  /// In en, this message translates to:
  /// **'PIN must be 4 digits'**
  String get staffPinInvalid;

  /// No description provided for @businessProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Business Profile'**
  String get businessProfileTitle;

  /// No description provided for @businessProfileName.
  ///
  /// In en, this message translates to:
  /// **'Business name'**
  String get businessProfileName;

  /// No description provided for @businessProfileAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get businessProfileAddress;

  /// No description provided for @businessProfilePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get businessProfilePhone;

  /// No description provided for @businessProfileGst.
  ///
  /// In en, this message translates to:
  /// **'GSTIN (optional)'**
  String get businessProfileGst;

  /// No description provided for @businessProfileFooter.
  ///
  /// In en, this message translates to:
  /// **'Receipt footer note'**
  String get businessProfileFooter;

  /// No description provided for @businessProfileSaved.
  ///
  /// In en, this message translates to:
  /// **'Business profile updated'**
  String get businessProfileSaved;

  /// No description provided for @businessProfileSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save. Check your connection.'**
  String get businessProfileSaveFailed;

  /// No description provided for @businessProfileSaveButton.
  ///
  /// In en, this message translates to:
  /// **'Save Profile'**
  String get businessProfileSaveButton;

  /// No description provided for @businessProfileNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes to save'**
  String get businessProfileNoChanges;

  /// No description provided for @businessProfileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get businessProfileUpdated;

  /// No description provided for @businessProfileSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get businessProfileSectionAccount;

  /// No description provided for @businessProfileOwnerName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get businessProfileOwnerName;

  /// No description provided for @businessProfileOwnerPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get businessProfileOwnerPhone;

  /// No description provided for @businessProfileSectionBasic.
  ///
  /// In en, this message translates to:
  /// **'BASIC INFO'**
  String get businessProfileSectionBasic;

  /// No description provided for @businessProfileSectionAddress.
  ///
  /// In en, this message translates to:
  /// **'ADDRESS'**
  String get businessProfileSectionAddress;

  /// No description provided for @businessProfileSectionTax.
  ///
  /// In en, this message translates to:
  /// **'TAX INFO'**
  String get businessProfileSectionTax;

  /// No description provided for @businessProfileSectionBilling.
  ///
  /// In en, this message translates to:
  /// **'BILLING'**
  String get businessProfileSectionBilling;

  /// No description provided for @businessProfileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Business Name'**
  String get businessProfileNameLabel;

  /// No description provided for @businessProfileNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Kamble Provisions'**
  String get businessProfileNameHint;

  /// No description provided for @businessProfilePhoneHint.
  ///
  /// In en, this message translates to:
  /// **'10-digit mobile number'**
  String get businessProfilePhoneHint;

  /// No description provided for @businessProfilePhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Must be 10 digits'**
  String get businessProfilePhoneInvalid;

  /// No description provided for @businessProfileEmail.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get businessProfileEmail;

  /// No description provided for @businessProfileEmailHint.
  ///
  /// In en, this message translates to:
  /// **'owner@example.com'**
  String get businessProfileEmailHint;

  /// No description provided for @businessProfileEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get businessProfileEmailInvalid;

  /// No description provided for @businessProfileWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website (optional)'**
  String get businessProfileWebsite;

  /// No description provided for @businessProfileWebsiteHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com'**
  String get businessProfileWebsiteHint;

  /// No description provided for @businessProfileType.
  ///
  /// In en, this message translates to:
  /// **'Business Type'**
  String get businessProfileType;

  /// No description provided for @businessProfileStreet.
  ///
  /// In en, this message translates to:
  /// **'Street Address'**
  String get businessProfileStreet;

  /// No description provided for @businessProfileStreetHint.
  ///
  /// In en, this message translates to:
  /// **'Shop No. 5, Market Road'**
  String get businessProfileStreetHint;

  /// No description provided for @businessProfileCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get businessProfileCity;

  /// No description provided for @businessProfileCityHint.
  ///
  /// In en, this message translates to:
  /// **'Vengurla'**
  String get businessProfileCityHint;

  /// No description provided for @businessProfileState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get businessProfileState;

  /// No description provided for @businessProfileStateHint.
  ///
  /// In en, this message translates to:
  /// **'Maharashtra'**
  String get businessProfileStateHint;

  /// No description provided for @businessProfilePincode.
  ///
  /// In en, this message translates to:
  /// **'Pincode'**
  String get businessProfilePincode;

  /// No description provided for @businessProfilePincodeHint.
  ///
  /// In en, this message translates to:
  /// **'416523'**
  String get businessProfilePincodeHint;

  /// No description provided for @businessProfilePincodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'6-digit pincode'**
  String get businessProfilePincodeInvalid;

  /// No description provided for @businessProfileGstHint.
  ///
  /// In en, this message translates to:
  /// **'27ABCDE1234F1Z5'**
  String get businessProfileGstHint;

  /// No description provided for @businessProfileGstInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid GSTIN format'**
  String get businessProfileGstInvalid;

  /// No description provided for @businessProfilePan.
  ///
  /// In en, this message translates to:
  /// **'PAN (optional)'**
  String get businessProfilePan;

  /// No description provided for @businessProfilePanHint.
  ///
  /// In en, this message translates to:
  /// **'ABCDE1234F'**
  String get businessProfilePanHint;

  /// No description provided for @businessProfilePanInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid PAN format'**
  String get businessProfilePanInvalid;

  /// No description provided for @businessProfileFssai.
  ///
  /// In en, this message translates to:
  /// **'FSSAI No. (optional)'**
  String get businessProfileFssai;

  /// No description provided for @businessProfileFssaiHint.
  ///
  /// In en, this message translates to:
  /// **'14-digit license number'**
  String get businessProfileFssaiHint;

  /// No description provided for @businessProfileFssaiInvalid.
  ///
  /// In en, this message translates to:
  /// **'FSSAI number must be exactly 14 digits'**
  String get businessProfileFssaiInvalid;

  /// No description provided for @businessProfileDefaultSac.
  ///
  /// In en, this message translates to:
  /// **'Default HSN/SAC (optional)'**
  String get businessProfileDefaultSac;

  /// No description provided for @businessProfileDefaultSacHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 9963 — used when an item has none'**
  String get businessProfileDefaultSacHint;

  /// No description provided for @businessProfileBillPrefix.
  ///
  /// In en, this message translates to:
  /// **'Bill Number Prefix'**
  String get businessProfileBillPrefix;

  /// No description provided for @businessProfileBillPrefixHelper.
  ///
  /// In en, this message translates to:
  /// **'Bills will be numbered INV-0001, INV-0002, …'**
  String get businessProfileBillPrefixHelper;

  /// No description provided for @businessProfileBillPrefixInvalid.
  ///
  /// In en, this message translates to:
  /// **'Letters, numbers, hyphens, slashes only'**
  String get businessProfileBillPrefixInvalid;

  /// No description provided for @businessProfileFooterNote.
  ///
  /// In en, this message translates to:
  /// **'Bill Footer Note (optional)'**
  String get businessProfileFooterNote;

  /// No description provided for @businessProfileFooterNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Thank you for shopping with us!'**
  String get businessProfileFooterNoteHint;

  /// No description provided for @printerSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Printer Setup'**
  String get printerSetupTitle;

  /// No description provided for @printerSetupScan.
  ///
  /// In en, this message translates to:
  /// **'Scan for printers'**
  String get printerSetupScan;

  /// No description provided for @printerSetupScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get printerSetupScanning;

  /// No description provided for @printerSetupNoPrinters.
  ///
  /// In en, this message translates to:
  /// **'No printers found. Make sure your printer is on and paired.'**
  String get printerSetupNoPrinters;

  /// No description provided for @printerSetupConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get printerSetupConnected;

  /// No description provided for @printerSetupConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get printerSetupConnect;

  /// No description provided for @printerSetupDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get printerSetupDisconnect;

  /// No description provided for @printerSetupTestPrint.
  ///
  /// In en, this message translates to:
  /// **'Test print'**
  String get printerSetupTestPrint;

  /// No description provided for @printerSetupNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'No printer configured'**
  String get printerSetupNotConfigured;

  /// No description provided for @conflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsynced Bills'**
  String get conflictTitle;

  /// No description provided for @conflictNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs your attention.'**
  String get conflictNone;

  /// No description provided for @conflictKeepMine.
  ///
  /// In en, this message translates to:
  /// **'Keep mine'**
  String get conflictKeepMine;

  /// No description provided for @conflictKeepServer.
  ///
  /// In en, this message translates to:
  /// **'Keep server copy'**
  String get conflictKeepServer;

  /// No description provided for @conflictResolved.
  ///
  /// In en, this message translates to:
  /// **'Conflict resolved'**
  String get conflictResolved;

  /// No description provided for @licenseBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription required'**
  String get licenseBlockedTitle;

  /// No description provided for @licenseBlockedOffline.
  ///
  /// In en, this message translates to:
  /// **'Please go online to verify your subscription.'**
  String get licenseBlockedOffline;

  /// No description provided for @licenseBlockedSubscription.
  ///
  /// In en, this message translates to:
  /// **'Your subscription has expired. Renew to continue billing.'**
  String get licenseBlockedSubscription;

  /// No description provided for @licenseBlockedPending.
  ///
  /// In en, this message translates to:
  /// **'Your account is pending activation.'**
  String get licenseBlockedPending;

  /// No description provided for @licenseContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get licenseContactSupport;

  /// No description provided for @licenseCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get licenseCheckAgain;

  /// No description provided for @licenseGraceLastDay.
  ///
  /// In en, this message translates to:
  /// **'Last day! Go online today to keep using the app.'**
  String get licenseGraceLastDay;

  /// No description provided for @licenseGraceDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days} days left — go online soon to verify your subscription.'**
  String licenseGraceDaysLeft(int days);

  /// No description provided for @updateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateTitle;

  /// No description provided for @updateBody.
  ///
  /// In en, this message translates to:
  /// **'A new version of Vittam is available.'**
  String get updateBody;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updateNow;

  /// No description provided for @updateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Bills will sync when you reconnect.'**
  String get offlineBanner;

  /// No description provided for @licenseTitleOffline.
  ///
  /// In en, this message translates to:
  /// **'Go Online to Continue'**
  String get licenseTitleOffline;

  /// No description provided for @licenseTitlePending.
  ///
  /// In en, this message translates to:
  /// **'Account Pending Activation'**
  String get licenseTitlePending;

  /// No description provided for @licenseTitleExpired.
  ///
  /// In en, this message translates to:
  /// **'Subscription Expired'**
  String get licenseTitleExpired;

  /// No description provided for @licenseSubtitleOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'ve been offline too long.\nConnect to the internet to verify your subscription.'**
  String get licenseSubtitleOffline;

  /// No description provided for @licenseSubtitlePending.
  ///
  /// In en, this message translates to:
  /// **'Your account is under review.\nContact support to activate your subscription.'**
  String get licenseSubtitlePending;

  /// No description provided for @licenseSubtitleExpired.
  ///
  /// In en, this message translates to:
  /// **'Your subscription has expired or been suspended.\nContact support to renew.'**
  String get licenseSubtitleExpired;

  /// No description provided for @licenseTitleDevice.
  ///
  /// In en, this message translates to:
  /// **'Device Not Allowed'**
  String get licenseTitleDevice;

  /// No description provided for @licenseSubtitleDevice.
  ///
  /// In en, this message translates to:
  /// **'Your account isn\'t enabled for this type of device.\nContact support to use the app here.'**
  String get licenseSubtitleDevice;

  /// No description provided for @licenseChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get licenseChecking;

  /// No description provided for @licenseConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect. Check your internet and try again.'**
  String get licenseConnectFailed;

  /// No description provided for @licenseMsgSubscription.
  ///
  /// In en, this message translates to:
  /// **'Your subscription has expired or been suspended. Please contact support.'**
  String get licenseMsgSubscription;

  /// No description provided for @licenseMsgPending.
  ///
  /// In en, this message translates to:
  /// **'Your account is pending activation. Please contact support.'**
  String get licenseMsgPending;

  /// No description provided for @licenseMsgStillOffline.
  ///
  /// In en, this message translates to:
  /// **'Still offline. Connect to the internet and try again.'**
  String get licenseMsgStillOffline;

  /// No description provided for @licenseMsgVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not verify subscription. Please try again.'**
  String get licenseMsgVerifyFailed;

  /// No description provided for @licenseBrandFooter.
  ///
  /// In en, this message translates to:
  /// **'Vittam Billing'**
  String get licenseBrandFooter;

  /// No description provided for @printerSetupPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission denied. Grant it in app settings.'**
  String get printerSetupPermissionDenied;

  /// No description provided for @printerSetupNoPaired.
  ///
  /// In en, this message translates to:
  /// **'No paired printers found. Pair your printer in phone Bluetooth settings first.'**
  String get printerSetupNoPaired;

  /// No description provided for @printerSetupLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load printers: {error}'**
  String printerSetupLoadFailed(String error);

  /// No description provided for @printerSetupSelectedSnack.
  ///
  /// In en, this message translates to:
  /// **'Printer \"{name}\" selected'**
  String printerSetupSelectedSnack(String name);

  /// No description provided for @printerSetupCleared.
  ///
  /// In en, this message translates to:
  /// **'Printer cleared'**
  String get printerSetupCleared;

  /// No description provided for @printerSetupTestSent.
  ///
  /// In en, this message translates to:
  /// **'Test page sent!'**
  String get printerSetupTestSent;

  /// No description provided for @printerSetupPrintFailed.
  ///
  /// In en, this message translates to:
  /// **'Print failed: {error}'**
  String printerSetupPrintFailed(String error);

  /// No description provided for @printerSetupActivePrinter.
  ///
  /// In en, this message translates to:
  /// **'Active Printer'**
  String get printerSetupActivePrinter;

  /// No description provided for @printerSetupUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get printerSetupUnknown;

  /// No description provided for @printerSetupActiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get printerSetupActiveBadge;

  /// No description provided for @printerSetupAvailablePrinters.
  ///
  /// In en, this message translates to:
  /// **'Available Printers'**
  String get printerSetupAvailablePrinters;

  /// No description provided for @printerSetupScanButton.
  ///
  /// In en, this message translates to:
  /// **'Scan for Printers'**
  String get printerSetupScanButton;

  /// No description provided for @printerSetupScanHint.
  ///
  /// In en, this message translates to:
  /// **'Shows printers already paired in your phone\'s Bluetooth settings. Pair the printer there first, then tap Scan.'**
  String get printerSetupScanHint;

  /// No description provided for @printerSetupTapScan.
  ///
  /// In en, this message translates to:
  /// **'Tap \"Scan\" to find printers'**
  String get printerSetupTapScan;

  /// No description provided for @printerSetupUnknownPrinter.
  ///
  /// In en, this message translates to:
  /// **'Unknown Printer'**
  String get printerSetupUnknownPrinter;

  /// No description provided for @printerSetupSelectedBadge.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get printerSetupSelectedBadge;

  /// No description provided for @printerSetupSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get printerSetupSelect;

  /// No description provided for @printerSetupNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get printerSetupNotes;

  /// No description provided for @printerSetupNoteBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Android/iPhone: pair the printer in phone Bluetooth settings first, then tap Scan here'**
  String get printerSetupNoteBluetooth;

  /// No description provided for @printerSetupNoteWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows: uses BLE or USB — printer must be powered on during scan'**
  String get printerSetupNoteWindows;

  /// No description provided for @printerSetupNoteUsb.
  ///
  /// In en, this message translates to:
  /// **'USB on Windows requires WinUSB driver installed for the printer'**
  String get printerSetupNoteUsb;

  /// No description provided for @printerSetupPaperSize.
  ///
  /// In en, this message translates to:
  /// **'Paper Size'**
  String get printerSetupPaperSize;

  /// No description provided for @printerSetupPaperSize58.
  ///
  /// In en, this message translates to:
  /// **'58mm (2 inch thermal)'**
  String get printerSetupPaperSize58;

  /// No description provided for @printerSetupPaperSize80.
  ///
  /// In en, this message translates to:
  /// **'80mm (3 inch thermal)'**
  String get printerSetupPaperSize80;

  /// No description provided for @printerSetupPaperSizeA5.
  ///
  /// In en, this message translates to:
  /// **'A5 (PDF invoice)'**
  String get printerSetupPaperSizeA5;

  /// No description provided for @printerSetupPaperSizeA4.
  ///
  /// In en, this message translates to:
  /// **'A4 (PDF invoice)'**
  String get printerSetupPaperSizeA4;

  /// No description provided for @printerSetupPaperSizePdfHint.
  ///
  /// In en, this message translates to:
  /// **'Opens your device\'s print dialog to print or save a PDF'**
  String get printerSetupPaperSizePdfHint;

  /// No description provided for @printerSetupNoteThermal.
  ///
  /// In en, this message translates to:
  /// **'58mm/80mm print to a thermal printer; A5/A4 make a PDF invoice'**
  String get printerSetupNoteThermal;

  /// No description provided for @conflictQueuedForRetry.
  ///
  /// In en, this message translates to:
  /// **'Bill queued for retry'**
  String get conflictQueuedForRetry;

  /// No description provided for @conflictDismissed.
  ///
  /// In en, this message translates to:
  /// **'Bill dismissed'**
  String get conflictDismissed;

  /// No description provided for @conflictSyncedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 bill synced} other{{count} bills synced}}'**
  String conflictSyncedCount(int count);

  /// No description provided for @conflictRemainCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 conflict remains} other{{count} conflicts remain}}'**
  String conflictRemainCount(int count);

  /// No description provided for @conflictNothingSynced.
  ///
  /// In en, this message translates to:
  /// **'Nothing synced'**
  String get conflictNothingSynced;

  /// No description provided for @conflictDismissTitle.
  ///
  /// In en, this message translates to:
  /// **'Dismiss bill?'**
  String get conflictDismissTitle;

  /// No description provided for @conflictDismissBody.
  ///
  /// In en, this message translates to:
  /// **'This bill will be permanently removed from the queue. It will not be recorded in the system.'**
  String get conflictDismissBody;

  /// No description provided for @conflictDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get conflictDismiss;

  /// No description provided for @conflictTabConflicts.
  ///
  /// In en, this message translates to:
  /// **'Conflicts'**
  String get conflictTabConflicts;

  /// No description provided for @conflictTabConflictsCount.
  ///
  /// In en, this message translates to:
  /// **'Conflicts ({count})'**
  String conflictTabConflictsCount(int count);

  /// No description provided for @conflictTabFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get conflictTabFailed;

  /// No description provided for @conflictTabFailedCount.
  ///
  /// In en, this message translates to:
  /// **'Failed ({count})'**
  String conflictTabFailedCount(int count);

  /// No description provided for @conflictRetryAll.
  ///
  /// In en, this message translates to:
  /// **'Retry All'**
  String get conflictRetryAll;

  /// No description provided for @conflictNoConflicts.
  ///
  /// In en, this message translates to:
  /// **'No stock conflicts — all clear.'**
  String get conflictNoConflicts;

  /// No description provided for @conflictNoFailed.
  ///
  /// In en, this message translates to:
  /// **'No permanently failed bills.'**
  String get conflictNoFailed;

  /// No description provided for @conflictStockConflict.
  ///
  /// In en, this message translates to:
  /// **'Stock conflict'**
  String get conflictStockConflict;

  /// No description provided for @conflictFailedAfterRetries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Failed after 1 retry} other{Failed after {count} retries}}'**
  String conflictFailedAfterRetries(int count);

  /// No description provided for @conflictMoreItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{+1 more item} other{+{count} more items}}'**
  String conflictMoreItems(int count);

  /// No description provided for @conflictItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String conflictItemCount(int count);

  /// No description provided for @conflictUnknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get conflictUnknownError;

  /// No description provided for @conflictJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get conflictJustNow;

  /// No description provided for @conflictMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String conflictMinutesAgo(int minutes);

  /// No description provided for @conflictHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String conflictHoursAgo(int hours);

  /// No description provided for @updateForceNote.
  ///
  /// In en, this message translates to:
  /// **'This update is required. Please update to continue.'**
  String get updateForceNote;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Smart Billing for Indian Businesses'**
  String get splashTagline;

  /// No description provided for @noInternetTitle.
  ///
  /// In en, this message translates to:
  /// **'No Internet Connection'**
  String get noInternetTitle;

  /// No description provided for @noInternetBody.
  ///
  /// In en, this message translates to:
  /// **'Connect to the network to get started.\nYour data will load automatically.'**
  String get noInternetBody;

  /// No description provided for @errorNoInternetBody.
  ///
  /// In en, this message translates to:
  /// **'This page needs an internet connection. Check your network and try again.'**
  String get errorNoInternetBody;

  /// No description provided for @connectivityNoConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get connectivityNoConnection;

  /// No description provided for @connectivityBackOnline.
  ///
  /// In en, this message translates to:
  /// **'Back online'**
  String get connectivityBackOnline;

  /// No description provided for @errorSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorSomethingWentWrong;

  /// No description provided for @itemsTabItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get itemsTabItems;

  /// No description provided for @itemsTabRawMaterials.
  ///
  /// In en, this message translates to:
  /// **'Raw Materials'**
  String get itemsTabRawMaterials;

  /// No description provided for @itemsAddRawMaterial.
  ///
  /// In en, this message translates to:
  /// **'Add raw material'**
  String get itemsAddRawMaterial;

  /// No description provided for @itemsEditRawMaterial.
  ///
  /// In en, this message translates to:
  /// **'Edit raw material'**
  String get itemsEditRawMaterial;

  /// No description provided for @itemsRawMaterialsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No raw materials yet.\nAdd ingredients to track their stock.'**
  String get itemsRawMaterialsEmpty;

  /// No description provided for @itemsRawMaterialDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete raw material?'**
  String get itemsRawMaterialDeleteTitle;

  /// No description provided for @itemsRawMaterialDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String itemsRawMaterialDeleteBody(String name);

  /// No description provided for @itemsLowStockThreshold.
  ///
  /// In en, this message translates to:
  /// **'Low-stock alert at'**
  String get itemsLowStockThreshold;

  /// No description provided for @itemsManageRecipe.
  ///
  /// In en, this message translates to:
  /// **'Manage recipe (raw materials)'**
  String get itemsManageRecipe;

  /// No description provided for @itemsRecipeTitle.
  ///
  /// In en, this message translates to:
  /// **'Recipe · {name}'**
  String itemsRecipeTitle(String name);

  /// No description provided for @itemsRecipeHint.
  ///
  /// In en, this message translates to:
  /// **'Set how much of each raw material this dish uses per unit sold. Leave blank to skip.'**
  String get itemsRecipeHint;

  /// No description provided for @itemsRecipeNoMaterials.
  ///
  /// In en, this message translates to:
  /// **'Add raw materials first, then set the recipe.'**
  String get itemsRecipeNoMaterials;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'mr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'mr':
      return AppLocalizationsMr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
