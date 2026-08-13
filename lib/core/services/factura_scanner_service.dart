import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Escaneo de facturas de compra con IA (ver EscanearFacturaDialog): manda
/// 1+ fotos de la MISMA factura a un Worker propio de Cloudflare, que hace
/// de intermediario con la API de Claude (Anthropic) para que la API key
/// nunca quede expuesta en el navegador. El proyecto de Firebase de Super
/// Color no puede pasar a plan Blaze (no hay Cloud Functions propias), por
/// eso el intermediario vive en Cloudflare en vez de Firebase -mismo motivo
/// por el que las fotos de producto van a Cloudinary y no a Firebase
/// Storage-.
///
/// El secreto compartido de acá abajo viaja en el bundle del navegador (no
/// hay forma de evitarlo sin un login propio para este endpoint, que sería
/// desproporcionado para esto): no es una barrera real contra un ataque
/// dedicado, solo filtra el ruido de quien encuentre la URL del Worker sin
/// buscarlo a propósito. La protección real contra un abuso caro es el
/// límite de gasto mensual configurado en la cuenta de Anthropic.
const _urlWorker = 'https://supercolor-factura-scanner.factura-scanner.workers.dev';
const _secretoApp = '2b76e9771ef4c26bd7e32905f2b6b8695a227c508e337969';

class FotoParaEscanear {
  final Uint8List bytes;
  final String mimeType;
  FotoParaEscanear({required this.bytes, required this.mimeType});
}

class LineaFacturaEscaneada {
  final String? codigo;
  final String nombre;
  final String? unidad;
  final double cantidad;
  final double precioUnitario;
  final double descuentoPorcentaje;

  LineaFacturaEscaneada({
    required this.codigo,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    required this.precioUnitario,
    required this.descuentoPorcentaje,
  });

  factory LineaFacturaEscaneada.fromJson(Map<String, dynamic> json) {
    return LineaFacturaEscaneada(
      codigo: json['codigo'] as String?,
      nombre: json['nombre'] as String? ?? '',
      unidad: json['unidad'] as String?,
      cantidad: (json['cantidad'] as num?)?.toDouble() ?? 0,
      precioUnitario: (json['precioUnitario'] as num?)?.toDouble() ?? 0,
      descuentoPorcentaje: (json['descuentoPorcentaje'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ResultadoEscaneoFactura {
  final String? proveedorNombre;
  final String? proveedorRtn;
  final String? numeroFactura;
  final DateTime? fecha;
  final String? condicionVenta;
  final DateTime? fechaVencimiento;
  final List<LineaFacturaEscaneada> items;

  ResultadoEscaneoFactura({
    required this.proveedorNombre,
    required this.proveedorRtn,
    required this.numeroFactura,
    required this.fecha,
    required this.condicionVenta,
    required this.fechaVencimiento,
    required this.items,
  });

  factory ResultadoEscaneoFactura.fromJson(Map<String, dynamic> json) {
    return ResultadoEscaneoFactura(
      proveedorNombre: json['proveedorNombre'] as String?,
      proveedorRtn: json['proveedorRtn'] as String?,
      numeroFactura: json['numeroFactura'] as String?,
      fecha: _parsearFecha(json['fecha'] as String?),
      condicionVenta: json['condicionVenta'] as String?,
      fechaVencimiento: _parsearFecha(json['fechaVencimiento'] as String?),
      items: ((json['items'] as List?) ?? []).map((e) => LineaFacturaEscaneada.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  static DateTime? _parsearFecha(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    return DateTime.tryParse(texto);
  }
}

/// [codigo] identifica el motivo para que la pantalla muestre el mensaje
/// correcto: 'LIMITE_AGOTADO' (se acabó el crédito/cuota, avisar y sugerir
/// cargar a mano o esperar), 'MODELO_SOBRECARGADO' (reintentar en un rato),
/// cualquier otro (error genérico).
class EscaneoFacturaException implements Exception {
  final String codigo;
  final String mensaje;
  EscaneoFacturaException(this.codigo, this.mensaje);
}

class FacturaScannerService {
  Future<ResultadoEscaneoFactura> escanear(List<FotoParaEscanear> fotos) async {
    final cuerpo = jsonEncode({
      'images': fotos.map((f) => {'data': base64Encode(f.bytes), 'mimeType': f.mimeType}).toList(),
    });

    http.Response respuesta;
    try {
      respuesta = await http
          .post(
            Uri.parse(_urlWorker),
            headers: {'Content-Type': 'application/json', 'X-App-Secret': _secretoApp},
            body: cuerpo,
          )
          // Leer varias fotos con un modelo de visión puede tardar: se vio
          // hasta varias decenas de segundos en las pruebas.
          .timeout(const Duration(seconds: 120));
    } catch (_) {
      throw EscaneoFacturaException('SIN_CONEXION', 'No se pudo conectar con el servicio de escaneo. Revisá tu conexión a internet.');
    }

    final data = jsonDecode(respuesta.body) as Map<String, dynamic>;

    if (respuesta.statusCode == 429 || data['error'] == 'LIMITE_AGOTADO') {
      throw EscaneoFacturaException('LIMITE_AGOTADO', 'Se agotó el crédito o el límite de uso del servicio de escaneo por ahora. Probá más tarde, o cargá los productos a mano.');
    }
    if (respuesta.statusCode == 503 || data['error'] == 'MODELO_SOBRECARGADO') {
      throw EscaneoFacturaException('MODELO_SOBRECARGADO', 'El servicio de lectura está saturado en este momento. Probá de nuevo en un par de minutos.');
    }
    if (respuesta.statusCode == 401) {
      throw EscaneoFacturaException('NO_AUTORIZADO', 'No se pudo autenticar con el servicio de escaneo.');
    }
    if (respuesta.statusCode != 200) {
      throw EscaneoFacturaException('ERROR', 'No se pudo leer la factura (${data['error'] ?? respuesta.statusCode}). Intentá de nuevo o cargá los productos a mano.');
    }

    return ResultadoEscaneoFactura.fromJson(data);
  }
}
