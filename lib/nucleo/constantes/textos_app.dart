class AppStrings {
  AppStrings._();

  static const String appName = 'Agua Milena';
  static const String appSubtitle = 'Gestión de Ventas e Inventario';

  // Auth
  static const String login = 'Iniciar Sesión';
  static const String logout = 'Cerrar Sesión';
  static const String email = 'Correo Electrónico';
  static const String password = 'CONFIGURAR_LOCALMENTE';
  static const String loginError = 'Correo o contraseña incorrectos';
  static const String loginButton = 'Ingresar';

  // Navegación
  static const String navDashboard = 'Inicio';
  static const String navInventory = 'Inventario';
  static const String navSales = 'Ventas';
  static const String navAlerts = 'Alertas';

  // Inventario
  static const String products = 'Productos';
  static const String addProduct = 'Nuevo Producto';
  static const String editProduct = 'Editar Producto';
  static const String productName = 'Nombre del Producto';
  static const String productDescription = 'Descripción';
  static const String productUnit = 'Unidad (ej: unidad, caja)';
  static const String productPrice = 'Precio de Venta';
  static const String stock = 'Stock Actual';
  static const String minStock = 'Stock Mínimo';

  // Ventas
  static const String sales = 'Ventas';
  static const String newSale = 'Nueva Venta';
  static const String saleTotal = 'Total';
  static const String confirmSale = 'Confirmar Venta';
  static const String saleNotes = 'Notas (opcional)';

  // Alertas
  static const String alerts = 'Alertas Inteligentes';
  static const String thresholdAlert = 'Stock Bajo';
  static const String predictionAlert = 'Alerta Predictiva';
  static const String markAsRead = 'Marcar como leída';

  // Comunes
  static const String save = 'Guardar';
  static const String cancel = 'Cancelar';
  static const String delete = 'Eliminar';
  static const String edit = 'Editar';
  static const String search = 'Buscar...';
  static const String noData = 'Sin datos disponibles';
  static const String loading = 'Cargando...';
  static const String errorGeneric = 'Ocurrió un error. Intenta de nuevo.';
  static const String retry = 'Reintentar';
  static const String confirm = 'Confirmar';
  static const String deleteConfirm =
      '¿Estás seguro de que deseas eliminar este elemento?';
}
