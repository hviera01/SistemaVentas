import 'package:cloud_firestore/cloud_firestore.dart';
import 'producto_model.dart';

/// Id de la categoría "TINTES" en Firestore (categorias/{id}.descripcion ==
/// 'TINTES'), confirmado contra datos reales de producción (12 productos
/// reales "COLORANTE {LETRA}" en esa categoría). Se deja fijo -no se
/// resuelve por nombre en cada consulta- porque de cualquier forma hace
/// falta cruzar por el nombre exacto del producto (ver [buscarProductoTinte])
/// y el id de una categoría ya creada no cambia solo.
const idCategoriaTintes = 'eLM8Htte9FM96gnAImGE';

/// Normaliza un código de colorante ("b", " Axx ") a mayúsculas sin
/// espacios de sobra -mismo criterio que ya usan los nombres reales de
/// producto ("COLORANTE B", "COLORANTE AXX") y que de paso corrige el
/// artefacto de OCR del JSON de fórmulas (una "l" minúscula suelta que en
/// realidad es una "L").
String normalizarColorante(String codigo) => codigo.trim().toUpperCase();

/// Cruza un código de colorante (ej. "B", "AXX") con su producto real de
/// inventario, nombrado exactamente "COLORANTE {LETRA}". Devuelve null (no
/// revienta) si no hay ningún producto con ese nombre -el llamador decide
/// cómo avisar sin romper la venta (ver CostoTinteService)-.
///
/// Se busca solo por 'nombre' (índice de un solo campo, sin necesidad de
/// índice compuesto) en vez de combinarlo con 'idCategoria': el nombre exacto
/// "COLORANTE {LETRA}" ya es prácticamente único en todo el catálogo, y para
/// blindarse igual contra un producto de otra categoría que por casualidad
/// se llame igual, se descarta el resultado si su categoría no es TINTES.
Future<ProductoModel?> buscarProductoTinte(String colorante) async {
  final letra = normalizarColorante(colorante);
  if (letra.isEmpty) return null;
  final snap = await FirebaseFirestore.instance.collection('productos').where('nombre', isEqualTo: 'COLORANTE $letra').limit(1).get();
  if (snap.docs.isEmpty) return null;
  final producto = ProductoModel.fromMap(snap.docs.first.id, snap.docs.first.data());
  if (producto.idCategoria != idCategoriaTintes) return null;
  return producto;
}

/// Todos los productos de tinte activos del catálogo (categoría TINTES),
/// para el selector del modo manual (Escenario B, ver
/// AgregarTinteManualDialog) -el cajero elige el tinte de una lista chica en
/// vez de escribir un código. Sin `orderBy` en la consulta (para no
/// necesitar un índice compuesto con la igualdad de categoría): son ~12
/// productos, se ordenan en memoria.
Future<List<ProductoModel>> listarProductosTinte() async {
  final snap = await FirebaseFirestore.instance.collection('productos').where('idCategoria', isEqualTo: idCategoriaTintes).get();
  final productos = snap.docs.map((d) => ProductoModel.fromMap(d.id, d.data())).where((p) => p.estado).toList()..sort((a, b) => a.nombre.compareTo(b.nombre));
  return productos;
}
