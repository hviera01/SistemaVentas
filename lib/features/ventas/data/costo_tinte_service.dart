import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// Producto de tinte ya conocido -ej. el cajero ya lo eligió de un
  /// dropdown, ver AgregarTinteManualDialog y ConsultarCostoScreen-: si se
  /// pasa, [calcular] se salta la consulta a Firestore por nombre
  /// (buscarProductoTinte). Sin esto, esa consulta se repetía en CADA
  /// recálculo mientras el cajero seguía escribiendo la cantidad -una idea y
  /// vuelta a Firestore por dígito tecleado, redundante porque ya se tenía
  /// el producto exacto a mano- y era la causa real de que esos diálogos se
  /// sintieran lentos ("las rueditas"), no la falta de Future.wait (eso ya
  /// estaba resuelto acá abajo para el caso de fórmula con varios
  /// colorantes).
  final ProductoModel? productoConocido;

  const UsoTinte({required this.colorante, required this.onzas, this.productoConocido});
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

  TinteConsumidoSnapshot toSnapshot({String? codigoOrigen}) => TinteConsumidoSnapshot(
    colorante: colorante,
    idProductoTinte: producto?.id ?? '',
    nombreProductoTinte: producto?.nombre ?? 'COLORANTE $colorante (sin producto en inventario)',
    cuartosConsumidos: cuartos,
    costoUnitario: costoUnitario,
    costoTotal: costoTotal,
    codigoOrigen: codigoOrigen,
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

  // Calibrado contra la máquina real del dueño (no el estándar de 32 oz por
  // cuarto que se había asumido al inicio): probó llenar un cuarto y a 32Y
  // quedaba un poquito corto, a 34Y se pasaba un poquito -33Y es el punto
  // medio de esa prueba real, ajustable más adelante si se afina la medición.
  static const onzasPorCuarto = 33.0;

  /// Antes esto hacía, POR CADA colorante y en SECUENCIA (un `for` con dos
  /// `await` adentro), una consulta a `productos` (buscarProductoTinte) y
  /// luego, si encontraba producto, otra a su subcolección `lotes`
  /// (consultarLotes) -una fórmula de 3-4 colorantes disparaba hasta 8 idas y
  /// vueltas a Firestore UNA DETRÁS DE OTRA antes de poder mostrar el costo,
  /// que es la demora real que reportó el dueño al elegir una fórmula (el
  /// buscador en sí, sobre el JSON ya cacheado en memoria por
  /// formulasColortrendProvider, no es el cuello de botella). Ahora se
  /// disparan todas las consultas de PRODUCTO en paralelo (Future.wait) y,
  /// con esos resultados, todas las consultas de LOTES en paralelo también
  /// -dos rondas en paralelo en vez de hasta 8 rondas en serie- y recién con
  /// todo eso ya en memoria se arma el resultado final.
  /// [lotesConocidos]: lotes YA consultados de antemano, por id de producto
  /// de tinte -si quien llama ya los tiene (ver AgregarTinteManualDialog,
  /// que precarga los lotes de los ~12 tintes reales de una sola vez al
  /// abrir el diálogo), se usan directo y no se repite la consulta a
  /// Firestore. Es la misma idea que [UsoTinte.productoConocido] pero para
  /// la ronda de lotes en vez de la de producto -antes esta era la consulta
  /// que quedaba pendiente en CADA cambio de tinte elegido, aunque el
  /// producto ya se conociera, y era la demora real reportada ("cada que
  /// cambio de tinte se tarda un mundo en cargar").
  Future<List<ResultadoCostoTinte>> calcular(
    List<UsoTinte> usos, {
    Map<String, QuerySnapshot<Map<String, dynamic>>>? lotesConocidos,
  }) async {
    if (usos.isEmpty) return [];
    final colorantes = [for (final uso in usos) normalizarColorante(uso.colorante)];

    // Ronda 1: un producto de tinte por colorante, todos a la vez -salvo que
    // el llamador ya lo tenga (productoConocido), en cuyo caso no hace falta
    // ni siquiera esa consulta.
    final productos = await Future.wait([
      for (var i = 0; i < usos.length; i++)
        if (usos[i].productoConocido != null) Future.value(usos[i].productoConocido) else buscarProductoTinte(colorantes[i]),
    ]);

    // Ronda 2: lotes de cada producto que sí se encontró, todos a la vez -
    // salvo los que ya vienen en [lotesConocidos], que se usan directo sin
    // consultar de nuevo (se indexan por posición en `usos`, no todos los
    // colorantes resuelven a un producto).
    final indicesConProducto = [for (var i = 0; i < usos.length; i++) if (productos[i] != null) i];
    final indicesPorConsultar = [for (final i in indicesConProducto) if (lotesConocidos?[productos[i]!.id] == null) i];
    final consultados = Map.fromIterables(
      indicesPorConsultar,
      await Future.wait(indicesPorConsultar.map((i) => _lotes.consultarLotes(productos[i]!.id))),
    );
    final lotesPorIndice = {
      for (final i in indicesConProducto) i: lotesConocidos?[productos[i]!.id] ?? consultados[i]!,
    };

    final resultados = <ResultadoCostoTinte>[];
    for (var i = 0; i < usos.length; i++) {
      final uso = usos[i];
      final colorante = colorantes[i];
      final cuartos = uso.onzas / onzasPorCuarto;
      final producto = productos[i];
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
      final estado = _lotes.inicializarEstado(lotesPorIndice[i]!);
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
