/// Un producto dentro de un ranking (más vendido, más comprado o más
/// rentable). El campo `monto` cambia de significado según el ranking en el
/// que aparezca (ingreso, costo o ganancia) — lo interpreta quien arma la
/// lista, no el modelo.
class RankingProducto {
  final String idProducto;
  final String nombreProducto;
  final double cantidad;
  final double monto;

  RankingProducto({required this.idProducto, required this.nombreProducto, required this.cantidad, required this.monto});
}

class ProductoSinVenta {
  final String idProducto;
  final String nombreProducto;
  final double stock;
  final double valorInventario;

  ProductoSinVenta({required this.idProducto, required this.nombreProducto, required this.stock, required this.valorInventario});
}

class VentasPorUsuario {
  final String usuario;
  final double totalVentas;
  final int cantidadTransacciones;

  VentasPorUsuario({required this.usuario, required this.totalVentas, required this.cantidadTransacciones});
}

/// Ganancia de una venta individual: para responder "qué tan rentable fue
/// esta venta puntual", no solo el agregado del periodo.
class GananciaPorVenta {
  final String idVenta;
  final String numeroDocumento;
  final DateTime? fecha;
  final String cliente;
  final double ventas;
  final double costo;

  GananciaPorVenta({required this.idVenta, required this.numeroDocumento, required this.fecha, required this.cliente, required this.ventas, required this.costo});

  double get ganancia => ventas - costo;
  double get margenPorcentaje => ventas <= 0 ? 0 : (ganancia / ventas) * 100;
}

class AbonoPorProveedor {
  final String proveedor;
  final double total;

  AbonoPorProveedor({required this.proveedor, required this.total});
}

/// Un mes de la serie de comparación (últimos 6 meses, terminando en el
/// actual).
class PuntoMensual {
  final DateTime mes;
  final double totalVentas;
  final double totalCompras;

  PuntoMensual({required this.mes, required this.totalVentas, required this.totalCompras});
}

class FlujoEfectivo {
  final double ingresosEfectivo;
  final double ingresosTarjeta;
  final double ingresosTransferencia;
  final double egresosEfectivo;
  final double egresosTransferencia;

  FlujoEfectivo({
    required this.ingresosEfectivo,
    required this.ingresosTarjeta,
    required this.ingresosTransferencia,
    required this.egresosEfectivo,
    required this.egresosTransferencia,
  });

  double get totalIngresos => ingresosEfectivo + ingresosTarjeta + ingresosTransferencia;
  double get totalEgresos => egresosEfectivo + egresosTransferencia;
  double get neto => totalIngresos - totalEgresos;
}

/// Sugerencias de cuánto destinar a pagos a proveedores sin comprometer el
/// flujo del negocio. Son referencias, no reglas — ver notas en la pantalla.
class RecomendacionPago {
  final double efectivoEstimado;
  final double reservaGastosFijos;
  final double sugeridoPorCaja;
  final double ingresoEfectivoCobrado;
  final double sugeridoPorVentas;

  RecomendacionPago({
    required this.efectivoEstimado,
    required this.reservaGastosFijos,
    required this.sugeridoPorCaja,
    required this.ingresoEfectivoCobrado,
    required this.sugeridoPorVentas,
  });
}

/// Balance general simplificado: no reemplaza un balance contable formal (no
/// hay partida doble, activos fijos ni capital aportado en el sistema). El
/// patrimonio es el residuo Activos − Pasivos, no una cuenta llevada aparte.
class BalanceGeneral {
  final double inventarioACosto;
  final double cuentasPorCobrar;
  final double efectivoEstimado;
  final double cuentasPorPagar;

  BalanceGeneral({
    required this.inventarioACosto,
    required this.cuentasPorCobrar,
    required this.efectivoEstimado,
    required this.cuentasPorPagar,
  });

  double get totalActivos => inventarioACosto + cuentasPorCobrar + efectivoEstimado;
  double get totalPasivos => cuentasPorPagar;
  double get patrimonio => totalActivos - totalPasivos;
}

/// Pronóstico simple de ventas para el próximo mes calendario, a partir de
/// la serie de los últimos 6 meses (`ReporteFinancieroData.serieMensual`).
/// Con 3 o más meses de datos usa una regresión lineal simple (mínimos
/// cuadrados); con menos, cae a un promedio móvil. No es Machine Learning
/// ni pretende serlo — es una proyección de referencia.
class PronosticoVentas {
  final double montoEstimado;
  final double promedioUltimosMeses;
  final double tendenciaMensual;
  final String metodo;

  PronosticoVentas({
    required this.montoEstimado,
    required this.promedioUltimosMeses,
    required this.tendenciaMensual,
    required this.metodo,
  });

  bool get tendenciaAlAlza => tendenciaMensual > 0;
}

/// Sugerencia de reposición: un producto activo cuyo stock, a la velocidad
/// de venta reciente que tuvo en el rango del reporte, se agotaría pronto.
/// Se pondera con el estado de cuenta del proveedor más reciente conocido
/// para ese producto: si ese proveedor tiene cuentas vencidas, se avisa en
/// vez de sugerir comprarle más sin más contexto.
class SugerenciaCompra {
  final String idProducto;
  final String nombreProducto;
  final double stockActual;
  final double ventaDiariaPromedio;
  final double diasParaAgotarse;
  final String? proveedor;
  final double deudaVencidaProveedor;
  final bool proveedorAlDia;

