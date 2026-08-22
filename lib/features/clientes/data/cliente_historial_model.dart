import '../../ventas_credito/data/venta_credito_model.dart';
import '../../referidores/data/referidor_model.dart';

/// Una venta resumida para la lista de "compras recientes" de Detalle de
/// Cliente: no trae el detalle (líneas) completo, solo lo que se muestra en
/// esa lista -no hace falta más, y traer el detalle completo de las últimas
/// N ventas sería una consulta extra que no aporta nada acá-.
class VentaResumenCliente {
  final String id;
  final String numeroDocumento;
  final DateTime? fecha;
  final double monto;
  final String metodoPago;
  final String condicion;
  // true cuando esta venta se emparejó a este cliente solo por coincidencia
  // de nombre (ventas de antes del vínculo real por idCliente) — ver nota en
  // ClienteHistorialData.hayVentasEmparejadasPorNombre.
  final bool emparejadaPorNombre;

  VentaResumenCliente({
    required this.id,
    required this.numeroDocumento,
    required this.fecha,
    required this.monto,
    required this.metodoPago,
    required this.condicion,
    required this.emparejadaPorNombre,
  });
}

/// Una línea con código de color, para el historial de colores usados por
/// este cliente (más reciente primero).
class ColorHistorialItem {
  final DateTime? fecha;
  final String nombreProducto;
  final List<String> codigosColor;
  final String numeroDocumento;

  ColorHistorialItem({
    required this.fecha,
    required this.nombreProducto,
    required this.codigosColor,
    required this.numeroDocumento,
  });
}

/// Producto que más le ha comprado este cliente (por cantidad acumulada).
class ProductoTopCliente {
  final String nombreProducto;
  final double cantidad;

  ProductoTopCliente({required this.nombreProducto, required this.cantidad});
}

/// Todo el historial agregado de un cliente para la pantalla Detalle de
/// Cliente: un solo objeto inmutable armado con consultas disparadas en
/// paralelo (ver ClienteHistorialRepository.obtener), mismo patrón que
/// ReporteFinancieroData/reporte_financiero_repository.dart.
class ClienteHistorialData {
  // ---- Seguimiento de crédito ----
  final List<VentaCreditoModel> creditosAbiertos;
  // Puntualidad histórica de pago (créditos liquidados o no, con al menos un
  // abono registrado): cuántos abonos cayeron antes/en la fecha de
  // vencimiento de su crédito vs. cuántos cayeron después. null cuando este
  // cliente no tiene ningún abono registrado todavía (no hay nada que medir).
  final int? abonosATiempo;
  final int? abonosAtrasados;

  // ---- Resumen de compras ----
  final double totalComprado;
  final int cantidadCompras;
  final double ticketPromedio;
  final DateTime? primeraCompra;
  final DateTime? ultimaCompra;
  final List<VentaResumenCliente> ventasRecientes;
  final String? metodoPagoPreferido;

  // ---- Qué compra más ----
  final List<ProductoTopCliente> productosTop;

  // ---- Historial de códigos de color ----
  final List<ColorHistorialItem> historialColores;

  // true si alguna de las ventas de este historial se emparejó solo por
  // nombre (no por idCliente real) — ventas de antes de que existiera el
  // vínculo real. Dispara la nota de "puede no ser 100% exacto" en pantalla.
  final bool hayVentasEmparejadasPorNombre;

  // ---- Quién lo refirió (Fase 2) ----
  // null cuando el cliente no tiene idReferidor, o cuando lo tiene pero ese
  // referidor ya no existe (se borró el registro) -no debería pasar en uso
  // normal, pero una lectura fallida no debe romper toda la pantalla-.
  final ReferidorModel? referidor;

  ClienteHistorialData({
    required this.creditosAbiertos,
    required this.abonosATiempo,
    required this.abonosAtrasados,
    required this.totalComprado,
    required this.cantidadCompras,
    required this.ticketPromedio,
    required this.primeraCompra,
    required this.ultimaCompra,
    required this.ventasRecientes,
    required this.metodoPagoPreferido,
    required this.productosTop,
    required this.historialColores,
    required this.hayVentasEmparejadasPorNombre,
    required this.referidor,
  });

  bool get hayCreditoVencido => creditosAbiertos.any((c) => c.vencida);

  double get saldoVencidoTotal => creditosAbiertos.where((c) => c.vencida).fold<double>(0, (s, c) => s + c.saldoPendiente);

  double get saldoPendienteTotal => creditosAbiertos.fold<double>(0, (s, c) => s + c.saldoPendiente);
}
