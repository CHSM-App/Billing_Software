import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../theme/app_theme.dart';
import '../utils/text_formatters.dart';

// Animated primary button with gradient and press effect
class PrimaryButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null && !widget.isLoading;

    return GestureDetector(
      onTapDown: isEnabled ? (_) => _controller.forward() : null,
      onTapUp: isEnabled
          ? (_) {
              _controller.reverse();
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedOpacity(
          opacity: isEnabled ? 1.0 : 0.6,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: isEnabled
                  ? AppColors.primaryGradient
                  : const LinearGradient(
                      colors: [AppColors.textDisabled, AppColors.textDisabled],
                    ),
              borderRadius: BorderRadius.circular(AppRadius.medium),
              boxShadow: isEnabled ? AppShadow.primary : [],
            ),
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 18, color: Colors.white),
                          const SizedBox(width: AppSpacing.space8),
                        ],
                        Flexible(
                          child: Text(
                            widget.text,
                            overflow: TextOverflow.ellipsis,
                            style: AppFont.style(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The footer's settle button: an amount on the first line and, under it, what
/// pressing will actually DO — "and print" or "no receipt".
///
/// The caption is the point. The same tap prints or doesn't depending on whether
/// a printer is reachable, and without saying so a dropped Bluetooth link
/// finalizes a sale silently while the customer walks away. Naming the outcome
/// on the control that causes it means the cashier can never be surprised by it.
///
/// [onLongPress] is the deliberate escape hatch: settle without printing even
/// when a printer IS connected.
class SettleButton extends StatelessWidget {
  final String amountLabel;
  final String outcomeLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool isLoading;
  /// Surfaces the long-press, which is otherwise undiscoverable.
  final String? longPressHint;

  const SettleButton({
    super.key,
    required this.amountLabel,
    required this.outcomeLabel,
    required this.onPressed,
    this.onLongPress,
    this.longPressHint,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !isLoading;
    final radius = BorderRadius.circular(AppRadius.medium);

    final button = Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: isEnabled
            ? AppColors.primaryGradient
            : const LinearGradient(
                colors: [AppColors.textDisabled, AppColors.textDisabled],
              ),
        borderRadius: radius,
        boxShadow: isEnabled ? AppShadow.primary : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          onLongPress: isEnabled ? onLongPress : null,
          borderRadius: radius,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 17, color: Colors.white),
                          const SizedBox(width: AppSpacing.space8),
                          Flexible(
                            child: Text(
                              amountLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFont.style(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        outcomeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    return (longPressHint == null || onLongPress == null)
        ? button
        : Tooltip(message: longPressHint!, child: button);
  }
}

/// A square outlined icon action sized to sit flush beside [SettleButton], with
/// a one-word caption underneath.
///
/// The caption is not decoration: an icon alone cannot say whether it takes the
/// customer's money. WhatsApp finalizes the bill exactly like settling does, so
/// its tile has to be readable as such rather than as a share.
class IconAction extends StatelessWidget {
  /// The glyph, when a Material icon says it. Mutually exclusive with
  /// [glyphBuilder], which exists for marks Material has no icon for.
  final IconData? icon;

  /// Draws the glyph at the given size and colour. Used for the WhatsApp mark,
  /// which Material omits because it is a trademark.
  final Widget Function(double size, Color color)? glyphBuilder;

  final String caption;
  final Color color;
  final VoidCallback? onPressed;
  final String? tooltip;

  const IconAction({
    super.key,
    this.icon,
    this.glyphBuilder,
    required this.caption,
    required this.color,
    required this.onPressed,
    this.tooltip,
  }) : assert(icon != null || glyphBuilder != null,
            'IconAction needs either an icon or a glyphBuilder');

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final c = enabled ? color : AppColors.textDisabled;
    final button = SizedBox(
      width: 56,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          // The shared theme forces an infinite minimum width; this action is
          // deliberately square, so it must be overridden here.
          minimumSize: const Size(56, 56),
          side: BorderSide(color: c, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
        child: glyphBuilder != null
            ? glyphBuilder!(20, c)
            : Icon(icon, size: 20, color: c),
      ),
    );

    return Column(mainAxisSize: MainAxisSize.min, children: [
      tooltip == null ? button : Tooltip(message: tooltip!, child: button),
      const SizedBox(height: 3),
      SizedBox(
        width: 56,
        child: Text(
          caption,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppFont.style(
              fontSize: 10, fontWeight: FontWeight.w600, color: c),
        ),
      ),
    ]);
  }
}

// Secondary button (outlined with primary color)
class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17),
              const SizedBox(width: AppSpacing.space8),
            ],
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

// Destructive button (red gradient)
class DestructiveButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const DestructiveButton({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: AppFont.style(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// Pre-styled card with shadow and hover animation
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: widget.color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadow.small,
      ),
      child: Padding(
        padding: widget.padding ?? const EdgeInsets.all(AppSpacing.space16),
        child: widget.child,
      ),
    );

    if (widget.onTap == null) return card;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scaleAnim, child: card),
    );
  }
}

// Text field with consistent styling
class AppTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? maxLength;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final bool enabled;
  final FocusNode? focusNode;
  final bool capitalizeWords;
  final List<TextInputFormatter>? inputFormatters;

  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.maxLength,
    this.suffixIcon,
    this.prefixIcon,
    this.enabled = true,
    this.focusNode,
    this.capitalizeWords = false,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
        prefixIcon: prefixIcon,
        counterText: '',
      ),
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength,
      validator: validator,
      enabled: enabled,
      textCapitalization:
          capitalizeWords ? TextCapitalization.words : TextCapitalization.none,
      inputFormatters: [
        if (capitalizeWords) const CapitalizeWordsFormatter(),
        ...?inputFormatters,
      ],
    );
  }
}