  SugerenciaCompra({
    required this.idProducto,
    required this.nombreProducto,
    required this.stockActual,
    required this.ventaDiariaPromedio,
    required this.diasParaAgotarse,
    required this.proveedor,
    required this.deudaVencidaProveedor,
    required this.proveedorAlDia,
  });
}

/// Un cliente dentro del ranking de mayores compradores del periodo.
class ClienteTop {
  final String cliente;
  final double totalComprado;
  final int cantidadCompras;

  ClienteTop({required this.cliente, required this.totalComprado, required this.cantidadCompras});

  double get ticketPromedio => cantidadCompras <= 0 ? 0 : totalComprado / cantidadCompras;
}

/// Ventas cuyo nombre de cliente se tipeó a mano pero no quedó vinculado a un
/// registro real (sin idCliente) — agrupadas por nombre normalizado, para
/// detectar compradores frecuentes que todavía no están registrados. Debería
/// ir bajando con el tiempo, ya que el auto-registro (CRM Fase 1, punto 2)
/// vincula las ventas nuevas solas.
class VentaSinCliente {
  final String nombre;
  final int cantidadVentas;
  final double totalComprado;

  VentaSinCliente({required this.nombre, required this.cantidadVentas, required this.totalComprado});
}

/// Un cliente activo que lleva más de 90 días sin comprar (o que nunca ha
/// comprado). [ultimaCompra]/[diasSinComprar] vienen null juntos cuando el
/// cliente nunca registró una compra -no hay "hace cuántos días" que calcular
/// en ese caso, pero igual cuenta como inactivo para efectos de seguimiento-.
class ClienteInactivo {
  final String nombreCompleto;
  final DateTime? ultimaCompra;
  final int? diasSinComprar;

  ClienteInactivo({required this.nombreCompleto, required this.ultimaCompra, required this.diasSinComprar});
}

/// Sección "Inteligencia de Negocios": analítica pensada para decisiones
/// (qué comprar, a quién priorizar, qué tan rentable es cada producto,
/// hacia dónde van las ventas). Se arma enteramente con datos que el resto
/// del Reporte Financiero ya pidió a Firestore — no dispara ninguna
/// consulta adicional.
class InteligenciaNegocioData {
  final PronosticoVentas pronosticoVentas;
  final List<SugerenciaCompra> sugerenciasCompra;
  final double rotacionInventario;
  final List<ClienteTop> clientesTop;
  final double ticketPromedio;
  final double valorStockMuerto;
  // Ventas a nombres no registrados (Fase 3 del CRM de clientes).
  final List<VentaSinCliente> ventasNoRegistradas;
  // Clientes activos con más de 90 días sin comprar (o que nunca compraron).
  final List<ClienteInactivo> clientesInactivos;

  InteligenciaNegocioData({
    required this.pronosticoVentas,
    required this.sugerenciasCompra,
    required this.rotacionInventario,
    required this.clientesTop,
    required this.ticketPromedio,
    required this.valorStockMuerto,
    required this.ventasNoRegistradas,
    required this.clientesInactivos,
  });
}

/// Resultado agregado completo del Reporte Financiero para un rango de
/// fechas. Se calcula una sola vez y lo consumen tanto la pantalla como el
/// PDF, para no recalcular ni arriesgar que muestren números distintos.
class ReporteFinancieroData {
  final DateTime inicio;
  final DateTime fin;

  final double ventasPeriodo;
  final double comprasPeriodo;
  final double costoVentas;
  final double utilidadBruta;
  final double gastosPeriodo;
  final double utilidadNeta;

  final FlujoEfectivo flujoEfectivo;
  final List<PuntoMensual> serieMensual;

  final List<RankingProducto> topVendidosPorCantidad;
  final List<RankingProducto> topCompradosPorCantidad;
  final List<RankingProducto> topGananciaPorProducto;
  final List<ProductoSinVenta> productosSinVenta;

  final List<GananciaPorVenta> gananciaPorVenta;
  final List<VentasPorUsuario> ventasPorUsuario;

  final double totalAbonosComprasCredito;
  final List<AbonoPorProveedor> abonosPorProveedor;

  final RecomendacionPago recomendacionPago;
  final BalanceGeneral balanceGeneral;
  final InteligenciaNegocioData inteligenciaNegocio;

  ReporteFinancieroData({
    required this.inicio,
    required this.fin,
    required this.ventasPeriodo,
    required this.comprasPeriodo,
    required this.costoVentas,
    required this.utilidadBruta,
    required this.gastosPeriodo,
    required this.utilidadNeta,
    required this.flujoEfectivo,
    required this.serieMensual,
    required this.gananciaPorVenta,
    required this.topVendidosPorCantidad,
    required this.topCompradosPorCantidad,
    required this.topGananciaPorProducto,
    required this.productosSinVenta,
    required this.ventasPorUsuario,
    required this.totalAbonosComprasCredito,
    required this.abonosPorProveedor,
    required this.recomendacionPago,
    required this.balanceGeneral,
    required this.inteligenciaNegocio,
  });

  double get margenBrutoPorcentaje => ventasPeriodo <= 0 ? 0 : (utilidadBruta / ventasPeriodo) * 100;
}
