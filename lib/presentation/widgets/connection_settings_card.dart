import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/ar_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/connection_settings.dart';
import '../../data/models/connection_status.dart';
import '../viewmodels/connection_view_model.dart';
import 'neon_button.dart';
import 'neon_card.dart';
import 'status_pill.dart';

/// بطاقة إعدادات الاتصال: العنوان، المنفذ، النقل، وزر الاتصال/القطع مع
/// مؤشر حي لحالة الاتصال.
class ConnectionSettingsCard extends StatefulWidget {
  const ConnectionSettingsCard({super.key, required this.viewModel});

  final ConnectionViewModel viewModel;

  @override
  State<ConnectionSettingsCard> createState() => _ConnectionSettingsCardState();
}

class _ConnectionSettingsCardState extends State<ConnectionSettingsCard> {
  late final TextEditingController _hostController =
      TextEditingController(text: widget.viewModel.host);
  late final TextEditingController _portController =
      TextEditingController(text: widget.viewModel.portText);
  late final TextEditingController _tokenController =
      TextEditingController(text: widget.viewModel.authToken);

  bool _advancedOpen = false;

  @override
  void didUpdateWidget(covariant ConnectionSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_hostController, widget.viewModel.host);
    _sync(_portController, widget.viewModel.portText);
    _sync(_tokenController, widget.viewModel.authToken);
  }

  /// مزامنة الحقل عند تغيّر القيمة من الـ ViewModel (وليس من الكتابة).
  void _sync(TextEditingController controller, String value) {
    if (controller.text != value) {
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ConnectionViewModel vm = widget.viewModel;
    final Color statusColor = _statusColor(vm);

    return NeonCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: ArStrings.connectionSettings,
            subtitle: ArStrings.connectionSettingsHint,
            icon: Icons.settings_input_antenna_rounded,
            trailing: StatusPill(
              label: vm.statusLabel,
              color: statusColor,
              pulsing: vm.isBusy || (vm.isConnected && !vm.isDataStale),
              compact: true,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _hostController,
                  onChanged: vm.setHost,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: AppColors.textPrimary,
                  ),
                  decoration: AppTheme.inputDecoration(
                    labelText: ArStrings.serverIp,
                    hintText: ArStrings.serverIpHint,
                    prefixIcon: Icons.lan_outlined,
                    errorText: vm.showValidation ? vm.hostError : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _portController,
                  onChanged: vm.setPort,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: AppColors.textPrimary,
                  ),
                  decoration: AppTheme.inputDecoration(
                    labelText: ArStrings.port,
                    hintText: ArStrings.portHint,
                    prefixIcon: Icons.dialpad_rounded,
                    errorText: vm.showValidation ? vm.portError : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TransportSelector(
            value: vm.transport,
            onChanged: vm.setTransport,
          ),
          const SizedBox(height: 6),
          _AdvancedSection(
            expanded: _advancedOpen,
            onToggle: () => setState(() => _advancedOpen = !_advancedOpen),
            child: Column(
              children: <Widget>[
                TextFormField(
                  controller: _tokenController,
                  onChanged: vm.setAuthToken,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textPrimary,
                  ),
                  decoration: AppTheme.inputDecoration(
                    labelText: ArStrings.authToken,
                    hintText: ArStrings.authTokenHint,
                    prefixIcon: Icons.key_rounded,
                  ),
                ),
                SwitchListTile.adaptive(
                  value: vm.secure,
                  onChanged:
                      vm.transport == TransportKind.webSocket ? vm.setSecure : null,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: AppColors.cyan,
                  title: const Text(
                    ArStrings.useSecureConnection,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (vm.errorMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            _MessageBox(
              message: vm.errorMessage!,
              hint: ArStrings.connectionErrorHint,
              color: AppColors.danger,
              icon: Icons.error_outline_rounded,
            ),
          ],
          if (vm.formMessage != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              vm.formMessage!,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 14),
          NeonButton(
            label: vm.isConnected || vm.isBusy
                ? ArStrings.disconnect
                : ArStrings.connect,
            icon: vm.isConnected || vm.isBusy
                ? Icons.link_off_rounded
                : Icons.wifi_tethering_rounded,
            loading: vm.status == ConnectionStatus.connecting,
            variant: vm.isConnected || vm.isBusy
                ? NeonButtonVariant.danger
                : NeonButtonVariant.filled,
            onPressed: vm.toggleConnection,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              InfoChip(
                icon: Icons.settings_ethernet_rounded,
                label: 'الهدف',
                value: vm.endpointLabel,
                color: AppColors.cyan,
              ),
              if (vm.isConnected)
                InfoChip(
                  icon: Icons.timer_outlined,
                  label: ArStrings.uptime,
                  value: Formatters.duration(vm.uptime),
                  color: AppColors.emerald,
                ),
              if (vm.isConnected)
                InfoChip(
                  icon: Icons.speed_rounded,
                  label: ArStrings.frameRate,
                  value: '${Formatters.decimal(vm.frameRateHz)} Hz',
                  color: AppColors.textSecondary,
                ),
              if (vm.retryIn != null)
                InfoChip(
                  icon: Icons.sync_rounded,
                  label: 'المحاولة',
                  value: '${vm.attempt}',
                  color: AppColors.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(ConnectionViewModel vm) {
    if (vm.isConnected && vm.isDataStale) return AppColors.warning;
    if (vm.isConnected) return AppColors.emerald;
    if (vm.isBusy) return AppColors.cyan;
    if (vm.status == ConnectionStatus.error) return AppColors.danger;
    return AppColors.idle;
  }
}

/// مبدّل بروتوكول النقل (WebSocket / UDP).
class _TransportSelector extends StatelessWidget {
  const _TransportSelector({required this.value, required this.onChanged});

  final TransportKind value;
  final ValueChanged<TransportKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(bottom: 7, right: 2),
          child: Text(
            ArStrings.transport,
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _TransportOption(
                label: ArStrings.transportWebSocket,
                caption: 'بث JSON حي',
                icon: Icons.bolt_rounded,
                selected: value == TransportKind.webSocket,
                onTap: () => onChanged(TransportKind.webSocket),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TransportOption(
                label: ArStrings.transportUdp,
                caption: 'حزم CSI مباشرة',
                icon: Icons.router_outlined,
                selected: value == TransportKind.udp,
                onTap: () => onChanged(TransportKind.udp),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TransportOption extends StatelessWidget {
  const _TransportOption({
    required this.label,
    required this.caption,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String caption;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color tone = selected ? AppColors.cyan : AppColors.textMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: selected
              ? AppColors.cyan.withAlpha(20)
              : AppColors.backgroundElevated,
          border: Border.all(
            color: selected ? AppColors.cyan.withAlpha(140) : AppColors.border,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: tone),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    caption,
                    style: TextStyle(fontSize: 10, color: tone.withAlpha(200)),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  size: 15, color: AppColors.cyan),
          ],
        ),
      ),
    );
  }
}

/// قسم قابل للطي للخيارات المتقدمة.
class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: AppColors.textSecondary,
            ),
            icon: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18,
            ),
            label: const Text(
              ArStrings.advancedOptions,
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: child,
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

/// صندوق رسالة خطأ/تنبيه.
class _MessageBox extends StatelessWidget {
  const _MessageBox({
    required this.message,
    required this.color,
    required this.icon,
    this.hint,
  });

  final String message;
  final String? hint;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (hint != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    hint!,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
