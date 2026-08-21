import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/formula_colortrend_model.dart';

/// Carga una sola vez (y cachea) las ~1500 fórmulas del libro Color Codex,
/// empaquetadas como asset -ver la nota grande en formula_colortrend_model.dart
/// sobre por qué es un archivo estático y no una colección de Firestore.
final formulasColortrendProvider = FutureProvider<List<FormulaColortrendModel>>((ref) async {
  final texto = await rootBundle.loadString('assets/data/formulas_colortrend.json');
  final lista = jsonDecode(texto) as List;
  return lista.map((m) => FormulaColortrendModel.fromMap(m as Map<String, dynamic>)).toList();
});
