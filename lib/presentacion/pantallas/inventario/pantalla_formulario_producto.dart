import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/constantes/textos_app.dart';
import '../../../datos/modelos/producto.dart';
import '../../../presentacion/proveedores/proveedor_producto.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final Producto? producto;

  const ProductFormScreen({super.key, this.producto});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _minStockCtrl;

  Uint8List? _pickedImageBytes;
  String? _pickedImageExtension;
  String? _existingImageUrl;
  bool _isLoading = false;
  CatalogoProducto _catalog = CatalogoProducto.distribuidora;

  bool get _isEditing => widget.producto != null;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    _nameCtrl = TextEditingController(text: p?.nombre ?? '');
    _descCtrl = TextEditingController(text: p?.descripcion ?? '');
    _unitCtrl = TextEditingController(text: p?.unidad ?? 'unidad');
    _priceCtrl = TextEditingController(
      text: p != null ? p.precio.toStringAsFixed(2) : '',
    );
    _stockCtrl = TextEditingController(
      text: p != null ? p.stock.toString() : '',
    );
    _minStockCtrl = TextEditingController(
      text: p != null ? p.stockMinimo.toString() : '5',
    );
    _existingImageUrl = p?.urlImagen;
    _catalog = p?.catalogo ?? CatalogoProducto.distribuidora;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _descCtrl,
      _unitCtrl,
      _priceCtrl,
      _stockCtrl,
      _minStockCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';
      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageExtension = ext;
      });
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final optionWidth = constraints.maxWidth >= 360
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seleccionar imagen',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: optionWidth,
                        child: _SourceOption(
                          icon: Icons.photo_library_rounded,
                          label: 'Galeria',
                          onTap: () {
                            Navigator.pop(context);
                            _pickImage(ImageSource.gallery);
                          },
                        ),
                      ),
                      SizedBox(
                        width: optionWidth,
                        child: _SourceOption(
                          icon: Icons.camera_alt_rounded,
                          label: 'Cámara',
                          onTap: () {
                            Navigator.pop(context);
                            _pickImage(ImageSource.camera);
                          },
                        ),
                      ),
                    ],
                  ),
                    if (_pickedImageBytes != null || _existingImageUrl != null) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(
                        'Eliminar foto',
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _pickedImageBytes = null;
                          _pickedImageExtension = null;
                          _existingImageUrl = null;
                        });
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final repository = ref.read(proveedorServicioProducto);
      String? finalImageUrl = _existingImageUrl;

      if (_pickedImageBytes != null) {
        if (_existingImageUrl != null) {
          try {
            await repository.eliminarImagen(_existingImageUrl!);
          } catch (_) {}
        }
        finalImageUrl = await repository.subirImagen(
          _pickedImageBytes!,
          _pickedImageExtension ?? 'jpg',
        );
      } else if (_existingImageUrl == null &&
          widget.producto?.urlImagen != null) {
        try {
          await repository.eliminarImagen(widget.producto!.urlImagen!);
        } catch (_) {}
        finalImageUrl = null;
      }

      final json = {
        'nombre': _nameCtrl.text.trim(),
        'descripcion': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'unidad': _unitCtrl.text.trim(),
        'precio': double.parse(_priceCtrl.text.trim()),
        'stock': int.parse(_stockCtrl.text.trim()),
        'stock_minimo': int.parse(_minStockCtrl.text.trim()),
        'catalogo': _catalog.valor,
        'url_imagen': finalImageUrl,
      };

      final notifier = ref.read(proveedorNotificadorProducto.notifier);
      if (_isEditing) {
        await notifier.actualizarProducto(widget.producto!.id, json);
      } else {
        await notifier.crearProducto(json);
      }

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Producto actualizado' : 'Producto creado',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final mensaje = e.toString().contains('Bucket not found')
            ? 'No existe el bucket product-images en Supabase. Crea ese bucket para poder subir imágenes.'
            : 'Error: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensaje), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? AppStrings.editProduct : AppStrings.addProduct,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _showImageSourceDialog,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariantLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primary.withAlpha((0.4 * 255).toInt()),
                        width: 2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildImagePreview(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _showImageSourceDialog,
                  icon: const Icon(
                    Icons.add_a_photo_outlined,
                    size: 16,
                    color: AppColors.primaryLight,
                  ),
                  label: Text(
                    _pickedImageBytes != null || _existingImageUrl != null
                        ? 'Cambiar foto'
                        : 'Agregar foto',
                    style: GoogleFonts.inter(
                      color: AppColors.primaryLight,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle('Información del producto'),
              const SizedBox(height: 12),
              _buildField(
                controller: _nameCtrl,
                label: AppStrings.productName,
                icon: Icons.label_outline_rounded,
                validator: (v) =>
                    v!.trim().isEmpty ? 'El nombre es obligatorio' : null,
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _descCtrl,
                label: AppStrings.productDescription,
                icon: Icons.notes_rounded,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _unitCtrl,
                label: AppStrings.productUnit,
                icon: Icons.straighten_rounded,
                validator: (v) =>
                    v!.trim().isEmpty ? 'La unidad es obligatoria' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<CatalogoProducto>(
                initialValue: _catalog,
                dropdownColor: AppColors.surfaceLight,
                style: const TextStyle(color: AppColors.textPrimaryLight),
                decoration: const InputDecoration(
                  labelText: 'Catálogo',
                  prefixIcon: Icon(Icons.storefront_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: CatalogoProducto.distribuidora,
                    child: Text('Distribuidora'),
                  ),
                  DropdownMenuItem(
                    value: CatalogoProducto.vendedor,
                    child: Text('Vendedores'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _catalog = v);
                },
              ),
              const SizedBox(height: 20),
              _SectionTitle('Precio y Stock'),
              const SizedBox(height: 12),
              _buildField(
                controller: _priceCtrl,
                label: AppStrings.productPrice,
                icon: Icons.attach_money_rounded,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v!.isEmpty) return 'Requerido';
                  if (double.tryParse(v) == null) return 'Número inválido';
                  if (double.parse(v) < 0) return 'Debe ser >= 0';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stockField = _buildField(
                    controller: _stockCtrl,
                    label: AppStrings.stock,
                    icon: Icons.inventory_2_outlined,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v!.isEmpty) return 'Requerido';
                      if (int.tryParse(v) == null) return 'Número inválido';
                      if (int.parse(v) < 0) return 'Debe ser >= 0';
                      return null;
                    },
                  );

                  final minStockField = _buildField(
                    controller: _minStockCtrl,
                    label: AppStrings.minStock,
                    icon: Icons.warning_amber_rounded,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v!.isEmpty) return 'Requerido';
                      if (int.tryParse(v) == null) return 'Número inválido';
                      if (int.parse(v) < 0) return 'Debe ser >= 0';
                      return null;
                    },
                  );

                  if (constraints.maxWidth < 420) {
                    return Column(
                      children: [
                        stockField,
                        const SizedBox(height: 14),
                        minStockField,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: stockField),
                      const SizedBox(width: 12),
                      Expanded(child: minStockField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          AppStrings.save,
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_pickedImageBytes != null) {
      return Image.memory(_pickedImageBytes!, fit: BoxFit.cover);
    }
    if (_existingImageUrl != null) {
      return CachedNetworkImage(
        imageUrl: _existingImageUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryLight,
            strokeWidth: 2,
          ),
        ),
        errorWidget: (_, _, _) => _imagePlaceholder(),
      );
    }
    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(
        Icons.add_photo_alternate_outlined,
        color: AppColors.textHintLight,
        size: 36,
      ),
      const SizedBox(height: 6),
      Text(
        'Toca para agregar',
        style: GoogleFonts.inter(color: AppColors.textHintLight, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimaryLight),
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: validator,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.inter(
        color: AppColors.primaryLight,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariantLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primaryLight, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: AppColors.textPrimaryLight,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