/// The unit-of-measure a quantity field is counted in, shown inside the field's
/// trailing edge (e.g. a stock box reading "12" followed by a grey "kg").
///
/// A bare number leaves the user guessing whether they typed grams or kilos —
/// especially on the low-stock alert, which is entered long after the unit was
/// chosen. Pass it as [AppTextField.suffixIcon]; it tracks whatever the unit
/// dropdown currently holds, so changing the unit relabels every field at once.
class UnitSuffix extends StatelessWidget {
  final String label;
  const UnitSuffix(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    // The suffix slot passes down unbounded height, so anything that expands to
    // fill it (Align, Center, a stretching Column) drags the whole field to the
    // viewport height. Keep every box here tightly sized: mainAxisSize.min on
    // the Row plus a width-only SizedBox leaves the field exactly as tall as it
    // is without a suffix.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppFont.style(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}

// Animated empty state widget
class EmptyState extends StatefulWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppRadius.large),
                  ),
                  child: Icon(widget.icon, size: 34, color: AppColors.textDisabled),
                ),
                const SizedBox(height: AppSpacing.space16),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                if (widget.actionLabel != null && widget.onAction != null) ...[
                  const SizedBox(height: AppSpacing.space24),
                  SizedBox(
                    width: 180,
                    child: PrimaryButton(
                        text: widget.actionLabel!, onPressed: widget.onAction),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Status badge pill
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusType status;

  const StatusBadge({super.key, required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (status) {
      StatusType.success => (AppColors.success, AppColors.successLight),
      StatusType.warning => (AppColors.warning, AppColors.warningLight),
      StatusType.error => (AppColors.error, AppColors.errorLight),
      StatusType.info => (AppColors.info, AppColors.infoLight),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space8,
        vertical: AppSpacing.space4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: AppFont.style(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

enum StatusType { success, warning, error, info }

// Full-screen no-internet widget
class NoInternetWidget extends StatefulWidget {
  final VoidCallback? onRetry;

  const NoInternetWidget({super.key, this.onRetry});

  @override
  State<NoInternetWidget> createState() => _NoInternetWidgetState();
}

class _NoInternetWidgetState extends State<NoInternetWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_off_rounded,
                    size: 38, color: AppColors.error),
              ),
            ),
            const SizedBox(height: AppSpacing.space24),
            Text(
              l10n.noInternetTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space8),
            Text(
              l10n.noInternetBody,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(height: AppSpacing.space24),
              SizedBox(
                width: 160,
                child: PrimaryButton(
                    text: l10n.commonRetry, onPressed: widget.onRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Generic error widget with retry button
class AppErrorWidget extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  final String? title;

  const AppErrorWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // An offline failure must never read as a bug. Show a dedicated "No
    // internet" state (wifi-off icon, its own copy) instead of the generic
    // error card, so the user knows to check their connection, not retry blindly.
    final offline = isNetworkError(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: offline ? AppColors.surfaceVariant : AppColors.errorLight,
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
              child: Icon(
                offline
                    ? Icons.wifi_off_rounded
                    : Icons.error_outline_rounded,
                size: 34,
                color: offline ? AppColors.textSecondary : AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.space16),
            Text(
              offline
                  ? l10n.noInternetTitle
                  : (title ?? l10n.errorSomethingWentWrong),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.space8),
            Text(
              offline
                  ? l10n.errorNoInternetBody
                  : sanitizeUiErrorMessage(error),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.space24),
              SizedBox(
                width: 160,
                child:
                    PrimaryButton(text: l10n.commonRetry, onPressed: onRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tappable support contact block: email (opens mail app) and phone (dials).
/// Shared by the pending-activation and subscription-expired screens so a
/// locked-out owner always has a way to reach support. [color] tints the text
/// and icons to match the surrounding card (warning vs error styling).
class SupportContactRow extends StatelessWidget {
  final Color color;
  final MainAxisAlignment alignment;

  const SupportContactRow({
    super.key,
    required this.color,
    this.alignment = MainAxisAlignment.start,
  });

  Future<void> _launch(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No mail/dialer app available — nothing to do; the number/email is still
      // shown on screen for the user to copy manually.
    }
  }

  Widget _line(IconData icon, String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: alignment,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final phone = l10n.supportPhone;
    final email = l10n.supportEmail;
    return Column(
      crossAxisAlignment: alignment == MainAxisAlignment.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        _line(Icons.phone_outlined, phone,
            () => _launch(Uri(scheme: 'tel', path: phone))),
        _line(Icons.email_outlined, email,
            () => _launch(Uri(scheme: 'mailto', path: email))),
      ],
    );
  }
}

// RadioGroup helper used in RegisterScreen
class RadioGroup<T> extends StatelessWidget {
  final T groupValue;
  final ValueChanged<T?> onChanged;
  final Widget child;

  const RadioGroup({
    super.key,
    required this.groupValue,
    required this.onChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return _RadioGroupScope<T>(
      groupValue: groupValue,
      onChanged: onChanged,
      child: child,
    );
  }
}

class _RadioGroupScope<T> extends InheritedWidget {
  final T groupValue;
  final ValueChanged<T?> onChanged;

  const _RadioGroupScope({
    required this.groupValue,
    required this.onChanged,
    required super.child,
  });

  @override
  bool updateShouldNotify(_RadioGroupScope<T> oldWidget) {
    return oldWidget.groupValue != groupValue;
  }
}
