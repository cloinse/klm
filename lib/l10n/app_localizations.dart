import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('pt', 'BR'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  String get _language => locale.languageCode;

  String tr(String key) {
    return _values[_language]?[key] ?? _values['en']![key] ?? key;
  }

  String format(String key, Map<String, Object> values) {
    var result = tr(key);
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }

  String get appTitle => tr('appTitle');
  String get library => tr('library');
  String get diagnostics => tr('diagnostics');
  String get activity => tr('activity');
  String get settings => tr('settings');
  String get refresh => tr('refresh');
  String get addLibrary => tr('addLibrary');
  String get total => tr('total');
  String get healthy => tr('healthy');
  String get needsAttention => tr('needsAttention');
  String get offline => tr('offline');
  String get all => tr('all');
  String get withWarnings => tr('withWarnings');
  String get sort => tr('sort');
  String get name => tr('name');
  String get status => tr('status');
  String get path => tr('path');
  String get retry => tr('retry');
  String inventorySummary(int count) =>
      format('inventorySummary', {'count': count});

  String minimumVersion(String version) =>
      format('issueKontakt6Incompatible', {'version': version});

  String languageName(String tag) => tr('language_$tag');

  String issueMessage(String code, String fallback, {String? version}) {
    if (code == 'kontakt6_incompatible' && version != null) {
      return minimumVersion(version);
    }
    final key = 'issue_$code';
    final translated = tr(key);
    return translated == key ? fallback : translated;
  }

  String diagnosticTitle(String code, String fallback) {
    final key = 'diagnostic_${code}_title';
    final translated = tr(key);
    return translated == key ? fallback : translated;
  }

  String diagnosticMessage(String code, String fallback, {String? detail}) {
    final key = 'diagnostic_${code}_message';
    final translated = tr(key);
    if (translated == key) return fallback;
    return detail == null ? translated : '$translated $detail';
  }

  String operationTitle(String code) => tr('operation_${code}_title');

  String operationDetail(String code, String detail, {int? count}) {
    if (code == 'inventory_updated' && count != null) {
      return inventorySummary(count);
    }
    return detail;
  }

  static const _values = <String, Map<String, String>>{
    'en': {
      'appTitle': 'Kontakt Library Manager',
      'library': 'Library',
      'diagnostics': 'Diagnostics',
      'activity': 'Activity',
      'settings': 'Settings',
      'inventoryTitle': 'Installed Libraries',
      'refresh': 'Reload',
      'addLibrary': 'Add library',
      'addMultipleLibraries': 'Add multiple libraries',
      'confirm': 'Confirm',
      'cancel': 'Cancel',
      'confirmAddTitle': 'Confirm registration',
      'confirmRepairTitle': 'Confirm repair',
      'confirmRelocateTitle': 'Confirm relocation',
      'confirmRemoveTitle': 'Remove library records?',
      'confirmAddMessage':
          'The following libraries will be registered for Kontakt:',
      'confirmRepairMessage':
          'The XML, preference, and installed_products records will be rebuilt.',
      'confirmRelocateMessage':
          'The registered content path will be changed to:',
      'confirmRemoveMessage':
          'The Service Center, preference, and installed_products records will be permanently removed.',
      'contentWillRemain':
          'Instruments, samples, and the library folder will not be deleted.',
      'candidateMismatch':
          'The selected folder belongs to a different library.',
      'alreadyRegistered':
          'This library is already registered. Use Repair instead.',
      'operationComplete': 'Operation completed successfully.',
      'helperApprovalTitle': 'Administrator approval required',
      'helperApprovalMessage':
          'The one-time administrator component is unavailable. Reinstall the application and retry the operation.',
      'helperUnsupportedMessage':
          'One-time administrator operations are unavailable on this system.',
      'close': 'Close',
      'inventoryReadError': 'The inventory could not be read',
      'retry': 'Retry',
      'noMatches': 'No matches found',
      'noLibraries': 'No libraries detected',
      'noMatchesMessage': 'Try another search or clear the filters.',
      'noLibrariesMessage':
          'Install a library with Native Access and refresh the inventory.',
      'helperPendingTitle': 'Administrator component unavailable',
      'helperPendingMessage':
          'The inventory remains available in safe read-only mode. Record changes use a bundled one-time component and never require background access.',
      'understood': 'Got it',
      'total': 'Total',
      'healthy': 'Healthy',
      'needsAttention': 'Needs attention',
      'offline': 'Offline',
      'searchHint': 'Search by name, path, or SNPID…',
      'all': 'All',
      'withWarnings': 'With warnings',
      'sort': 'Sort',
      'customOrder': 'Custom order',
      'dragToReorder': 'Drag to move this library',
      'saveChanges': 'Save changes',
      'classicOrderSaved': 'The classic Kontakt order was saved.',
      'classicOrderSaveFailed': 'The order could not be saved',
      'closeKontaktBeforeOrderSave':
          'Close Kontakt and any DAW using Kontakt before saving the order.',
      'name': 'Name',
      'status': 'Status',
      'path': 'Path',
      'unknownContentPath': 'Unknown content path',
      'actions': 'Actions',
      'showInFolder': 'Show in folder',
      'viewDiagnostics': 'View diagnostics',
      'repairRecords': 'Repair records',
      'relocateLibrary': 'Relocate library',
      'removeRecords': 'Remove records',
      'healthHealthy': 'Healthy',
      'healthIncomplete': 'Incomplete',
      'healthErrors': 'Errors found',
      'diagnosticsEyebrow': 'SYSTEM HEALTH',
      'diagnosticsTitle': 'Diagnostics',
      'diagnosticsSubtitle':
          'Incomplete records, missing paths, and duplicates.',
      'allGood': 'Everything looks good',
      'allGoodMessage': 'No inventory problems were detected.',
      'activityEyebrow': 'LOCAL LOG',
      'activityTitle': 'Activity',
      'activitySubtitle': 'Operations and errors from this session.',
      'noActivity': 'No activity yet',
      'noActivityMessage': 'Operations will appear here.',
      'settingsTitle': 'Settings',
      'languageSection': 'Interface language',
      'languageDescription': 'Changes are applied immediately and saved.',
      'language_en': 'English',
      'language_es': 'Spanish',
      'language_pt_BR': 'Portuguese (Brazil)',
      'themeSection': 'Appearance',
      'themeDescription': 'Choose the app theme or follow the system.',
      'theme_system': 'System',
      'theme_light': 'Light',
      'theme_dark': 'Dark',
      'updatesSection': 'Application updates',
      'updatesDescription': 'Updates are checked only while the app is open.',
      'updatesDescriptionWithVersion':
          'Version {version}. Updates are checked only while the app is open.',
      'checkForUpdates': 'Check for updates',
      'updateAvailable': 'Update available',
      'downloadAndInstall': 'Download and install',
      'updatesUnavailable': 'The update service is unavailable.',
      'inventorySummary': '{count} libraries detected.',
      'operation_inventory_updated_title': 'Inventory refreshed',
      'operation_inventory_error_title': 'Inventory error',
      'operation_folder_opened_title': 'Folder opened',
      'operation_folder_error_title': 'The folder could not be opened',
      'operation_library_added_title': 'Library added',
      'operation_library_repaired_title': 'Library repaired',
      'operation_library_relocated_title': 'Library relocated',
      'operation_library_removed_title': 'Library records removed',
      'operation_mutation_error_title': 'Operation failed',
      'operation_helper_enabled_title': 'Administrator component available',
      'operation_classic_order_saved_title': 'Classic order saved',
      'operation_classic_order_error_title': 'Classic order could not be saved',
      'issue_missing_service_center': 'The Service Center XML is missing.',
      'issue_missing_legacy_registration':
          'The registration required by Kontakt 6 is missing.',
      'issue_missing_installed_product': 'The Kontakt 7/8 manifest is missing.',
      'issue_missing_content_path': 'The content path could not be determined.',
      'issue_content_offline':
          'The path does not exist or the drive is disconnected.',
      'issue_duplicate_snpid': 'Another library uses the same SNPID.',
      'issue_duplicate_path': 'The path is assigned to more than one library.',
      'issueKontakt6Incompatible':
          'The metadata requires Kontakt {version} or later.',
      'diagnostic_service_center_missing_title': 'Service Center not found',
      'diagnostic_service_center_missing_message':
          'The shared Service Center folder does not exist.',
      'diagnostic_installed_products_missing_title': 'Modern catalog not found',
      'diagnostic_installed_products_missing_message':
          'installed_products for Kontakt 7/8 does not exist.',
      'diagnostic_invalid_json_title': 'Unreadable JSON',
      'diagnostic_invalid_json_message': 'A manifest could not be read.',
      'diagnostic_windows_registry_pending_title':
          'Windows Registry validation pending',
      'diagnostic_windows_registry_pending_message':
          'The inventory reads XML and JSON. Registry views will be enabled after validation on a Windows machine with Kontakt.',
      'diagnostic_unsupported_platform_title': 'Unsupported platform',
      'diagnostic_unsupported_platform_message':
          'Inventory is only available on macOS and Windows.',
    },
    'es': {
      'appTitle': 'Kontakt Library Manager',
      'library': 'Biblioteca',
      'diagnostics': 'Diagnóstico',
      'activity': 'Actividad',
      'settings': 'Ajustes',
      'inventoryTitle': 'Bibliotecas instaladas',
      'refresh': 'Recargar',
      'addLibrary': 'Agregar librería',
      'addMultipleLibraries': 'Agregar múltiples librerías',
      'confirm': 'Confirmar',
      'cancel': 'Cancelar',
      'confirmAddTitle': 'Confirmar registro',
      'confirmRepairTitle': 'Confirmar reparación',
      'confirmRelocateTitle': 'Confirmar reubicación',
      'confirmRemoveTitle': '¿Eliminar los registros de la librería?',
      'confirmAddMessage':
          'Las siguientes librerías se registrarán para Kontakt:',
      'confirmRepairMessage':
          'Se reconstruirán los registros XML, de preferencias e installed_products.',
      'confirmRelocateMessage':
          'La ruta de contenido registrada se cambiará a:',
      'confirmRemoveMessage':
          'Los registros de Service Center, preferencias e installed_products se eliminarán permanentemente.',
      'contentWillRemain':
          'Los instrumentos, samples y la carpeta de la librería no se eliminarán.',
      'candidateMismatch': 'La carpeta seleccionada pertenece a otra librería.',
      'alreadyRegistered':
          'Esta librería ya está registrada. Utiliza Reparar en su lugar.',
      'operationComplete': 'Operación completada correctamente.',
      'helperApprovalTitle': 'Se requiere aprobación administrativa',
      'helperApprovalMessage':
          'El componente de autorización administrativa puntual no está disponible. Reinstala la aplicación y vuelve a intentar la operación.',
      'helperUnsupportedMessage':
          'Las operaciones administrativas puntuales no están disponibles en este sistema.',
      'close': 'Cerrar',
      'inventoryReadError': 'No se pudo leer el inventario',
      'retry': 'Reintentar',
      'noMatches': 'No hay coincidencias',
      'noLibraries': 'No se detectaron librerías',
      'noMatchesMessage': 'Prueba con otra búsqueda o elimina los filtros.',
      'noLibrariesMessage':
          'Instala una librería con Native Access y actualiza el inventario.',
      'helperPendingTitle': 'Componente administrativo no disponible',
      'helperPendingMessage':
          'El inventario sigue disponible en modo seguro de lectura. Los cambios de registros utilizan un componente puntual incluido y nunca requieren acceso en segundo plano.',
      'understood': 'Entendido',
      'total': 'Total',
      'healthy': 'Sin problemas',
      'needsAttention': 'Requieren atención',
      'offline': 'Fuera de línea',
      'searchHint': 'Buscar por nombre, ruta o SNPID…',
      'all': 'Todas',
      'withWarnings': 'Con alertas',
      'sort': 'Ordenar',
      'customOrder': 'Orden personalizado',
      'dragToReorder': 'Arrastra para mover esta librería',
      'saveChanges': 'Guardar cambios',
      'classicOrderSaved': 'Se guardó el orden clásico de Kontakt.',
      'classicOrderSaveFailed': 'No se pudo guardar el orden',
      'closeKontaktBeforeOrderSave':
          'Cierra Kontakt y cualquier DAW que esté usando Kontakt antes de guardar el orden.',
      'name': 'Nombre',
      'status': 'Estado',
      'path': 'Ruta',
      'unknownContentPath': 'Ruta de contenido desconocida',
      'actions': 'Acciones',
      'showInFolder': 'Mostrar en carpeta',
      'viewDiagnostics': 'Ver diagnóstico',
      'repairRecords': 'Reparar registros',
      'relocateLibrary': 'Reubicar librería',
      'removeRecords': 'Eliminar registros',
      'healthHealthy': 'Correcta',
      'healthIncomplete': 'Incompleta',
      'healthErrors': 'Con errores',
      'diagnosticsEyebrow': 'SALUD DEL SISTEMA',
      'diagnosticsTitle': 'Diagnóstico',
      'diagnosticsSubtitle':
          'Registros incompletos, rutas perdidas y duplicados.',
      'allGood': 'Todo se ve bien',
      'allGoodMessage': 'No se detectaron problemas en el inventario.',
      'activityEyebrow': 'REGISTRO LOCAL',
      'activityTitle': 'Actividad',
      'activitySubtitle': 'Operaciones y errores de esta sesión.',
      'noActivity': 'Sin actividad',
      'noActivityMessage': 'Las operaciones aparecerán aquí.',
      'settingsTitle': 'Ajustes',
      'languageSection': 'Idioma de la interfaz',
      'languageDescription': 'Los cambios se aplican al instante y se guardan.',
      'language_en': 'Inglés',
      'language_es': 'Español',
      'language_pt_BR': 'Portugués (Brasil)',
      'themeSection': 'Apariencia',
      'themeDescription':
          'Elige el tema de la aplicación o usa el del sistema.',
      'theme_system': 'Sistema',
      'theme_light': 'Claro',
      'theme_dark': 'Oscuro',
      'updatesSection': 'Actualizaciones de la aplicación',
      'updatesDescription':
          'Las actualizaciones solo se comprueban mientras la aplicación está abierta.',
      'updatesDescriptionWithVersion':
          'Versión {version}. Las actualizaciones solo se comprueban mientras la aplicación está abierta.',
      'checkForUpdates': 'Buscar actualizaciones',
      'updateAvailable': 'Actualización disponible',
      'downloadAndInstall': 'Descargar e instalar',
      'updatesUnavailable':
          'El servicio de actualizaciones no está disponible.',
      'inventorySummary': '{count} librerías detectadas.',
      'operation_inventory_updated_title': 'Inventario actualizado',
      'operation_inventory_error_title': 'Error de inventario',
      'operation_folder_opened_title': 'Carpeta abierta',
      'operation_folder_error_title': 'No se pudo abrir la carpeta',
      'operation_library_added_title': 'Librería agregada',
      'operation_library_repaired_title': 'Librería reparada',
      'operation_library_relocated_title': 'Librería reubicada',
      'operation_library_removed_title': 'Registros de librería eliminados',
      'operation_mutation_error_title': 'La operación falló',
      'operation_helper_enabled_title': 'Componente administrativo disponible',
      'operation_classic_order_saved_title': 'Orden clásico guardado',
      'operation_classic_order_error_title':
          'No se pudo guardar el orden clásico',
      'issue_missing_service_center': 'Falta el XML de Service Center.',
      'issue_missing_legacy_registration':
          'Falta el registro requerido por Kontakt 6.',
      'issue_missing_installed_product': 'Falta el manifiesto de Kontakt 7/8.',
      'issue_missing_content_path':
          'No se pudo determinar la ruta del contenido.',
      'issue_content_offline':
          'La ruta no existe o el disco está desconectado.',
      'issue_duplicate_snpid': 'Otra librería utiliza el mismo SNPID.',
      'issue_duplicate_path': 'La ruta está asignada a más de una librería.',
      'issueKontakt6Incompatible':
          'La metadata requiere Kontakt {version} o posterior.',
      'diagnostic_service_center_missing_title': 'Service Center no encontrado',
      'diagnostic_service_center_missing_message':
          'No existe la carpeta compartida de Service Center.',
      'diagnostic_installed_products_missing_title':
          'Catálogo moderno no encontrado',
      'diagnostic_installed_products_missing_message':
          'No existe installed_products para Kontakt 7/8.',
      'diagnostic_invalid_json_title': 'JSON ilegible',
      'diagnostic_invalid_json_message':
          'No se pudo leer uno de los manifiestos.',
      'diagnostic_windows_registry_pending_title':
          'Validación del Registro de Windows pendiente',
      'diagnostic_windows_registry_pending_message':
          'El inventario lee XML y JSON. Las vistas del Registro se habilitarán después de validarlas en Windows con Kontakt.',
      'diagnostic_unsupported_platform_title': 'Plataforma no compatible',
      'diagnostic_unsupported_platform_message':
          'El inventario solo está disponible en macOS y Windows.',
    },
    'pt': {
      'appTitle': 'Kontakt Library Manager',
      'library': 'Biblioteca',
      'diagnostics': 'Diagnóstico',
      'activity': 'Atividade',
      'settings': 'Configurações',
      'inventoryTitle': 'Bibliotecas instaladas',
      'refresh': 'Recarregar',
      'addLibrary': 'Adicionar biblioteca',
      'addMultipleLibraries': 'Adicionar várias bibliotecas',
      'confirm': 'Confirmar',
      'cancel': 'Cancelar',
      'confirmAddTitle': 'Confirmar registro',
      'confirmRepairTitle': 'Confirmar reparo',
      'confirmRelocateTitle': 'Confirmar realocação',
      'confirmRemoveTitle': 'Remover os registros da biblioteca?',
      'confirmAddMessage':
          'As seguintes bibliotecas serão registradas para o Kontakt:',
      'confirmRepairMessage':
          'Os registros XML, de preferências e installed_products serão reconstruídos.',
      'confirmRelocateMessage':
          'O caminho de conteúdo registrado será alterado para:',
      'confirmRemoveMessage':
          'Os registros do Service Center, preferências e installed_products serão removidos permanentemente.',
      'contentWillRemain':
          'Os instrumentos, samples e a pasta da biblioteca não serão excluídos.',
      'candidateMismatch': 'A pasta selecionada pertence a outra biblioteca.',
      'alreadyRegistered': 'Esta biblioteca já está registrada. Use Reparar.',
      'operationComplete': 'Operação concluída com sucesso.',
      'helperApprovalTitle': 'Aprovação de administrador necessária',
      'helperApprovalMessage':
          'O componente de autorização administrativa pontual não está disponível. Reinstale o aplicativo e tente novamente.',
      'helperUnsupportedMessage':
          'As operações administrativas pontuais não estão disponíveis neste sistema.',
      'close': 'Fechar',
      'inventoryReadError': 'Não foi possível ler o inventário',
      'retry': 'Tentar novamente',
      'noMatches': 'Nenhum resultado encontrado',
      'noLibraries': 'Nenhuma biblioteca detectada',
      'noMatchesMessage': 'Tente outra busca ou remova os filtros.',
      'noLibrariesMessage':
          'Instale uma biblioteca com o Native Access e atualize o inventário.',
      'helperPendingTitle': 'Componente administrativo indisponível',
      'helperPendingMessage':
          'O inventário permanece disponível no modo seguro de somente leitura. As alterações de registros usam um componente pontual incluído e nunca exigem acesso em segundo plano.',
      'understood': 'Entendi',
      'total': 'Total',
      'healthy': 'Sem problemas',
      'needsAttention': 'Precisam de atenção',
      'offline': 'Offline',
      'searchHint': 'Buscar por nome, caminho ou SNPID…',
      'all': 'Todas',
      'withWarnings': 'Com alertas',
      'sort': 'Ordenar',
      'customOrder': 'Ordem personalizada',
      'dragToReorder': 'Arraste para mover esta biblioteca',
      'saveChanges': 'Salvar alterações',
      'classicOrderSaved': 'A ordem clássica do Kontakt foi salva.',
      'classicOrderSaveFailed': 'Não foi possível salvar a ordem',
      'closeKontaktBeforeOrderSave':
          'Feche o Kontakt e qualquer DAW que esteja usando o Kontakt antes de salvar a ordem.',
      'name': 'Nome',
      'status': 'Status',
      'path': 'Caminho',
      'unknownContentPath': 'Caminho do conteúdo desconhecido',
      'actions': 'Ações',
      'showInFolder': 'Mostrar na pasta',
      'viewDiagnostics': 'Ver diagnóstico',
      'repairRecords': 'Reparar registros',
      'relocateLibrary': 'Realocar biblioteca',
      'removeRecords': 'Remover registros',
      'healthHealthy': 'Correta',
      'healthIncomplete': 'Incompleta',
      'healthErrors': 'Com erros',
      'diagnosticsEyebrow': 'SAÚDE DO SISTEMA',
      'diagnosticsTitle': 'Diagnóstico',
      'diagnosticsSubtitle':
          'Registros incompletos, caminhos perdidos e duplicados.',
      'allGood': 'Tudo parece correto',
      'allGoodMessage': 'Nenhum problema foi detectado no inventário.',
      'activityEyebrow': 'REGISTRO LOCAL',
      'activityTitle': 'Atividade',
      'activitySubtitle': 'Operações e erros desta sessão.',
      'noActivity': 'Nenhuma atividade',
      'noActivityMessage': 'As operações aparecerão aqui.',
      'settingsTitle': 'Configurações',
      'languageSection': 'Idioma da interface',
      'languageDescription': 'As alterações são imediatas e ficam salvas.',
      'language_en': 'Inglês',
      'language_es': 'Espanhol',
      'language_pt_BR': 'Português (Brasil)',
      'themeSection': 'Aparência',
      'themeDescription': 'Escolha o tema do aplicativo ou use o do sistema.',
      'theme_system': 'Sistema',
      'theme_light': 'Claro',
      'theme_dark': 'Escuro',
      'updatesSection': 'Atualizações do aplicativo',
      'updatesDescription':
          'As atualizações são verificadas somente enquanto o aplicativo está aberto.',
      'updatesDescriptionWithVersion':
          'Versão {version}. As atualizações são verificadas somente enquanto o aplicativo está aberto.',
      'checkForUpdates': 'Buscar atualizações',
      'updateAvailable': 'Atualização disponível',
      'downloadAndInstall': 'Baixar e instalar',
      'updatesUnavailable': 'O serviço de atualizações não está disponível.',
      'inventorySummary': '{count} bibliotecas detectadas.',
      'operation_inventory_updated_title': 'Inventário atualizado',
      'operation_inventory_error_title': 'Erro no inventário',
      'operation_folder_opened_title': 'Pasta aberta',
      'operation_folder_error_title': 'Não foi possível abrir a pasta',
      'operation_library_added_title': 'Biblioteca adicionada',
      'operation_library_repaired_title': 'Biblioteca reparada',
      'operation_library_relocated_title': 'Biblioteca realocada',
      'operation_library_removed_title': 'Registros da biblioteca removidos',
      'operation_mutation_error_title': 'Falha na operação',
      'operation_helper_enabled_title': 'Componente administrativo disponível',
      'operation_classic_order_saved_title': 'Ordem clássica salva',
      'operation_classic_order_error_title':
          'Não foi possível salvar a ordem clássica',
      'issue_missing_service_center': 'O XML do Service Center está ausente.',
      'issue_missing_legacy_registration':
          'O registro exigido pelo Kontakt 6 está ausente.',
      'issue_missing_installed_product':
          'O manifesto do Kontakt 7/8 está ausente.',
      'issue_missing_content_path':
          'Não foi possível determinar o caminho do conteúdo.',
      'issue_content_offline':
          'O caminho não existe ou a unidade está desconectada.',
      'issue_duplicate_snpid': 'Outra biblioteca usa o mesmo SNPID.',
      'issue_duplicate_path':
          'O caminho está atribuído a mais de uma biblioteca.',
      'issueKontakt6Incompatible':
          'Os metadados exigem o Kontakt {version} ou posterior.',
      'diagnostic_service_center_missing_title':
          'Service Center não encontrado',
      'diagnostic_service_center_missing_message':
          'A pasta compartilhada do Service Center não existe.',
      'diagnostic_installed_products_missing_title':
          'Catálogo moderno não encontrado',
      'diagnostic_installed_products_missing_message':
          'installed_products do Kontakt 7/8 não existe.',
      'diagnostic_invalid_json_title': 'JSON ilegível',
      'diagnostic_invalid_json_message':
          'Não foi possível ler um dos manifestos.',
      'diagnostic_windows_registry_pending_title':
          'Validação do Registro do Windows pendente',
      'diagnostic_windows_registry_pending_message':
          'O inventário lê XML e JSON. As exibições do Registro serão ativadas após a validação no Windows com o Kontakt.',
      'diagnostic_unsupported_platform_title': 'Plataforma incompatível',
      'diagnostic_unsupported_platform_message':
          'O inventário está disponível apenas no macOS e Windows.',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
