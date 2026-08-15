import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/features/libraries/library_inventory_controller.dart';
import 'package:kontakt_library_manager/l10n/app_localizations.dart';
import 'package:kontakt_library_manager/l10n/locale_controller.dart';
import 'package:kontakt_library_manager/platform/app_update_platform.dart';
import 'package:kontakt_library_manager/platform/feedback_service.dart';
import 'package:kontakt_library_manager/theme/app_theme.dart';
import 'package:kontakt_library_manager/theme/theme_controller.dart';
import 'package:kontakt_library_manager/platform/windows/windows_portable_settings.dart';

enum DashboardSection { library, diagnostics, activity, settings }

class LibraryDashboard extends StatefulWidget {
  const LibraryDashboard({
    super.key,
    required this.controller,
    required this.localeController,
    required this.themeController,
    required this.updatePlatform,
    required this.feedbackService,
    this.portableSupport,
  });

  final LibraryInventoryController controller;
  final LocaleController localeController;
  final ThemeController themeController;
  final AppUpdatePlatform updatePlatform;
  final FeedbackService feedbackService;
  final WindowsPortableSupport? portableSupport;

  @override
  State<LibraryDashboard> createState() => _LibraryDashboardState();
}

class _LibraryDashboardState extends State<LibraryDashboard> {
  DashboardSection _section = DashboardSection.library;
  late Future<AppUpdateInfo> _appUpdateInfo;
  Future<AvailableAppUpdate?>? _activeUpdateProbe;
  AvailableAppUpdate? _availableUpdate;

  @override
  void initState() {
    super.initState();
    _appUpdateInfo = widget.updatePlatform.getInfo();
    _probeForUpdates();
  }

