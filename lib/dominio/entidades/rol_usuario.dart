enum RolUsuario {
  admin,
  vendedor,
  planta;

  static RolUsuario desdeTexto(String rol) {
    switch (rol.toLowerCase()) {
      case 'admin':
      case 'administrador':
        return RolUsuario.admin;
      case 'vendedor':
        return RolUsuario.vendedor;
      case 'planta':
        return RolUsuario.planta;
      default:
        throw Exception('Rol no reconocido: $rol');
    }
  }
}

class UsuarioApp {
  final String id;
  final String email;
  final String nombre;
  final RolUsuario rol;
  final String? vendedorId;
  final String? telefono;
  final String? urlAvatar;

  const UsuarioApp({
    required this.id,
    required this.email,
    required this.nombre,
    required this.rol,
    this.vendedorId,
    this.telefono,
    this.urlAvatar,
  });

  factory UsuarioApp.desdeJson(Map<String, dynamic> json) {
    return UsuarioApp(
      id: json['id'] as String,
      email: json['email'] as String,
      nombre: (json['name'] ?? json['nombre']) as String,
      rol: RolUsuario.desdeTexto((json['role'] ?? json['rol']) as String),
      vendedorId: (json['seller_id'] ?? json['vendedor_id']) as String?,
      telefono: (json['phone'] ?? json['telefono']) as String?,
      urlAvatar: (json['avatar_url'] ?? json['url_avatar']) as String?,
    );
  }

  Map<String, dynamic> aJson() {
    return {
      'id': id,
      'email': email,
      'name': nombre,
      'role': rol.name,
      if (vendedorId != null) 'seller_id': vendedorId,
      if (telefono != null) 'phone': telefono,
      if (urlAvatar != null) 'avatar_url': urlAvatar,
    };
  }

  UsuarioApp copiarCon({
    String? id,
    String? email,
    String? nombre,
    RolUsuario? rol,
    String? vendedorId,
    String? telefono,
    String? urlAvatar,
    bool limpiarVendedorId = false,
    bool limpiarTelefono = false,
    bool limpiarUrlAvatar = false,
  }) {
    return UsuarioApp(
      id: id ?? this.id,
      email: email ?? this.email,
      nombre: nombre ?? this.nombre,
      rol: rol ?? this.rol,
      vendedorId: limpiarVendedorId ? null : (vendedorId ?? this.vendedorId),
      telefono: limpiarTelefono ? null : (telefono ?? this.telefono),
      urlAvatar: limpiarUrlAvatar ? null : (urlAvatar ?? this.urlAvatar),
    );
  }
}
