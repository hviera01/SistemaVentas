import '../../productos/data/lote_costo_repository.dart';
import '../../productos/data/producto_model.dart';
import '../../productos/data/tinte_lookup.dart';
import 'item_venta_model.dart';

/// Un uso de colorante a costear: cuántas onzas de qué colorante -viene de
/// una fórmula conectada (Escenario A, ver CodigosColorDialog) o de una
/// carga manual (Escenario B).
class UsoTinte {
  final String colorante;
  final double onzas;
  const UsoTinte({required this.colorante, required this.onzas});
}

/// Resultado de costear un uso de tinte: onzas → cuartos, producto de
/// inventario cruzado (si existe) y su costo real (FIFO, con el estado de
/// lotes vigente en el momento de calcular). [producto] null significa que
/// no hay producto de inventario para ese colorante -no se pudo calcular
/// costo real ni se va a poder descontar stock para esa parte, pero no
/// rompe nada: [advertencia] lo explica para que el cajero lo vea-.
class ResultadoCostoTinte {
  final String colorante;
  final double onzas;
  final double cuartos;
  final ProductoModel? producto;
  final double costoUnitario;
  final double costoTotal;
  final String? advertencia;

  const ResultadoCostoTinte({
    required this.colorante,
    required this.onzas,
    required this.cuartos,
    required this.producto,
    required this.costoUnitario,
    required this.costoTotal,
    this.advertencia,
  });

  bool get resuelto => producto != null;

  TinteConsumidoSnapshot toSnapshot() => TinteConsumidoSnapshot(
    colorante: colorante,
    idProductoTinte: producto?.id ?? '',
    nombreProductoTinte: producto?.nombre ?? 'COLORANTE $colorante (sin producto en inventario)',
    cuartosConsumidos: cuartos,
    costoUnitario: costoUnitario,
    costoTotal: costoTotal,
  );
}

/// Motor de costeo de tinte compartido por los dos escenarios de venta
/// (fórmula conectada y carga manual, ver CodigosColorDialog) y por la
/// herramienta de consulta (ConsultarCostoScreen). Es de SOLO LECTURA -no
/// descuenta stock ni escribe nada en Firestore, solo consulta lotes-: da un
/// estimado con el costo FIFO vigente en este momento, que sirve para
/// mostrarle al cajero cuánto va a costar el tinte ANTES de confirmar la
/// venta. El costo real que se termina guardando es el que recalcula
/// VentaRepository.registrarVenta dentro de su propia transacción -mismo
/// criterio que ya usa hoy ItemVentaModel.precioCompraUsado con productos
/// normales-.
class CostoTinteService {
  final _lotes = LoteCostoRepository();

  static const onzasPorCuarto = 32.0;

  Future<List<ResultadoCostoTinte>> calcular(List<UsoTinte> usos) async {
    final resultados = <ResultadoCostoTinte>[];
    for (final uso in usos) {
      final colorante = normalizarColorante(uso.colorante);
      final cuartos = uso.onzas / onzasPorCuarto;
      final producto = await buscarProductoTinte(colorante);
      if (producto == null) {
        resultados.add(ResultadoCostoTinte(
          colorante: colorante,
          onzas: uso.onzas,
          cuartos: cuartos,
          producto: null,
          costoUnitario: 0,
          costoTotal: 0,
          advertencia: 'No hay un producto "COLORANTE $colorante" en el inventario -no se pudo calcular su costo ni se va a descontar stock para este tinte.',
        ));
        continue;
      }
      final queryLotes = await _lotes.consultarLotes(producto.id);
      final estado = _lotes.inicializarEstado(queryLotes);
      final costoUnitario = _lotes.consumir(estado, cuartos, costoFallback: producto.precioCompra);
      String? advertencia;
      if (producto.stock < cuartos) {
        advertencia =
            'El stock de ${producto.nombre} (${producto.stock.toStringAsFixed(2)} cuartos) es menor al que necesita esta línea (${cuartos.toStringAsFixed(2)} cuartos) -el costo es un estimado, el stock puede quedar en 0 al vender.';
      }
      resultados.add(ResultadoCostoTinte(
        colorante: colorante,
        onzas: uso.onzas,
        cuartos: cuartos,
        producto: producto,
        costoUnitario: costoUnitario,
        costoTotal: costoUnitario * cuartos,
        advertencia: advertencia,
      ));
    }
    return resultados;
  }
}