  @override
  void didUpdateWidget(covariant LibraryDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updatePlatform != widget.updatePlatform) {
      _appUpdateInfo = widget.updatePlatform.getInfo();
      _activeUpdateProbe = null;
      _availableUpdate = null;
      _probeForUpdates();
    }
  }

  Future<void> _probeForUpdates() async {
    try {
      final update = await _runUpdateProbe();
      if (mounted) setState(() => _availableUpdate = update);
    } catch (_) {
      // The launch check is intentionally silent when the feed is unavailable.
    }
  }

  Future<void> _checkForUpdates({AvailableAppUpdate? knownUpdate}) async {
    try {
      final update = knownUpdate ?? await _runUpdateProbe();
      if (!mounted) return;
      setState(() => _availableUpdate = update);
      final info = await _appUpdateInfo;
      if (!mounted) return;
      if (update == null) {
        await _showUpToDateDialog(info.currentVersion);
      } else {
        await _showUpdateAvailableDialog(info, update);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('updatesUnavailable'))),
        );
      }
    }
  }

  Future<AvailableAppUpdate?> _runUpdateProbe() {
    final activeProbe = _activeUpdateProbe;
    if (activeProbe != null) return activeProbe;

    late final Future<AvailableAppUpdate?> trackedProbe;
    trackedProbe = widget.updatePlatform.probeForUpdates().whenComplete(() {
      if (identical(_activeUpdateProbe, trackedProbe)) {
        _activeUpdateProbe = null;
      }
    });
    _activeUpdateProbe = trackedProbe;
    return trackedProbe;
  }

  Future<void> _showUpdateAvailableDialog(
    AppUpdateInfo info,
    AvailableAppUpdate update,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('update-available-dialog'),
        icon: const Icon(Icons.system_update_alt_rounded),
        title: Text(context.l10n.tr('updateAvailable')),
        content: Text(
          context.l10n.format('updateAvailableMessage', {
            'version': update.version,
            'currentVersion': info.currentVersion,
          }),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('confirm-install-update'),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _installUpdate();
            },
            child: Text(context.l10n.tr('downloadAndInstall')),
          ),
        ],
      ),
    );
  }

  Future<void> _showUpToDateDialog(String currentVersion) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('up-to-date-dialog'),
        icon: const Icon(Icons.check_circle_outline_rounded),
        title: Text(context.l10n.tr('upToDate')),
        content: Text(
          context.l10n.format('upToDateMessage', {'version': currentVersion}),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.tr('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _installUpdate() async {
    try {
      await widget.updatePlatform.installUpdate();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('updatesUnavailable'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                _Sidebar(
                  compact: MediaQuery.sizeOf(context).width < 860,
                  section: _section,
                  attentionCount: widget.controller.attentionCount,
                  updateInfo: _appUpdateInfo,
                  updateAvailable: _availableUpdate != null,
                  onInstallUpdate: () =>
                      _checkForUpdates(knownUpdate: _availableUpdate),
                  onSelected: (section) => setState(() => _section = section),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildSection()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSection() => switch (_section) {
    DashboardSection.library => _InventoryView(
      controller: widget.controller,
      onShowDiagnostics: () =>
          setState(() => _section = DashboardSection.diagnostics),
    ),
    DashboardSection.diagnostics => _DiagnosticsView(
      controller: widget.controller,
    ),
    DashboardSection.activity => _ActivityView(controller: widget.controller),
    DashboardSection.settings => _SettingsView(
      localeController: widget.localeController,
      themeController: widget.themeController,
      updatePlatform: widget.updatePlatform,
      feedbackService: widget.feedbackService,
      onCheckForUpdates: _checkForUpdates,
      portableSupport: widget.portableSupport,
    ),
  };
}

class _UpdateAvailableBanner extends StatelessWidget {
  const _UpdateAvailableBanner({
    required this.compact,
    required this.onInstall,
  });

  final bool compact;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final colors = context.klmColors;
    if (compact) {
      return Tooltip(
        message:
            '${context.l10n.tr('updateAvailable')} — '
            '${context.l10n.tr('downloadAndInstall')}',
        child: IconButton.filled(
          key: const ValueKey('update-available-banner'),
          onPressed: onInstall,
          icon: const Icon(Icons.system_update_alt_rounded),
        ),
      );
    }

    return Container(
      key: const ValueKey('update-available-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                size: 19,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  context.l10n.tr('updateAvailable'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('download-install-update'),
            onPressed: onInstall,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            ),
            child: Text(
              context.l10n.tr('downloadAndInstall'),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.compact,
    required this.section,
    required this.attentionCount,
    required this.updateInfo,
    required this.updateAvailable,
    required this.onInstallUpdate,
    required this.onSelected,
  });

  final bool compact;
  final DashboardSection section;
  final int attentionCount;
  final Future<AppUpdateInfo> updateInfo;
  final bool updateAvailable;
  final VoidCallback onInstallUpdate;
  final ValueChanged<DashboardSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 76 : 240,
      color: context.klmColors.sidebar,
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 16,
        20,
        compact ? 10 : 16,
        14,
      ),
      child: Column(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2B544),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.library_music_rounded,
                    color: Color(0xFF16130C),
                    size: 21,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 11),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'KLM',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'LIBRARY MANAGER',
                        style: TextStyle(
                          color: context.klmColors.tertiaryText,
                          fontSize: 8,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          _NavigationItem(
            key: const ValueKey('navigation-library'),
            compact: compact,
            selected: section == DashboardSection.library,
            icon: Icons.grid_view_rounded,
            label: context.l10n.library,
            onTap: () => onSelected(DashboardSection.library),
          ),
          _NavigationItem(
            key: const ValueKey('navigation-diagnostics'),
            compact: compact,
            selected: section == DashboardSection.diagnostics,
            icon: Icons.monitor_heart_outlined,
            label: context.l10n.diagnostics,
            badge: attentionCount == 0 ? null : '$attentionCount',
            onTap: () => onSelected(DashboardSection.diagnostics),
          ),
          _NavigationItem(
            key: const ValueKey('navigation-activity'),
            compact: compact,
            selected: section == DashboardSection.activity,
            icon: Icons.history_rounded,
            label: context.l10n.activity,
            onTap: () => onSelected(DashboardSection.activity),
          ),
          const Spacer(),
          if (updateAvailable) ...[
            _UpdateAvailableBanner(
              compact: compact,
              onInstall: onInstallUpdate,
            ),
            const SizedBox(height: 12),
          ],
          _NavigationItem(
            key: const ValueKey('navigation-settings'),
            compact: compact,
            selected: section == DashboardSection.settings,
            icon: Icons.settings_outlined,
            label: context.l10n.settings,
            onTap: () => onSelected(DashboardSection.settings),
          ),
          if (!compact) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FutureBuilder<AppUpdateInfo>(
                future: updateInfo,
                builder: (context, snapshot) {
                  final version = snapshot.data?.currentVersion.trim() ?? '';
                  final footer = version.isEmpty
                      ? 'KLM - Juan Ayala'
                      : 'KLM v$version - Juan Ayala';
                  return Text(
                    footer,
                    style: TextStyle(
                      color: context.klmColors.tertiaryText,
                      fontSize: 11,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    super.key,
    required this.compact,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final bool compact;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.klmColors;
    final foreground = selected
        ? colors.navigationSelectedForeground
        : colors.secondaryText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Tooltip(
        message: compact ? label : '',
        child: Material(
          color: selected
              ? colors.navigationSelectedBackground
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: selected
                ? BorderSide(color: colors.navigationSelectedBorder)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  SizedBox(width: compact ? 0 : 12),
                  Icon(icon, size: 20, color: foreground),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF623C30),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Color(0xFFFFAA85),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryView extends StatelessWidget {
  const _InventoryView({
    required this.controller,
    required this.onShowDiagnostics,
  });

  final LibraryInventoryController controller;
  final VoidCallback onShowDiagnostics;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            title: context.l10n.tr('inventoryTitle'),
            actions: [
              if (controller.hasUnsavedCustomOrder) ...[
                Tooltip(
                  message: context.l10n.tr('closeKontaktBeforeOrderSave'),
                  child: FilledButton.icon(
                    onPressed:
                        controller.orderSaveInProgress ||
                            controller.mutationInProgress
                        ? null
                        : () => _saveCustomOrder(context),
                    icon: controller.orderSaveInProgress
                        ? const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(context.l10n.tr('saveChanges')),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              OutlinedButton.icon(
                onPressed: controller.state == InventoryLoadState.loading
                    ? null
                    : controller.refresh,
                icon: controller.state == InventoryLoadState.loading
                    ? const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.l10n.refresh),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const ValueKey('add-library-button'),
                onPressed: controller.mutationInProgress
                    ? null
                    : () => _addLibraries(context, allowMultiple: false),
                style: FilledButton.styleFrom(
                  backgroundColor: context.klmColors.accentButtonBackground,
                  foregroundColor: context.klmColors.accentButtonForeground,
                  side: BorderSide(color: context.klmColors.accentButtonBorder),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: Text(context.l10n.addLibrary),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                enabled: !controller.mutationInProgress,
                tooltip: context.l10n.tr('addMultipleLibraries'),
                icon: const Icon(Icons.arrow_drop_down_rounded),
                onSelected: (_) => _addLibraries(context, allowMultiple: true),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'multiple',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.playlist_add_rounded),
                      title: Text(context.l10n.tr('addMultipleLibraries')),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          _StatsRow(controller: controller),
          const SizedBox(height: 18),
          _InventoryToolbar(controller: controller),
          const SizedBox(height: 12),
          Expanded(child: _inventoryBody(context)),
        ],
      ),
    );
  }

  Widget _inventoryBody(BuildContext context) {
    if (controller.state == InventoryLoadState.initial ||
        (controller.state == InventoryLoadState.loading &&
            controller.snapshot == null)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.state == InventoryLoadState.failure) {
      return _CenteredMessage(
        icon: Icons.error_outline_rounded,
        title: context.l10n.tr('inventoryReadError'),
        message: controller.lastError.toString(),
        actionLabel: context.l10n.retry,
        onAction: controller.refresh,
      );
    }

    final libraries = controller.visibleLibraries;
    if (libraries.isEmpty) {
      final filtering =
          controller.query.isNotEmpty || controller.filter != LibraryFilter.all;
      return _CenteredMessage(
        icon: filtering
            ? Icons.search_off_rounded
            : Icons.library_music_outlined,
        title: context.l10n.tr(filtering ? 'noMatches' : 'noLibraries'),
        message: context.l10n.tr(
          filtering ? 'noMatchesMessage' : 'noLibrariesMessage',
        ),
      );
    }

    if (controller.canReorderVisibleLibraries) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        buildDefaultDragHandles: false,
        itemCount: libraries.length,
        // Keep the callback supported by Flutter 3.38.9 for the Catalina
        // Codemagic build. Its newIndex is measured before removing oldIndex.
        // ignore: deprecated_member_use
        onReorder: (oldIndex, newIndex) {
          final adjustedNewIndex = oldIndex < newIndex
              ? newIndex - 1
              : newIndex;
          controller.reorderLibrary(oldIndex, adjustedNewIndex);
        },
        proxyDecorator: (child, _, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            color: Colors.transparent,
            elevation: 10 * animation.value,
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
          child: child,
        ),
        itemBuilder: (context, index) => Padding(
          key: ValueKey('custom-order-${libraries[index].id}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: _libraryCard(
            context,
            libraries[index],
            dragHandle: ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: context.l10n.tr('dragToReorder'),
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: const SizedBox(
                    width: 36,
                    height: 44,
                    child: Center(child: Icon(Icons.drag_indicator_rounded)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: libraries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _libraryCard(context, libraries[index]),
    );
  }

  Widget _libraryCard(
    BuildContext context,
    KontaktLibrary library, {
    Widget? dragHandle,
  }) {
    return _LibraryCard(
      key: ValueKey('library-card-${library.id}'),
      library: library,
      dragHandle: dragHandle,
      onReveal: () async {
        try {
          await controller.reveal(library);
        } catch (error) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      },
      onDiagnose: onShowDiagnostics,
      onRepair: () => _repairLibrary(context, library),
      onRelocate: () => _relocateLibrary(context, library),
      onRemove: () => _removeLibrary(context, library),
    );
  }

  Future<void> _saveCustomOrder(BuildContext context) async {
    try {
      await controller.saveCustomOrder();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('classicOrderSaved'))),
      );
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      await _showMessage(
        context,
        error.code == 'kontakt_running'
            ? context.l10n.tr('closeKontaktBeforeOrderSave')
            : error.message ?? context.l10n.tr('classicOrderSaveFailed'),
        title: context.l10n.tr('classicOrderSaveFailed'),
      );
    } catch (error) {
      if (!context.mounted) return;
      await _showMessage(
        context,
        error.toString(),
        title: context.l10n.tr('classicOrderSaveFailed'),
      );
    }
  }

  Future<void> _addLibraries(
    BuildContext context, {
    required bool allowMultiple,
  }) async {
    try {
      final candidates = await controller.chooseLibraryCandidates(
        allowMultiple: allowMultiple,
      );
      if (candidates.isEmpty || !context.mounted) return;
      final confirmed = await _confirmCandidates(
        context,
        candidates,
        repair: false,
      );
      if (!confirmed || !context.mounted) return;
      await _runMutation(
        context,
        () => controller.upsertCandidates(candidates, repair: false),
      );
    } catch (error) {
      if (context.mounted) await _showMutationError(context, error);
    }
  }

  Future<void> _repairLibrary(
    BuildContext context,
    KontaktLibrary library,
  ) async {
    try {
      final candidates = await controller.chooseLibraryCandidates(
        allowMultiple: false,
      );
      if (candidates.isEmpty || !context.mounted) return;
      final candidate = candidates.first;
      if (!controller.candidateMatchesLibrary(candidate, library)) {
        await _showMessage(context, context.l10n.tr('candidateMismatch'));
        return;
      }
      final confirmed = await _confirmCandidates(context, [
        candidate,
      ], repair: true);
      if (!confirmed || !context.mounted) return;
      await _runMutation(
        context,
        () => controller.upsertCandidates([candidate], repair: true),
      );
    } catch (error) {
      if (context.mounted) await _showMutationError(context, error);
    }
  }

  Future<void> _relocateLibrary(
    BuildContext context,
    KontaktLibrary library,
  ) async {
    try {
      final path = await controller.chooseContentDirectory();
      if (path == null || !context.mounted) return;
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              icon: const Icon(Icons.drive_file_move_outline),
              title: Text(context.l10n.tr('confirmRelocateTitle')),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.tr('confirmRelocateMessage')),
                    const SizedBox(height: 12),
                    SelectableText(
                      path,
                      style: const TextStyle(color: Color(0xFFF2B544)),
                    ),
                  ],
                ),
              ),
              actions: _confirmationActions(context),
            ),
          ) ??
          false;
      if (!confirmed || !context.mounted) return;
      await _runMutation(
        context,
        () => controller.relocateLibrary(library, path),
      );
    } catch (error) {
      if (context.mounted) await _showMutationError(context, error);
    }
  }

  Future<void> _removeLibrary(
    BuildContext context,
    KontaktLibrary library,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFFF806E),
            ),
            title: Text(context.l10n.tr('confirmRemoveTitle')),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    library.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(context.l10n.tr('confirmRemoveMessage')),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.tr('contentWillRemain'),
                    style: const TextStyle(color: Color(0xFF61D39A)),
                  ),
                ],
              ),
            ),
            actions: _confirmationActions(context, destructive: true),
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    await _runMutation(context, () => controller.removeLibrary(library));
  }

  Future<bool> _confirmCandidates(
    BuildContext context,
    List<KontaktLibraryCandidate> candidates, {
    required bool repair,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(
              repair ? Icons.build_outlined : Icons.library_add_outlined,
            ),
            title: Text(
              context.l10n.tr(
                repair ? 'confirmRepairTitle' : 'confirmAddTitle',
              ),
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.tr(
                      repair ? 'confirmRepairMessage' : 'confirmAddMessage',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.album_outlined, size: 20),
                        title: Text(candidates[index].metadata.name),
                        subtitle: Text(
                          candidates[index].contentPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: _confirmationActions(context),
          ),
        ) ??
        false;
  }

  List<Widget> _confirmationActions(
    BuildContext context, {
    bool destructive = false,
  }) {
    return [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(context.l10n.tr('cancel')),
      ),
      FilledButton(
        style: destructive
            ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB84E43))
            : null,
        onPressed: () => Navigator.pop(context, true),
        child: Text(context.l10n.tr('confirm')),
      ),
    ];
  }

  Future<void> _runMutation(
    BuildContext context,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('operationComplete'))),
      );
    } catch (error) {
      if (context.mounted) await _showMutationError(context, error);
    }
  }

  Future<void> _showMutationError(BuildContext context, Object error) {
    if (error is LibraryAlreadyRegistered) {
      return _showMessage(
        context,
        '${context.l10n.tr('alreadyRegistered')}\n\n${error.libraryName}',
      );
    }
    if (error is PrivilegedHelperRequired) {
      final unsupported = error.status == PrivilegedHelperStatus.unsupported;
      return _showMessage(
        context,
        context.l10n.tr(
          unsupported ? 'helperUnsupportedMessage' : 'helperApprovalMessage',
        ),
        title: context.l10n.tr('helperApprovalTitle'),
      );
    }
    if (error is PlatformException) {
      return _showMessage(
        context,
        error.message ?? context.l10n.tr('operation_mutation_error_title'),
        title: context.l10n.tr('operation_mutation_error_title'),
      );
    }
    return _showMessage(context, error.toString());
  }

  Future<void> _showMessage(
    BuildContext context,
    String message, {
    String? title,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.admin_panel_settings_outlined),
        title: title == null ? null : Text(title),
        content: SizedBox(width: 440, child: Text(message)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.tr('close')),
          ),
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  final String? eyebrow;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!,
                  style: const TextStyle(
                    color: Color(0xFFF2B544),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: context.klmColors.secondaryText,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.controller});

  final LibraryInventoryController controller;

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatData(
        context.l10n.total,
        '${controller.totalCount}',
        Icons.album_outlined,
        const Color(0xFF8BA8FF),
      ),
      _StatData(
        context.l10n.healthy,
        '${controller.healthyCount}',
        Icons.check_circle_outline,
        const Color(0xFF65D5A0),
      ),
      _StatData(
        context.l10n.needsAttention,
        '${controller.attentionCount}',
        Icons.warning_amber_rounded,
        const Color(0xFFFFA46C),
      ),
      _StatData(
        context.l10n.offline,
        '${controller.offlineCount}',
        Icons.usb_off_outlined,
        const Color(0xFFD493FF),
      ),
    ];
    return Row(
      children: [
        for (var index = 0; index < stats.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(child: _StatCard(data: stats[index])),
        ],
      ],
    );
  }
}

