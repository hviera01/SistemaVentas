import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/formula_colortrend_model.dart';

/// Carga una sola vez (y cachea) las ~1500 fórmulas del libro Color Codex,
/// empaquetadas como asset -ver la nota grande en formula_colortrend_model.dart
/// sobre por qué es un archivo estático y no una colección de Firestore. En
/// la versión web (Pages, incluida la app "Fórmulas" aparte que se agrega a
/// pantalla de inicio) este archivo -~1.2MB- se pide por HTTP, no viene
/// empaquetado en el binario como en Windows: con una conexión lenta o
/// inestable esa descarga puede fallar o cortarse a mitad (el error real
/// reportado por el dueño: "no se pudo cargar el libro de fórmulas...
/// Json", un FormatException por JSON truncado). Antes esa falla quedaba
/// cacheada como error hasta cerrar y volver a entrar a la app -pedido
/// explícito del dueño: "que nunca falle la carga, que él solo lo
/// reintente"-: ahora reintenta solo, unas cuantas veces con una pausa
/// corta entre cada intento, antes de recién ahí dar el error por
/// definitivo (ver también el botón "Reintentar" en las pantallas que
/// muestran este error, por si ni así carga -sin red de verdad, por
/// ejemplo-).
final formulasColortrendProvider = FutureProvider<List<FormulaColortrendModel>>((ref) async {
  const intentosMax = 4;
  for (var intento = 1; intento <= intentosMax; intento++) {
    try {
      final texto = await rootBundle.loadString('assets/data/formulas_colortrend.json');
      final lista = jsonDecode(texto) as List;
      return lista.map((m) => FormulaColortrendModel.fromMap(m as Map<String, dynamic>)).toList();
    } catch (_) {
      if (intento == intentosMax) rethrow;
      await Future.delayed(Duration(milliseconds: 500 * intento));
    }
  }
  throw Exception('No se pudo cargar el libro de fórmulas');
});
