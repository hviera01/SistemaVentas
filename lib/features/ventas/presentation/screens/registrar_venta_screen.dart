import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../data/venta_en_espera_model.dart';
import '../../data/venta_export_service.dart';
import '../../providers/carrito_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../../../negocio/data/negocio_model.dart';
import '../../../negocio/presentation/widgets/acceso_especial.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/providers/productos_provider.dart';
import '../../../categorias/providers/categorias_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../widgets/buscar_producto_dialog.dart';
import '../widgets/buscar_cliente_dialog.dart';
import '../widgets/reembase_dialog.dart';
import '../widgets/cobrar_dialog.dart';
import '../widgets/ventas_en_espera_dialog.dart';
import 'detalle_venta_screen.dart';

const _metodosPago = ['Efectivo', 'Tarjeta', 'Transferencia'];
const _tiposDocumento = {
  'Factura': 'Factura',
  'Boleta': 'Boleta',
  'Cotizacion': 'Cotización',
  'VentaSinFacturar': 'Venta Sin Facturar',
};

class RegistrarVentaScreen extends ConsumerStatefulWidget {
  const RegistrarVentaScreen({super.key});

  @override
  ConsumerState<RegistrarVentaScreen> createState() => _RegistrarVentaScreenState();
}

class _RegistrarVentaScreenState extends ConsumerState<RegistrarVentaScreen> {
  final _nombreClienteController = TextEditingController();
  final _documentoClienteController = TextEditingController();
  final _ocController = TextEditingController();
  final _regExoneradoController = TextEditingController();
  final _regSagController = TextEditingController();
  final _descuentoGlobalController = TextEditingController();
  bool _datosExpandidos = false;
  bool _precioCarritoConIsv = true;

  final _servicioExport = VentaExportService();
  bool _guardando = false;

  // Controladores para la edición inline (cantidad / precio / descuento) de
  // cada fila de la tabla de productos. Se reindexan cuando cambia el total
  // de filas (agregar/quitar producto).
  final Map<int, TextEditingController> _ctrlCantidad = {};
  final Map<int, TextEditingController> _ctrlPrecio = {};
  final Map<int, TextEditingController> _ctrlDescuento = {};
  int _conteoItemsControladores = -1;