class _StatData {
  const _StatData(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _StatData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.klmColors;
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.secondaryText, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryToolbar extends StatelessWidget {
  const _InventoryToolbar({required this.controller});
  final LibraryInventoryController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: controller.setQuery,
            decoration: InputDecoration(
              hintText: context.l10n.tr('searchHint'),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<LibraryFilter>(
          initialValue: controller.filter,
          onSelected: controller.setFilter,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: LibraryFilter.all,
              child: Text(context.l10n.all),
            ),
            PopupMenuItem(
              value: LibraryFilter.healthy,
              child: Text(context.l10n.healthy),
            ),
            PopupMenuItem(
              value: LibraryFilter.attention,
              child: Text(context.l10n.withWarnings),
            ),
            PopupMenuItem(
              value: LibraryFilter.offline,
              child: Text(context.l10n.offline),
            ),
          ],
          child: _ToolbarButton(
            icon: Icons.filter_list_rounded,
            label: _filterLabel(context, controller.filter),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<LibrarySort>(
          initialValue: controller.sort,
          onSelected: controller.setSort,
          itemBuilder: (_) => [
            if (controller.platform.capabilities.canManageClassicOrder)
              PopupMenuItem(
                value: LibrarySort.custom,
                child: Text(context.l10n.tr('customOrder')),
              ),
            PopupMenuItem(
              value: LibrarySort.name,
              child: Text(context.l10n.name),
            ),
            PopupMenuItem(
              value: LibrarySort.health,
              child: Text(context.l10n.status),
            ),
            PopupMenuItem(
              value: LibrarySort.path,
              child: Text(context.l10n.path),
            ),
          ],
          child: _ToolbarButton(
            icon: Icons.sort_rounded,
            label: _sortLabel(context, controller.sort),
          ),
        ),
      ],
    );
  }

