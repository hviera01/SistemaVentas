import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

typedef RangoFechas = ({DateTime inicio, DateTime fin});

DateTime _soloDia(DateTime f) => DateTime(f.year, f.month, f.day);

DateTime _lunesDe(DateTime f) {
  final d = _soloDia(f);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

class _Atajo<T> {
  final String texto;
  final T valor;

  const _Atajo(this.texto, this.valor);
}

Widget _chip(String texto, VoidCallback alTocar) {
  return ActionChip(
    label: Text(
      texto,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.texto,
      ),
    ),
    onPressed: alTocar,
    backgroundColor: AppColors.fondoSuave,
    side: BorderSide(color: AppColors.bordeTenue),
    visualDensity: VisualDensity.compact,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

class _DialogoFecha extends StatefulWidget {
  final DateTime inicial;
  final DateTime primera;
  final DateTime ultima;
  final List<_Atajo<DateTime>> atajosFecha;
  final List<_Atajo<RangoFechas>> atajosRango;
  final String titulo;

  const _DialogoFecha({
    required this.inicial,
    required this.primera,
    required this.ultima,
    required this.atajosFecha,
    required this.atajosRango,
    required this.titulo,
  });

  @override
  State<_DialogoFecha> createState() => _DialogoFechaState();
}

class _DialogoFechaState extends State<_DialogoFecha> {
  late DateTime _elegida = widget.inicial;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final alto = MediaQuery.of(context).size.height;
    final enRango = widget.atajosRango.isNotEmpty;
    return Dialog(
      backgroundColor: AppColors.superficie,
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ancho < 400 ? ancho - 24 : 360,
          maxHeight: alto - 24,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.titulo,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.texto,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final a in widget.atajosRango)
                    _chip(a.texto, () => Navigator.pop(context, a.valor)),
                  for (final a in widget.atajosFecha)
                    _chip(a.texto, () => Navigator.pop(context, a.valor)),
                ],
              ),
              if (enRango) ...[
                const SizedBox(height: 6),
                Text(
                  'o elegí un día puntual',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.gris600,
                  ),
                ),
              ],
              CalendarDatePicker(
                initialDate: widget.inicial,
                firstDate: widget.primera,
                lastDate: widget.ultima,
                onDateChanged: (f) => _elegida = f,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.poppins(color: AppColors.gris700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _elegida),
                    child: Text(
                      'Aceptar',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        color: AppColors.rojo,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<_Atajo<DateTime>> _atajosDeUnDia(DateTime primera, DateTime ultima) {
  final hoy = _soloDia(DateTime.now());
  final candidatos = <_Atajo<DateTime>>[
    _Atajo('Hoy', hoy),
    _Atajo('Ayer', hoy.subtract(const Duration(days: 1))),
    _Atajo('Hace 7 días', hoy.subtract(const Duration(days: 7))),
    _Atajo('Inicio de semana', _lunesDe(hoy)),
    _Atajo('Inicio de mes', DateTime(hoy.year, hoy.month, 1)),
    _Atajo('Mañana', hoy.add(const Duration(days: 1))),
    _Atajo('En 7 días', hoy.add(const Duration(days: 7))),
    _Atajo('En 15 días', hoy.add(const Duration(days: 15))),
    _Atajo('En 30 días', hoy.add(const Duration(days: 30))),
    _Atajo('Fin de mes', DateTime(hoy.year, hoy.month + 1, 0)),
  ];
  final vistos = <DateTime>{};
  return candidatos.where((a) {
    if (a.valor.isBefore(_soloDia(primera)) || a.valor.isAfter(_soloDia(ultima))) {
      return false;
    }
    if (a.texto == 'Inicio de semana' && a.valor == hoy) return false;
    if (a.texto == 'Inicio de mes' && a.valor == hoy) return false;
    if (a.texto == 'Fin de mes' && a.valor == hoy) return false;
    return !['Hoy', 'Ayer', 'Mañana'].contains(a.texto) ? vistos.add(a.valor) : true;
  }).toList();
}

List<_Atajo<RangoFechas>> _atajosDeRango() {
  final hoy = _soloDia(DateTime.now());
  final lunes = _lunesDe(hoy);
  final ayer = hoy.subtract(const Duration(days: 1));
  return [
    _Atajo('Hoy', (inicio: hoy, fin: hoy)),
    _Atajo('Ayer', (inicio: ayer, fin: ayer)),
    _Atajo('Esta semana', (inicio: lunes, fin: hoy)),
    _Atajo('Semana pasada', (
      inicio: lunes.subtract(const Duration(days: 7)),
      fin: lunes.subtract(const Duration(days: 1)),
    )),
    _Atajo('Este mes', (inicio: DateTime(hoy.year, hoy.month, 1), fin: hoy)),
    _Atajo('Mes pasado', (
      inicio: DateTime(hoy.year, hoy.month - 1, 1),
      fin: DateTime(hoy.year, hoy.month, 0),
    )),
    _Atajo('Últimos 7 días', (
      inicio: hoy.subtract(const Duration(days: 6)),
      fin: hoy,
    )),
    _Atajo('Últimos 30 días', (
      inicio: hoy.subtract(const Duration(days: 29)),
      fin: hoy,
    )),
    _Atajo('Este año', (inicio: DateTime(hoy.year, 1, 1), fin: hoy)),
  ];
}

/// Reemplazo directo de showDatePicker con atajos rápidos (hoy, ayer,
/// inicio de semana/mes, y hacia adelante mañana, +7, +15, +30 días, fin de
/// mes cuando el rango lo permite) -pedido explícito del dueño: no tener que
/// buscar cada fecha en el calendario-.
Future<DateTime?> seleccionarFechaRapida({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String titulo = 'Elegí una fecha',
}) async {
  final inicial = _soloDia(initialDate).isBefore(_soloDia(firstDate))
      ? _soloDia(firstDate)
      : (_soloDia(initialDate).isAfter(_soloDia(lastDate))
            ? _soloDia(lastDate)
            : _soloDia(initialDate));
  final r = await showDialog<Object?>(
    context: context,
    builder: (_) => _DialogoFecha(
      inicial: inicial,
      primera: firstDate,
      ultima: lastDate,
      atajosFecha: _atajosDeUnDia(firstDate, lastDate),
      atajosRango: const [],
      titulo: titulo,
    ),
  );
  return r is DateTime ? r : null;
}

/// Para los filtros "Desde / Hasta": además de los atajos de un día, ofrece
/// periodos completos (hoy, ayer, esta semana, semana pasada, este mes, mes
/// pasado, últimos 7/30 días, este año) que rellenan las DOS fechas de una
/// sola vez. Si se elige un día puntual del calendario solo cambia el lado
/// que se tocó (y se corrige el otro si quedara invertido el rango).
Future<RangoFechas?> seleccionarRangoRapido({
  required BuildContext context,
  required bool esInicio,
  required DateTime inicio,
  required DateTime fin,
  DateTime? primera,
  DateTime? ultima,
}) async {
  final primeraF = primera ?? DateTime(2000);
  final ultimaF = ultima ?? DateTime(2100);
  final r = await showDialog<Object?>(
    context: context,
    builder: (_) => _DialogoFecha(
      inicial: _soloDia(esInicio ? inicio : fin),
      primera: primeraF,
      ultima: ultimaF,
      atajosFecha: const [],
      atajosRango: _atajosDeRango(),
      titulo: esInicio ? 'Fecha desde' : 'Fecha hasta',
    ),
  );
  if (r == null) return null;
  if (r is Record) return r as RangoFechas;
  final f = _soloDia(r as DateTime);
  if (esInicio) {
    return (inicio: f, fin: fin.isBefore(f) ? f : fin);
  }
  return (inicio: inicio.isAfter(f) ? f : inicio, fin: f);
}