  @override
  void dispose() {
    _nombreClienteController.dispose();
    _documentoClienteController.dispose();
    _ocController.dispose();
    _regExoneradoController.dispose();
    _regSagController.dispose();
    _descuentoGlobalController.dispose();
    for (final c in _ctrlCantidad.values) {
      c.dispose();
    }
    for (final c in _ctrlPrecio.values) {
      c.dispose();
    }
    for (final c in _ctrlDescuento.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<bool> _confirmarDialogo(String titulo, String mensaje) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titulo, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(mensaje, style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('No', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sí', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  // ---------- Cliente ----------

  Future<void> _buscarCliente() async {
    final cliente = await showDialog(context: context, builder: (context) => const BuscarClienteDialog());
    if (cliente == null) return;
    final documento = (cliente as dynamic).dni ?? '';
    final nombre = cliente.nombreCompleto ?? '';
    // Antes solo se actualizaba el nombre visible en el campo "Cliente": el
    // RTN/documento sí quedaba guardado en el carrito (se usaba al grabar la
    // venta), pero el campo "RTN / Documento" en pantalla no se refrescaba,
    // así que parecía que elegir un cliente solo traía el nombre.
    setState(() {
      _nombreClienteController.text = nombre;
      _documentoClienteController.text = documento;
    });
    ref.read(carritoVentaProvider.notifier).establecerCliente(documento: documento, nombre: nombre);
  }

  // ---------- Producto: agregar directo desde el buscador ----------

  /// Categorías como servicios o pintura preparada pueden marcarse para no
  /// controlar existencia: en ese caso la existencia en 0 (o negativa) no
  /// debe bloquear ni pedir clave especial, ni disparar el reembasado.
  bool _categoriaControlaStock(String idCategoria) {
    final categorias = ref.read(categoriasStreamProvider).value ?? [];
    final coincidencias = categorias.where((c) => c.id == idCategoria).toList();
    return coincidencias.isEmpty ? true : coincidencias.first.controlaStock;
  }

  /// Calcula, para un tipo de reembasado y una cantidad a vender, cuánto hay
  /// que descontar del producto base y la cantidad final que queda en la
  /// línea de venta. Compartido entre "agregar producto sin existencia" y
  /// "aumentar cantidad sin existencia suficiente".
  ({double cantidadReembasar, double cantidadFinal})? _calcularReembase(String tipo, double nuevaCantidad) {
    switch (tipo) {
      case 'GalonACuarto':
        return (cantidadReembasar: 0.25 * nuevaCantidad, cantidadFinal: nuevaCantidad);
      case 'CubetaACuarto':
        return (cantidadReembasar: 0.05 * nuevaCantidad, cantidadFinal: nuevaCantidad);
      case 'CubetaAGalon':
        return (cantidadReembasar: 0.2 * nuevaCantidad, cantidadFinal: nuevaCantidad);
      case 'GalonAMedioCuarto':
        if (nuevaCantidad == 0.5) {
          return (cantidadReembasar: 0.125, cantidadFinal: 1);
        }
        return (cantidadReembasar: 0.125 * nuevaCantidad, cantidadFinal: nuevaCantidad);
      default:
        return null;
    }
  }

  Future<void> _agregarProductoDesdeBusqueda() async {
    final resultado = await Navigator.of(context).push<ProductoConPrecio>(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => const BuscarProductoDialog()),
    );
    if (resultado == null || !mounted) return;
    final producto = resultado.producto;
    final carrito = ref.read(carritoVentaProvider);
    final sinExistencia = producto.stock <= 0 && _categoriaControlaStock(producto.idCategoria);

    if (sinExistencia && carrito.esCotizacion) {
      _mostrarMensaje('Advertencia: "${producto.nombre}" no tiene existencia disponible, pero se agregará a la cotización.');
    } else if (sinExistencia) {
      final quiereReembasar = await _confirmarDialogo(
        'Reembasado',
        'El producto "${producto.nombre}" no tiene existencia disponible.\n¿Desea realizar un reembasado?',
      );
      if (!mounted) return;
      if (quiereReembasar) {
        final resultadoReembase = await showDialog<ReembaseResultado>(context: context, builder: (context) => const ReembaseDialog());
        if (resultadoReembase == null || !mounted) return;

        final calculo = _calcularReembase(resultadoReembase.tipo, 1);
        if (calculo == null) {
          _mostrarMensaje('Opción de reembasado inválida');
          return;
        }
        final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
        final ok = await ref.read(productoRepositoryProvider).descontarStock(
              id: resultadoReembase.productoBase.id,
              cantidad: calculo.cantidadReembasar,
              usuario: usuario,
              motivo: 'Reembasado para venta de "${producto.nombre}"',
            );
        if (!mounted) return;
        if (!ok) {
          _mostrarMensaje('No se pudo descontar el stock del producto base');
          return;
        }
        ref.read(carritoVentaProvider.notifier).agregarProductoDirecto(producto, precioSeleccionado: resultado.precio, reembasado: true);
        return;
      }
      // Si dice que no, se ignora la falta de existencia y se agrega igual
      // (sin marcar reembasado): al vender no baja de 0 (ver venta_repository).
    }
    if (!mounted) return;
    ref.read(carritoVentaProvider.notifier).agregarProductoDirecto(producto, precioSeleccionado: resultado.precio);
  }

  void _quitarItem(int index) {
    ref.read(carritoVentaProvider.notifier).quitarItem(index);
  }

  // Cuando el usuario cancela o rechaza la operación (reembasado, opción
  // inválida, etc.) hay que devolver el campo de cantidad a su valor real;
  // si no, el texto tipeado se queda en el campo y el próximo toque afuera
  // (onTapOutside) vuelve a disparar la misma confirmación una y otra vez.
  void _revertirCantidad(int index) {
    final carrito = ref.read(carritoVentaProvider);
    if (index >= carrito.items.length) return;
    _ctrlCantidad[index]?.text = _formatoCantidad(carrito.items[index].cantidad);
  }

  Future<void> _actualizarCantidad(int index, double nuevaCantidad) async {
    if (nuevaCantidad <= 0) {
      _mostrarMensaje('La cantidad debe ser mayor a 0');
      _revertirCantidad(index);
      return;
    }
    final carrito = ref.read(carritoVentaProvider);
    if (index >= carrito.items.length) return;
    final item = carrito.items[index];

    if (!_categoriaControlaStock(item.idCategoria)) {
      ref.read(carritoVentaProvider.notifier).actualizarLinea(index, cantidad: nuevaCantidad);
      return;
    }

    final productos = ref.read(productosStreamProvider).value ?? [];
    final coincidencias = productos.where((p) => p.id == item.idProducto).toList();
    final stockDisponible = coincidencias.isNotEmpty ? coincidencias.first.stock : 0.0;

    if (stockDisponible < nuevaCantidad && !carrito.esCotizacion) {
      final quiereReembasar = await _confirmarDialogo(
        'Reembasado',
        'El producto "${item.nombreProducto}" no tiene suficiente stock para $nuevaCantidad unidad(es).\n¿Desea realizar un reembasado?',
      );
      if (!quiereReembasar) {
        _revertirCantidad(index);
        return;
      }
      if (!mounted) return;

      final resultado = await showDialog<ReembaseResultado>(context: context, builder: (context) => const ReembaseDialog());
      if (resultado == null) {
        _revertirCantidad(index);
        return;
      }

      final calculo = _calcularReembase(resultado.tipo, nuevaCantidad);
      if (calculo == null) {
        _mostrarMensaje('Opción de reembasado inválida');
        _revertirCantidad(index);
        return;
      }

      final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
      final ok = await ref.read(productoRepositoryProvider).descontarStock(
            id: resultado.productoBase.id,
            cantidad: calculo.cantidadReembasar,
            usuario: usuario,
            motivo: 'Reembasado para venta de "${item.nombreProducto}"',
          );
      if (!ok) {
        _mostrarMensaje('No se pudo descontar el stock del producto base');
        _revertirCantidad(index);
        return;
      }
      ref.read(carritoVentaProvider.notifier).actualizarLinea(index, cantidad: calculo.cantidadFinal, reembasado: true);
      return;
    } else if (stockDisponible < nuevaCantidad && carrito.esCotizacion) {
      _mostrarMensaje('Advertencia: "${item.nombreProducto}" no tiene stock suficiente, pero se actualizará en la cotización.');
    }

    ref.read(carritoVentaProvider.notifier).actualizarLinea(index, cantidad: nuevaCantidad);
  }

  Future<void> _actualizarPrecio(int index, double nuevoPrecioConIsv) async {
    if (nuevoPrecioConIsv < 0) {
      _mostrarMensaje('Precio inválido');
      return;
    }
    final autorizado = await verificarAccesoEspecial(context, ref, PermisosEspeciales.ventasCambiarPrecio);
    if (!mounted) return;
    if (!autorizado) {
      // Revierte el campo al precio actual (en la unidad que se esté
      // mostrando): el usuario ya había escrito el nuevo valor en el
      // TextField antes de que se pidiera la clave.
      final carrito = ref.read(carritoVentaProvider);
      if (index < carrito.items.length) {
        final precioBase = carrito.items[index].precioVenta;
        final valorMostrado = _precioCarritoConIsv ? redondearMoneda(precioBase * 1.15) : precioBase;
        _ctrlPrecio[index]?.text = valorMostrado.toStringAsFixed(2);
      }
      return;
    }
    ref.read(carritoVentaProvider.notifier).actualizarLinea(index, precioConIsv: nuevoPrecioConIsv);
  }

  Future<void> _actualizarPrecioSinIsv(int index, double nuevoPrecioSinIsv) {
    return _actualizarPrecio(index, redondearMoneda(nuevoPrecioSinIsv * 1.15));
  }

  void _alternarVistaPrecioCarrito(bool conIsv) {
    final carrito = ref.read(carritoVentaProvider);
    setState(() {
      _precioCarritoConIsv = conIsv;
      for (var i = 0; i < carrito.items.length; i++) {
        final ctrl = _ctrlPrecio[i];
        if (ctrl == null) continue;
        final base = carrito.items[i].precioVenta;
        final valor = conIsv ? redondearMoneda(base * 1.15) : base;
        ctrl.text = valor.toStringAsFixed(2);
      }
    });
  }

  void _actualizarDescuentoLinea(int index, double descuento) {
    if (descuento < 0 || descuento > 100) {
      _mostrarMensaje('El descuento debe estar entre 0 y 100');
      return;
    }
    ref.read(carritoVentaProvider.notifier).actualizarLinea(index, descuentoPorcentaje: descuento);
  }

  double _subtotalConIsv(dynamic item) {
    final precioConIsv = redondearMoneda(item.precioVenta * 1.15);
    return redondearMoneda(precioConIsv * item.cantidad * (1 - item.descuentoPorcentaje / 100));
  }

  double _subtotalSinIsv(dynamic item) {
    return redondearMoneda((item.precioVenta as double) * item.cantidad * (1 - item.descuentoPorcentaje / 100));
  }

  double _importeMostrado(dynamic item) => _precioCarritoConIsv ? _subtotalConIsv(item) : _subtotalSinIsv(item);

  // ---------- Ventas en espera ----------

  Future<void> _guardarEnEspera() async {
    final carrito = ref.read(carritoVentaProvider);
    if (carrito.items.isEmpty) {
      _mostrarMensaje('No hay productos para guardar en espera.');
      return;
    }
    final repo = ref.read(ventaRepositoryProvider);
    final sesion = VentaEnEsperaModel(
      id: carrito.idEnEspera ?? '',
      fecha: DateTime.now(),
      tipoDocumento: carrito.tipoDocumento,
      condicion: carrito.condicion,
      metodoPago: carrito.metodoPago,
      documentoCliente: carrito.documentoCliente,
      nombreCliente: _nombreClienteController.text.trim(),
      fechaVencimiento: carrito.fechaVencimiento,
      oc: carrito.oc,
      regExonerado: carrito.regExonerado,
      regSag: carrito.regSag,
      descuentoGlobal: carrito.descuentoGlobalPorcentaje,
      items: carrito.items,
    );

    if (carrito.idEnEspera != null) {
      await repo.actualizarVentaEnEspera(carrito.idEnEspera!, sesion);
      _mostrarMensaje('Venta en espera actualizada.');
    } else {
      await repo.guardarVentaEnEspera(sesion);
      _mostrarMensaje('Venta guardada en espera.');
    }
    _limpiarTodo();
  }

  Future<void> _verEnEspera() async {
    final sesion = await showDialog<VentaEnEsperaModel>(context: context, builder: (context) => const VentasEnEsperaDialog());
    if (sesion == null || !mounted) return;
    ref.read(carritoVentaProvider.notifier).cargarSesion(sesion);
    setState(() {
      _nombreClienteController.text = sesion.nombreCliente;
      _documentoClienteController.text = sesion.documentoCliente;
      _ocController.text = sesion.oc;
      _regExoneradoController.text = sesion.regExonerado;
      _regSagController.text = sesion.regSag;
      _descuentoGlobalController.text = sesion.descuentoGlobal == 0 ? '' : _formatoCantidad(sesion.descuentoGlobal);
    });
  }

  void _limpiarTodo() {
    ref.read(carritoVentaProvider.notifier).limpiar();
    _nombreClienteController.clear();
    _documentoClienteController.clear();
    _ocController.clear();
    _regExoneradoController.clear();
    _regSagController.clear();
    _descuentoGlobalController.clear();
    for (final c in _ctrlCantidad.values) {
      c.dispose();
    }
    for (final c in _ctrlPrecio.values) {
      c.dispose();
    }
    for (final c in _ctrlDescuento.values) {
      c.dispose();
    }
    _ctrlCantidad.clear();
    _ctrlPrecio.clear();
    _ctrlDescuento.clear();
    _conteoItemsControladores = 0;
  }

  Future<void> _confirmarLimpiar() async {
    final carrito = ref.read(carritoVentaProvider);
    final hayAlgoQuePerder = carrito.items.isNotEmpty || _nombreClienteController.text.trim().isNotEmpty;
    if (hayAlgoQuePerder) {
      final continuar = await _confirmarDialogo('Limpiar venta', '¿Seguro que querés borrar todos los productos y datos ingresados en esta venta?');
      if (!continuar) return;
    }
    _limpiarTodo();
  }

  // ---------- Confirmar venta ----------

  String get _textoBoton {
    final tipo = ref.watch(carritoVentaProvider).tipoDocumento;
    switch (tipo) {
      case 'Cotizacion':
        return 'Crear Cotización';
      case 'VentaSinFacturar':
        return 'Registrar Venta';
      default:
        return 'Crear Venta';
    }
  }

  Future<void> _confirmarVenta() async {
    final carrito = ref.read(carritoVentaProvider);
    if (carrito.items.isEmpty) {
      _mostrarMensaje('Debe ingresar productos en la venta');
      return;
    }

    var montoPago = 0.0;
    var montoCambio = 0.0;
    final esCotizacion = carrito.esCotizacion;

    setState(() => _guardando = true);
    try {
      if (!esCotizacion) {
        if (carrito.condicion == 'Credito') {
          montoPago = 0;
          montoCambio = 0;
        } else if (carrito.metodoPago == 'Efectivo') {
          final resultado = await showDialog<CobrarResultado>(context: context, builder: (context) => CobrarDialog(total: carrito.totalAPagar));
          if (resultado == null) return;
          montoPago = resultado.pagoCon;
          montoCambio = resultado.cambio;
        }

        final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
        if (!mounted) return;
        if (carrito.tipoDocumento == 'Factura' || carrito.tipoDocumento == 'Boleta') {
          final continuar = await _validarRangoYFecha(negocio, carrito.tipoDocumento);
          if (!continuar) return;
        }
      }

      final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
      final categorias = ref.read(categoriasStreamProvider).value ?? [];
      final categoriasSinControlStock = categorias.where((c) => !c.controlaStock).map((c) => c.id).toSet();
      final venta = await ref.read(ventaRepositoryProvider).registrarVenta(
            tipoDocumento: carrito.tipoDocumento,
            condicion: esCotizacion ? 'Contado' : carrito.condicion,
            metodoPago: esCotizacion ? 'N/A' : (carrito.condicion == 'Credito' ? 'N/A' : carrito.metodoPago),
            documentoCliente: carrito.documentoCliente.trim().isEmpty ? 'N/A' : carrito.documentoCliente.trim(),
            nombreCliente: _nombreClienteController.text.trim().isEmpty ? 'CONSUMIDOR FINAL' : _nombreClienteController.text.trim(),
            fechaRegistro: carrito.fecha,
            fechaVencimiento: (!esCotizacion && carrito.condicion == 'Credito') ? carrito.fechaVencimiento : null,
            oc: carrito.oc,
            regExonerado: carrito.regExonerado,
            regSag: carrito.regSag,
            descuentoGlobal: carrito.descuentoGlobalPorcentaje,
            items: carrito.items,
            montoPago: montoPago,
            montoCambio: montoCambio,
            subtotal: carrito.subtotal,
            impuesto: carrito.impuesto,
            totalAPagar: carrito.totalAPagar,
            usuario: usuario,
            categoriasSinControlStock: categoriasSinControlStock,
          );

      if (carrito.idEnEspera != null) {
        await ref.read(ventaRepositoryProvider).eliminarVentaEnEspera(carrito.idEnEspera!);
      }

      if (!mounted) return;

      final esFacturable = carrito.tipoDocumento == 'Factura' || carrito.tipoDocumento == 'Boleta';
      _limpiarTodo();

      if (esFacturable) {
        final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
        if (!mounted) return;
        final impresora = negocio.impresoraTermicaUrl.isEmpty ? null : Printer(url: negocio.impresoraTermicaUrl, name: negocio.impresoraTermicaNombre);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => PdfPreviewDialog(
            titulo: 'Vista previa · ${venta.numeroDocumento}',
            nombreArchivo: 'venta_${venta.numeroDocumento}.pdf',
            generarPdf: () => _servicioExport.generarPdfFactura(venta, negocio),
            impresora: impresora,
          ),
        );
      } else {
        _mostrarMensaje('${_tiposDocumento[venta.tipoDocumento]} generada: ${venta.numeroDocumento}');
      }
    } catch (e) {
      _mostrarMensaje(e is TimeoutException
          ? 'No se pudo guardar: se agotó el tiempo de espera. Revisá la conexión a internet e intentá de nuevo.'
          : 'Error al registrar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<bool> _validarRangoYFecha(NegocioModel negocio, String tipoDocumento) async {
    final rangoHasta = int.tryParse(negocio.rangoHasta) ?? 0;
    if (rangoHasta > 0) {
      final proximo = await ref.read(ventaRepositoryProvider).obtenerProximoCorrelativo(tipoDocumento);
      if (proximo > rangoHasta) {
        final continuar = await _confirmarDialogo(
          '¡Alerta!',
          'Se ha alcanzado el rango autorizado para las facturas. ¿Desea continuar con la venta?',
        );
        if (!continuar) return false;
      }
    }
    if (negocio.fechaLimiteEmision != null) {
      final hoy = DateTime.now();
      final limite = negocio.fechaLimiteEmision!;
      final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
      final limiteSinHora = DateTime(limite.year, limite.month, limite.day);
      if (!hoySinHora.isBefore(limiteSinHora)) {
        final continuar = await _confirmarDialogo(
          '¡Alerta!',
          'Se ha alcanzado la fecha límite de emisión. ¿Desea continuar con la venta?',
        );
        if (!continuar) return false;
      }
    }
    return true;
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final carrito = ref.watch(carritoVentaProvider);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 900;
          // La tabla de productos debe dominar la pantalla, pero se le da una
          // altura fija generosa (no Expanded) para que nunca desaparezca si
          // el encabezado ocupa más espacio del previsto; si el contenido no
          // cabe completo, la pantalla se vuelve desplazable en vez de
          // recortarse en silencio.
          final altoTabla = (constraints.maxHeight * 0.58).clamp(360.0, 1000.0);
          return SingleChildScrollView(
            padding: EdgeInsets.all(esMovil ? 14 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _encabezado(esMovil),
                const SizedBox(height: 14),
                _tarjetaDatosVenta(carrito, esMovil),
                const SizedBox(height: 14),
                esMovil
                    ? _tarjetaCarritoGrande(carrito, esMovil)
                    : SizedBox(height: altoTabla, child: _tarjetaCarritoGrande(carrito, esMovil)),
                const SizedBox(height: 14),
                _tarjetaTotales(carrito, esMovil),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _encabezado(bool esMovil) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Text('Registrar Venta', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
        OutlinedButton.icon(
          onPressed: _confirmarLimpiar,
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: Text('Limpiar Venta', style: GoogleFonts.poppins(fontSize: 13)),
          style: _estiloBotonSecundario(),
        ),
        OutlinedButton.icon(
          onPressed: _guardarEnEspera,
          icon: const Icon(Icons.pause_circle_outline, size: 18),
          label: Text('Guardar en Espera', style: GoogleFonts.poppins(fontSize: 13)),
          style: _estiloBotonSecundario(),
        ),
        OutlinedButton.icon(
          onPressed: _verEnEspera,
          icon: const Icon(Icons.list_alt_outlined, size: 18),
          label: Text('Ver en Espera', style: GoogleFonts.poppins(fontSize: 13)),
          style: _estiloBotonSecundario(),
        ),
        OutlinedButton.icon(
          onPressed: _verDetalleVenta,
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Text('Ver Detalle', style: GoogleFonts.poppins(fontSize: 13)),
          style: _estiloBotonSecundario(),
        ),
      ],
    );
  }

  void _verDetalleVenta() {
    Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => const DetalleVentaScreen()),
    );
  }

  ButtonStyle _estiloBotonSecundario() {
    return OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF1A1A1A),
      side: const BorderSide(color: Color(0xFFDCDFE6)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _tarjeta({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EC)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 12.5),
      filled: true,
      fillColor: const Color(0xFFF5F6FA),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _tarjetaDatosVenta(CarritoVentaState carrito, bool esMovil) {
    final formatoFecha = DateFormat('dd/MM/yyyy');

    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: esMovil ? double.infinity : 160,
                child: InkWell(
                  onTap: () async {
                    final fecha = await showDatePicker(context: context, initialDate: carrito.fecha, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (fecha != null) ref.read(carritoVentaProvider.notifier).establecerFecha(fecha);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 10),
                        Flexible(child: Text(formatoFecha.format(carrito.fecha), overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)))),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 190,
                child: DropdownButtonFormField<String>(
                  initialValue: carrito.tipoDocumento,
                  isExpanded: true,
                  decoration: _decoracion('Tipo de documento'),
                  style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                  items: _tiposDocumento.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(carritoVentaProvider.notifier).establecerTipoDocumento(v);
                  },
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 220,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nombreClienteController,
                        style: GoogleFonts.poppins(fontSize: 13),
                        decoration: _decoracion('Cliente').copyWith(
                          hintText: 'Vacío = Consumidor Final',
                          hintStyle: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade400),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _buscarCliente,
                      icon: const Icon(Icons.search),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFF5F6FA), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 180,
                child: TextField(
                  controller: _documentoClienteController,
                  style: GoogleFonts.poppins(fontSize: 13),
                  decoration: _decoracion('RTN / Documento'),
                  onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerDocumentoCliente(v),
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 150,
                child: DropdownButtonFormField<String>(
                  initialValue: carrito.condicion,
                  isExpanded: true,
                  decoration: _decoracion('Condición'),
                  style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                  items: const [
                    DropdownMenuItem(value: 'Contado', child: Text('Contado')),
                    DropdownMenuItem(value: 'Credito', child: Text('Crédito')),
                  ],
                  onChanged: carrito.esCotizacion
                      ? null
                      : (v) {
                          if (v == null) return;
                          ref.read(carritoVentaProvider.notifier).establecerCondicion(v);
                        },
                ),
              ),
              if (!carrito.esCotizacion && carrito.condicion != 'Credito')
                SizedBox(
                  width: esMovil ? double.infinity : 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: _metodosPago.contains(carrito.metodoPago) ? carrito.metodoPago : null,
                    isExpanded: true,
                    decoration: _decoracion('Método de pago'),
                    style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                    items: _metodosPago.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      ref.read(carritoVentaProvider.notifier).establecerMetodoPago(v);
                    },
                  ),
                ),
              InkWell(
                onTap: () => setState(() => _datosExpandidos = !_datosExpandidos),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _datosExpandidos ? 'Ver menos' : 'Más datos',
                        style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFFC62828)),
                      ),
                      Icon(_datosExpandidos ? Icons.expand_less : Icons.expand_more, size: 20, color: const Color(0xFFC62828)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: !_datosExpandidos
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: Colors.grey.shade200),
                        const SizedBox(height: 14),
                        Text('Descuento y campos fiscales de uso poco frecuente', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 14,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (carrito.esCredito && !carrito.esCotizacion)
                              SizedBox(
                                width: esMovil ? double.infinity : 160,
                                child: InkWell(
                                  onTap: () async {
                                    final fecha = await showDatePicker(
                                      context: context,
                                      initialDate: carrito.fechaVencimiento ?? DateTime.now().add(const Duration(days: 30)),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2100),
                                    );
                                    if (fecha != null) ref.read(carritoVentaProvider.notifier).establecerFechaVencimiento(fecha);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                    decoration: BoxDecoration(color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(12)),
                                    child: Row(
                                      children: [
                                        Icon(Icons.event_outlined, size: 16, color: Colors.grey.shade500),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: Text(
                                            'Vence: ${carrito.fechaVencimiento != null ? formatoFecha.format(carrito.fechaVencimiento!) : 'Sin definir'}',
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: esMovil ? double.infinity : 260,
                              child: TextField(
                                controller: _descuentoGlobalController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('Descuento global (%) sobre toda la venta'),
                                onChanged: (v) {
                                  final valor = double.tryParse(v.replaceAll(',', '').trim());
                                  if (valor == null || valor < 0 || valor > 100) return;
                                  ref.read(carritoVentaProvider.notifier).establecerDescuentoGlobal(valor);
                                },
                              ),
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 200,
                              child: TextField(
                                enabled: !carrito.esCotizacion,
                                controller: _ocController,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('No. O/C exenta'),
                                onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerOc(v),
                              ),
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 200,
                              child: TextField(
                                enabled: !carrito.esCotizacion,
                                controller: _regExoneradoController,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('No. Reg. exonerado'),
                                onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerRegExonerado(v),
                              ),
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 200,
                              child: TextField(
                                enabled: !carrito.esCotizacion,
                                controller: _regSagController,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('No. Reg. SAG'),
                                onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerRegSag(v),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaCarritoGrande(CarritoVentaState carrito, bool esMovil) {
    final productos = ref.watch(productosStreamProvider).value ?? [];
    final mapaProductos = {for (final p in productos) p.id: p};

    if (carrito.items.length != _conteoItemsControladores) {
      for (final c in _ctrlCantidad.values) {
        c.dispose();
      }
      for (final c in _ctrlPrecio.values) {
        c.dispose();
      }
      for (final c in _ctrlDescuento.values) {
        c.dispose();
      }
      _ctrlCantidad.clear();
      _ctrlPrecio.clear();
      _ctrlDescuento.clear();
      _conteoItemsControladores = carrito.items.length;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EC)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          esMovil
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Productos en la venta', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _agregarProductoDesdeBusqueda,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('Agregar Producto', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Text('Productos en la venta', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _agregarProductoDesdeBusqueda,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('Agregar Producto', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ],
                ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Precio unitario:', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 10),
              _selectorPrecioIsvCarrito(),
            ],
          ),
          const SizedBox(height: 14),
          if (!esMovil) ...[
            _encabezadoTablaCarrito(),
            Divider(height: 18, color: Colors.grey.shade300),
          ],
          if (carrito.items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Todavía no agregaste productos.\nUsá "Agregar Producto" para buscar del inventario.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.grey.shade500),
                ),
              ),
            )
          else if (esMovil)
            // En móvil no usamos una lista con scroll propio: la tabla del
            // carrito viviría dentro del SingleChildScrollView de toda la
            // pantalla, y dos scrolls verticales anidados hacen que, al
            // llegar al borde de este (el interno), ya no se pueda volver a
            // subir arrastrando "por fuera" porque no queda nada de esa
            // pantalla visible fuera de la tabla. Con una Column simple todo
            // el scroll lo maneja la pantalla completa.
            Column(
              children: [
                for (var i = 0; i < carrito.items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                  _filaCarritoMovil(i, carrito.items[i], mapaProductos),
                ],
              ],
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: carrito.items.length,
                separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, i) => _filaCarritoTabla(i, carrito.items[i], mapaProductos),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectorPrecioIsvCarrito() {
    Widget opcion(String texto, bool valor) {
      final activo = _precioCarritoConIsv == valor;
      return InkWell(
        onTap: () => _alternarVistaPrecioCarrito(valor),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: activo ? const Color(0xFFC62828) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            texto,
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF666A72)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCDFE6))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          opcion('Con ISV', true),
          opcion('Sin ISV', false),
        ],
      ),
    );
  }

  Widget _encabezadoTablaCarrito() {
    final estilo = GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600);
    return Row(
      children: [
        Expanded(flex: 2, child: Text('Código', style: estilo)),
        Expanded(flex: 4, child: Text('Descripción', style: estilo)),
        Expanded(flex: 2, child: Text('Cantidad', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text(_precioCarritoConIsv ? 'Precio (c/ISV)' : 'Precio (s/ISV)', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text('Descuento %', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text(_precioCarritoConIsv ? 'Importe (c/ISV)' : 'Importe (s/ISV)', textAlign: TextAlign.right, style: estilo)),
        const SizedBox(width: 40),
      ],
    );
  }

  // [valorActual] es el valor ya aplicado (el que tiene el item en el
  // carrito). Antes, este campo confirmaba en cada tecla (onChanged) y al
  // tocar fuera (onTapOutside) sin desenfocarse, lo que provocaba pedir la
  // clave especial (o el diálogo de reembasado) una y otra vez con
  // cualquier botón que se tocara: como el campo nunca perdía el foco,
  // *todo* toque fuera de él se interpretaba como "confirmar de nuevo".
  // Ahora solo se confirma al enviar o al salir del campo, se desenfoca
  // explícitamente, y si el valor no cambió respecto al ya aplicado no se
  // vuelve a llamar a alConfirmar.
  Widget _campoInlineNumero(TextEditingController controlador, double valorActual, void Function(double) alConfirmar, {String? sufijo}) {
    void confirmar() {
      final valor = double.tryParse(controlador.text.replaceAll(',', '').trim());
      if (valor == null || (valor - valorActual).abs() < 0.005) return;
      alConfirmar(valor);
    }

    return TextField(
      controller: controlador,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.poppins(fontSize: 13),
      decoration: InputDecoration(
        suffixText: sufijo,
        filled: true,
        fillColor: const Color(0xFFF5F6FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onSubmitted: (_) => confirmar(),
      onTapOutside: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
        confirmar();
      },
    );
  }

  Widget _campoInlineConEtiqueta(String etiqueta, TextEditingController controlador, double valorActual, void Function(double) alConfirmar) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        _campoInlineNumero(controlador, valorActual, alConfirmar),
      ],
    );
  }

  Widget _filaCarritoTabla(int index, dynamic item, Map<String, ProductoModel> mapaProductos) {
    final producto = mapaProductos[item.idProducto as String];
    final precioSinIsv = item.precioVenta as double;
    final precioMostrado = _precioCarritoConIsv ? redondearMoneda(precioSinIsv * 1.15) : precioSinIsv;
    final importe = _importeMostrado(item);

    final ctrlCantidad = _ctrlCantidad.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.cantidad as double)));
    final ctrlPrecio = _ctrlPrecio.putIfAbsent(index, () => TextEditingController(text: precioMostrado.toStringAsFixed(2)));
    final ctrlDescuento = _ctrlDescuento.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.descuentoPorcentaje as double)));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 2, child: Text(producto?.codigo ?? '-', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600))),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.nombreProducto as String, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                if (item.reembasado as bool) Text('Reembasado', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade400)),
              ],
            ),
          ),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoInlineNumero(ctrlCantidad, item.cantidad as double, (v) => _actualizarCantidad(index, v)))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoInlineNumero(ctrlPrecio, precioMostrado, (v) => _precioCarritoConIsv ? _actualizarPrecio(index, v) : _actualizarPrecioSinIsv(index, v)))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoInlineNumero(ctrlDescuento, item.descuentoPorcentaje as double, (v) => _actualizarDescuentoLinea(index, v), sufijo: '%'))),
          Expanded(flex: 2, child: Text(formatearMoneda(importe), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700))),
          SizedBox(
            width: 40,
            child: IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC62828)), onPressed: () => _quitarItem(index)),
          ),
        ],
      ),
    );
  }

  Widget _filaCarritoMovil(int index, dynamic item, Map<String, ProductoModel> mapaProductos) {
    final producto = mapaProductos[item.idProducto as String];
    final precioSinIsv = item.precioVenta as double;
    final precioMostrado = _precioCarritoConIsv ? redondearMoneda(precioSinIsv * 1.15) : precioSinIsv;
    final importe = _importeMostrado(item);

    final ctrlCantidad = _ctrlCantidad.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.cantidad as double)));
    final ctrlPrecio = _ctrlPrecio.putIfAbsent(index, () => TextEditingController(text: precioMostrado.toStringAsFixed(2)));
    final ctrlDescuento = _ctrlDescuento.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.descuentoPorcentaje as double)));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EC))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombreProducto as String, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('${producto?.codigo ?? '-'}${(item.reembasado as bool) ? ' · reembasado' : ''}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC62828)), onPressed: () => _quitarItem(index)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _campoInlineConEtiqueta('Cantidad', ctrlCantidad, item.cantidad as double, (v) => _actualizarCantidad(index, v))),
              const SizedBox(width: 8),
              Expanded(child: _campoInlineConEtiqueta(_precioCarritoConIsv ? 'Precio (c/ISV)' : 'Precio (s/ISV)', ctrlPrecio, precioMostrado, (v) => _precioCarritoConIsv ? _actualizarPrecio(index, v) : _actualizarPrecioSinIsv(index, v))),
              const SizedBox(width: 8),
              Expanded(child: _campoInlineConEtiqueta('Desc. %', ctrlDescuento, item.descuentoPorcentaje as double, (v) => _actualizarDescuentoLinea(index, v))),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Importe (${_precioCarritoConIsv ? 'c/ISV' : 's/ISV'}): ${formatearMoneda(importe)}', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  Widget _tarjetaTotales(CarritoVentaState carrito, bool esMovil) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _filaTotalTexto('Subtotal', carrito.subtotal),
              _filaTotalTexto('ISV (15%)', carrito.impuesto),
              if (carrito.descuentoGlobalPorcentaje > 0) _filaTotalTextoPorcentaje('Descuento global', carrito.descuentoGlobalPorcentaje),
              if (!carrito.esCotizacion && carrito.condicion != 'Credito' && carrito.metodoPago == 'Efectivo' && carrito.pagoCon > 0) ...[
                _filaTotalTexto('Paga con', carrito.pagoCon),
                _filaTotalTexto('Cambio', carrito.cambio),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(color: const Color(0xFFC62828), borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL A PAGAR', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(formatearMoneda(carrito.totalAPagar), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _guardando ? null : _confirmarVenta,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                  : Text(_textoBoton, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaTotalTexto(String etiqueta, double valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
        Text(formatearMoneda(valor), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
      ],
    );
  }

  Widget _filaTotalTextoPorcentaje(String etiqueta, double porcentaje) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
        Text('${_formatoCantidad(porcentaje)}%', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
      ],
    );
  }
}
