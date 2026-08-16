import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('pt', 'BR'),
    Locale('zh'),
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

  String issueMessage(
    String code,
    String fallback, {
    String? version,
    int? visibility,
  }) {
    if (code == 'kontakt6_incompatible' && version != null) {
      return minimumVersion(version);
    }
    if (code == 'hidden_in_kontakt' && visibility != null) {
      return format('issue_hidden_in_kontakt', {'visibility': visibility});
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
      'confirmRemoveMultipleTitle': 'Remove {count} library records?',
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
      'removeSelected': 'Remove selected ({count})',
      'selectVisible': 'Select visible',
      'clearSelection': 'Clear selection',
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
      'language_zh': 'Chinese (Simplified)',
      'themeSection': 'Appearance',
      'themeDescription': 'Choose the app theme or follow the system.',
      'theme_system': 'System',
      'theme_light': 'Light',
      'theme_dark': 'Dark',
      'portableSection': 'Kontakt Portable',
      'portableDescription':
          'Use only the libraries registered by the selected portable copy.',
      'portableEnable': 'Use Kontakt Portable libraries',
      'portableChoosePath': 'Select portable folder',
      'portableInvalidPath':
          'The selected folder does not contain UserData/Settings.cfg.',
      'updatesSection': 'Application updates',
      'updatesDescription': 'Updates are checked only while the app is open.',
      'updatesDescriptionWithVersion':
          'Version {version}. Updates are checked only while the app is open.',
      'checkForUpdates': 'Check for updates',
      'updateAvailable': 'Update available',
      'updateAvailableMessage':
          'Kontakt Library Manager {version} is now available (you have {currentVersion}).',
      'releaseNotes': "What's new",
      'downloadAndInstall': 'Install update',
      'upToDate': "You're up to date!",
      'upToDateMessage':
          'Kontakt Library Manager {version} is currently the newest version available.',
      'updatesUnavailable': 'The update service is unavailable.',
      'feedbackSection': 'Feedback',
      'feedbackDescription':
          'Share a problem, suggestion, or question with the developer.',
      'sendFeedback': 'Send feedback',
      'feedbackDialogTitle': 'Send feedback',
      'feedbackType': 'Type',
      'feedbackTypeBug': 'Problem',
      'feedbackTypeSuggestion': 'Suggestion',
      'feedbackTypeQuestion': 'Question',
      'feedbackMessage': 'Message',
      'feedbackMessageHint': 'Tell us what happened or what you would improve.',
      'feedbackEmailOptional': 'Email (optional)',
      'feedbackIncludeTechnicalInfo': 'Include technical information',
      'feedbackTechnicalInfoDescription':
          'App version, platform, and language only.',
      'feedbackMissingMessage': 'Write a message before sending.',
      'submitFeedback': 'Send',
      'feedbackSent': 'Feedback sent successfully.',
      'feedbackFailed': 'The feedback could not be sent.',
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
      'issue_hidden_in_kontakt':
          'Kontakt is hiding this library (Visibility={visibility}). Repair its records to show it.',
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
      'confirmRemoveMultipleTitle':
          '¿Eliminar {count} registros de la librería?',
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
      'removeSelected': 'Eliminar seleccionadas ({count})',
      'selectVisible': 'Seleccionar visibles',
      'clearSelection': 'Limpiar selección',
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
      'language_zh': 'Chino (simplificado)',
      'themeSection': 'Apariencia',
      'themeDescription':
          'Elige el tema de la aplicación o usa el del sistema.',
      'theme_system': 'Sistema',
      'theme_light': 'Claro',
      'theme_dark': 'Oscuro',
      'portableSection': 'Kontakt Portable',
      'portableDescription':
          'Muestra únicamente las librerías registradas por la copia portable seleccionada.',
      'portableEnable': 'Usar las librerías de Kontakt Portable',
      'portableChoosePath': 'Seleccionar carpeta portable',
      'portableInvalidPath':
          'La carpeta seleccionada no contiene UserData/Settings.cfg.',
      'updatesSection': 'Actualizaciones de la aplicación',
      'updatesDescription':
          'Las actualizaciones solo se comprueban mientras la aplicación está abierta.',
      'updatesDescriptionWithVersion':
          'Versión {version}. Las actualizaciones solo se comprueban mientras la aplicación está abierta.',
      'checkForUpdates': 'Buscar actualizaciones',
      'updateAvailable': 'Actualización disponible',
      'updateAvailableMessage':
          'Kontakt Library Manager {version} ya está disponible (tienes la versión {currentVersion}).',
      'releaseNotes': 'Cambios de esta versión',
      'downloadAndInstall': 'Instalar actualización',
      'upToDate': '¡Estás al día!',
      'upToDateMessage':
          'Kontakt Library Manager {version} es actualmente la versión más reciente disponible.',
      'updatesUnavailable':
          'El servicio de actualizaciones no está disponible.',
      'feedbackSection': 'Comentarios',
      'feedbackDescription':
          'Comparte un problema, sugerencia o pregunta con el desarrollador.',
      'sendFeedback': 'Enviar comentarios',
      'feedbackDialogTitle': 'Enviar comentarios',
      'feedbackType': 'Tipo',
      'feedbackTypeBug': 'Problema',
      'feedbackTypeSuggestion': 'Sugerencia',
      'feedbackTypeQuestion': 'Pregunta',
      'feedbackMessage': 'Mensaje',
      'feedbackMessageHint': 'Cuéntanos qué ocurrió o qué mejorarías.',
      'feedbackEmailOptional': 'Correo electrónico (opcional)',
      'feedbackIncludeTechnicalInfo': 'Incluir información técnica',
      'feedbackTechnicalInfoDescription':
          'Solo la versión de la app, plataforma e idioma.',
      'feedbackMissingMessage': 'Escribe un mensaje antes de enviar.',
      'submitFeedback': 'Enviar',
      'feedbackSent': 'Los comentarios se enviaron correctamente.',
      'feedbackFailed': 'No se pudieron enviar los comentarios.',
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
      'issue_hidden_in_kontakt':
          'Kontakt está ocultando esta librería (Visibility={visibility}). Repara sus registros para mostrarla.',
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
      'confirmRemoveMultipleTitle': 'Remover {count} registros da biblioteca?',
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
      'removeSelected': 'Remover selecionadas ({count})',
      'selectVisible': 'Selecionar visíveis',
      'clearSelection': 'Limpar seleção',
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
      'language_zh': 'Chinês (simplificado)',
      'themeSection': 'Aparência',
      'themeDescription': 'Escolha o tema do aplicativo ou use o do sistema.',
      'theme_system': 'Sistema',
      'theme_light': 'Claro',
      'theme_dark': 'Escuro',
      'portableSection': 'Kontakt Portable',
      'portableDescription':
          'Mostra somente as bibliotecas registradas pela cópia portátil selecionada.',
      'portableEnable': 'Usar bibliotecas do Kontakt Portable',
      'portableChoosePath': 'Selecionar pasta portátil',
      'portableInvalidPath':
          'A pasta selecionada não contém UserData/Settings.cfg.',
      'updatesSection': 'Atualizações do aplicativo',
      'updatesDescription':
          'As atualizações são verificadas somente enquanto o aplicativo está aberto.',
      'updatesDescriptionWithVersion':
          'Versão {version}. As atualizações são verificadas somente enquanto o aplicativo está aberto.',
      'checkForUpdates': 'Buscar atualizações',
      'updateAvailable': 'Atualização disponível',
      'updateAvailableMessage':
          'Kontakt Library Manager {version} está disponível (você tem a versão {currentVersion}).',
      'releaseNotes': 'Novidades desta versão',
      'downloadAndInstall': 'Instalar atualização',
      'upToDate': 'Você está atualizado!',
      'upToDateMessage':
          'Kontakt Library Manager {version} é atualmente a versão mais recente disponível.',
      'updatesUnavailable': 'O serviço de atualizações não está disponível.',
      'feedbackSection': 'Feedback',
      'feedbackDescription':
          'Compartilhe um problema, sugestão ou pergunta com o desenvolvedor.',
      'sendFeedback': 'Enviar feedback',
      'feedbackDialogTitle': 'Enviar feedback',
      'feedbackType': 'Tipo',
      'feedbackTypeBug': 'Problema',
      'feedbackTypeSuggestion': 'Sugestão',
      'feedbackTypeQuestion': 'Pergunta',
      'feedbackMessage': 'Mensagem',
      'feedbackMessageHint': 'Conte o que aconteceu ou o que você melhoraria.',
      'feedbackEmailOptional': 'E-mail (opcional)',
      'feedbackIncludeTechnicalInfo': 'Incluir informações técnicas',
      'feedbackTechnicalInfoDescription':
          'Somente a versão do app, plataforma e idioma.',
      'feedbackMissingMessage': 'Escreva uma mensagem antes de enviar.',
      'submitFeedback': 'Enviar',
      'feedbackSent': 'Feedback enviado com sucesso.',
      'feedbackFailed': 'Não foi possível enviar o feedback.',
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
      'issue_hidden_in_kontakt':
          'O Kontakt está ocultando esta biblioteca (Visibility={visibility}). Repare os registros para mostrá-la.',
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
    'zh': {
      'appTitle': 'Kontakt Library Manager',
      'library': '音色库',
      'diagnostics': '诊断',
      'activity': '活动',
      'settings': '设置',
      'inventoryTitle': '已安装的音色库',
      'refresh': '刷新',
      'addLibrary': '添加音色库',
      'addMultipleLibraries': '添加多个音色库',
      'confirm': '确认',
      'cancel': '取消',
      'confirmAddTitle': '确认注册',
      'confirmRepairTitle': '确认修复',
      'confirmRelocateTitle': '确认移动',
      'confirmRemoveTitle': '删除音色库记录？',
      'confirmRemoveMultipleTitle': '删除 {count} 条音色库记录？',
      'confirmAddMessage': '以下音色库将注册到 Kontakt：',
      'confirmRepairMessage': '将重建 XML、偏好设置和 installed_products 记录。',
      'confirmRelocateMessage': '注册的内容路径将更改为：',
      'confirmRemoveMessage':
          'Service Center、偏好设置和 installed_products 记录将被永久删除。',
      'contentWillRemain': '乐器、采样和音色库文件夹不会被删除。',
      'candidateMismatch': '所选文件夹属于其他音色库。',
      'alreadyRegistered': '该音色库已注册。请改用修复。',
      'operationComplete': '操作已成功完成。',
      'removeSelected': '删除所选项（{count}）',
      'selectVisible': '选择当前列表',
      'clearSelection': '清除选择',
      'helperApprovalTitle': '需要管理员授权',
      'helperApprovalMessage': '一次性管理员组件不可用。请重新安装应用程序并重试该操作。',
      'helperUnsupportedMessage': '此系统不支持一次性管理员操作。',
      'close': '关闭',
      'inventoryReadError': '无法读取音色库清单',
      'retry': '重试',
      'noMatches': '未找到匹配项',
      'noLibraries': '未检测到音色库',
      'noMatchesMessage': '请尝试其他搜索或清除筛选条件。',
      'noLibrariesMessage': '请使用 Native Access 安装音色库并刷新清单。',
      'helperPendingTitle': '管理员组件不可用',
      'helperPendingMessage': '清单仍可在安全的只读模式下使用。记录更改使用随附的一次性组件，绝不要求后台访问。',
      'understood': '知道了',
      'total': '总计',
      'healthy': '正常',
      'needsAttention': '需要注意',
      'offline': '离线',
      'searchHint': '按名称、路径或 SNPID 搜索…',
      'all': '全部',
      'withWarnings': '有警告',
      'sort': '排序',
      'customOrder': '自定义顺序',
      'dragToReorder': '拖动以移动此音色库',
      'saveChanges': '保存更改',
      'classicOrderSaved': '经典 Kontakt 顺序已保存。',
      'classicOrderSaveFailed': '无法保存顺序',
      'closeKontaktBeforeOrderSave': '保存顺序前请关闭 Kontakt 及任何正在使用 Kontakt 的 DAW。',
      'name': '名称',
      'status': '状态',
      'path': '路径',
      'unknownContentPath': '未知内容路径',
      'actions': '操作',
      'showInFolder': '在文件夹中显示',
      'viewDiagnostics': '查看诊断',
      'repairRecords': '修复记录',
      'relocateLibrary': '移动音色库',
      'removeRecords': '删除记录',
      'healthHealthy': '正常',
      'healthIncomplete': '不完整',
      'healthErrors': '存在错误',
      'diagnosticsEyebrow': '系统健康',
      'diagnosticsTitle': '诊断',
      'diagnosticsSubtitle': '不完整的记录、丢失的路径和重复项。',
      'allGood': '一切正常',
      'allGoodMessage': '未检测到清单问题。',
      'activityEyebrow': '本地日志',
      'activityTitle': '活动',
      'activitySubtitle': '本次会话的操作和错误。',
      'noActivity': '暂无活动',
      'noActivityMessage': '操作将显示在此处。',
      'settingsTitle': '设置',
      'languageSection': '界面语言',
      'languageDescription': '更改立即生效并自动保存。',
      'language_en': '英语',
      'language_es': '西班牙语',
      'language_pt_BR': '葡萄牙语（巴西）',
      'language_zh': '简体中文',
      'themeSection': '外观',
      'themeDescription': '选择应用主题或跟随系统。',
      'theme_system': '系统',
      'theme_light': '浅色',
      'theme_dark': '深色',
      'portableSection': 'Kontakt 便携版',
      'portableDescription': '仅使用所选便携副本中注册的音色库。',
      'portableEnable': '使用 Kontakt 便携版音色库',
      'portableChoosePath': '选择便携版文件夹',
      'portableInvalidPath': '所选文件夹中未找到 UserData/Settings.cfg 文件。',
      'updatesSection': '应用更新',
      'updatesDescription': '仅在应用打开时检查更新。',
      'updatesDescriptionWithVersion': '版本 {version}。仅在应用打开时检查更新。',
      'checkForUpdates': '检查更新',
      'updateAvailable': '有可用更新',
      'updateAvailableMessage':
          'Kontakt Library Manager {version} 已可用（您当前的版本为 {currentVersion}）。',
      'releaseNotes': '更新内容',
      'downloadAndInstall': '安装更新',
      'upToDate': '您已是最新版本！',
      'upToDateMessage': 'Kontakt Library Manager {version} 是目前可用的最新版本。',
      'updatesUnavailable': '更新服务不可用。',
      'feedbackSection': '反馈',
      'feedbackDescription': '向开发者分享问题、建议或疑问。',
      'sendFeedback': '发送反馈',
      'feedbackDialogTitle': '发送反馈',
      'feedbackType': '类型',
      'feedbackTypeBug': '问题',
      'feedbackTypeSuggestion': '建议',
      'feedbackTypeQuestion': '疑问',
      'feedbackMessage': '消息',
      'feedbackMessageHint': '告诉我们发生了什么或您希望改进的地方。',
      'feedbackEmailOptional': '电子邮件（可选）',
      'feedbackIncludeTechnicalInfo': '包含技术信息',
      'feedbackTechnicalInfoDescription': '仅包含应用版本、平台和语言。',
      'feedbackMissingMessage': '发送前请先输入消息。',
      'submitFeedback': '发送',
      'feedbackSent': '反馈发送成功。',
      'feedbackFailed': '无法发送反馈。',
      'inventorySummary': '检测到 {count} 个音色库。',
      'operation_inventory_updated_title': '清单已刷新',
      'operation_inventory_error_title': '清单错误',
      'operation_folder_opened_title': '已打开文件夹',
      'operation_folder_error_title': '无法打开文件夹',
      'operation_library_added_title': '已添加音色库',
      'operation_library_repaired_title': '已修复音色库',
      'operation_library_relocated_title': '已移动音色库',
      'operation_library_removed_title': '已删除音色库记录',
      'operation_mutation_error_title': '操作失败',
      'operation_helper_enabled_title': '管理员组件可用',
      'operation_classic_order_saved_title': '已保存经典顺序',
      'operation_classic_order_error_title': '无法保存经典顺序',
      'issue_missing_service_center': '缺少 Service Center XML。',
      'issue_missing_legacy_registration': '缺少 Kontakt 6 所需的注册。',
      'issue_missing_installed_product': '缺少 Kontakt 7/8 清单。',
      'issue_hidden_in_kontakt':
          'Kontakt 正在隐藏此音色库（可见性={visibility}）。请修复其记录以显示它。',
      'issue_missing_content_path': '无法确定内容路径。',
      'issue_content_offline': '路径不存在或磁盘已断开连接。',
      'issue_duplicate_snpid': '另一个音色库使用相同的 SNPID。',
      'issue_duplicate_path': '该路径分配给了多个音色库。',
      'issueKontakt6Incompatible': '元数据要求 Kontakt {version} 或更高版本。',
      'diagnostic_service_center_missing_title': '未找到 Service Center',
      'diagnostic_service_center_missing_message': '共享的 Service Center 文件夹不存在。',
      'diagnostic_installed_products_missing_title': '未找到现代目录',
      'diagnostic_installed_products_missing_message':
          'Kontakt 7/8 的 installed_products 不存在。',
      'diagnostic_invalid_json_title': '无法读取 JSON',
      'diagnostic_invalid_json_message': '无法读取某个清单。',
      'diagnostic_windows_registry_pending_title': '待验证 Windows 注册表',
      'diagnostic_windows_registry_pending_message':
          '清单读取 XML 和 JSON。在装有 Kontakt 的 Windows 机器上验证后，注册表视图将被启用。',
      'diagnostic_unsupported_platform_title': '不支持的平台',
      'diagnostic_unsupported_platform_message': '清单仅在 macOS 和 Windows 上可用。',
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