  String _filterLabel(BuildContext context, LibraryFilter filter) =>
      switch (filter) {
        LibraryFilter.all => context.l10n.all,
        LibraryFilter.healthy => context.l10n.healthy,
        LibraryFilter.attention => context.l10n.withWarnings,
        LibraryFilter.offline => context.l10n.offline,
      };

  String _sortLabel(BuildContext context, LibrarySort sort) => switch (sort) {
    LibrarySort.custom => context.l10n.tr('customOrder'),
    LibrarySort.name => context.l10n.name,
    LibrarySort.health => context.l10n.status,
    LibrarySort.path => context.l10n.path,
  };
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.klmColors;
    return Container(
      height: 47,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: colors.control,
        border: Border.all(color: colors.controlBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.mutedIcon),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 5),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        ],
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    super.key,
    required this.library,
    required this.onReveal,
    required this.onDiagnose,
    required this.onRepair,
    required this.onRelocate,
    required this.onRemove,
    this.dragHandle,
  });

  final KontaktLibrary library;
  final VoidCallback onReveal;
  final VoidCallback onDiagnose;
  final VoidCallback onRepair;
  final VoidCallback onRelocate;
  final VoidCallback onRemove;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final colors = context.klmColors;
    // ReorderableListView may lay out and move this child in the same frame.
    // Reading the window size avoids a nested LayoutBuilder requesting a
    // relayout while its reorderable ancestor is performing layout.
    final compact = MediaQuery.sizeOf(context).width < 1120;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (dragHandle != null) ...[dragHandle!, const SizedBox(width: 2)],
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.iconTileStart, colors.iconTileEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.graphic_eq_rounded, color: colors.iconForeground),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  library.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  library.contentPath ?? context.l10n.tr('unknownContentPath'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.secondaryText, fontSize: 11),
                ),
                if (compact) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children: [
                      _SnpidChip(snpid: library.snpid),
                      _HealthChip(health: library.health),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 16),
            SizedBox(width: 76, child: _SnpidChip(snpid: library.snpid)),
            const SizedBox(width: 10),
            SizedBox(width: 36, child: _HealthChip(health: library.health)),
          ],
          PopupMenuButton<String>(
            tooltip: context.l10n.tr('actions'),
            icon: Icon(Icons.more_horiz_rounded, color: colors.mutedIcon),
            onSelected: (value) {
              if (value == 'reveal') onReveal();
              if (value == 'diagnose') onDiagnose();
              if (value == 'repair') onRepair();
              if (value == 'relocate') onRelocate();
              if (value == 'remove') onRemove();
            },
            itemBuilder: (_) => [
              if (library.contentPath != null)
                PopupMenuItem(
                  value: 'reveal',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_open_outlined),
                    title: Text(context.l10n.tr('showInFolder')),
                  ),
                ),
              PopupMenuItem(
                value: 'diagnose',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: Text(context.l10n.tr('viewDiagnostics')),
                ),
              ),
              PopupMenuItem(
                value: 'repair',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.build_outlined),
                  title: Text(context.l10n.tr('repairRecords')),
                ),
              ),
              PopupMenuItem(
                value: 'relocate',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: Text(context.l10n.tr('relocateLibrary')),
                ),
              ),
              PopupMenuItem(
                value: 'remove',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(context.l10n.tr('removeRecords')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnpidChip extends StatelessWidget {
  const _SnpidChip({required this.snpid});

  final String? snpid;

  @override
  Widget build(BuildContext context) {
    final normalized = snpid?.trim().toUpperCase();
    final value = normalized == null || normalized.isEmpty ? '—' : normalized;
    final tooltip = 'SNPID: $value';
    final color = Theme.of(context).colorScheme.secondary;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.health});
  final LibraryHealth health;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (health) {
      LibraryHealth.healthy => (
        context.l10n.tr('healthHealthy'),
        const Color(0xFF61D39A),
        Icons.check_circle_rounded,
      ),
      LibraryHealth.warning => (
        context.l10n.tr('healthIncomplete'),
        const Color(0xFFFFB56B),
        Icons.warning_rounded,
      ),
      LibraryHealth.error => (
        context.l10n.tr('healthErrors'),
        const Color(0xFFFF806E),
        Icons.error_rounded,
      ),
    };
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          width: 30,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

class _DiagnosticsView extends StatelessWidget {
  const _DiagnosticsView({required this.controller});
  final LibraryInventoryController controller;

  @override
  Widget build(BuildContext context) {
    final diagnostics = controller.snapshot?.diagnostics ?? const [];
    final libraries =
        controller.snapshot?.libraries
            .where((library) => library.issues.isNotEmpty)
            .toList() ??
        const <KontaktLibrary>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            eyebrow: context.l10n.tr('diagnosticsEyebrow'),
            title: context.l10n.tr('diagnosticsTitle'),
            subtitle: context.l10n.tr('diagnosticsSubtitle'),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: diagnostics.isEmpty && libraries.isEmpty
                ? _CenteredMessage(
                    icon: Icons.verified_outlined,
                    title: context.l10n.tr('allGood'),
                    message: context.l10n.tr('allGoodMessage'),
                  )
                : ListView(
                    children: [
                      for (final diagnostic in diagnostics)
                        _DiagnosticTile(
                          title: context.l10n.diagnosticTitle(
                            diagnostic.code,
                            diagnostic.title,
                          ),
                          message: context.l10n.diagnosticMessage(
                            diagnostic.code,
                            diagnostic.message,
                            detail: diagnostic.detail,
                          ),
                          severity: diagnostic.severity,
                        ),
                      for (final library in libraries)
                        for (final issue in library.issues)
                          _DiagnosticTile(
                            title: library.name,
                            message: context.l10n.issueMessage(
                              issue.code,
                              issue.message,
                              version: library.minimumKontaktVersion,
                              visibility: library.visibility,
                            ),
                            severity: issue.severity,
                            suffix: library.snpid?.toUpperCase(),
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  const _DiagnosticTile({
    required this.title,
    required this.message,
    required this.severity,
    this.suffix,
  });
  final String title;
  final String message;
  final IssueSeverity severity;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final colors = context.klmColors;
    final (color, icon) = switch (severity) {
      IssueSeverity.information => (
        const Color(0xFF7CA8FF),
        Icons.info_outline_rounded,
      ),
      IssueSeverity.warning => (
        const Color(0xFFFFB56B),
        Icons.warning_amber_rounded,
      ),
      IssueSeverity.error => (
        const Color(0xFFFF806E),
        Icons.error_outline_rounded,
      ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(color: colors.secondaryText, fontSize: 12),
                ),
              ],
            ),
          ),
          if (suffix != null)
            Text(
              suffix!,
              style: TextStyle(color: colors.tertiaryText, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _ActivityView extends StatelessWidget {
  const _ActivityView({required this.controller});
  final LibraryInventoryController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            eyebrow: context.l10n.tr('activityEyebrow'),
            title: context.l10n.tr('activityTitle'),
            subtitle: context.l10n.tr('activitySubtitle'),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: controller.logs.isEmpty
                ? _CenteredMessage(
                    icon: Icons.history_rounded,
                    title: context.l10n.tr('noActivity'),
                    message: context.l10n.tr('noActivityMessage'),
                  )
                : ListView.separated(
                    itemCount: controller.logs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = controller.logs[index];
                      final time =
                          '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 7,
                        ),
                        leading: CircleAvatar(
                          backgroundColor:
                              (log.isError
                                      ? const Color(0xFFFF806E)
                                      : const Color(0xFF61D39A))
                                  .withValues(alpha: 0.12),
                          child: Icon(
                            log.isError
                                ? Icons.close_rounded
                                : Icons.check_rounded,
                            color: log.isError
                                ? const Color(0xFFFF806E)
                                : const Color(0xFF61D39A),
                            size: 18,
                          ),
                        ),
                        title: Text(context.l10n.operationTitle(log.code)),
                        subtitle: Text(
                          context.l10n.operationDetail(
                            log.code,
                            log.detail,
                            count: log.count,
                          ),
                        ),
                        trailing: Text(
                          time,
                          style: TextStyle(
                            color: context.klmColors.tertiaryText,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({
    required this.localeController,
    required this.themeController,
    required this.updatePlatform,
    required this.feedbackService,
    required this.onCheckForUpdates,
    this.portableSupport,
  });

  final LocaleController localeController;
  final ThemeController themeController;
  final AppUpdatePlatform updatePlatform;
  final FeedbackService feedbackService;
  final Future<void> Function() onCheckForUpdates;
  final WindowsPortableSupport? portableSupport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(title: context.l10n.tr('settingsTitle')),
          const SizedBox(height: 24),
          _LanguageSettingsCard(localeController: localeController),
          const SizedBox(height: 14),
          _ThemeSettingsCard(themeController: themeController),
          const SizedBox(height: 14),
          if (Platform.isWindows && portableSupport != null) ...[
            _PortableSettingsCard(support: portableSupport!),
            const SizedBox(height: 14),
          ],
          _UpdateSettingsCard(
            updatePlatform: updatePlatform,
            onCheckForUpdates: onCheckForUpdates,
          ),
          const SizedBox(height: 14),
          _FeedbackSettingsCard(
            feedbackService: feedbackService,
            updatePlatform: updatePlatform,
          ),
        ],
      ),
    );
  }
}

class _LanguageSettingsCard extends StatelessWidget {
  const _LanguageSettingsCard({required this.localeController});

  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.translate_rounded,
      title: context.l10n.tr('languageSection'),
      description: context.l10n.tr('languageDescription'),
      child: SizedBox(
        width: 205,
        child: DropdownButtonFormField<AppLanguage>(
          initialValue: localeController.language,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: AppLanguage.values
              .map(
                (language) => DropdownMenuItem(
                  value: language,
                  child: Text(
                    context.l10n.languageName(language.tag),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (language) {
            if (language != null) localeController.setLanguage(language);
          },
        ),
      ),
    );
  }
}

class _PortableSettingsCard extends StatelessWidget {
  const _PortableSettingsCard({required this.support});

  final WindowsPortableSupport support;

  Future<void> _toggle(BuildContext context, bool enabled) async {
    if (!enabled) {
      await support.configure(enabled: false);
      return;
    }
    if (support.rootPath == null) {
      await _chooseRoot(context, enableAfterSelection: true);
    } else {
      await support.configure(enabled: true);
    }
  }

  Future<void> _chooseRoot(
    BuildContext context, {
    bool enableAfterSelection = false,
  }) async {
    const options = FileDialogOptions(canCreateDirectories: false);
    final selected = await FileSelectorPlatform.instance
        .getDirectoryPathWithOptions(options);
    if (selected == null || !context.mounted) return;

    final settingsPath =
        '$selected${Platform.pathSeparator}UserData${Platform.pathSeparator}Settings.cfg';
    if (!File(settingsPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('portableInvalidPath'))),
      );
      return;
    }

    await support.configure(
      enabled: enableAfterSelection || support.enabled,
      rootPath: selected,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: support,
      builder: (context, _) => _SettingsCard(
        icon: Icons.usb_rounded,
        title: context.l10n.tr('portableSection'),
        description: context.l10n.tr('portableDescription'),
        child: SizedBox(
          width: 310,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                key: const ValueKey('portable-support-checkbox'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: support.enabled,
                onChanged: (value) {
                  if (value != null) _toggle(context, value);
                },
                title: Text(context.l10n.tr('portableEnable')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('portable-path-button'),
                onPressed: () => _chooseRoot(context),
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: Text(context.l10n.tr('portableChoosePath')),
              ),
              if (support.rootPath != null) ...[
                const SizedBox(height: 6),
                Text(
                  support.rootPath!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.klmColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.klmColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF7CA8FF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF658FE5), size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(color: colors.secondaryText, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          child,
        ],
      ),
    );
  }
}

class _ThemeSettingsCard extends StatelessWidget {
  const _ThemeSettingsCard({required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.contrast_rounded,
      title: context.l10n.tr('themeSection'),
      description: context.l10n.tr('themeDescription'),
      child: SizedBox(
        width: 205,
        child: DropdownButtonFormField<AppThemePreference>(
          initialValue: themeController.preference,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: AppThemePreference.values
              .map(
                (preference) => DropdownMenuItem(
                  value: preference,
                  child: Text(
                    context.l10n.tr('theme_${preference.name}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (preference) {
            if (preference != null) {
              themeController.setPreference(preference);
            }
          },
        ),
      ),
    );
  }
}

class _UpdateSettingsCard extends StatefulWidget {
  const _UpdateSettingsCard({
    required this.updatePlatform,
    required this.onCheckForUpdates,
  });

  final AppUpdatePlatform updatePlatform;
  final Future<void> Function() onCheckForUpdates;

  @override
  State<_UpdateSettingsCard> createState() => _UpdateSettingsCardState();
}

class _UpdateSettingsCardState extends State<_UpdateSettingsCard> {
  AppUpdateInfo? _info;
  bool _loading = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await widget.updatePlatform.getInfo();
      if (mounted) setState(() => _info = info);
    } catch (_) {
      // A missing native adapter is represented as an unavailable updater.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checking = true);
    try {
      await widget.onCheckForUpdates();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = _info?.currentVersion ?? '';
    final configured = _info?.configured ?? false;
    final description = version.isEmpty
        ? context.l10n.tr('updatesDescription')
        : context.l10n.format('updatesDescriptionWithVersion', {
            'version': version,
          });

    return _SettingsCard(
      icon: Icons.system_update_alt_rounded,
      title: context.l10n.tr('updatesSection'),
      description: description,
      child: SizedBox(
        width: 205,
        child: OutlinedButton.icon(
          onPressed: _loading || _checking || !configured
              ? null
              : _checkForUpdates,
          icon: _checking
              ? const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: Text(context.l10n.tr('checkForUpdates')),
        ),
      ),
    );
  }
}

class _FeedbackSettingsCard extends StatefulWidget {
  const _FeedbackSettingsCard({
    required this.feedbackService,
    required this.updatePlatform,
  });

  final FeedbackService feedbackService;
  final AppUpdatePlatform updatePlatform;

  @override
  State<_FeedbackSettingsCard> createState() => _FeedbackSettingsCardState();
}

class _FeedbackSettingsCardState extends State<_FeedbackSettingsCard> {
  bool _submitting = false;

  Future<void> _openFeedbackDialog() async {
    final draft = await showDialog<_FeedbackDraft>(
      context: context,
      builder: (_) => const _FeedbackDialog(),
    );
    if (draft == null || !mounted) return;

    final locale = Localizations.localeOf(context);
    final localeTag = locale.countryCode == null
        ? locale.languageCode
        : '${locale.languageCode}_${locale.countryCode}';

    setState(() => _submitting = true);
    try {
      String? appVersion;
      if (draft.includeTechnicalInfo) {
        try {
          appVersion = (await widget.updatePlatform.getInfo()).currentVersion;
        } catch (_) {
          // Technical metadata is optional and should not block feedback.
        }
      }

      await widget.feedbackService.submit(
        FeedbackSubmission(
          type: draft.type,
          message: draft.message,
          email: draft.email,
          appVersion: appVersion,
          platform: draft.includeTechnicalInfo
              ? Platform.operatingSystem
              : null,
          locale: draft.includeTechnicalInfo ? localeTag : null,
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('feedbackSent'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('feedbackFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.feedback_outlined,
      title: context.l10n.tr('feedbackSection'),
      description: context.l10n.tr('feedbackDescription'),
      child: SizedBox(
        width: 205,
        child: OutlinedButton.icon(
          key: const ValueKey('open-feedback-button'),
          onPressed: _submitting ? null : _openFeedbackDialog,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.feedback_outlined, size: 18),
          label: Text(context.l10n.tr('sendFeedback')),
        ),
      ),
    );
  }
}

class _FeedbackDraft {
  const _FeedbackDraft({
    required this.type,
    required this.message,
    required this.email,
    required this.includeTechnicalInfo,
  });

  final String type;
  final String message;
  final String? email;
  final bool includeTechnicalInfo;
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _messageController = TextEditingController();
  final _emailController = TextEditingController();
  String _type = 'suggestion';
  bool _includeTechnicalInfo = false;
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    final message = _messageController.text.trim();
    if (message.length < 3) {
      setState(() => _error = context.l10n.tr('feedbackMissingMessage'));
      return;
    }

    Navigator.pop(
      context,
      _FeedbackDraft(
        type: _type,
        message: message,
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        includeTechnicalInfo: _includeTechnicalInfo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('feedback-dialog'),
      title: Text(context.l10n.tr('feedbackDialogTitle')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: context.l10n.tr('feedbackType'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'bug',
                    child: Text(context.l10n.tr('feedbackTypeBug')),
                  ),
                  DropdownMenuItem(
                    value: 'suggestion',
                    child: Text(context.l10n.tr('feedbackTypeSuggestion')),
                  ),
                  DropdownMenuItem(
                    value: 'question',
                    child: Text(context.l10n.tr('feedbackTypeQuestion')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                autofocus: true,
                maxLines: 7,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: context.l10n.tr('feedbackMessage'),
                  hintText: context.l10n.tr('feedbackMessageHint'),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: context.l10n.tr('feedbackEmailOptional'),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeTechnicalInfo,
                onChanged: (value) =>
                    setState(() => _includeTechnicalInfo = value ?? false),
                title: Text(context.l10n.tr('feedbackIncludeTechnicalInfo')),
                subtitle: Text(
                  context.l10n.tr('feedbackTechnicalInfoDescription'),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.tr('cancel')),
        ),
        FilledButton(
          key: const ValueKey('submit-feedback'),
          onPressed: _submit,
          child: Text(context.l10n.tr('submitFeedback')),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.klmColors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: colors.mutedIcon),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondaryText, height: 1.4),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
